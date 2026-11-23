import Foundation

/// A failed analysis of one asset at one revision. The asset is retried on later runs
/// until `attempts` reaches `AnalysisRecord.maxAttempts`.
public struct AnalysisFailure: Sendable, Codable, Equatable {
    /// A short, technical reason, for the debug scoring log. Never shown as user copy.
    public var reason: String
    public var attempts: Int
    public var lastAttempt: Date

    public init(reason: String, attempts: Int, lastAttempt: Date) {
        self.reason = reason
        self.attempts = attempts
        self.lastAttempt = lastAttempt
    }
}

/// The analysis result of one asset at one revision.
public struct AnalysisRecord: Sendable, Codable, Equatable {
    /// Failed analyses of one revision are tried at most this many times.
    public static let maxAttempts = 3

    /// `PhotoAsset.revision` at analysis time. A different revision means the asset changed.
    public var revision: String
    public var captureDate: Date
    /// The analysis result. `nil` when the asset is excluded or the analysis failed.
    public var candidate: PhotoCandidate?
    /// Set when the analysis failed. A failed record is retried until it reaches `maxAttempts`.
    public var failure: AnalysisFailure?
    /// The asset is never suggested (screenshot), so it is never analyzed.
    public var isExcluded: Bool

    public init(
        revision: String,
        captureDate: Date,
        candidate: PhotoCandidate?,
        failure: AnalysisFailure? = nil,
        isExcluded: Bool = false
    ) {
        self.revision = revision
        self.captureDate = captureDate
        self.candidate = candidate
        self.failure = failure
        self.isExcluded = isExcluded
    }

    private enum CodingKeys: String, CodingKey {
        case revision, captureDate, candidate, failure, isExcluded
    }

    /// Older files have only `revision`, `captureDate` and `candidate`.
    /// An old record without a candidate is then neither failed nor excluded, so it is analyzed again.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decode(String.self, forKey: .revision)
        captureDate = try c.decode(Date.self, forKey: .captureDate)
        candidate = try c.decodeIfPresent(PhotoCandidate.self, forKey: .candidate)
        failure = try c.decodeIfPresent(AnalysisFailure.self, forKey: .failure)
        isExcluded = try c.decodeIfPresent(Bool.self, forKey: .isExcluded) ?? false
    }

    /// `true` when this record is final for `revision`: analyzed, excluded, or failed too often.
    public func isSettled(for revision: String) -> Bool {
        guard self.revision == revision else { return false }
        if candidate != nil || isExcluded { return true }
        guard let failure else { return false }
        return failure.attempts >= Self.maxAttempts
    }

    /// Failed and given up for this revision.
    public var hasGivenUp: Bool {
        candidate == nil && (failure?.attempts ?? 0) >= Self.maxAttempts
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
