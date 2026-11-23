#if os(iOS)
import FirsthandCore
import SwiftUI

/// The home screen: today's moment, friends' moments and your moments in one scroll.
/// Friends and Profile open as sheets from the toolbar. There is no tab bar.
struct MomentsView: View {
    @Environment(AppModel.self) private var model
    @State private var shareTarget: Suggestion?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.betweenSections) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Today", subtitle: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            TodaySection(onShare: { shareTarget = $0 })
                        }
                        FriendsMomentsSection()
                        YourMomentsShelf()
                            .id(HomeAnchor.shelf)
                    }
                    .padding(.horizontal, Theme.Spacing.margin)
                    .padding(.bottom, Theme.Spacing.betweenSections)
                }
                #if DEBUG
                .onAppear {
                    if UserDefaults.standard.string(forKey: "demoScroll") == "shelf" {
                        proxy.scrollTo(HomeAnchor.shelf, anchor: .bottom)
                    }
                }
                #endif
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .modifier(MinimizingToolbar())
            .refreshable { await model.refreshSharing() }
            .navigationTitle("Moments")
            .toolbar { MomentsToolbar() }
            .sheet(item: $shareTarget) { suggestion in
                ShareSheet(suggestion: suggestion) {
                    shareTarget = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        model.homeSheet = .friends
                    }
                }
            }
            .sensoryFeedback(.success, trigger: model.shareSuccessCount)
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.string(forKey: "demoSheet") == "share" { shareTarget = model.pending }
            }
            #endif
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
        ToolbarItem(placement: Self.profilePlacement) {
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

extension MomentsToolbar {
    /// iOS 27 keeps the profile avatar visible when the toolbar compacts.
    static var profilePlacement: ToolbarItemPlacement {
        if #available(iOS 27, *) { .topBarPinnedTrailing } else { .topBarTrailing }
    }
}

private enum HomeAnchor: Hashable {
    case shelf
}

/// iOS 27: the toolbar shrinks while the user scrolls through friends' moments.
private struct MinimizingToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        } else {
            content
        }
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
