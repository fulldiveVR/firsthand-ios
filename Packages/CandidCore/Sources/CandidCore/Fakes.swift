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

    public func feed() -> [Post] { Post.chronological(incoming) }

    public func deleteAllData() { published.removeAll() }
}

public enum ShareError: Error, Equatable {
    case noRecipients
    case notSignedIn
    case notImplemented
}

public actor InMemoryFriendDirectory: FriendDirectory {
    private var list: [Friend]

    public init(_ friends: [Friend] = []) {
        list = friends
    }

    public func friends() -> [Friend] { list }

    public func makeInviteURL() -> URL { URL(string: "https://example.com/invite")! }

    public func remove(_ friendID: Friend.ID) { list.removeAll { $0.id == friendID } }
}

public struct FixedClock: Clock {
    public var now: Date

    public init(_ now: Date) {
        self.now = now
    }
}
