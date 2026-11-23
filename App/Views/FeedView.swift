#if os(iOS)
import FirsthandCore
import SwiftUI

/// Friends' posts, newest first. No like counts, no ranking.
struct FeedSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete: Post?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let posts = model.visibleFeed()
            if posts.isEmpty {
                Text("Moments you and your friends share appear here for 30 days.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(posts, id: \.feedItemID) { post in
                    PostRow(post: post)
                        .contextMenu {
                            if post.authorID == CloudKitSharing.ownOwnerID {
                                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = post }
                            }
                        }
                }
            }
        }
        .confirmationDialog(
                "Delete this moment?",
                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                titleVisibility: .visible,
                presenting: confirmDelete
            ) { post in
                Button("Delete", role: .destructive) { Task { await model.delete(post) } }
            } message: { _ in
                Text("Your friends will no longer see it.")
            }
    }
}

private struct PostRow: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(id: post.authorID, name: post.authorName, size: 28)
                Text(post.authorName).font(.headline)
                Spacer()
                Text(post.createdAt.shortRelative()).font(.footnote).foregroundStyle(.secondary)
            }
            if let url = post.imageURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if let caption = post.caption {
                Text(caption)
            }
            ExpiryLabel(post: post)
        }
        .padding(.vertical, 8)
    }
}
/// The 30-day rule, shown quietly on every post.
private struct ExpiryLabel: View {
    let post: Post

    var body: some View {
        let days = post.daysLeft(now: Date())
        Group {
            if days <= 1 {
                Text("Disappears within a day")
            } else {
                Text("Disappears in \(days) days")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
}
#endif
