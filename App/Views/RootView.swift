#if os(iOS)
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.isOnboarded {
            TabView {
                Tab("Today", systemImage: "sun.max") { TodayView() }
                Tab("Feed", systemImage: "rectangle.stack") { FeedView() }
                Tab("Friends", systemImage: "person.2") { FriendsView() }
                Tab("Settings", systemImage: "gearshape") { SettingsView() }
            }
            .sheet(item: $model.outgoingInvite) { invite in
                InviteLinkSheet(invite: invite)
            }
            .alert(
                "Share your moments with \(model.reverseShareOffer?.displayName ?? "")?",
                isPresented: Binding(
                    get: { model.reverseShareOffer != nil },
                    set: { if !$0 { model.reverseShareOffer = nil } }
                ),
                presenting: model.reverseShareOffer
            ) { friendship in
                Button("Share Back") { Task { await model.shareBack(with: friendship) } }
                Button("Not Now", role: .cancel) {}
            } message: { _ in
                Text("You can now see their moments. Share back so they can see yours.")
            }
            .alert(
                model.sharingError ?? "",
                isPresented: Binding(get: { model.sharingError != nil }, set: { if !$0 { model.sharingError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        } else {
            OnboardingView()
        }
    }
}
#endif
