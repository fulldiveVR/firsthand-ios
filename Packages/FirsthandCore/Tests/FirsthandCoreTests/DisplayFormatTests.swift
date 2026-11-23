import Foundation
import Testing
@testable import FirsthandCore

@Suite struct ShortRelativeTimeTests {
    let format = ShortRelativeTime(calendar: utcCalendar, locale: Locale(identifier: "en_US"))
    /// 2027-01-15 12:00 UTC, a Friday.
    let now = Date(timeIntervalSince1970: 1_800_014_400)

    func string(ago seconds: TimeInterval) -> String {
        format.string(for: now.addingTimeInterval(-seconds), now: now)
    }

    @Test func underAMinuteIsNow() {
        #expect(string(ago: 0) == "Now")
        #expect(string(ago: 59) == "Now")
        #expect(format.string(for: now.addingTimeInterval(30), now: now) == "Now")
    }

    @Test func minutesAndHoursAreNarrow() {
        #expect(string(ago: 12 * 60 + 5) == "12m")
        #expect(string(ago: 3 * 3600 + 120) == "3h")
        #expect(string(ago: 23 * 3600) == "23h")
    }

    @Test func yesterdayThenWeekdayThenDate() {
        #expect(string(ago: 25 * 3600) == "Yesterday")
        #expect(string(ago: 3 * 86_400) == "Tue")
        #expect(string(ago: 6 * 86_400) == "Sat")
        #expect(string(ago: 10 * 86_400) == "Jan 5")
    }
}

@Suite struct MonogramTests {
    @Test func initialsFromFirstAndLastWord() {
        #expect(Monogram.initials("Mia Chen") == "MC")
        #expect(Monogram.initials("mia") == "M")
        #expect(Monogram.initials("Ana Maria Souza") == "AS")
        #expect(Monogram.initials("  ") == "?")
        #expect(Monogram.initials("") == "?")
    }

    @Test func colorIsStableAndInRange() {
        let a = Monogram.colorIndex(for: "_abc123")
        #expect(a == Monogram.colorIndex(for: "_abc123"))
        #expect((0..<Monogram.colorCount).contains(a))
        let spread = Set((0..<50).map { Monogram.colorIndex(for: "friend-\($0)") })
        #expect(spread.count > 3)
    }
}
