import Foundation

public struct AnalysisCheckpoint: Sendable, Codable, Equatable {
    /// Assets already analyzed, including ones that failed analysis.
    public var processedAssetIDs: Set<String>
    public var candidates: [PhotoCandidate]

    public init(processedAssetIDs: Set<String> = [], candidates: [PhotoCandidate] = []) {
        self.processedAssetIDs = processedAssetIDs
        self.candidates = candidates
    }
}

public protocol CheckpointStore: Sendable {
    func load() async throws -> AnalysisCheckpoint
    func save(_ checkpoint: AnalysisCheckpoint) async throws
    func clear() async throws
}

public actor InMemoryCheckpointStore: CheckpointStore {
    public private(set) var checkpoint: AnalysisCheckpoint
    public private(set) var saveCount = 0

    public init(_ checkpoint: AnalysisCheckpoint = AnalysisCheckpoint()) {
        self.checkpoint = checkpoint
    }

    public func load() -> AnalysisCheckpoint { checkpoint }

    public func save(_ checkpoint: AnalysisCheckpoint) {
        self.checkpoint = checkpoint
        saveCount += 1
    }

    public func clear() { checkpoint = AnalysisCheckpoint() }
}

/// JSON file store. Writes are atomic, so a kill mid-write keeps the previous checkpoint.
/// Protection allows reads while locked after first unlock, because background tasks run on a locked device.
public actor FileCheckpointStore: CheckpointStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> AnalysisCheckpoint {
        guard FileManager.default.fileExists(atPath: url.path) else { return AnalysisCheckpoint() }
        return try JSONDecoder().decode(AnalysisCheckpoint.self, from: Data(contentsOf: url))
    }

    public func save(_ checkpoint: AnalysisCheckpoint) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(checkpoint).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

public struct AnalysisRunResult: Sendable, Equatable {
    /// `true` when every fetched asset is processed.
    public var isComplete: Bool
    public var analyzedThisRun: Int
    public var candidates: [PhotoCandidate]
}

/// Analyzes recent photos one by one and saves a checkpoint after each photo,
/// so an interrupted background task loses no finished work.
public actor AnalysisQueue {
    private let library: PhotoLibrary
    private let analyzer: ImageAnalyzer
    private let store: CheckpointStore

    public init(library: PhotoLibrary, analyzer: ImageAnalyzer, store: CheckpointStore) {
        self.library = library
        self.analyzer = analyzer
        self.store = store
    }

    /// Stops early when the task is cancelled or `shouldContinue` returns `false`.
    public func run(
        since: Date,
        limit: Int = 200,
        shouldContinue: @Sendable () -> Bool = { true }
    ) async throws -> AnalysisRunResult {
        var checkpoint = try await store.load()
        let assets = try await library.recentAssets(since: since, limit: limit)
        let pending = assets.filter { !checkpoint.processedAssetIDs.contains($0.id) }
        var analyzed = 0

        for asset in pending {
            if Task.isCancelled || !shouldContinue() {
                return AnalysisRunResult(isComplete: false, analyzedThisRun: analyzed, candidates: checkpoint.candidates)
            }
            if asset.isScreenshot {
                // No need to load pixels for a photo we never suggest.
                checkpoint.processedAssetIDs.insert(asset.id)
            } else {
                do {
                    let signals = try await analyzer.analyze(asset)
                    checkpoint.candidates.append(PhotoCandidate(asset: asset, signals: signals))
                    analyzed += 1
                } catch is CancellationError {
                    return AnalysisRunResult(isComplete: false, analyzedThisRun: analyzed, candidates: checkpoint.candidates)
                } catch {
                    // A broken asset must not block the queue forever.
                }
                checkpoint.processedAssetIDs.insert(asset.id)
            }
            try await store.save(checkpoint)
        }

        return AnalysisRunResult(isComplete: true, analyzedThisRun: analyzed, candidates: checkpoint.candidates)
    }
}
