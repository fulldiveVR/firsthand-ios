#if os(iOS)
import FirsthandCore
import CloudKit
import SwiftUI

/// Friends sheet. Two user words only: Friend (mutual or one way) and Waiting.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var contactSheet = false
    @State private var manageShare: CKShare?
    @State private var confirmRemove: Friendship?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.friendships.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await model.refreshSharing() }
            .sheet(isPresented: $contactSheet) { InviteContactSheet() }
            .sheet(item: $model.outgoingInvite) { invite in InviteLinkSheet(invite: invite) }
            .sheet(item: $manageShare) { share in
                CloudSharingView(share: share, container: model.services.sharing.container) {
                    Task { await model.refreshSharing() }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog(
                confirmTitle,
                isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                titleVisibility: .visible,
                presenting: confirmRemove
            ) { friendship in
                Button(friendship.isWaiting ? "Cancel Invite" : "Remove", role: .destructive) {
                    Task { await model.remove(friendship) }
                }
            } message: { friendship in
                if friendship.isWaiting {
                    Text("The invite link stops working.")
                } else {
                    Text("They stop seeing your moments and you stop seeing theirs.")
                }
            }
            .sharingErrorAlert()
        }
        .onDisappear { model.highlightedFriendID = nil }
    }

    private var confirmTitle: String {
        guard let f = confirmRemove else { return "" }
        return f.isWaiting
            ? String(localized: "Cancel the invite to \(f.shownName)?")
            : String(localized: "Remove \(f.shownName)?")
    }

    private var list: some View {
        let waiting = model.friendships.filter(\.isWaiting)
        let friends = model.friendships.filter { !$0.isWaiting }
        return List {
            Section {
                InviteCard(showQR: showQR)
            }

            if !waiting.isEmpty {
                Section("Waiting") {
                    ForEach(waiting) { friendship in
                        FriendRow(friendship: friendship, highlighted: friendship.id == model.highlightedFriendID)
                            .swipeActions {
                                Button("Cancel Invite", role: .destructive) { confirmRemove = friendship }
                            }
                    }
                }
            }

            if !friends.isEmpty {
                Section {
                    ForEach(friends) { friendship in
                        FriendRow(friendship: friendship, highlighted: friendship.id == model.highlightedFriendID)
                            .swipeActions {
                                Button("Remove", role: .destructive) { confirmRemove = friendship }
                            }
                    }
                } header: {
                    Text("Friends")
                } footer: {
                    Text("\(model.friendships.count) of \(FriendRoster.defaultLimit)")
                }
            }

            Section {
                Button {
                    Task { manageShare = try? await model.services.sharing.ensureShare() }
                } label: {
                    NavigationRowLabel(title: "Sharing Details", systemImage: "icloud")
                }
                Button {
                    contactSheet = true
                } label: {
                    NavigationRowLabel(title: "Invite by Email or Phone", systemImage: "envelope")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add your first friend", systemImage: "person.2")
        } description: {
            Text("Only people you invite can see what you share. Up to \(FriendRoster.defaultLimit) friends.")
        } actions: {
            VStack(spacing: 12) {
                ShareLink(
                    item: ShareInvite(sharing: model.services.sharing),
                    preview: SharePreview(String(localized: "\(AppInfo.name) moments"))
                ) {
                    Text("Message an Invite").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                Button(action: showQR) {
                    Text("Show QR Code").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.72, 320) }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func showQR() {
        Task { await model.makeInvite() }
    }
}

/// Top of the Friends list: one compact invite card.
private struct InviteCard: View {
    @Environment(AppModel.self) private var model
    var showQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(.white)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.title)
                            .foregroundStyle(.black)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a Friend").font(.headline)
                    Text("They need iPhone and iCloud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                ShareLink(
                    item: ShareInvite(sharing: model.services.sharing),
                    preview: SharePreview(String(localized: "\(AppInfo.name) moments"))
                ) {
                    Label("Message", systemImage: "message").frame(maxWidth: .infinity)
                }
                Button(action: showQR) {
                    Label("Show QR Code", systemImage: "qrcode").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .labelStyle(.titleOnly)
        }
        .padding(.vertical, 6)
    }
}

/// A friend or a waiting invite.
private struct FriendRow: View {
    @Environment(AppModel.self) private var model
    let friendship: Friendship
    var highlighted = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(id: friendship.id, name: friendship.shownName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(friendship.shownName)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 2)
        .listRowBackground(highlighted ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        if friendship.needsReverseShare {
            Button("Finish") { Task { await model.shareBack(with: friendship) } }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .controlSize(.small)
        } else if friendship.incoming == .pending {
            EmptyView()
        } else if friendship.isWaiting {
            Text("Invited")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        if friendship.needsReverseShare {
            return String(localized: "Finish adding \(friendship.shownName)")
        }
        if friendship.incoming == .pending {
            return String(localized: "Open their invite link again to finish.")
        }
        if friendship.isWaiting {
            return String(localized: "Waiting for them to join")
        }
        if let last = model.friendsPosts().first(where: { $0.authorID == friendship.id }) {
            return String(localized: "Shared \(last.createdAt.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "No moments yet")
    }
}

/// A list row that looks like a navigation link: icon, title, chevron.
struct NavigationRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

extension Friendship {
    /// Waiting: invited and not joined, or an invite I opened but did not finish.
    /// Everything else that is active is a friend.
    var isWaiting: Bool {
        outgoing != .accepted && incoming != .accepted
    }

    var shownName: String {
        displayName.isEmpty ? String(localized: "Friend") : displayName
    }
}

extension CKShare: @retroactive Identifiable {
    public var id: CKRecord.ID { recordID }
}

extension View {
    /// The sharing error alert. Each presented sheet shows it, so it is never hidden behind a sheet.
    func sharingErrorAlert() -> some View {
        modifier(SharingErrorAlert())
    }
}

private struct SharingErrorAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert(
            model.sharingError ?? "",
            isPresented: Binding(get: { model.sharingError != nil }, set: { if !$0 { model.sharingError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}
#endif
