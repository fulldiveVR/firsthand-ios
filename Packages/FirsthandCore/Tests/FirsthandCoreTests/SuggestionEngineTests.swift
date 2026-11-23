import Foundation
import Testing
@testable import FirsthandCore

@Suite struct SuggestionEngineTests {
    let engine = SuggestionEngine(policy: SuggestionPolicy(dailyCap: 1, cooldown: 6 * 3600, minimumScore: 0.55), calendar: utcCalendar)
    let scorer = MomentScorer()

    var batch: [ScoredCandidate] {
        scorer.score([
            candidate("best", signals(aesthetic: 0.9, faces: 2, labels: ["outdoor"])),
            candidate("second", signals(aesthetic: 0.7, faces: 1)),
            candidate("weak", signals(aesthetic: 0.1, exif: false)),
            candidate("shot", signals(aesthetic: 1, faces: 3, screenshot: true)),
        ], context: ctx0)
    }

    @Test func picksExactlyTheTopEligibleCandidate() {
        let s = engine.pick(from: batch, history: SuggestionHistory(), now: day0)
        #expect(s?.assetID == "best")
        #expect(s?.decision == nil)
    }

    @Test func neverPicksScreenshots() {
        let only = scorer.score([candidate("shot", signals(aesthetic: 1, faces: 3, screenshot: true))], context: ctx0)
        #expect(engine.pick(from: only, history: SuggestionHistory(), now: day0) == nil)
    }

    @Test func ignoresCandidatesBelowMinimumScore() {
        let only = scorer.score([candidate("weak", signals(aesthetic: 0.1, exif: false))], context: ctx0)
        #expect(engine.pick(from: only, history: SuggestionHistory(), now: day0) == nil)
    }

    @Test func pendingSuggestionBlocksAnother() {
        let first = engine.pick(from: batch, history: SuggestionHistory(), now: day0)!
        let history = SuggestionHistory(suggestions: [first])
        #expect(engine.pick(from: batch, history: history, now: day0.addingTimeInterval(2 * 86_400)) == nil)
    }

    @Test func dailyCapHoldsEvenAfterCooldown() {
        let start = utcCalendar.startOfDay(for: day0)
        var first = engine.pick(from: batch, history: SuggestionHistory(), now: start.addingTimeInterval(3600))!
        first.decision = .share
        let history = SuggestionHistory(suggestions: [first])
        // 8 h later: past the 6 h cooldown, same calendar day.
        #expect(engine.pick(from: batch, history: history, now: start.addingTimeInterval(9 * 3600)) == nil)
    }

    @Test func cooldownHoldsAcrossMidnight() {
        let midnight = utcCalendar.startOfDay(for: day0).addingTimeInterval(86_400)
        var first = engine.pick(from: batch, history: SuggestionHistory(), now: midnight.addingTimeInterval(-3600))!
        first.decision = .share
        let history = SuggestionHistory(suggestions: [first])
        #expect(engine.pick(from: batch, history: history, now: midnight.addingTimeInterval(3600)) == nil)
        #expect(engine.pick(from: batch, history: history, now: midnight.addingTimeInterval(6 * 3600)) != nil)
    }

    @Test func skippedAssetIsNeverSuggestedAgain() {
        var history = SuggestionHistory()
        let first = engine.pick(from: batch, history: history, now: day0)!
        history.suggestions.append(first)
        history.record(.skip, for: first.id)
        #expect(history.skippedAssetIDs == ["best"])

        let next = engine.pick(from: batch, history: history, now: day0.addingTimeInterval(86_400))
        #expect(next?.assetID == "second")
    }

    @Test func higherDailyCapAllowsMore() {
        let relaxed = SuggestionEngine(policy: SuggestionPolicy(dailyCap: 2, cooldown: 0, minimumScore: 0.55), calendar: utcCalendar)
        let start = utcCalendar.startOfDay(for: day0)
        var first = relaxed.pick(from: batch, history: SuggestionHistory(), now: start)!
        first.decision = .share
        let second = relaxed.pick(from: batch, history: SuggestionHistory(suggestions: [first]), now: start.addingTimeInterval(60))
        #expect(second?.assetID == "second")
    }
}

@Suite struct FeedTests {
    @Test func feedIsNewestFirst() {
        let old = Post(authorID: "a", authorName: "A", provenance: .likelyCamera, createdAt: day0)
        let new = Post(authorID: "b", authorName: "B", provenance: .unknown, createdAt: day0.addingTimeInterval(60))
        #expect(Post.chronological([old, new]).map(\.authorID) == ["b", "a"])
    }

    @Test func fakeShareRequiresRecipients() async {
        let service = InMemoryShareService(author: Friend(id: "me", displayName: "Me"), clock: FixedClock(day0))
        let s = Suggestion(assetID: "x", score: 1, provenance: .likelyCamera, createdAt: day0)
        await #expect(throws: ShareError.noRecipients) {
            try await service.share(s, imageData: Data(), with: [])
        }
        let post = try? await service.share(s, imageData: Data(), with: ["f1"])
        #expect(post?.provenance == .likelyCamera)
        #expect(await service.published.count == 1)
    }
}
