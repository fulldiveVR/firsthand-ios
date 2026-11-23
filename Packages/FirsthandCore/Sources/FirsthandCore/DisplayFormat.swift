import Foundation

/// Short feed time, like Apple feeds: "Now", "12m", "3h", "Yesterday", "Mon", "Nov 12".
public struct ShortRelativeTime: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    public func string(for date: Date, now: Date) -> String {
        let age = now.timeIntervalSince(date)
        if age < 60 { return String(localized: "Now") }
        if age < 60 * 60 {
            return Duration.seconds(Int(age / 60) * 60)
                .formatted(.units(allowed: [.minutes], width: .narrow).locale(locale))
        }
        if age < 24 * 60 * 60 {
            return Duration.seconds(Int(age / 3600) * 3600)
                .formatted(.units(allowed: [.hours], width: .narrow).locale(locale))
        }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if days <= 1 { return String(localized: "Yesterday") }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if days < 7 {
            style = style.weekday(.abbreviated)
        } else {
            style = style.month(.abbreviated).day()
        }
        return date.formatted(style)
    }
}

/// Monogram avatar data: initials and a stable color slot from the friend id.
public enum Monogram {
    /// Number of avatar colors. The app maps slots to system colors.
    public static let colorCount = 7

    /// Up to two initials from the first and last word. "?" for an empty name.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).filter { $0.first?.isLetter ?? false }
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    /// Stable across launches and devices (FNV-1a), unlike `hashValue`.
    public static func colorIndex(for id: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(colorCount))
    }
}
