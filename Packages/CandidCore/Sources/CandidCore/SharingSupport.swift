import Foundation

/// How the user identifies a friend for an invite. CloudKit turns this into a share participant.
/// The value is used only for the lookup and is never stored by the app.
public enum InviteContact: Sendable, Hashable {
    case email(String)
    case phone(String)

    /// Accepts an email address or a phone number with at least 7 digits.
    /// Phone numbers keep a leading "+" and digits only.
    public static func parse(_ raw: String) -> InviteContact? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("@") {
            let parts = text.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
                  !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
                  !text.contains(where: \.isWhitespace)
            else { return nil }
            return .email(text.lowercased())
        }
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        guard text.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let digits = text.filter(\.isNumber)
        guard digits.count >= 7, digits.count <= 15 else { return nil }
        return .phone((text.hasPrefix("+") ? "+" : "") + digits)
    }
}

/// Tells friends that a new post exists. Phase P3 uses a CloudKit database subscription.
/// A stateless push relay can replace it later without changes elsewhere.
public protocol FriendAlertChannel: Sendable {
    /// Called at launch. Must be idempotent.
    func setUp() async throws
    /// Called by "Delete all data".
    func tearDown() async throws
}

public struct NoFriendAlerts: FriendAlertChannel {
    public init() {}
    public func setUp() async throws {}
    public func tearDown() async throws {}
}
