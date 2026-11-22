import Foundation

/// Which change feed a token belongs to. CloudKit tokens are opaque, the app archives them to `Data`.
public enum ChangeTokenKey: Sendable, Hashable, Codable {
    /// Database-level changes of the shared database (which friend zones changed).
    case sharedDatabase
    /// Record changes of one zone. `ownerName` is the zone owner, `CKCurrentUserDefaultName` for my zone.
    case zone(ownerName: String, zoneName: String)

    /// Stable string form, used as the file key.
    public var storageKey: String {
        switch self {
        case .sharedDatabase: "db.shared"
        case .zone(let owner, let zone): "zone.\(owner).\(zone)"
        }
    }
}

public protocol ChangeTokenStore: Sendable {
    func token(for key: ChangeTokenKey) async -> Data?
    func setToken(_ token: Data?, for key: ChangeTokenKey) async throws
    /// Removes the tokens of every zone with this owner. Used when a friend's zone goes away.
    func removeTokens(ownerName: String) async throws
    func removeAll() async throws
}

public actor InMemoryChangeTokenStore: ChangeTokenStore {
    public private(set) var tokens: [String: Data]

    public init(_ tokens: [String: Data] = [:]) {
        self.tokens = tokens
    }

    public func token(for key: ChangeTokenKey) -> Data? { tokens[key.storageKey] }

    public func setToken(_ token: Data?, for key: ChangeTokenKey) {
        tokens[key.storageKey] = token
    }

    public func removeTokens(ownerName: String) {
        tokens = tokens.filter { !$0.key.hasPrefix("zone.\(ownerName).") }
    }

    public func removeAll() { tokens.removeAll() }
}

/// JSON file of all tokens. Writes are atomic. A missing or broken file means "no tokens",
/// which only costs a full refetch.
public actor FileChangeTokenStore: ChangeTokenStore {
    private let url: URL
    private var cache: [String: Data]?

    public init(url: URL) {
        self.url = url
    }

    private func load() -> [String: Data] {
        if let cache { return cache }
        let loaded = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
        cache = loaded
        return loaded
    }

    private func write(_ tokens: [String: Data]) throws {
        cache = tokens
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(tokens).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func token(for key: ChangeTokenKey) -> Data? { load()[key.storageKey] }

    public func setToken(_ token: Data?, for key: ChangeTokenKey) throws {
        var tokens = load()
        tokens[key.storageKey] = token
        try write(tokens)
    }

    public func removeTokens(ownerName: String) throws {
        try write(load().filter { !$0.key.hasPrefix("zone.\(ownerName).") })
    }

    public func removeAll() throws {
        cache = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
