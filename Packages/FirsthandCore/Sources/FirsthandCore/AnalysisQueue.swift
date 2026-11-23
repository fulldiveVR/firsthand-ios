import Foundation

public struct AnalysisRunResult: Sendable, Equatable {
    /// `true` when every new or changed asset is processed.
    public var isComplete: Bool
    public var analyzedThisRun: Int
    /// New or changed assets found at the start of the run.
    public var pendingAtStart: Int
    /// Analyses that failed in this run. They are retried on the next run.
    public var failedThisRun: Int = 0
    /// Analyzed candidates of the assets in this run's window, from the cache.
    public var candidates: [PhotoCandidate]
    /// The assets of this run's window, newest first.
    public var assets: [PhotoAsset] = []
    /// Cache records of `assets`, keyed by asset id.
    public var records: [String: AnalysisRecord] = [:]
}

/// The step of a run that the UI shows.
public enum AnalysisPhase: Sendable, Equatable {
    /// Reading photo metadata to find new or changed photos.
    case scanning
    /// Analyzing photos one by one. `completed` and `total` count photos.
    case analyzing
    /// Grouping moments and picking at most one suggestion.
    case choosing
}

/// Progress of one run, for UI such as a `BGContinuedProcessingTask` or the "Find moments now" view.
public struct AnalysisProgress: Sendable, Equatable {
    public var completed: Int
    public var total: Int
    public var phase: AnalysisPhase

    public init(completed: Int, total: Int, phase: AnalysisPhase = .analyzing) {
        self.completed = completed
        self.total = total
        self.phase = phase
    }

    /// 0...1. With nothing to analyze, scanning is 0 and the later phases are 1.
    public var fractionCompleted: Double {
        guard total > 0 else { return phase == .scanning ? 0 : 1 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    /// Whole percent, 0...100.
    public var percent: Int { Int((fractionCompleted * 100).rounded(.down)) }
}

/// Analyzes only new or changed photos. Each result goes to the analysis cache,
/// so an interrupted background task loses no finished work.
public actor AnalysisQueue {
    private let library: PhotoLibrary
    private let analyzer: ImageAnalyzer
    private let cache: AnalysisCacheStore
    private let clock: Clock
    private var isRunning = false

    public init(library: PhotoLibrary, analyzer: ImageAnalyzer, cache: AnalysisCacheStore, clock: Clock = SystemClock()) {
        self.library = library
        self.analyzer = analyzer
        self.cache = cache
        self.clock = clock
    }

    /// Assets without a final record: new, changed, or failed fewer than `AnalysisRecord.maxAttempts` times.
    public func pendingAssets(_ assets: [PhotoAsset]) async throws -> [PhotoAsset] {
        let records = try await cache.records()
        return assets.filter { records[$0.id]?.isSettled(for: $0.revision) != true }
    }

    /// Cached records of the given assets, without analysis. For the debug scoring log.
    public func cachedRecords(for assets: [PhotoAsset]) async throws -> [String: AnalysisRecord] {
        let ids = Set(assets.map(\.id))
        return try await cache.records().filter { ids.contains($0.key) }
    }

    /// Fetches photos since `since`, analyzes the new or changed ones, and drops older records.
    /// Stops early when the task is cancelled or `shouldContinue` returns `false`.
    public func run(
        since: Date,
        limit: Int = 200,
        shouldContinue: @Sendable () -> Bool = { true },
        progress: @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> AnalysisRunResult {
        progress(AnalysisProgress(completed: 0, total: 0, phase: .scanning))
        let assets = try await library.recentAssets(since: since, limit: limit)
        try await cache.prune(capturedBefore: since)
        return try await analyze(assets, shouldContinue: shouldContinue, progress: progress)
    }

    /// Analyzes the given assets if they are new or changed. The library change observer calls this.
    /// Returns an incomplete result without work when another run is active.
    public func analyze(
        _ assets: [PhotoAsset],
        shouldContinue: @Sendable () -> Bool = { true },
        progress: @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> AnalysisRunResult {
        guard !isRunning else {
            return AnalysisRunResult(isComplete: false, analyzedThisRun: 0, pendingAtStart: 0, candidates: [])
        }
        isRunning = true
        defer { isRunning = false }

        let before = try await cache.records()
        let pending = assets.filter { before[$0.id]?.isSettled(for: $0.revision) != true }
        var analyzed = 0
        var failed = 0
        var processed = 0
        progress(AnalysisProgress(completed: 0, total: pending.count))

        func result(complete: Bool) async throws -> AnalysisRunResult {
            try await cache.flush()
            let all = try await cache.records()
            var records: [String: AnalysisRecord] = [:]
            for asset in assets { records[asset.id] = all[asset.id] }
            return AnalysisRunResult(
                isComplete: complete,
                analyzedThisRun: analyzed,
                pendingAtStart: pending.count,
                failedThisRun: failed,
                candidates: assets.compactMap { records[$0.id]?.candidate },
                assets: assets,
                records: records
            )
        }

        for asset in pending {
            if Task.isCancelled || !shouldContinue() {
                return try await result(complete: false)
            }
            var record = AnalysisRecord(revision: asset.revision, captureDate: asset.captureDate, candidate: nil)
            if asset.isScreenshot {
                // Screenshots are never suggested, so their pixels are never loaded.
                record.isExcluded = true
            } else {
                do {
                    record.candidate = PhotoCandidate(asset: asset, signals: try await analyzer.analyze(asset))
                    analyzed += 1
                } catch is CancellationError {
                    return try await result(complete: false)
                } catch {
                    // A broken asset must not block the queue. It is retried on later runs, up to the attempt limit.
                    let previous = before[asset.id].flatMap { $0.revision == asset.revision ? $0.failure : nil }
                    record.failure = AnalysisFailure(
                        reason: Self.describe(error),
                        attempts: (previous?.attempts ?? 0) + 1,
                        lastAttempt: clock.now
                    )
                    failed += 1
                }
            }
            try await cache.upsert(record, for: asset.id)
            processed += 1
            progress(AnalysisProgress(completed: processed, total: pending.count))
        }
        return try await result(complete: true)
    }

    static func describe(_ error: Error) -> String {
        String(describing: error)
    }

    /// Removes records of deleted assets.
    public func forget(_ assetIDs: Set<String>) async throws {
        try await cache.remove(assetIDs)
    }

    /// Metadata only, no pixels. Used for the place history.
    public func metadata(since: Date, limit: Int) async throws -> [PhotoAsset] {
        try await library.recentAssets(since: since, limit: limit)
    }
}
