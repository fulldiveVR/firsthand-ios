#if os(iOS)
import FirsthandCore
import Foundation

/// The product name and bundle id come from project.yml. Code reads them from the bundle.
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "App"
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.fulldive.firsthand" }

    static var analysisTaskID: String { bundleID + ".analysis" }

    /// Matches the `<bundle id>.firstscan.*` wildcard in Info.plist.
    static var firstScanTaskID: String { bundleID + ".firstscan.onboarding" }
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
    let sharing: CloudKitSharing
    let shareService: any ShareService
    let friends: any FriendDirectory
    let alerts: any FriendAlertChannel
    let notifier: LocalNotifier
    let analysisCache: FileAnalysisCache
    /// One queue per process, so the observer and background tasks never analyze the same photo twice at once.
    let queue: AnalysisQueue
    let captioner: OnDeviceCaptioner
    let history: HistoryStore
    let observer: PhotoLibraryObserver

    /// How far back photos are analyzed and suggested.
    static let lookback: TimeInterval = 3 * 24 * 60 * 60

    static let live: AppServices = {
        let library = PhotoKitLibrary()
        let cache = FileAnalysisCache(url: AppInfo.dataDirectory.appending(path: "analysis-cache.json"))
        let queue = AnalysisQueue(library: library, analyzer: VisionImageAnalyzer(), cache: cache)
        let sharing = CloudKitSharing()
        return AppServices(
            library: library,
            sharing: sharing,
            shareService: CloudKitShareService(sharing: sharing),
            friends: CloudKitFriendDirectory(sharing: sharing),
            alerts: CloudKitFriendAlerts(container: sharing.container),
            notifier: LocalNotifier(),
            analysisCache: cache,
            queue: queue,
            captioner: OnDeviceCaptioner(),
            history: HistoryStore(),
            observer: PhotoLibraryObserver(lookback: lookback) { delta in
                Task { await handleLibraryChange(delta, queue: queue) }
            }
        )
    }()

    func makePipeline() -> SuggestionPipeline {
        SuggestionPipeline(queue: queue, notifier: notifier, captioner: captioner, lookback: Self.lookback)
    }

    /// Analyzes only new or changed photos right away. Choosing a suggestion waits for the next pass,
    /// so a photo taken a minute ago does not interrupt the user.
    private static func handleLibraryChange(_ delta: PhotoLibraryDelta, queue: AnalysisQueue) async {
        try? await queue.forget(delta.removedIDs)
        let since = Date(timeIntervalSinceNow: -lookback)
        _ = try? await queue.analyze(delta.updated.filter { $0.captureDate >= since })
    }

    /// Call when photo access allows reading.
    func startObservingLibrary() {
        observer.start()
    }

    /// Runs one analysis pass and stores a new suggestion, if any.
    func runAnalysis(shouldContinue: @escaping @Sendable () -> Bool = { true }) async throws -> Suggestion? {
        try await runPass(shouldContinue: shouldContinue, progress: { _ in })?.suggestion
    }

    /// The onboarding scan: the same pass, with progress for the UI.
    func runFirstScan(
        shouldContinue: @escaping @Sendable () -> Bool = { true },
        progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> PipelineOutcome? {
        try await runPass(shouldContinue: shouldContinue, progress: progress)
    }

    private func runPass(
        shouldContinue: @escaping @Sendable () -> Bool,
        progress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> PipelineOutcome? {
        // Limited access shows only photos the user picked, so there is nothing new to find.
        guard await library.authorizationStatus() == .authorized else { return nil }
        let outcome = try await makePipeline().runWithOutcome(
            history: await history.load(), shouldContinue: shouldContinue, progress: progress
        )
        if let suggestion = outcome.suggestion { try await history.append(suggestion) }
        return outcome
    }

    func deleteAllLocalAndSharedData() async throws {
        try await shareService.deleteAllData()
        try await friends.reset()
        try? await alerts.tearDown()
        try await analysisCache.clear()
        try await history.clear()
    }
}
#endif
