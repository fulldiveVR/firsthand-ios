#if os(iOS)
import FirsthandCore
import SwiftUI

// Onboarding heroes. One style for every page: real-looking photo cards from the bundled sample photos
// (abstract renders made for this app), glass controls, one accent color.
// Each animation runs once per appearance. With Reduce Motion the hero is static.
// The heroes are decorative and hidden from VoiceOver.

struct OnboardingHero: View {
    @Environment(AppModel.self) private var model
    let page: OnboardingPage

    var body: some View {
        Group {
            switch page {
            case .welcome: WelcomeHero()
            case .howItWorks: HowItWorksHero()
            case .privacy: PrivacyHero()
            case .photos: PhotosHero()
            case .notifications: NotificationHero()
            case .sharing: FriendsHero()
            case .signIn: AppGlyph(size: 120)
            case .firstScan: FirstScanHero()
            }
        }
        // Decorative: the hero keeps its size at large text sizes.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityHidden(true)
    }
}

/// A sample photo as a rounded card.
private struct SampleCard: View {
    let name: String
    var width: CGFloat
    var radius: CGFloat = 24

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width / Theme.momentAspect)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

/// Runs `content(false)` then animates to `content(true)` once on appear. Static with Reduce Motion.
private struct OnceAnimation<Content: View>: View {
    var delay: Double = 0.15
    var animation: Animation = .smooth(duration: 0.9)
    @ViewBuilder var content: (Bool) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var done = false

    var body: some View {
        content(done || reduceMotion)
            .onAppear {
                guard !reduceMotion, !done else { return }
                withAnimation(animation.delay(delay)) { done = true }
            }
    }
}

/// 1. Three fanned cards. The center card has a glass "Today" chip. The cards float in once.
private struct WelcomeHero: View {
    var body: some View {
        OnceAnimation(animation: .smooth(duration: 1.2)) { settled in
            ZStack {
                SampleCard(name: "sample-mountain", width: 150)
                    .rotationEffect(.degrees(settled ? -11 : -4))
                    .offset(x: settled ? -88 : -30, y: settled ? 16 : 30)
                SampleCard(name: "sample-beach", width: 150)
                    .rotationEffect(.degrees(settled ? 11 : 4))
                    .offset(x: settled ? 88 : 30, y: settled ? 16 : 30)
                SampleCard(name: "sample-lake", width: 170, radius: 28)
                    .overlay(alignment: .top) {
                        Label("Today", systemImage: "sparkles")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.clear, in: .capsule)
                            .padding(.top, 12)
                    }
                    .offset(y: settled ? -6 : 10)
            }
            .opacity(settled ? 1 : 0.6)
        }
    }
}

/// 2. A hero card with glass Skip and Share. Share pulses once.
private struct HowItWorksHero: View {
    var body: some View {
        OnceAnimation(delay: 0.5, animation: .spring(duration: 0.5, bounce: 0.5)) { pulsed in
            SampleCard(name: "sample-park", width: 210, radius: 28)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                }
                .overlay(alignment: .bottom) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Skip")
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .glassEffect(.regular, in: .capsule)
                            Label("Share", systemImage: "faceid")
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .glassEffect(.regular.tint(.accentColor), in: .capsule)
                                .scaleEffect(pulsed ? 1 : 1.12)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
                }
        }
    }
}

/// 3. A photo card with an iPhone glass badge. The lock draws on once.
private struct PrivacyHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLock = false

    var body: some View {
        SampleCard(name: "sample-mountain", width: 200, radius: 28)
            .overlay {
                ZStack {
                    Image(systemName: "iphone")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.white)
                    if showLock || reduceMotion {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .transition(.symbolEffect(.drawOn))
                    }
                }
                .frame(width: 112, height: 112)
                .glassEffect(.clear, in: .circle)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.3)) { showLock = true }
            }
    }
}

/// 4. Six photo tiles with one scan shimmer.
private struct PhotosHero: View {
    private let names = ["sample-lake", "sample-beach", "sample-mountain", "sample-park", "sample-city", "sample-food"]

    var body: some View {
        OnceAnimation(delay: 0.3, animation: .easeInOut(duration: 1.4)) { scanned in
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            Image(names[row * 3 + column])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 84, height: 105)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        }
                    }
                }
            }
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 80)
                    .rotationEffect(.degrees(12))
                    .offset(x: scanned ? proxy.size.width + 40 : -120)
                    .blendMode(.plusLighter)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }
    }
}

/// 5. A Lock Screen with a glass notification: "A moment is ready". No photo in the notification.
private struct NotificationHero: View {
    var body: some View {
        OnceAnimation(delay: 0.4, animation: .spring(duration: 0.6, bounce: 0.25)) { shown in
            SampleCard(name: "sample-city", width: 232, radius: 32)
                .overlay(alignment: .top) {
                    VStack(spacing: 2) {
                        Text(Date(), format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        Text(Date(), format: .dateTime.weekday(.wide).month().day())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.top, 22)
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 10) {
                        AppGlyph(size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AppInfo.name).font(.caption.weight(.semibold))
                            Text("A moment is ready").font(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("now").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(10)
                    .offset(y: shown ? 0 : 30)
                    .opacity(shown ? 1 : 0)
                }
        }
    }
}

/// 6. Three monogram avatars around a card, with a "30 days" chip.
private struct FriendsHero: View {
    var body: some View {
        OnceAnimation { shown in
            SampleCard(name: "sample-beach", width: 170, radius: 28)
                .overlay(alignment: .bottom) {
                    Label("30 days", systemImage: "hourglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.clear, in: .capsule)
                        .padding(.bottom, 14)
                }
                .overlay {
                    ZStack {
                        avatar("hero-mia", "Mia Chen").offset(x: shown ? -100 : -60, y: -70)
                        avatar("hero-leo", "Leo Novak").offset(x: shown ? 102 : 60, y: -18)
                        avatar("hero-ana", "Ana Souza").offset(x: shown ? -96 : -60, y: 62)
                    }
                    .opacity(shown ? 1 : 0)
                }
        }
    }

    private func avatar(_ id: String, _ name: String) -> some View {
        Avatar(id: id, name: name, size: 52)
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

/// 8. The live analyzing card.
private struct FirstScanHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AnalyzingCard(
            progress: progress,
            failed: false,
            onStop: {},
            onRetry: {},
            showsButton: false,
            compact: true
        )
        .frame(width: 224)
    }

    private var progress: AnalysisProgress? {
        if case .scanning(let p) = model.firstScan { return p }
        return nil
    }
}

/// The app glyph: a sunrise in the accent color on a rounded tile. Used until the app has an icon.
struct AppGlyph: View {
    var size: CGFloat = 120

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.mix(with: .pink, by: 0.35)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.accentColor.opacity(size > 60 ? 0.35 : 0), radius: 20, y: 10)
    }
}
#endif
