import Foundation

/// One background run: analyze new photos, pick at most one suggestion, notify.
public struct SuggestionPipeline: Sendable {
    public var queue: AnalysisQueue
    public var scorer: MomentScorer
    public var engine: SuggestionEngine
    public var notifier: Notifier
    public var clock: Clock
    /// How far back to look for photos.
    public var lookback: TimeInterval

    public init(
        queue: AnalysisQueue,
        scorer: MomentScorer = MomentScorer(),
        engine: SuggestionEngine = SuggestionEngine(),
        notifier: Notifier,
        clock: Clock = SystemClock(),
        lookback: TimeInterval = 3 * 24 * 60 * 60
    ) {
        self.queue = queue
        self.scorer = scorer
        self.engine = engine
        self.notifier = notifier
        self.clock = clock
        self.lookback = lookback
    }

    /// Returns the new suggestion, or `nil` if the run was interrupted or nothing qualified.
    public func run(
        history: SuggestionHistory,
        shouldContinue: @Sendable () -> Bool = { true }
    ) async throws -> Suggestion? {
        let now = clock.now
        let result = try await queue.run(since: now.addingTimeInterval(-lookback), shouldContinue: shouldContinue)
        guard result.isComplete else { return nil }

        let recent = history.suggestions.filter { now.timeIntervalSince($0.createdAt) < lookback * 3 }
        let scored = scorer.score(result.candidates, recentSuggestions: recent)
        guard let suggestion = engine.pick(from: scored, history: history, now: now) else { return nil }
        await notifier.notifySuggestionReady(suggestion)
        return suggestion
    }
}
