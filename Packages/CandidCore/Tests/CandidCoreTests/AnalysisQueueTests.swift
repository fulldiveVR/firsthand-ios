import Foundation
import Testing
@testable import CandidCore

@Suite struct AnalysisQueueTests {
    let assets = (1...5).map { PhotoAsset(id: "p\($0)", captureDate: day0.addingTimeInterval(Double($0))) }

    @Test func resumesAfterInterruptionWithoutRepeatingWork() async throws {
        let library = FakeLibrary(assets: assets)
        let store = InMemoryCheckpointStore()

        let analyzer1 = RecordingAnalyzer()
        let queue1 = AnalysisQueue(library: library, analyzer: analyzer1, store: store)
        let budget = Budget(2)
        let partial = try await queue1.run(since: day0, shouldContinue: { budget.take() })
        #expect(!partial.isComplete)
        #expect(partial.analyzedThisRun == 2)
        #expect(await store.checkpoint.processedAssetIDs == ["p1", "p2"])

        // A new process: new queue and analyzer, same store.
        let analyzer2 = RecordingAnalyzer()
        let queue2 = AnalysisQueue(library: library, analyzer: analyzer2, store: store)
        let full = try await queue2.run(since: day0)
        #expect(full.isComplete)
        #expect(await analyzer2.analyzed == ["p3", "p4", "p5"])
        #expect(full.candidates.map(\.assetID) == ["p1", "p2", "p3", "p4", "p5"])
    }

    @Test func savesCheckpointAfterEveryPhoto() async throws {
        let store = InMemoryCheckpointStore()
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), store: store)
        _ = try await queue.run(since: day0)
        #expect(await store.saveCount == 5)
    }

    @Test func screenshotsAreSkippedWithoutAnalysis() async throws {
        let withShot = assets + [PhotoAsset(id: "shot", captureDate: day0, isScreenshot: true)]
        let analyzer = RecordingAnalyzer()
        let store = InMemoryCheckpointStore()
        let queue = AnalysisQueue(library: FakeLibrary(assets: withShot), analyzer: analyzer, store: store)
        let result = try await queue.run(since: day0)
        #expect(!(await analyzer.analyzed).contains("shot"))
        #expect(await store.checkpoint.processedAssetIDs.contains("shot"))
        #expect(!result.candidates.contains { $0.assetID == "shot" })
    }

    @Test func brokenAssetDoesNotBlockQueue() async throws {
        let analyzer = RecordingAnalyzer(failing: ["p2"])
        let store = InMemoryCheckpointStore()
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: analyzer, store: store)
        let result = try await queue.run(since: day0)
        #expect(result.isComplete)
        #expect(result.candidates.count == 4)

        _ = try await queue.run(since: day0)
        #expect(await analyzer.analyzed.count == 5)
    }

    @Test func fileStoreRoundTrips() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("checkpoint.json")
        let store = FileCheckpointStore(url: url)
        #expect(try await store.load() == AnalysisCheckpoint())

        let checkpoint = AnalysisCheckpoint(processedAssetIDs: ["a"], candidates: [candidate("a")])
        try await store.save(checkpoint)
        #expect(try await FileCheckpointStore(url: url).load() == checkpoint)

        try await store.clear()
        #expect(try await store.load() == AnalysisCheckpoint())
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@Suite struct SuggestionPipelineTests {
    @Test func interruptedRunDoesNotSuggest() async throws {
        let assets = (1...3).map { PhotoAsset(id: "p\($0)", captureDate: day0) }
        let notifier = RecordingNotifier()
        let pipeline = SuggestionPipeline(
            queue: AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), store: InMemoryCheckpointStore()),
            engine: SuggestionEngine(calendar: utcCalendar),
            notifier: notifier,
            clock: FixedClock(day0.addingTimeInterval(3600))
        )
        let budget = Budget(1)
        #expect(try await pipeline.run(history: SuggestionHistory(), shouldContinue: { budget.take() }) == nil)
        #expect(await notifier.notified.isEmpty)

        let suggestion = try await pipeline.run(history: SuggestionHistory())
        #expect(suggestion?.assetID == "p1")
        #expect(await notifier.notified.count == 1)
    }
}
