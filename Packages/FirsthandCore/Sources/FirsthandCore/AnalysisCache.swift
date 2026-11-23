import Foundation

/// The analysis result of one asset at one revision.
public struct AnalysisRecord: Sendable, Codable, Equatable {
    /// `PhotoAsset.revision` at analysis time. A different revision means the asset changed.
    public var revision: String
    public var captureDate: Date
    /// `nil` when the asset is never suggested (screenshot) or the analysis failed.
    /// The record still exists, so the asset is not analyzed again until it changes.
    public var candidate: PhotoCandidate?

    public init(revision: String, captureDate: Date, candidate: PhotoCandidate?) {
        self.revision = revision
        self.captureDate = captureDate
        self.candidate = candidate
    }
}

/// Per-asset analysis cache, keyed by asset id.
public protocol AnalysisCacheStore: Sendable {
    func records() async throws -> [String: AnalysisRecord]
    func upsert(_ record: AnalysisRecord, for assetID: String) async throws
    func remove(_ assetIDs: Set<String>) async throws
    /// Drops records of assets captured before `date`. Keeps the cache small.
    func prune(capturedBefore date: Date) async throws
    /// Writes buffered changes. Call it when a run stops.
    func flush() async throws
    func clear() async throws
}

public actor InMemoryAnalysisCache: AnalysisCacheStore {
    public private(set) var storage: [String: AnalysisRecord]
    public private(set) var upsertCount = 0

    public init(_ records: [String: AnalysisRecord] = [:]) {
        storage = records
    }

    public func records() -> [String: AnalysisRecord] { storage }

    public func upsert(_ record: AnalysisRecord, for assetID: String) {
        storage[assetID] = record
        upsertCount += 1
    }

    public func remove(_ assetIDs: Set<String>) {
        for id in assetIDs { storage[id] = nil }
    }

    public func prune(capturedBefore date: Date) {
        storage = storage.filter { $0.value.captureDate >= date }
    }

    public func flush() {}

    public func clear() { storage = [:] }
}

/// JSON file cache. Writes are atomic, so a kill mid-write keeps the previous file.
/// Changes are buffered and written every `writeEvery` records and on `flush()`.
/// A hard kill loses at most `writeEvery - 1` analyses, which are then repeated.
/// Protection allows reads while locked after first unlock, because background tasks run on a locked device.
public actor FileAnalysisCache: AnalysisCacheStore {
    private let url: URL
    private let writeEvery: Int
    private var loaded: [String: AnalysisRecord]?
    private var unsaved = 0

    public init(url: URL, writeEvery: Int = 20) {
        self.url = url
        self.writeEvery = max(writeEvery, 1)
    }

    public func records() throws -> [String: AnalysisRecord] {
        try load()
    }

    public func upsert(_ record: AnalysisRecord, for assetID: String) throws {
        var all = try load()
        all[assetID] = record
        loaded = all
        unsaved += 1
        if unsaved >= writeEvery { try write() }
    }

    public func remove(_ assetIDs: Set<String>) throws {
        var all = try load()
        let before = all.count
        for id in assetIDs { all[id] = nil }
        loaded = all
        if all.count != before { try write() }
    }

    public func prune(capturedBefore date: Date) throws {
        let all = try load()
        let kept = all.filter { $0.value.captureDate >= date }
        loaded = kept
        if kept.count != all.count { try write() }
    }

    public func flush() throws {
        if unsaved > 0 { try write() }
    }

    public func clear() throws {
        loaded = [:]
        unsaved = 0
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func load() throws -> [String: AnalysisRecord] {
        if let loaded { return loaded }
        var result: [String: AnalysisRecord] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                result = try JSONDecoder().decode([String: AnalysisRecord].self, from: Data(contentsOf: url))
            } catch is DecodingError {
                // An old or broken format only costs a new analysis. Start empty.
                result = [:]
            }
        }
        loaded = result
        return result
    }

    private func write() throws {
        let all = try load()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(all).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        unsaved = 0
    }
}
