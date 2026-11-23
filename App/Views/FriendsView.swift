#if os(iOS)
import FirsthandCore
import CloudKit
import SwiftUI

struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var contactSheet = false
    @State private var manageShare: CKShare?
    @State private var confirmRemove: Friendship?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ShareLink(
                        item: ShareInvite(sharing: model.services.sharing),
                        preview: SharePreview(String(localized: "\(AppInfo.name) moments"))
                    ) {
                        Label("Invite with Messages", systemImage: "message")
                    }
                    Button {
                        Task { await model.makeInvite() }
                    } label: {
                        Label("Show Invite QR Code", systemImage: "qrcode")
                    }
                    Button {
                        contactSheet = true
                    } label: {
                        Label("Invite by Email or Phone", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("Only people you invite can see what you share. \(model.friendCapText).")
                }

                Section("Friends") {
                    if model.friendships.isEmpty {
                        Text("No friends yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.friendships) { friendship in
                        FriendRow(friendship: friendship)
                            .swipeActions {
                                Button("Remove", role: .destructive) { confirmRemove = friendship }
                            }
                    }
                }

                Section {
                    Button("Manage Sharing in iCloud") {
                        Task { manageShare = try? await model.services.sharing.ensureShare() }
                    }
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await model.refreshSharing() }
            .sheet(isPresented: $contactSheet) { InviteContactSheet() }
            .sheet(item: $manageShare) { share in
                CloudSharingView(share: share, container: model.services.sharing.container) {
                    Task { await model.refreshSharing() }
                }
            }
            .confirmationDialog(
                "Remove \(confirmRemove?.displayName ?? "")?",
                isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                titleVisibility: .visible,
                presenting: confirmRemove
            ) { friendship in
                Button("Remove", role: .destructive) { Task { await model.remove(friendship) } }
            } message: { _ in
                Text("They stop seeing your moments and you stop seeing theirs.")
            }
        }
    }
}

extension CKShare: @retroactive Identifiable {
    public var id: CKRecord.ID { recordID }
}

private struct FriendRow: View {
    @Environment(AppModel.self) private var model
    let friendship: Friendship

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(friendship.displayName.isEmpty ? String(localized: "Friend") : friendship.displayName)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if friendship.needsReverseShare {
                Button("Share Back") { Task { await model.shareBack(with: friendship) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var statusText: String {
        switch friendship.state {
        case .invited: String(localized: "Invited")
        case .pendingAccept: String(localized: "Waiting for you to accept")
        case .oneWay(.incoming): String(localized: "You see their moments")
        case .oneWay(.outgoing): String(localized: "They see your moments")
        case .mutual: String(localized: "Friends")
        case .removed: String(localized: "Removed")
        }
    }
}
#endif
