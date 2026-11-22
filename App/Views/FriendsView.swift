#if os(iOS)
import CandidCore
import SwiftUI

struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var inviteUnavailable = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            // TODO: Present UICloudSharingController with the zone share.
                            inviteUnavailable = (try? await model.services.friends.makeInviteURL()) == nil
                        }
                    } label: {
                        Label("Invite a friend", systemImage: "person.badge.plus")
                    }
                }
                Section("Friends") {
                    if model.friends.isEmpty {
                        Text("No friends yet. Only people you invite can see what you share.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.friends) { friend in
                        HStack {
                            Text(friend.displayName)
                            Spacer()
                            if friend.status == .invited {
                                Text("Invited").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Friends")
            .alert("Invites are not ready yet.", isPresented: $inviteUnavailable) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
#endif
