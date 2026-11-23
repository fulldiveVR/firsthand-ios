#if os(iOS)
import FirsthandCore
import SwiftUI

/// Friends' moments, newest first. No like counts, no ranking. Own moments live in the shelf below.
struct FriendsMomentsSection: View {
    @Environment(AppModel.self) private var model
    var onOpen: (Post) -> Void = { _ in }

    var body: some View {
        let posts = model.friendsPosts()
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "From Friends")
            if model.friendships.isEmpty {
                FriendsEmptyCard()
            } else if posts.isEmpty {
                Text("No moments from friends in the last 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.betweenCards) {
                    ForEach(posts, id: \.feedItemID) { post in
                        FriendMomentCard(post: post, onOpen: { onOpen(post) })
                    }
                }
            }
        }
    }
}

/// One friend's moment: who and when, the photo, the caption, and the expiry when it is near.
struct FriendMomentCard: View {
    let post: Post
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Avatar(id: post.authorID, name: post.authorName, size: 28)
                Text(post.authorName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(post.createdAt.shortRelative())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)

            Button(action: onOpen) {
                PostPhoto(url: post.imageURL, clampAspect: true)
                    .clipShape(Theme.shape(Theme.Radius.card))
                    .contentShape(Theme.shape(Theme.Radius.card))
                    .momentTransitionSource(MomentRoute.post(post).id)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Moment from \(post.authorName)"))
            .accessibilityHint("Shows details")
            .contextMenu {
                Button("Moment Details", systemImage: "info.circle", action: onOpen)
            }

            if let caption = post.caption {
                Text(caption)
                    .font(.body)
                    .padding(.horizontal, 4)
            }
            ExpiryNote(post: post)
                .padding(.horizontal, 4)
        }
    }
}

/// Shown only in the last 7 days of a moment.
struct ExpiryNote: View {
    let post: Post
    var now = Date()

    var body: some View {
        let days = post.daysLeft(now: now)
        if days <= 7 {
            Label {
                if days <= 1 {
                    Text("Disappears within a day")
                } else {
                    Text("Disappears in \(days) days")
                }
            } icon: {
                Image(systemName: "hourglass")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

/// No friends yet. Three grey monograms and one action.
struct FriendsEmptyCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: -12) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                        .zIndex(Double(index == 1 ? 1 : 0))
                        .scaleEffect(index == 1 ? 1.15 : 1)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Moments are better with friends")
                    .font(.headline)
                Text("Only people you invite can see what you share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Button("Invite Friends") { model.homeSheet = .friends }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .controlSize(.large)
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }
}

/// My moments of the last 30 days, as a horizontal shelf of 3:4 thumbs.
struct YourMomentsShelf: View {
    @Environment(AppModel.self) private var model
    var onOpen: (Post) -> Void = { _ in }
    @State private var confirmDelete: Post?

    var body: some View {
        let posts = model.myPosts()
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Your Moments")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(posts, id: \.feedItemID) { post in
                            Button { onOpen(post) } label: {
                                PostPhoto(url: post.imageURL, fixedAspect: 3 / 4)
                                    .frame(width: 120)
                                    .clipShape(Theme.shape(Theme.Radius.small))
                                    .contentShape(Theme.shape(Theme.Radius.small))
                                    .momentTransitionSource(MomentRoute.post(post).id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(post.caption ?? String(localized: "Your moment"))
                            .accessibilityValue(post.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .contextMenu {
                                Button("Moment Details", systemImage: "info.circle") { onOpen(post) }
                                Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = post }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
            }
            .confirmationDialog(
                "Delete this moment?",
                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                titleVisibility: .visible,
                presenting: confirmDelete
            ) { post in
                Button("Delete Moment", role: .destructive) { Task { await model.delete(post) } }
            } message: { _ in
                Text("Your friends will no longer see it.")
            }
        }
    }
}

/// A downloaded post image, loaded off the main thread and cached in memory.
struct PostPhoto: View {
    let url: URL?
    /// Native aspect, clamped between 4:5 and 1:1.
    var clampAspect = false
    var fixedAspect: CGFloat?
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: url) { image = await PostImageCache.shared.image(at: url) }
            .accessibilityHidden(true)
    }

    private var aspect: CGFloat {
        if let fixedAspect { return fixedAspect }
        guard clampAspect, let image, image.size.height > 0 else { return Theme.momentAspect }
        return min(max(image.size.width / image.size.height, Theme.momentAspect), 1)
    }
}

/// Decoded post images by file URL.
@MainActor
final class PostImageCache {
    static let shared = PostImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(at url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
        if let loaded { cache.setObject(loaded, forKey: url as NSURL) }
        return loaded
    }
}

extension AppModel {
    /// Friends' posts that are not expired, newest first.
    func friendsPosts(now: Date = Date()) -> [Post] {
        visibleFeed(now: now).filter { $0.authorID != CloudKitSharing.ownOwnerID }
    }

    /// My posts that are not expired, newest first.
    func myPosts(now: Date = Date()) -> [Post] {
        visibleFeed(now: now).filter { $0.authorID == CloudKitSharing.ownOwnerID }
    }
}
#endif
