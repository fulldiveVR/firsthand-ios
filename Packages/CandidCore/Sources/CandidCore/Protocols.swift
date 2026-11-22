import Foundation

public enum PhotoAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case limited
    case authorized

    public var canRead: Bool { self == .limited || self == .authorized }
    /// With limited access only user-selected photos are visible, so new moments are never found.
    /// The app treats `.limited` as a degraded mode and asks for full access.
    public var isDegraded: Bool { self == .limited }
}

public protocol PhotoLibrary: Sendable {
    func authorizationStatus() async -> PhotoAuthorization
    func requestAuthorization() async -> PhotoAuthorization
    /// Newest first.
    func recentAssets(since: Date, limit: Int) async throws -> [PhotoAsset]
    /// Full-size image data for sharing. Returns `nil` if the asset is gone.
    func imageData(for assetID: String) async throws -> Data?
}

public protocol ImageAnalyzer: Sendable {
    func analyze(_ asset: PhotoAsset) async throws -> AnalysisSignals
}

public protocol ShareService: Sendable {
    /// Publishes one approved photo to the given friends only.
    func share(_ suggestion: Suggestion, imageData: Data, with friendIDs: [Friend.ID]) async throws -> Post
    /// Posts that friends shared with this user.
    func feed() async throws -> [Post]
    /// Removes everything this user published.
    func deleteAllData() async throws
}

public protocol FriendDirectory: Sendable {
    func friends() async throws -> [Friend]
    /// Returns a link the user can send to invite a friend.
    func makeInviteURL() async throws -> URL
    func remove(_ friendID: Friend.ID) async throws
}

public protocol Notifier: Sendable {
    func requestAuthorization() async -> Bool
    func notifySuggestionReady(_ suggestion: Suggestion) async
}

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}
