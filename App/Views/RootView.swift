#if os(iOS)
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isOnboarded {
            TabView {
                Tab("Today", systemImage: "sun.max") { TodayView() }
                Tab("Feed", systemImage: "rectangle.stack") { FeedView() }
                Tab("Friends", systemImage: "person.2") { FriendsView() }
                Tab("Settings", systemImage: "gearshape") { SettingsView() }
            }
        } else {
            OnboardingView()
        }
    }
}
#endif
