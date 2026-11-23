import Foundation
import Testing
@testable import FirsthandCore

private let day: TimeInterval = 24 * 60 * 60

private func post(_ n: Int, by owner: String, sharedDaysAgo days: Double, now: Date = day0) -> Post {
    Post(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
        authorID: owner,
        authorName: owner.uppercased(),
        provenance: .likelyCamera,
        createdAt: now.addingTimeInterval(-days * day)
    )
}

@Suite struct PostExpiryTests {
    @Test func expiresThirtyDaysAfterSharing() {
        let p = post(1, by: "a", sharedDaysAgo: 0)
        #expect(p.expiresAt == day0.addingTimeInterval(30 * day))
        #expect(!p.isExpired(now: day0.addingTimeInterval(30 * day - 1)))
        #expect(p.isExpired(now: day0.addingTimeInterval(30 * day)))
    }

    @Test func daysLeftRoundsUp() {
        let p = post(1, by: "a", sharedDaysAgo: 0)
        #expect(p.daysLeft(now: day0) == 30)
        #expect(p.daysLeft(now: day0.addingTimeInterval(1)) == 30)
        #expect(p.daysLeft(now: day0.addingTimeInterval(29.5 * day)) == 1)
        #expect(p.daysLeft(now: day0.addingTimeInterval(30 * day)) == 0)
        #expect(p.daysLeft(now: day0.addingTimeInterval(40 * day)) == 0)
    }

    @Test func visibleHidesExpiredPostsAndKeepsOrder() {
        let posts = [
            post(1, by: "a", sharedDaysAgo: 31),
            post(2, by: "b", sharedDaysAgo: 1),
            post(3, by: "a", sharedDaysAgo: 29),
            post(4, by: "b", sharedDaysAgo: 30),
        ]
        #expect(Post.visible(posts, now: day0).map(\.id) == [posts[1].id, posts[2].id])
    }

    @Test func feedStateFiltersAndRemovesExpired() {
        var feed = FeedState([post(1, by: "a", sharedDaysAgo: 31), post(2, by: "a", sharedDaysAgo: 2)])
        #expect(feed.visiblePosts(now: day0).count == 1)
        #expect(feed.count == 2)
        let removed = feed.removeExpired(now: day0)
        #expect(removed.map(\.authorID) == ["a"])
        #expect(feed.count == 1)
        #expect(feed.removeExpired(now: day0).isEmpty)
    }

    @Test func cleanupSelectsOnlyExpiredOwnPosts() {
        let posts = [
            post(1, by: "me", sharedDaysAgo: 31),
            post(2, by: "me", sharedDaysAgo: 3),
            post(3, by: "friend", sharedDaysAgo: 45),
        ]
        let expired = PostExpiry.expiredOwnPosts(posts, ownerID: "me", now: day0)
        #expect(expired.map(\.id) == [posts[0].id])
    }

    @Test func inMemoryServiceDeletesExpiredOwnPostsAndHidesExpiredFeed() async throws {
        let clock = FixedClock(day0)
        let incoming = [post(10, by: "friend", sharedDaysAgo: 31), post(11, by: "friend", sharedDaysAgo: 1)]
        let service = InMemoryShareService(author: Friend(id: "me", displayName: "Me"), incoming: incoming, clock: clock)
        let s = Suggestion(assetID: "x", score: 1, provenance: .likelyCamera, createdAt: day0)
        let p = try await service.share(s, imageData: Data(), with: ["friend"])

        #expect(await service.feed().map(\.id) == [incoming[1].id])
        #expect(try await service.deleteExpiredPosts(now: day0.addingTimeInterval(29 * day)) == 0)
        #expect(await service.myPosts().map(\.id) == [p.id])
        #expect(try await service.deleteExpiredPosts(now: day0.addingTimeInterval(30 * day)) == 1)
        #expect(await service.myPosts().isEmpty)
    }
}
