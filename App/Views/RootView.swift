#if os(iOS)
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.isOnboarded {
            MomentsView()
            .sheet(item: $model.homeSheet) { sheet in
                switch sheet {
                case .friends: FriendsView()
                case .profile: SettingsView()
                }
            }
            // While the Friends sheet is open, it presents the invite itself.
            .sheet(item: Binding(
                get: { model.homeSheet == nil ? model.outgoingInvite : nil },
                set: { model.outgoingInvite = $0 }
            )) { invite in
                InviteLinkSheet(invite: invite)
            }
            .alert(
                model.sharingError ?? "",
                isPresented: Binding(
                    get: { model.sharingError != nil && model.homeSheet == nil },
                    set: { if !$0 { model.sharingError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
        } else {
            OnboardingView()
        }
    }
}
#endif
