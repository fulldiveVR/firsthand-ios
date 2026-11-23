#if os(iOS)
import FirsthandCore
import SwiftUI

/// The home screen: today's moment, friends' moments and your moments in one scroll.
/// Friends and Profile open as sheets from the toolbar. There is no tab bar.
struct MomentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.betweenSections) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Today", subtitle: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        TodaySection()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "From Friends")
                        FeedSection()
                    }
                }
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.bottom, Theme.Spacing.betweenSections)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await model.refreshSharing() }
            .navigationTitle("Moments")
            .toolbar { MomentsToolbar() }
        }
    }
}

/// Friends on the leading side, the profile avatar on the trailing side.
struct MomentsToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Friends", systemImage: "person.2") { model.homeSheet = .friends }
                .badge(model.friendsNeedingAction)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.homeSheet = .profile
            } label: {
                Avatar(id: model.appleUserID ?? "me", name: model.userName ?? "", size: 32)
            }
            .accessibilityLabel("Profile and Privacy")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// A home section title: `.title3.bold()` and an optional secondary line.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

extension AppModel {
    /// Invites I received and did not accept. The only badge in the app.
    var friendsNeedingAction: Int {
        friendships.filter { $0.incoming == .pending }.count
    }
}
#endif
