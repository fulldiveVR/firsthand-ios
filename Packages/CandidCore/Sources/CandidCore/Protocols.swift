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
    /// Posts that friends shared with this user, newest first. Fetches changes since the last call.
    func feed() async throws -> [Post]
    /// Posts this user published, newest first.
    func myPosts() async throws -> [Post]
    /// Deletes one of this user's posts. Friends lose it on their next sync.
    func deletePost(_ id: Post.ID) async throws
    /// Removes everything this user published and every local copy of friends' posts.
    func deleteAllData() async throws
}

public protocol FriendDirectory: Sendable {
    func friends() async throws -> [Friend]
    /// Both sides of every friendship, matched with CloudKit.
    func friendships() async throws -> [Friendship]
    /// Returns the link of this user's share. Only participants can open it.
    func makeInviteURL() async throws -> URL
    /// Adds a participant to this user's share and returns the link to send. Throws at the friend cap.
    func invite(_ contact: InviteContact) async throws -> URL
    /// After this user accepted a friend's share: adds that friend to this user's share and returns the link.
    func shareBack(with friendID: Friend.ID) async throws -> URL
    /// Removes the friend from this user's share and leaves the friend's share.
    func remove(_ friendID: Friend.ID) async throws
    /// Forgets all local friend state, for "Delete all data".
    func reset() async throws
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
