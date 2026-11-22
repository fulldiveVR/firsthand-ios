import Foundation

/// One background run: analyze new photos, group into moments, pick at most one suggestion, caption, notify.
public struct SuggestionPipeline: Sendable {
    public var queue: AnalysisQueue
    public var ranker: MomentRanker
    public var engine: SuggestionEngine
    public var notifier: Notifier
    public var captioner: (any MomentCaptioner)?
    public var clock: Clock
    /// How far back to look for photos to suggest.
    public var lookback: TimeInterval
    /// Upper bound of metadata rows read for the place history.
    public var placeHistoryLimit: Int

    public init(
        queue: AnalysisQueue,
        ranker: MomentRanker = MomentRanker(),
        engine: SuggestionEngine = SuggestionEngine(),
        notifier: Notifier,
        captioner: (any MomentCaptioner)? = nil,
        clock: Clock = SystemClock(),
        lookback: TimeInterval = 3 * 24 * 60 * 60,
        placeHistoryLimit: Int = 5_000
    ) {
        self.queue = queue
        self.ranker = ranker
        self.engine = engine
        self.notifier = notifier
        self.captioner = captioner
        self.clock = clock
        self.lookback = lookback
        self.placeHistoryLimit = placeHistoryLimit
    }

    /// Returns the new suggestion, or `nil` if the run was interrupted or nothing passed the threshold.
    public func run(
        history: SuggestionHistory,
        shouldContinue: @Sendable () -> Bool = { true },
        progress: @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> Suggestion? {
        let now = clock.now
        let since = now.addingTimeInterval(-lookback)
        let result = try await queue.run(since: since, shouldContinue: shouldContinue, progress: progress)
        guard result.isComplete else { return nil }

        let placeWindow = ranker.scorer.weights.newPlaceWindow
        let places = PlaceHistory(assets: try await queue.metadata(since: since.addingTimeInterval(-placeWindow), limit: placeHistoryLimit))
        let context = ScoringContext(
            now: now,
            recentSuggestions: history.suggestions.filter { now.timeIntervalSince($0.createdAt) < lookback * 3 },
            placeHistory: places
        )
        let moments = ranker.rank(
            result.candidates, context: context, excludedAssetIDs: Set(history.suggestions.map(\.assetID))
        )
        guard var suggestion = engine.pick(from: moments, history: history, now: now) else { return nil }

        if let captioner, let moment = moments.first(where: { $0.best.candidate.assetID == suggestion.assetID }) {
            suggestion.caption = await captioner.caption(for: CaptionContext(moment))
        }
        await notifier.notifySuggestionReady(suggestion)
        return suggestion
    }
}
