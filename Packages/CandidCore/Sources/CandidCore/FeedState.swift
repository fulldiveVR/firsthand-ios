import Foundation

/// A record id is unique only inside one zone, so the feed key is owner plus record name.
public struct FeedItemID: Sendable, Hashable, Codable, Comparable {
    public var ownerID: String
    public var recordName: String

    public init(ownerID: String, recordName: String) {
        self.ownerID = ownerID
        self.recordName = recordName
    }

    public static func < (a: FeedItemID, b: FeedItemID) -> Bool {
        (a.ownerID, a.recordName) < (b.ownerID, b.recordName)
    }
}

extension Post {
    /// Record name of a post is its UUID string. The zone owner is the author.
    public var feedItemID: FeedItemID { FeedItemID(ownerID: authorID, recordName: id.uuidString) }
}

/// One batch of changes from CloudKit (record zone changes, or a full refetch).
public struct FeedChanges: Sendable, Hashable {
    public var changed: [Post]
    public var deleted: [FeedItemID]
    /// Zone owners whose whole zone is gone (friend removed, share left, zone deleted).
    public var removedOwners: Set<String>
    /// Owners whose zone was refetched from scratch (expired change token). Their old posts are replaced.
    public var resetOwners: Set<String>

    public init(
        changed: [Post] = [],
        deleted: [FeedItemID] = [],
        removedOwners: Set<String> = [],
        resetOwners: Set<String> = []
    ) {
        self.changed = changed
        self.deleted = deleted
        self.removedOwners = removedOwners
        self.resetOwners = resetOwners
    }
}

/// The merged feed. Codable so the app can cache it between launches.
public struct FeedState: Sendable, Hashable, Codable {
    private var items: [FeedItemID: Post]

    public init(_ posts: [Post] = []) {
        items = [:]
        for post in posts { items[post.feedItemID] = post }
    }

    public var count: Int { items.count }

    /// Newest first, no ranking. One entry per record.
    public var posts: [Post] { Post.chronological(Array(items.values)) }

    public func posts(by ownerID: String) -> [Post] { posts.filter { $0.authorID == ownerID } }

    /// Order of steps: drop reset and removed owners, apply changes, then deletions.
    /// A record that is both changed and deleted in one batch ends up deleted.
    public mutating func apply(_ changes: FeedChanges) {
        let dropOwners = changes.removedOwners.union(changes.resetOwners)
        if !dropOwners.isEmpty {
            items = items.filter { !dropOwners.contains($0.key.ownerID) }
        }
        for post in changes.changed where !changes.removedOwners.contains(post.authorID) {
            items[post.feedItemID] = post
        }
        for id in changes.deleted {
            items[id] = nil
        }
    }

    /// Returns the merged result without changing `self`.
    public func applying(_ changes: FeedChanges) -> FeedState {
        var copy = self
        copy.apply(changes)
        return copy
    }

    /// Replaces local image URLs, for example after the app container path changed.
    public mutating func mapImageURLs(_ transform: (URL) -> URL?) {
        for (key, post) in items {
            var p = post
            p.imageURL = post.imageURL.flatMap(transform)
            items[key] = p
        }
    }
}
