import Foundation

/// In-memory `ShareService` for previews and tests.
public actor InMemoryShareService: ShareService {
    public private(set) var published: [Post] = []
    private var incoming: [Post]
    private let author: Friend
    private let clock: Clock

    public init(author: Friend, incoming: [Post] = [], clock: Clock = SystemClock()) {
        self.author = author
        self.incoming = incoming
        self.clock = clock
    }

    public func share(_ suggestion: Suggestion, imageData: Data, with friendIDs: [Friend.ID]) throws -> Post {
        guard !friendIDs.isEmpty else { throw ShareError.noRecipients }
        let post = Post(
            authorID: author.id,
            authorName: author.displayName,
            caption: suggestion.caption,
            provenance: suggestion.provenance,
            createdAt: clock.now
        )
        published.append(post)
        return post
    }

    /// Expired posts are hidden, the same as in the real feed.
    public func feed() -> [Post] { Post.visible(incoming, now: clock.now) }

    public func myPosts() -> [Post] { Post.chronological(published) }

    public func deletePost(_ id: Post.ID) { published.removeAll { $0.id == id } }

    public func deleteExpiredPosts(now: Date) -> Int {
        let expired = Set(PostExpiry.expiredOwnPosts(published, ownerID: author.id, now: now).map(\.id))
        published.removeAll { expired.contains($0.id) }
        return expired.count
    }

    public func deleteAllData() {
        published.removeAll()
        incoming.removeAll()
    }
}

public enum ShareError: Error, Equatable {
    case noRecipients
    case notSignedIn
    case notImplemented
}

/// In-memory `FriendDirectory` on top of `FriendRoster`. Invites by contact use the contact as friend id.
public actor InMemoryFriendDirectory: FriendDirectory {
    public private(set) var roster: FriendRoster
    public static let inviteURL = URL(string: "https://example.com/invite")!

    public init(_ friends: [Friend] = [], limit: Int = FriendRoster.defaultLimit) {
        roster = FriendRoster(
            friends.map {
                $0.status == .accepted
                    ? Friendship(id: $0.id, displayName: $0.displayName, outgoing: .accepted, incoming: .accepted)
                    : Friendship(id: $0.id, displayName: $0.displayName, outgoing: .invited)
            },
            limit: limit
        )
    }

    public func friends() -> [Friend] { roster.active.map(\.asFriend) }

    public func friendships() -> [Friendship] { roster.friendships }

    public func makeInviteURL() -> URL { Self.inviteURL }

    public func invite(_ contact: InviteContact) throws -> URL {
        let id = switch contact {
        case .email(let v), .phone(let v): v
        }
        try roster.apply(.sentInvite, to: id, displayName: id)
        return Self.inviteURL
    }

    public func shareBack(with friendID: Friend.ID) throws -> URL {
        guard roster[friendID] != nil else { throw FriendshipError.unknownFriend(friendID) }
        try roster.apply(.sentInvite, to: friendID)
        return Self.inviteURL
    }

    /// Test hook: simulates a CloudKit event for one friend.
    public func simulate(_ event: FriendshipEvent, for friendID: Friend.ID, displayName: String = "") throws {
        try roster.apply(event, to: friendID, displayName: displayName)
    }

    public func remove(_ friendID: Friend.ID) throws {
        guard roster[friendID] != nil else { throw FriendshipError.unknownFriend(friendID) }
        try roster.apply(.iRemoved, to: friendID)
    }

    public func reset() { roster.removeAll() }
}

public struct FixedClock: Clock {
    public var now: Date

    public init(_ now: Date) {
        self.now = now
    }
}
