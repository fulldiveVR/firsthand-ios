#if os(iOS)
import FirsthandCore
import SwiftUI

/// Onboarding, one idea per page. Each system prompt opens only from a button on the page that explains it.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: OnboardingPage = Self.initialPage
    @State private var forward = true

    private static var initialPage: OnboardingPage {
        #if DEBUG
        if let index = AppModel.debugOnboardingPage, let page = OnboardingPage(rawValue: index) { return page }
        #endif
        return .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 28) {
                    page.illustration
                    OnboardingText(page: page)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(page)
            .transition(pageTransition)
            footer
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .background {
            LinearGradient(
                colors: [page.palette.primary.opacity(0.16), Color(.systemBackground)],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
            .animation(.easeInOut, value: page)
        }
        .onChange(of: model.appleUserID) { _, id in
            if id != nil && page == .signIn { next() }
        }
    }

    // MARK: Navigation

    private var isScanning: Bool {
        if case .scanning = model.firstScan { true } else { false }
    }

    private var header: some View {
        HStack {
            if page != .welcome && !isScanning {
                Button {
                    go(to: page.previous)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .labelStyle(.titleAndIcon)
            }
            Spacer()
            PageIndicator(current: page.rawValue, count: OnboardingPage.allCases.count, tint: page.palette.primary)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func go(to target: OnboardingPage?) {
        guard let target else { return }
        forward = target.rawValue > page.rawValue
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4)) { page = target }
    }

    private func next() { go(to: page.next) }

    // MARK: Actions per page

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            switch page {
            case .welcome:
                primary("Get Started", action: next)
            case .howItWorks, .privacy, .sharing:
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
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
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
            StatusLine(
                text: "Limited access: the AI sees only the photos you selected and cannot find new moments.",
                symbol: "exclamationmark.circle.fill", color: .orange
            )
            primary("Allow Full Access in Settings") { SystemSettings.open() }
            secondary("Continue with Limited Access", action: next)
        case .denied:
            StatusLine(
                text: "Photo access is off. \(AppInfo.name) needs it to find moments. In Settings, choose Photos, then Full Access.",
                symbol: "xmark.circle.fill", color: .red
            )
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
            StatusLine(
                text: "Notifications are off. You can turn them on later in Settings.",
                symbol: "bell.slash.fill", color: .secondary
            )
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
            primary("Back to Photo Access") { go(to: .photos) }
        } else if model.appleUserID == nil {
            primary("Back to Sign In") { go(to: .signIn) }
        } else {
            switch model.firstScan {
            case .notStarted:
                primary("Find My Moments") { model.startFirstScan() }
            case .scanning(let progress):
                ProgressView(progress.subtitle)
                    .padding(16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

// MARK: Pages

enum OnboardingPage: Int, CaseIterable {
    case welcome, howItWorks, privacy, photos, notifications, sharing, signIn, firstScan

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }

    var palette: IllustrationPalette {
        switch self {
        case .welcome: .welcome
        case .howItWorks: .howItWorks
        case .privacy: .privacy
        case .photos: .photos
        case .notifications: .notifications
        case .sharing: .sharing
        case .signIn: .signIn
        case .firstScan: .firstScan
        }
    }

    @ViewBuilder
    var illustration: some View {
        switch self {
        case .welcome: WelcomeIllustration()
        case .howItWorks: HowItWorksIllustration()
        case .privacy: PrivacyIllustration()
        case .photos: PhotosAccessIllustration()
        case .notifications: NotificationsIllustration()
        case .sharing: SharingIllustration()
        case .signIn: SignInIllustration()
        case .firstScan: FirstScanIllustration()
        }
    }
}

private struct OnboardingText: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(page.palette.primary)
            }
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !points.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(points, id: \.text) { point in
                        Label {
                            Text(point.text)
                        } icon: {
                            Image(systemName: point.symbol)
                                .foregroundStyle(page.palette.primary)
                                .frame(width: 28)
                        }
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Point {
        var symbol: String
        var text: String
    }

    private var eyebrow: String? {
        page == .welcome ? AppInfo.name : nil
    }

    private var title: String {
        switch page {
        case .welcome: String(localized: "Live it. We'll find the moment.")
        case .howItWorks: String(localized: "One moment a day. You say yes or no.")
        case .privacy: String(localized: "Private by design")
        case .photos: String(localized: "Let the AI see your recent photos")
        case .notifications: String(localized: "Know when your moment is ready")
        case .sharing: String(localized: "Friends only. Gone after 30 days.")
        case .signIn: String(localized: "Sign in with Apple")
        case .firstScan: String(localized: "Find your first moment")
        }
    }

    private var message: String {
        switch page {
        case .welcome:
            String(localized: "\(AppInfo.name) finds a meaningful moment in your recent photos and suggests a camera-original photo to share with your friends. Only when you say yes.")
        case .howItWorks:
            String(localized: "The AI picks one moment. You only choose Share or Skip. You never scroll or pick a photo yourself.")
        case .privacy:
            String(localized: "Analysis happens on this iPhone. Your photos never leave it unless you tap Share and confirm with Face ID.")
        case .photos:
            String(localized: "Full access lets the AI look across your recent photos to find a moment. With limited access it sees only the photos you select, so it cannot find new ones.")
        case .notifications:
            String(localized: "We tell you when your moment is ready and when a friend shares. The notification never shows the photo.")
        case .sharing:
            String(localized: "You share only with friends you invite, through iCloud. Friends can see a moment for 30 days. Then it disappears from their feed and your iCloud.")
        case .signIn:
            String(localized: "Your Apple account is your identity for friends. We get no photos, and we do not ask for your email.")
        case .firstScan:
            String(localized: "\(AppInfo.name) looks at your photos from the last few days, on this iPhone. You can leave the app while it works.")
        }
    }

    private var points: [Point] {
        switch page {
        case .welcome:
            []
        case .howItWorks:
            [
                Point(symbol: "sparkles", text: String(localized: "At most one suggestion a day, only when a moment stands out.")),
                Point(symbol: "faceid", text: String(localized: "Face ID confirms every share.")),
                Point(symbol: "person.2.fill", text: String(localized: "Friends only. No public profile, no likes.")),
            ]
        case .privacy:
            [
                Point(symbol: "iphone", text: String(localized: "On-device AI. No photo is uploaded to analyze it.")),
                Point(symbol: "icloud.fill", text: String(localized: "Shared photos live in your iCloud. There is no photo server.")),
                Point(symbol: "hand.raised.fill", text: String(localized: "No ads and no tracking.")),
            ]
        case .photos:
            [
                Point(symbol: "eye", text: String(localized: "We read photos from the last few days: the picture, its date and a rough place.")),
                Point(symbol: "eye.slash", text: String(localized: "We skip screenshots and never edit or delete a photo.")),
                Point(symbol: "lock.fill", text: String(localized: "Nothing leaves this iPhone unless you share it.")),
            ]
        case .notifications:
            [
                Point(symbol: "sparkles", text: String(localized: "\"A moment is ready\", at most once a day.")),
                Point(symbol: "person.2.fill", text: String(localized: "\"A friend shared a moment.\"")),
            ]
        case .sharing:
            [
                Point(symbol: "link", text: String(localized: "Invite with a link or a QR code. Up to \(FriendRoster.defaultLimit) friends.")),
                Point(symbol: "calendar.badge.clock", text: String(localized: "Each moment shows how many days it has left.")),
                Point(symbol: "trash", text: String(localized: "Delete your moment any time.")),
            ]
        case .signIn:
            [
                Point(symbol: "person.crop.circle", text: String(localized: "Friends see only the name you choose.")),
                Point(symbol: "photo", text: String(localized: "Signing in gives us no access to your photos.")),
            ]
        case .firstScan:
            []
        }
    }
}

private struct PageIndicator: View {
    let current: Int
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary))
                    .frame(width: i == current ? 20 : 7, height: 7)
            }
        }
        .animation(.smooth, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

private struct StatusLine: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
