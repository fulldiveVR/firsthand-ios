#if os(iOS)
import FirsthandCore
import SwiftUI

/// Onboarding, one idea per page, pushed in a NavigationStack with the system back button.
/// Each system prompt opens only from a button on the page that explains it.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [OnboardingPage] = Self.initialPath

    private static var initialPath: [OnboardingPage] {
        #if DEBUG
        if let index = AppModel.debugOnboardingPage, index > 0 {
            return OnboardingPage.allCases.filter { $0.rawValue > 0 && $0.rawValue <= index }
        }
        #endif
        return []
    }

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingPageView(page: .welcome, go: go)
                .navigationDestination(for: OnboardingPage.self) { page in
                    OnboardingPageView(page: page, go: go)
                        .modifier(OnboardingPush())
                }
        }
        .onChange(of: model.appleUserID) { _, id in
            if id != nil && (path.last ?? .welcome) == .signIn { go(.firstScan) }
        }
    }

    /// Pushes a later page, or pops back to an earlier one.
    private func go(_ target: OnboardingPage) {
        if target == .welcome {
            path = []
        } else if let index = path.firstIndex(of: target) {
            path = Array(path.prefix(through: index))
        } else {
            path.append(target)
        }
    }
}

/// Reduce Motion: a cross-fade push on iOS 27, the default push on iOS 26.
private struct OnboardingPush: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion, #available(iOS 27, *) {
            content.navigationTransition(.crossFade)
        } else {
            content
        }
    }
}

enum OnboardingPage: Int, CaseIterable, Hashable {
    case welcome, howItWorks, privacy, photos, notifications, sharing, signIn, firstScan

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: "\(AppInfo.name)"
        case .howItWorks: "You just say yes or no"
        case .privacy: "Stays on your iPhone"
        case .photos: "Allow access to recent photos"
        case .notifications: "Know when a moment is ready"
        case .sharing: "Friends only. Gone in 30 days."
        case .signIn: "Sign in with Apple"
        case .firstScan: "Finding your first moment"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .welcome: "One real moment a day, shared only with friends, only when you say yes."
        case .howItWorks: "\(AppInfo.name) picks one moment from your recent photos. You never scroll or choose."
        case .privacy: "Photos are analyzed on device. Nothing leaves without Face ID."
        case .photos: "\(AppInfo.name) needs full access to find new moments."
        case .notifications: "At most once a day. Never shows the photo."
        case .sharing: "Share with up to \(FriendRoster.defaultLimit) people you invite. Every moment disappears after 30 days."
        case .signIn: "Friends see only the name you choose."
        case .firstScan: "You can leave the app. We'll let you know."
        }
    }
}

/// One page: hero, centered title and one or two sentences, buttons pinned at the bottom.
private struct OnboardingPageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let page: OnboardingPage
    var go: (OnboardingPage) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    OnboardingHero(page: page)
                        .frame(maxWidth: .infinity)
                        .frame(height: typeSize.isAccessibilitySize ? 180 : 280)
                    VStack(spacing: 12) {
                        Text(page.title)
                            .font(.largeTitle.bold())
                        Text(page.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 36)
                    if page == .welcome {
                        FeatureRows()
                            .padding(.top, 32)
                    }
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 32)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaBar(edge: .bottom) {
            OnboardingActions(page: page, go: go)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isScanning)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var isScanning: Bool {
        if case .scanning = model.firstScan { true } else { false }
    }
}

/// Three short feature rows, welcome page only.
private struct FeatureRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            row("sparkles", "One moment a day", "The AI picks it from your recent photos.")
            row("faceid", "Only when you say yes", "Face ID confirms every share.")
            row("person.2.fill", "Friends only", "No public profile, no likes.")
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(.title2))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bottom buttons. Permission logic is the same as before the redesign.
private struct OnboardingActions: View {
    @Environment(AppModel.self) private var model
    let page: OnboardingPage
    var go: (OnboardingPage) -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch page {
            case .welcome, .howItWorks, .privacy, .sharing:
                primary("Continue", action: next)
            case .photos:
                photosActions
            case .notifications:
                notificationActions
            case .signIn:
                signInActions
            case .firstScan:
                firstScanActions
            }
        }
        .tint(.accentColor)
        .frame(maxWidth: 500)
    }

    private func next() {
        if let next = page.next { go(next) }
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private var photosActions: some View {
        switch model.photoAccess {
        case .notDetermined:
            primary("Allow Photo Access") {
                Task {
                    await model.requestPhotoAccess()
                    if model.photoAccess == .authorized { next() }
                }
            }
        case .authorized:
            StatusLine(text: "Full photo access is on.", symbol: "checkmark.circle.fill", color: .green)
            primary("Continue", action: next)
        case .limited:
            StatusLine(text: "With limited access, \(AppInfo.name) can't find new moments.", symbol: "exclamationmark.circle.fill", color: .orange)
            primary("Allow Full Access") { SystemSettings.open() }
            secondary("Continue with Limited Access", action: next)
        case .denied:
            StatusLine(text: "Photo access is off. In Settings, choose Photos, then Full Access.", symbol: "xmark.circle.fill", color: .red)
            primary("Open Settings") { SystemSettings.open() }
        }
    }

    @ViewBuilder
    private var notificationActions: some View {
        switch model.notificationAccess {
        case .notDetermined:
            primary("Turn On Notifications") {
                Task {
                    await model.requestNotificationAccess()
                    next()
                }
            }
            secondary("Not Now", action: next)
        case .allowed:
            StatusLine(text: "Notifications are on.", symbol: "checkmark.circle.fill", color: .green)
            primary("Continue", action: next)
        case .denied:
            StatusLine(text: "Notifications are off. You can turn them on in Settings.", symbol: "bell.slash.fill", color: .secondary)
            primary("Continue", action: next)
        }
    }

    @ViewBuilder
    private var signInActions: some View {
        if model.appleUserID == nil {
            SignInWithAppleView()
        } else {
            StatusLine(text: "You are signed in.", symbol: "checkmark.circle.fill", color: .green)
            primary("Continue", action: next)
        }
    }

    @ViewBuilder
    private var firstScanActions: some View {
        if !model.photoAccess.canRead {
            StatusLine(text: "Photo access is needed first.", symbol: "photo.badge.exclamationmark", color: .orange)
            primary("Back to Photo Access") { go(.photos) }
        } else if model.appleUserID == nil {
            primary("Back to Sign In") { go(.signIn) }
        } else if case .notStarted = model.firstScan {
            primary("Find My Moments") { model.startFirstScan() }
        }
        // While scanning there is no button. Onboarding ends by itself when the scan finishes.
    }
}

private struct StatusLine: View {
    let text: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
#endif
