#if os(iOS)
import CandidCore
import Foundation

/// The product name and bundle id come from project.yml. Code reads them from the bundle.
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "App"
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.example.candid" }

    static var analysisTaskID: String { bundleID + ".analysis" }

    /// Info.plist sets this to `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`, the same value as the entitlements.
    /// A rename changes only project.yml. A container id cannot be renamed later in CloudKit.
    static var cloudKitContainerID: String {
        Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String ?? "iCloud." + bundleID
    }

    /// Sandboxed per app, so no app-specific subfolder is needed.
    static var dataDirectory: URL { URL.applicationSupportDirectory }
}

/// Suggestion history on disk. Shared by the UI and the background task.
actor HistoryStore {
    private let url = AppInfo.dataDirectory.appending(path: "history.json")

    func load() -> SuggestionHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(SuggestionHistory.self, from: data)
        else { return SuggestionHistory() }
        return history
    }

    func save(_ history: SuggestionHistory) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func append(_ suggestion: Suggestion) throws {
        var history = load()
        history.suggestions.append(suggestion)
        try save(history)
    }

    func clear() throws {
        try? FileManager.default.removeItem(at: url)
    }
}

struct AppServices: Sendable {
    let library: PhotoKitLibrary
    let analyzer: VisionImageAnalyzer
    let sharing: CloudKitSharing
    let shareService: any ShareService
    let friends: any FriendDirectory
    let alerts: any FriendAlertChannel
    let notifier: LocalNotifier
    let checkpoints: FileCheckpointStore
    let history: HistoryStore

    static let live: AppServices = {
        let sharing = CloudKitSharing()
        return AppServices(
            library: PhotoKitLibrary(),
            analyzer: VisionImageAnalyzer(),
            sharing: sharing,
            shareService: CloudKitShareService(sharing: sharing),
            friends: CloudKitFriendDirectory(sharing: sharing),
            alerts: CloudKitFriendAlerts(container: sharing.container),
            notifier: LocalNotifier(),
            checkpoints: FileCheckpointStore(url: AppInfo.dataDirectory.appending(path: "checkpoint.json")),
            history: HistoryStore()
        )
    }()

    func makePipeline() -> SuggestionPipeline {
        SuggestionPipeline(
            queue: AnalysisQueue(library: library, analyzer: analyzer, store: checkpoints),
            notifier: notifier
        )
    }

    /// Runs one analysis pass and stores a new suggestion, if any.
    func runAnalysis(shouldContinue: @escaping @Sendable () -> Bool = { true }) async throws -> Suggestion? {
        // Limited access shows only photos the user picked, so there is nothing new to find.
        guard await library.authorizationStatus() == .authorized else { return nil }
        let suggestion = try await makePipeline().run(history: await history.load(), shouldContinue: shouldContinue)
        if let suggestion { try await history.append(suggestion) }
        return suggestion
    }

    func deleteAllLocalAndSharedData() async throws {
        try await shareService.deleteAllData()
        try await friends.reset()
        try? await alerts.tearDown()
        try await checkpoints.clear()
        try await history.clear()
    }
}
#endif
