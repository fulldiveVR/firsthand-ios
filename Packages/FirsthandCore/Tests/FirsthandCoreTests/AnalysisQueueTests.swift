import Foundation
import Testing
@testable import FirsthandCore

@Suite struct AnalysisQueueTests {
    let assets = (1...5).map { PhotoAsset(id: "p\($0)", captureDate: day0.addingTimeInterval(Double($0))) }

    @Test func resumesAfterInterruptionWithoutRepeatingWork() async throws {
        let library = FakeLibrary(assets: assets)
        let cache = InMemoryAnalysisCache()

        let analyzer1 = RecordingAnalyzer()
        let queue1 = AnalysisQueue(library: library, analyzer: analyzer1, cache: cache)
        let budget = Budget(2)
        let partial = try await queue1.run(since: day0, shouldContinue: { budget.take() })
        #expect(!partial.isComplete)
        #expect(partial.analyzedThisRun == 2)
        #expect(Set(await cache.storage.keys) == ["p1", "p2"])

        // A new process: new queue and analyzer, same cache.
        let analyzer2 = RecordingAnalyzer()
        let queue2 = AnalysisQueue(library: library, analyzer: analyzer2, cache: cache)
        let full = try await queue2.run(since: day0)
        #expect(full.isComplete)
        #expect(await analyzer2.analyzed == ["p3", "p4", "p5"])
        #expect(full.candidates.map(\.assetID) == ["p1", "p2", "p3", "p4", "p5"])
    }

    @Test func storesARecordAfterEveryPhoto() async throws {
        let cache = InMemoryAnalysisCache()
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), cache: cache)
        _ = try await queue.run(since: day0)
        #expect(await cache.upsertCount == 5)
    }

    @Test func screenshotsAreSkippedWithoutAnalysis() async throws {
        let withShot = assets + [PhotoAsset(id: "shot", captureDate: day0, isScreenshot: true)]
        let analyzer = RecordingAnalyzer()
        let cache = InMemoryAnalysisCache()
        let queue = AnalysisQueue(library: FakeLibrary(assets: withShot), analyzer: analyzer, cache: cache)
        let result = try await queue.run(since: day0)
        #expect(!(await analyzer.analyzed).contains("shot"))
        #expect(await cache.storage["shot"] != nil)
        #expect(!result.candidates.contains { $0.assetID == "shot" })
    }

    @Test func brokenAssetDoesNotBlockQueue() async throws {
        let analyzer = RecordingAnalyzer(failing: ["p2"])
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: analyzer, cache: InMemoryAnalysisCache())
        let result = try await queue.run(since: day0)
        #expect(result.isComplete)
        #expect(result.candidates.count == 4)

        // The failed asset is retried on the next run, and only that asset.
        _ = try await queue.run(since: day0)
        #expect(await analyzer.analyzed.count == 6)
        #expect(await analyzer.analyzed.last == "p2")
    }

    @Test func failureIsRecordedAndRetriedUpToTheAttemptLimit() async throws {
        let analyzer = RecordingAnalyzer(failing: ["p2"])
        let cache = InMemoryAnalysisCache()
        let queue = AnalysisQueue(
            library: FakeLibrary(assets: assets), analyzer: analyzer, cache: cache, clock: FixedClock(day0.addingTimeInterval(60))
        )
        for run in 1...AnalysisRecord.maxAttempts {
            let result = try await queue.run(since: day0)
            #expect(result.failedThisRun == 1)
            let record = try #require(await cache.storage["p2"])
            #expect(record.candidate == nil)
            #expect(record.failure?.attempts == run)
            #expect(record.failure?.lastAttempt == day0.addingTimeInterval(60))
            #expect(record.failure?.reason.isEmpty == false)
        }
        // Given up for this revision: not analyzed again.
        let calls = await analyzer.analyzed.count
        let after = try await queue.run(since: day0)
        #expect(after.failedThisRun == 0)
        #expect(after.pendingAtStart == 0)
        #expect(await analyzer.analyzed.count == calls)
        #expect(await cache.storage["p2"]?.hasGivenUp == true)

        // A new revision starts over.
        var changed = assets
        changed[1].modificationDate = day0.addingTimeInterval(500)
        #expect(try await queue.pendingAssets(changed).map(\.id) == ["p2"])
    }

    @Test func successAfterFailureClearsTheMarker() async throws {
        let cache = InMemoryAnalysisCache()
        let failing = RecordingAnalyzer(failing: ["p1"])
        _ = try await AnalysisQueue(library: FakeLibrary(assets: [assets[0]]), analyzer: failing, cache: cache).run(since: day0)
        #expect(await cache.storage["p1"]?.failure?.attempts == 1)

        _ = try await AnalysisQueue(library: FakeLibrary(assets: [assets[0]]), analyzer: RecordingAnalyzer(), cache: cache).run(since: day0)
        let record = try #require(await cache.storage["p1"])
        #expect(record.candidate != nil)
        #expect(record.failure == nil)
    }

    @Test func screenshotsAreMarkedExcludedAndNotRetried() async throws {
        let shot = PhotoAsset(id: "shot", captureDate: day0, isScreenshot: true)
        let cache = InMemoryAnalysisCache()
        let queue = AnalysisQueue(library: FakeLibrary(assets: [shot]), analyzer: RecordingAnalyzer(), cache: cache)
        _ = try await queue.run(since: day0)
        #expect(await cache.storage["shot"]?.isExcluded == true)
        #expect(try await queue.pendingAssets([shot]).isEmpty)
    }

    @Test func oldCacheFormatDecodesAndNilCandidatesAreRetried() async throws {
        // The format before failure markers: only revision, captureDate and an optional candidate.
        let json = """
        {"a":{"revision":"-|0","captureDate":\(day0.timeIntervalSinceReferenceDate)},
         "b":{"revision":"-|0","captureDate":\(day0.timeIntervalSinceReferenceDate),
              "candidate":\(String(decoding: try JSONEncoder().encode(candidate("b")), as: UTF8.self))}}
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("analysis.json")
        try Data(json.utf8).write(to: url)

        let cache = FileAnalysisCache(url: url)
        let records = try await cache.records()
        #expect(records.count == 2)
        #expect(records["a"]?.failure == nil)
        #expect(records["a"]?.isExcluded == false)
        #expect(records["b"]?.candidate?.assetID == "b")

        let assets = [PhotoAsset(id: "a", captureDate: day0), PhotoAsset(id: "b", captureDate: day0)]
        let analyzer = RecordingAnalyzer()
        let result = try await AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: analyzer, cache: cache).run(since: day0)
        #expect(await analyzer.analyzed == ["a"])
        #expect(result.candidates.count == 2)
    }

    @Test func secondRunAnalyzesOnlyNewAndChangedAssets() async throws {
        let analyzer = RecordingAnalyzer()
        let cache = InMemoryAnalysisCache()
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: analyzer, cache: cache)
        _ = try await queue.run(since: day0)

        var changed = assets
        changed[1].hasAdjustments = true
        changed[2].modificationDate = day0.addingTimeInterval(100)
        changed.append(PhotoAsset(id: "p6", captureDate: day0.addingTimeInterval(6)))
        #expect(try await queue.pendingAssets(changed).map(\.id) == ["p2", "p3", "p6"])

        let result = try await AnalysisQueue(library: FakeLibrary(assets: changed), analyzer: analyzer, cache: cache)
            .run(since: day0)
        #expect(result.analyzedThisRun == 3)
        #expect(result.pendingAtStart == 3)
        #expect(await analyzer.analyzed == ["p1", "p2", "p3", "p4", "p5", "p2", "p3", "p6"])
        #expect(result.candidates.first { $0.assetID == "p2" }?.hasAdjustments == true)
    }

    @Test func observerPathAnalyzesOnlyGivenNewAssets() async throws {
        let analyzer = RecordingAnalyzer()
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: analyzer, cache: InMemoryAnalysisCache())
        _ = try await queue.analyze([assets[0]])
        _ = try await queue.analyze([assets[0], assets[1]])
        #expect(await analyzer.analyzed == ["p1", "p2"])
    }

    @Test func reportsProgress() async throws {
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), cache: InMemoryAnalysisCache())
        let log = ProgressLog()
        _ = try await queue.run(since: day0, progress: { log.add($0) })
        #expect(log.items.first == AnalysisProgress(completed: 0, total: 0, phase: .scanning))
        let analyzing = log.items.filter { $0.phase == .analyzing }
        #expect(analyzing.first == AnalysisProgress(completed: 0, total: 5))
        #expect(analyzing.last == AnalysisProgress(completed: 5, total: 5))
        #expect(analyzing.map(\.completed) == [0, 1, 2, 3, 4, 5])
    }

    @Test func progressFractionAndPercent() {
        #expect(AnalysisProgress(completed: 0, total: 0, phase: .scanning).fractionCompleted == 0)
        #expect(AnalysisProgress(completed: 0, total: 0, phase: .analyzing).fractionCompleted == 1)
        #expect(AnalysisProgress(completed: 0, total: 0, phase: .choosing).percent == 100)
        #expect(AnalysisProgress(completed: 1, total: 3).percent == 33)
        #expect(AnalysisProgress(completed: 4, total: 3).fractionCompleted == 1)
    }

    @Test func forgetAndPruneDropRecords() async throws {
        let cache = InMemoryAnalysisCache()
        let queue = AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), cache: cache)
        _ = try await queue.run(since: day0)
        try await queue.forget(["p1"])
        #expect(await cache.storage["p1"] == nil)

        // A later window prunes records captured before it.
        _ = try await queue.run(since: day0.addingTimeInterval(4))
        #expect(Set(await cache.storage.keys) == ["p4", "p5"])
    }

    @Test func fileCacheRoundTripsAndBuffersWrites() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("analysis.json")
        let cache = FileAnalysisCache(url: url, writeEvery: 2)
        #expect(try await cache.records().isEmpty)

        let record = AnalysisRecord(revision: "r1", captureDate: day0, candidate: candidate("a"))
        try await cache.upsert(record, for: "a")
        // Buffered: a new process does not see it yet.
        #expect(try await FileAnalysisCache(url: url).records().isEmpty)

        try await cache.upsert(AnalysisRecord(revision: "r1", captureDate: day0, candidate: nil), for: "b")
        #expect(try await FileAnalysisCache(url: url).records() == ["a": record, "b": AnalysisRecord(revision: "r1", captureDate: day0, candidate: nil)])

        try await cache.upsert(AnalysisRecord(revision: "r2", captureDate: day0, candidate: nil), for: "c")
        try await cache.flush()
        #expect(try await FileAnalysisCache(url: url).records().count == 3)

        try await cache.clear()
        #expect(try await cache.records().isEmpty)
        #expect(try await FileAnalysisCache(url: url).records().isEmpty)
    }

    @Test func queueWithFileCacheSkipsWorkAcrossProcesses() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("analysis.json")
        let library = FakeLibrary(assets: assets)
        _ = try await AnalysisQueue(library: library, analyzer: RecordingAnalyzer(), cache: FileAnalysisCache(url: url)).run(since: day0)

        let analyzer = RecordingAnalyzer()
        let result = try await AnalysisQueue(library: library, analyzer: analyzer, cache: FileAnalysisCache(url: url)).run(since: day0)
        #expect(await analyzer.analyzed.isEmpty)
        #expect(result.candidates.count == 5)
    }
}

@Suite struct SuggestionPipelineTests {
    @Test func interruptedRunDoesNotSuggest() async throws {
        let assets = (1...3).map { PhotoAsset(id: "p\($0)", captureDate: day0) }
        let notifier = RecordingNotifier()
        let pipeline = SuggestionPipeline(
            queue: AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), cache: InMemoryAnalysisCache()),
            engine: SuggestionEngine(calendar: utcCalendar),
            notifier: notifier,
            clock: FixedClock(day0.addingTimeInterval(3600))
        )
        let budget = Budget(1)
        let partial = try await pipeline.runWithOutcome(history: SuggestionHistory(), shouldContinue: { budget.take() })
        #expect(partial.suggestion == nil)
        #expect(!partial.analysis.isComplete)
        #expect(await notifier.notified.isEmpty)

        let suggestion = try await pipeline.run(history: SuggestionHistory())
        #expect(suggestion?.assetID == "p1")
        #expect(await notifier.notified.count == 1)
    }

    @Test func reportsPhasesInOrder() async throws {
        let assets = (1...3).map { PhotoAsset(id: "p\($0)", captureDate: day0) }
        let pipeline = SuggestionPipeline(
            queue: AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), cache: InMemoryAnalysisCache()),
            engine: SuggestionEngine(calendar: utcCalendar),
            notifier: RecordingNotifier(),
            clock: FixedClock(day0.addingTimeInterval(3600))
        )
        let log = ProgressLog()
        _ = try await pipeline.runWithOutcome(history: SuggestionHistory(), progress: { log.add($0) })
        var phases: [AnalysisPhase] = []
        for p in log.items where phases.last != p.phase { phases.append(p.phase) }
        #expect(phases == [.scanning, .analyzing, .choosing])
        #expect(log.items.last == AnalysisProgress(completed: 3, total: 3, phase: .choosing))
    }

    @Test func interruptedRunNeverReportsChoosing() async throws {
        let assets = (1...3).map { PhotoAsset(id: "p\($0)", captureDate: day0) }
        let pipeline = SuggestionPipeline(
            queue: AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: RecordingAnalyzer(), cache: InMemoryAnalysisCache()),
            notifier: RecordingNotifier(),
            clock: FixedClock(day0.addingTimeInterval(3600))
        )
        let log = ProgressLog()
        let budget = Budget(1)
        _ = try await pipeline.runWithOutcome(history: SuggestionHistory(), shouldContinue: { budget.take() }, progress: { log.add($0) })
        #expect(!log.items.contains { $0.phase == .choosing })
    }
}

@Suite struct AnalysisRunLockTests {
    @Test func allowsOneRunAtATime() {
        let lock = AnalysisRunLock()
        #expect(lock.tryAcquire())
        #expect(lock.isRunning)
        #expect(!lock.tryAcquire())
        lock.release()
        #expect(!lock.isRunning)
        #expect(lock.tryAcquire())
    }

    @Test func concurrentCallersGetExactlyOneRun() async {
        let lock = AnalysisRunLock()
        let wins = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 { group.addTask { lock.tryAcquire() } }
            var count = 0
            for await won in group where won { count += 1 }
            return count
        }
        #expect(wins == 1)
    }
}
