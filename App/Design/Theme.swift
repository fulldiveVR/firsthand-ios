#if os(iOS)
import FirsthandCore
import SwiftUI

/// Design tokens. Every radius and spacing value in the app comes from here.
enum Theme {
    enum Radius {
        /// The Today hero card. Matches the large concentric corners of iOS 26.
        static let hero: CGFloat = 32
        /// Friends' moment photos and non-photo cards on the home screen.
        static let card: CGFloat = 24
        /// The Wallet-style invite card.
        static let pass: CGFloat = 28
        /// Photo thumbs in the share sheet.
        static let medium: CGFloat = 16
        /// Small thumbs and tiles.
        static let small: CGFloat = 12
    }

    enum Spacing {
        /// Side margin of the home screen.
        static let margin: CGFloat = 16
        /// Inner padding of cards.
        static let cardPadding: CGFloat = 20
        /// Between two cards in one section.
        static let betweenCards: CGFloat = 28
        /// Between two sections.
        static let betweenSections: CGFloat = 36
    }

    /// The moment photo aspect ratio (width / height).
    static let momentAspect: CGFloat = 4 / 5

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension ShapeStyle where Self == Color {
    /// App accent, "Firsthand Sunrise". Light, dark and high-contrast variants live in the asset catalog.
    static var sunrise: Color { Color.accentColor }
}

/// Non-photo cards on the home screen: quaternary fill in light mode, secondary background in dark mode.
/// Content, not controls, so no glass.
struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = Theme.Radius.card

    func body(content: Content) -> some View {
        content.background {
            if colorScheme == .dark {
                Theme.shape(radius).fill(Color(.secondarySystemBackground))
            } else {
                Theme.shape(radius).fill(.fill.quaternary)
            }
        }
    }
}

extension View {
    func cardBackground(radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

extension Date {
    /// "Now", "12m", "3h", "Yesterday", "Mon", "Nov 12".
    func shortRelative(now: Date = Date()) -> String {
        ShortRelativeTime().string(for: self, now: now)
    }
}
#endif
