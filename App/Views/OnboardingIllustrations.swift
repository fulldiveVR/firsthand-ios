#if os(iOS)
import SwiftUI

// Onboarding graphics, built only from SwiftUI shapes, gradients and SF Symbols.
// Every animation stops when Reduce Motion is on. The graphics are decorative and hidden from VoiceOver.

/// Colors of one onboarding page.
struct IllustrationPalette {
    var primary: Color
    var secondary: Color

    static let welcome = IllustrationPalette(primary: .orange, secondary: .pink)
    static let howItWorks = IllustrationPalette(primary: .indigo, secondary: .purple)
    static let privacy = IllustrationPalette(primary: .teal, secondary: .blue)
    static let photos = IllustrationPalette(primary: .orange, secondary: .yellow)
    static let notifications = IllustrationPalette(primary: .red, secondary: .pink)
    static let sharing = IllustrationPalette(primary: .green, secondary: .teal)
    static let signIn = IllustrationPalette(primary: .blue, secondary: .indigo)
    static let firstScan = IllustrationPalette(primary: .purple, secondary: .blue)

    var gradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The shared backdrop: soft rings and a gradient disc.
struct IllustrationStage<Content: View>: View {
    let palette: IllustrationPalette
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let compact = typeSize.isAccessibilitySize
        ZStack {
            Circle()
                .fill(palette.gradient.opacity(0.22))
                .frame(width: 230, height: 230)
            Circle()
                .strokeBorder(palette.primary.opacity(0.22), lineWidth: 1)
                .frame(width: 280, height: 280)
            Circle()
                .fill(palette.secondary.opacity(0.25))
                .frame(width: 90, height: 90)
                .blur(radius: 24)
                .offset(x: 90, y: -80)
            Circle()
                .fill(palette.primary.opacity(0.2))
                .frame(width: 70, height: 70)
                .blur(radius: 20)
                .offset(x: -100, y: 85)
            content
        }
        .frame(width: 300, height: 290)
        .scaleEffect(compact ? 0.62 : 0.86)
        .frame(height: compact ? 180 : 250)
        .accessibilityHidden(true)
    }
}

/// Repeats a two-state animation. With Reduce Motion it shows the first state only.
struct Looping<Content: View>: View {
    var duration: Double = 2
    @ViewBuilder var content: (Bool) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(false)
        } else {
            PhaseAnimator([false, true]) { phase in
                content(phase)
            } animation: { _ in
                .easeInOut(duration: duration)
            }
        }
    }
}

/// A stylized photo: gradient card with a symbol. No real photo is ever shown here.
struct PhotoTile: View {
    var symbol: String
    var colors: [Color]
    var width: CGFloat = 120
    var height: CGFloat = 150

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: width * 0.36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 3)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

/// A round badge with a symbol.
struct SymbolBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 48

    var body: some View {
        Circle()
            .fill(color.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.35), radius: 8, y: 4)
    }
}

// MARK: Pages

/// Page 1: a fan of photos, the middle one picked.
struct WelcomeIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IllustrationStage(palette: .welcome) {
            Looping(duration: 2.4) { open in
                ZStack {
                    PhotoTile(symbol: "mountain.2.fill", colors: [.teal, .blue])
                        .rotationEffect(.degrees(open ? -16 : -11))
                        .offset(x: open ? -62 : -52, y: 10)
                    PhotoTile(symbol: "cup.and.saucer.fill", colors: [.brown, .orange])
                        .rotationEffect(.degrees(open ? 16 : 11))
                        .offset(x: open ? 62 : 52, y: 10)
                    PhotoTile(symbol: "figure.2.arms.open", colors: [.orange, .pink], width: 132, height: 166)
                        .scaleEffect(open ? 1.04 : 1)
                    SymbolBadge(symbol: "sparkles", color: .yellow, size: 52)
                        .symbolEffect(.breathe, isActive: !reduceMotion)
                        .offset(x: 56, y: -82)
                }
            }
        }
    }
}

/// Page 2: one moment, and only two choices.
struct HowItWorksIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IllustrationStage(palette: .howItWorks) {
            VStack(spacing: 14) {
                PhotoTile(symbol: "sun.horizon.fill", colors: [.purple, .orange], width: 140, height: 150)
                    .overlay(alignment: .topTrailing) {
                        Text("1")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.indigo.gradient))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 12, y: -12)
                    }
                HStack(spacing: 28) {
                    SymbolBadge(symbol: "xmark", color: .gray, size: 50)
                    SymbolBadge(symbol: "faceid", color: .indigo, size: 58)
                        .symbolEffect(.breathe, isActive: !reduceMotion)
                }
            }
            .offset(y: 6)
        }
    }
}

/// Page 3: the iPhone keeps the photos. A lock, nothing leaves.
struct PrivacyIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IllustrationStage(palette: .privacy) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.background)
                    .frame(width: 128, height: 220)
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(IllustrationPalette.privacy.gradient, lineWidth: 6)
                    }
                    .overlay(alignment: .top) {
                        Capsule().fill(.primary.opacity(0.8)).frame(width: 38, height: 10).padding(.top, 12)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(IllustrationPalette.privacy.gradient)
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                    HStack(spacing: 6) {
                        ForEach(0..<3) { i in
                            RoundedRectangle(cornerRadius: 5)
                                .fill([Color.teal, .blue, .cyan][i].opacity(0.7))
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                SymbolBadge(symbol: "icloud.slash.fill", color: .blue, size: 44)
                    .offset(x: 88, y: -70)
                SymbolBadge(symbol: "cpu.fill", color: .teal, size: 40)
                    .offset(x: -86, y: 64)
            }
        }
    }
}

/// Page 4: a photo stack with a scan line. The AI looks across recent photos.
struct PhotosAccessIllustration: View {
    var body: some View {
        IllustrationStage(palette: .photos) {
            ZStack {
                PhotoTile(symbol: "tree.fill", colors: [.green, .teal], width: 130, height: 160)
                    .rotationEffect(.degrees(-9))
                    .offset(x: -24, y: -8)
                PhotoTile(symbol: "fork.knife", colors: [.orange, .red], width: 130, height: 160)
                    .rotationEffect(.degrees(7))
                    .offset(x: 22, y: -4)
                PhotoTile(symbol: "figure.hiking", colors: [.yellow, .orange], width: 140, height: 172)
                    .overlay {
                        Looping(duration: 1.8) { down in
                            ScanLine(color: .white)
                                .frame(width: 150)
                                .offset(y: down ? 74 : -74)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .offset(y: 8)
                SymbolBadge(symbol: "photo.stack.fill", color: .orange, size: 46)
                    .offset(x: 90, y: -86)
            }
        }
    }
}

/// A bright line with a sparkle at its end.
struct ScanLine: View {
    var color: Color

    var body: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0), color, color.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 4)
                .shadow(color: color, radius: 6)
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: .yellow, radius: 4)
                .offset(x: -18)
        }
    }
}

/// Page 5: a bell with a badge and a quiet banner.
struct NotificationsIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IllustrationStage(palette: .notifications) {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(IllustrationPalette.welcome.gradient)
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: "sparkles").font(.caption.bold()).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(.primary.opacity(0.55)).frame(width: 110, height: 8)
                        Capsule().fill(.primary.opacity(0.25)).frame(width: 80, height: 8)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                Image(systemName: "bell.fill")
                    .font(.system(size: 92, weight: .semibold))
                    .foregroundStyle(IllustrationPalette.notifications.gradient)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.6)), isActive: !reduceMotion)
                    .overlay(alignment: .topTrailing) {
                        Text("1")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.red))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 8, y: -4)
                    }
            }
        }
    }
}

/// Page 6: two friends, a link, and a calendar with "30".
struct SharingIllustration: View {
    var body: some View {
        IllustrationStage(palette: .sharing) {
            ZStack {
                HStack(spacing: 0) {
                    SymbolBadge(symbol: "person.fill", color: .green, size: 62)
                    Image(systemName: "link")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44)
                    SymbolBadge(symbol: "person.fill", color: .teal, size: 62)
                }
                .offset(y: -70)
                Looping(duration: 2.2) { up in
                    CalendarThirty()
                        .rotationEffect(.degrees(up ? 3 : -3))
                        .offset(y: up ? 44 : 50)
                }
            }
        }
    }
}

/// A calendar page that reads "30 days".
struct CalendarThirty: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.red.gradient)
                .frame(height: 30)
                .overlay {
                    HStack(spacing: 34) {
                        Circle().fill(.white).frame(width: 8, height: 8)
                        Circle().fill(.white).frame(width: 8, height: 8)
                    }
                }
            VStack(spacing: -4) {
                Text("30")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text("DAYS")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 120, height: 124)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

/// Page 7: an identity with a key. No photos, no email.
struct SignInIllustration: View {
    var body: some View {
        IllustrationStage(palette: .signIn) {
            ZStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 130))
                    .foregroundStyle(.white, IllustrationPalette.signIn.gradient)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                SymbolBadge(symbol: "key.fill", color: .indigo, size: 50)
                    .offset(x: 52, y: 50)
                NoChip(symbol: "photo.fill")
                    .offset(x: -96, y: -64)
                NoChip(symbol: "envelope.fill")
                    .offset(x: 96, y: -64)
            }
        }
    }
}

/// A symbol with a slash badge: "we do not get this".
struct NoChip: View {
    var symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 54, height: 54)
            .background(.regularMaterial, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "nosign")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.red)
                    .background(Circle().fill(.background).padding(-2))
            }
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
    }
}

/// Page 8: a grid of photos with a sweep, and one tile picked.
struct FirstScanIllustration: View {
    private let symbols = ["sun.max.fill", "leaf.fill", "cup.and.saucer.fill",
                           "figure.walk", "heart.fill", "music.note",
                           "building.2.fill", "bicycle", "moon.stars.fill"]
    private let colors: [[Color]] = [[.orange, .yellow], [.green, .teal], [.brown, .orange],
                                     [.blue, .cyan], [.pink, .red], [.purple, .indigo],
                                     [.gray, .blue], [.teal, .green], [.indigo, .purple]]

    var body: some View {
        IllustrationStage(palette: .firstScan) {
            ZStack {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<3) { row in
                        GridRow {
                            ForEach(0..<3) { column in
                                let i = row * 3 + column
                                PhotoTile(symbol: symbols[i], colors: colors[i], width: 58, height: 58)
                                    .scaleEffect(i == 4 ? 1.18 : 1)
                                    .zIndex(i == 4 ? 1 : 0)
                                    .overlay {
                                        if i == 4 {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(.yellow, lineWidth: 3)
                                                .scaleEffect(1.18)
                                        }
                                    }
                            }
                        }
                    }
                }
                Looping(duration: 2) { right in
                    ScanLine(color: .white)
                        .frame(width: 200)
                        .rotationEffect(.degrees(90))
                        .offset(x: right ? 92 : -92)
                }
            }
        }
    }
}
#endif
