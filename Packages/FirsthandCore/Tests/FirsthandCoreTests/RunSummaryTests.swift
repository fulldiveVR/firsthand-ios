import Foundation
import Testing
@testable import FirsthandCore

/// Returns the same signals for every asset, or fails for the given ids.
private struct FixedAnalyzer: ImageAnalyzer {
    var signals: AnalysisSignals
    var failing: Set<String> = []

    func analyze(_ asset: PhotoAsset) async throws -> AnalysisSignals {
        struct NotLocal: Error {}
        if failing.contains(asset.id) { throw NotLocal() }
        return signals
    }
}

@Suite struct RunSummaryTests {
    let now = day0.addingTimeInterval(3600)
    let assets = (1...4).map { PhotoAsset(id: "p\($0)", captureDate: day0.addingTimeInterval(-Double($0) * 7200)) }

    func pipeline(
        _ assets: [PhotoAsset],
        analyzer: ImageAnalyzer = RecordingAnalyzer(),
        cache: AnalysisCacheStore = InMemoryAnalysisCache()
    ) -> SuggestionPipeline {
        SuggestionPipeline(
            queue: AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: analyzer, cache: cache),
            engine: SuggestionEngine(calendar: utcCalendar),
            notifier: RecordingNotifier(),
            clock: FixedClock(now)
        )
    }

    @Test func suggestionHasNoReasonAndReportsCounts() async throws {
        let outcome = try await pipeline(assets).runWithOutcome(history: SuggestionHistory())
        #expect(outcome.suggestion != nil)
        let s = outcome.summary
        #expect(s.reason == nil)
        #expect(s.photosFound == 4)
        #expect(s.analyzed == 4)
        #expect(s.failed == 0)
        #expect(s.eligible == 4)
        #expect(s.threshold == 0.55)
        #expect(s.lookbackDays == 7)
        #expect(try #require(s.bestScore) >= s.threshold)
        #expect(outcome.log.count == 4)
        #expect(outcome.log.allSatisfy { $0.score != nil && $0.passesThreshold })
    }

    @Test func noPhotos() async throws {
        let outcome = try await pipeline([]).runWithOutcome(history: SuggestionHistory())
        #expect(outcome.summary.reason == .noPhotos)
        #expect(outcome.summary.bestScore == nil)
    }

    @Test func allFailed() async throws {
        let analyzer = FixedAnalyzer(signals: signals(), failing: Set(assets.map(\.id)))
        let outcome = try await pipeline(assets, analyzer: analyzer).runWithOutcome(history: SuggestionHistory())
        #expect(outcome.summary.reason == .allFailed)
        #expect(outcome.summary.failed == 4)
        #expect(outcome.summary.analyzed == 0)
        #expect(outcome.log.allSatisfy { $0.failure?.attempts == 1 && $0.score == nil })
    }

    @Test func belowThresholdReportsBestScore() async throws {
        // A plain photo: aesthetic 0.5, camera EXIF, no people or scene.
        let analyzer = FixedAnalyzer(signals: signals(aesthetic: 0.5), failing: ["p4"])
        let outcome = try await pipeline(assets, analyzer: analyzer).runWithOutcome(history: SuggestionHistory())
        let s = outcome.summary
        #expect(outcome.suggestion == nil)
        #expect(s.reason == .belowThreshold)
        #expect(s.analyzed == 3)
        #expect(s.failed == 1)
        let best = try #require(s.bestScore)
        #expect(best < s.threshold)
        #expect(outcome.log.compactMap(\.score).max() == best)
        #expect(outcome.log.allSatisfy { !$0.passesThreshold })
    }

    @Test func onlyScreenshotsAreNothingEligible() async throws {
        let shots = (1...2).map { PhotoAsset(id: "s\($0)", captureDate: day0, isScreenshot: true) }
        let outcome = try await pipeline(shots).runWithOutcome(history: SuggestionHistory())
        #expect(outcome.summary.reason == .nothingEligible)
        #expect(outcome.summary.excluded == 2)
        #expect(outcome.log.allSatisfy { $0.isExcluded })
    }

    @Test func gatesComeBeforePhotoReasons() async throws {
        let p = pipeline(assets)
        let pending = Suggestion(assetID: "x", score: 1, provenance: .likelyCamera, createdAt: now.addingTimeInterval(-86_400))
        let r1 = try await p.runWithOutcome(history: SuggestionHistory(suggestions: [pending])).summary.reason
        #expect(r1 == .pendingSuggestion)

        var decided = pending
        decided.decision = .share
        decided.createdAt = now.addingTimeInterval(-60)
        let r2 = try await p.runWithOutcome(history: SuggestionHistory(suggestions: [decided])).summary.reason
        #expect(r2 == .alreadyDecidedToday)

        // One minute before midnight: another day, but inside the 12 h cooldown.
        var lateYesterday = decided
        lateYesterday.createdAt = utcCalendar.startOfDay(for: now).addingTimeInterval(-60)
        let outcome = try await p.runWithOutcome(history: SuggestionHistory(suggestions: [lateYesterday]))
        #expect(outcome.summary.reason == .cooldown)
        #expect(outcome.summary.nextAllowed == lateYesterday.createdAt.addingTimeInterval(12 * 3600))
    }

    @Test func interruptedRunSaysSo() async throws {
        let budget = Budget(1)
        let outcome = try await pipeline(assets).runWithOutcome(history: SuggestionHistory(), shouldContinue: { budget.take() })
        #expect(outcome.summary.reason == .interrupted)
    }

    @Test func reportReadsTheCacheWithoutAnalysis() async throws {
        let cache = InMemoryAnalysisCache()
        _ = try await pipeline(assets, cache: cache).runWithOutcome(history: SuggestionHistory())
        let analyzer = RecordingAnalyzer()
        let report = try await pipeline(assets, analyzer: analyzer, cache: cache).report(history: SuggestionHistory())
        #expect(await analyzer.analyzed.isEmpty)
        #expect(report.suggestion == nil)
        #expect(report.summary.analyzed == 4)
        #expect(report.log.map(\.assetID) == assets.map(\.id))
    }

    @Test func logScoresMatchTheRankerForCollapsedBursts() async throws {
        // A burst at a beach. The last frame is the best, so the ranker keeps it.
        let burst = (0..<3).map { i in
            PhotoAsset(id: "b\(i)", captureDate: day0.addingTimeInterval(Double(i)), burstIdentifier: "B", locationBucket: "beach")
        }
        let home = PhotoAsset(id: "home", captureDate: day0.addingTimeInterval(-10 * 86_400), locationBucket: "home")
        struct ByID: ImageAnalyzer {
            func analyze(_ asset: PhotoAsset) async throws -> AnalysisSignals {
                signals(aesthetic: asset.id == "b2" ? 0.9 : 0.6, faces: 1)
            }
        }
        let outcome = try await pipeline(burst + [home], analyzer: ByID()).runWithOutcome(history: SuggestionHistory())
        let best = try #require(outcome.log.first { $0.isMomentBest })
        #expect(best.assetID == "b2")
        #expect(best.score == outcome.summary.bestScore)
        #expect(outcome.suggestion?.score == best.score)
        #expect(outcome.log.filter { $0.isCollapsedDuplicate }.map(\.assetID).sorted() == ["b0", "b1"])
        // Every logged score is at most the best moment score the engine saw.
        #expect(outcome.log.compactMap(\.score).allSatisfy { $0 <= best.score! })
    }

    @Test func lookbackIsAWeek() {
        #expect(SuggestionPipeline.defaultLookback == 7 * 24 * 3600)
        #expect(pipeline([]).lookback == SuggestionPipeline.defaultLookback)
    }

    @Test func engineGateMatchesPick() {
        let engine = SuggestionEngine(calendar: utcCalendar)
        #expect(engine.gate(history: SuggestionHistory(), now: now) == nil)
        let pending = Suggestion(assetID: "x", score: 1, provenance: .likelyCamera, createdAt: now.addingTimeInterval(-2 * 86_400))
        #expect(engine.gate(history: SuggestionHistory(suggestions: [pending]), now: now) == .pendingSuggestion)
    }
}
