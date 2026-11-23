import Foundation

public struct AnalysisRunResult: Sendable, Equatable {
    /// `true` when every new or changed asset is processed.
    public var isComplete: Bool
    public var analyzedThisRun: Int
    /// New or changed assets found at the start of the run.
    public var pendingAtStart: Int
    /// Analyzed candidates of the assets in this run's window, from the cache.
    public var candidates: [PhotoCandidate]
}

/// Progress of one run, for UI such as a `BGContinuedProcessingTask`.
public struct AnalysisProgress: Sendable, Equatable {
    public var completed: Int
    public var total: Int
}

/// Analyzes only new or changed photos. Each result goes to the analysis cache,
/// so an interrupted background task loses no finished work.
public actor AnalysisQueue {
    private let library: PhotoLibrary
    private let analyzer: ImageAnalyzer
    private let cache: AnalysisCacheStore
    private var isRunning = false

    public init(library: PhotoLibrary, analyzer: ImageAnalyzer, cache: AnalysisCacheStore) {
        self.library = library
        self.analyzer = analyzer
        self.cache = cache
    }

    /// Assets without a record, or with a record of an older revision.
    public func pendingAssets(_ assets: [PhotoAsset]) async throws -> [PhotoAsset] {
        let records = try await cache.records()
        return assets.filter { records[$0.id]?.revision != $0.revision }
    }

    /// Fetches photos since `since`, analyzes the new or changed ones, and drops older records.
    /// Stops early when the task is cancelled or `shouldContinue` returns `false`.
    public func run(
        since: Date,
        limit: Int = 200,
        shouldContinue: @Sendable () -> Bool = { true },
        progress: @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> AnalysisRunResult {
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

        let pending = try await pendingAssets(assets)
        var analyzed = 0
        var processed = 0
        progress(AnalysisProgress(completed: 0, total: pending.count))

        func result(complete: Bool) async throws -> AnalysisRunResult {
            try await cache.flush()
            let records = try await cache.records()
            let candidates = assets.compactMap { records[$0.id]?.candidate }
            return AnalysisRunResult(
                isComplete: complete, analyzedThisRun: analyzed, pendingAtStart: pending.count, candidates: candidates
            )
        }

        for asset in pending {
            if Task.isCancelled || !shouldContinue() {
                return try await result(complete: false)
            }
            var candidate: PhotoCandidate?
            if !asset.isScreenshot {
                // Screenshots are never suggested, so their pixels are never loaded.
                do {
                    candidate = PhotoCandidate(asset: asset, signals: try await analyzer.analyze(asset))
                    analyzed += 1
                } catch is CancellationError {
                    return try await result(complete: false)
                } catch {
                    // A broken asset must not block the queue. It is retried when it changes.
                }
            }
            try await cache.upsert(
                AnalysisRecord(revision: asset.revision, captureDate: asset.captureDate, candidate: candidate),
                for: asset.id
            )
            processed += 1
            progress(AnalysisProgress(completed: processed, total: pending.count))
        }
        return try await result(complete: true)
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
