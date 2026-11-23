import Foundation

/// The 30-day rule: a shared post disappears 30 days after it was shared.
/// Friends' apps hide it at that time. The owner's app deletes the record from its own zone.
public enum PostExpiry {
    public static let lifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Own posts that are expired, for deletion from the owner's zone.
    public static func expiredOwnPosts(_ posts: [Post], ownerID: String, now: Date) -> [Post] {
        posts.filter { $0.authorID == ownerID && $0.isExpired(now: now) }
    }
}

extension Post {
    /// The time this post disappears from friends' feeds and from the owner's iCloud.
    public var expiresAt: Date { createdAt.addingTimeInterval(PostExpiry.lifetime) }

    public func isExpired(now: Date) -> Bool { now >= expiresAt }

    /// Whole days left, rounded up. 0 when expired, 1 on the last day.
    public func daysLeft(now: Date) -> Int {
        let remaining = expiresAt.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return Int((remaining / (24 * 60 * 60)).rounded(.up))
    }

    /// Posts that are not expired, in feed order.
    public static func visible(_ posts: [Post], now: Date) -> [Post] {
        chronological(posts.filter { !$0.isExpired(now: now) })
    }
}

extension FeedState {
    /// Posts that are not expired, newest first.
    public func visiblePosts(now: Date) -> [Post] { Post.visible(posts, now: now) }

    /// Drops expired posts and returns them, so the caller can delete cached images.
    @discardableResult
    public mutating func removeExpired(now: Date) -> [Post] {
        let expired = posts.filter { $0.isExpired(now: now) }
        apply(FeedChanges(deleted: expired.map(\.feedItemID)))
        return expired
    }
}
