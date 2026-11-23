import Foundation

public struct PipelineOutcome: Sendable {
    public var analysis: AnalysisRunResult
    /// `nil` when the analysis is incomplete or no moment passed the threshold.
    public var suggestion: Suggestion?
    /// Counts, best score and the reason for no suggestion.
    public var summary: RunSummary
    /// Every photo of the window with its score. For the debug scoring log.
    public var log: [ScoringLogEntry]
}

/// One background run: analyze new photos, group into moments, pick at most one suggestion, caption, notify.
public struct SuggestionPipeline: Sendable {
    public var queue: AnalysisQueue
    public var ranker: MomentRanker
    public var engine: SuggestionEngine
    public var notifier: Notifier
    public var captioner: (any MomentCaptioner)?
    public var clock: Clock
    /// How far back to look for photos to suggest. A normal week has enough photos.
    /// Scoring still prefers recent photos (`MomentScorer.Weights.recencyWindow`).
    public static let defaultLookback: TimeInterval = 7 * 24 * 60 * 60
    /// Suggestions newer than this lower the score of similar photos (scene and place repeat).
    public static let noveltyWindow: TimeInterval = 9 * 24 * 60 * 60

    /// How far back to look for photos to suggest.
    public var lookback: TimeInterval
    /// Upper bound of photos analyzed per run.
    public var analysisLimit: Int
    /// Upper bound of metadata rows read for the place history.
    public var placeHistoryLimit: Int

    public init(
        queue: AnalysisQueue,
        ranker: MomentRanker = MomentRanker(),
        engine: SuggestionEngine = SuggestionEngine(),
        notifier: Notifier,
        captioner: (any MomentCaptioner)? = nil,
        clock: Clock = SystemClock(),
        lookback: TimeInterval = SuggestionPipeline.defaultLookback,
        analysisLimit: Int = 200,
        placeHistoryLimit: Int = 5_000
    ) {
        self.queue = queue
        self.ranker = ranker
        self.engine = engine
        self.notifier = notifier
        self.captioner = captioner
        self.clock = clock
        self.lookback = lookback
        self.analysisLimit = analysisLimit
        self.placeHistoryLimit = placeHistoryLimit
    }

    /// Returns the new suggestion, or `nil` if the run was interrupted or nothing passed the threshold.
    public func run(
        history: SuggestionHistory,
        shouldContinue: @Sendable () -> Bool = { true },
        progress: @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> Suggestion? {
        try await runWithOutcome(history: history, shouldContinue: shouldContinue, progress: progress).suggestion
    }

    /// Like `run`, and also returns the analysis result and the run summary, for progress UI and copy.
    public func runWithOutcome(
        history: SuggestionHistory,
        shouldContinue: @Sendable () -> Bool = { true },
        progress: @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> PipelineOutcome {
        let now = clock.now
        let since = now.addingTimeInterval(-lookback)
        let result = try await queue.run(since: since, limit: analysisLimit, shouldContinue: shouldContinue, progress: progress)
        if result.isComplete {
            progress(AnalysisProgress(completed: result.pendingAtStart, total: result.pendingAtStart, phase: .choosing))
        }
        var (outcome, moments) = try await evaluate(result, history: history, now: now, mayPick: result.isComplete)
        guard var suggestion = outcome.suggestion else { return outcome }

        if let captioner, let moment = moments.first(where: { $0.best.candidate.assetID == suggestion.assetID }) {
            suggestion.caption = await captioner.caption(for: CaptionContext(moment))
        }
        await notifier.notifySuggestionReady(suggestion)
        outcome.suggestion = suggestion
        return outcome
    }

    /// The summary and scoring log from cached analysis only. Analyzes nothing, suggests nothing, notifies nobody.
    public func report(history: SuggestionHistory) async throws -> PipelineOutcome {
        let now = clock.now
        let assets = try await queue.metadata(since: now.addingTimeInterval(-lookback), limit: analysisLimit)
        let records = try await queue.cachedRecords(for: assets)
        let pending = assets.filter { records[$0.id]?.isSettled(for: $0.revision) != true }.count
        let result = AnalysisRunResult(
            isComplete: pending == 0,
            analyzedThisRun: 0,
            pendingAtStart: pending,
            candidates: assets.compactMap { records[$0.id]?.candidate },
            assets: assets,
            records: records
        )
        var (outcome, _) = try await evaluate(result, history: history, now: now, mayPick: true)
        outcome.suggestion = nil
        return outcome
    }

    private func context(now: Date, since: Date, history: SuggestionHistory) async throws -> ScoringContext {
        let placeWindow = ranker.scorer.weights.newPlaceWindow
        let places = PlaceHistory(assets: try await queue.metadata(since: since.addingTimeInterval(-placeWindow), limit: placeHistoryLimit))
        return ScoringContext(
            now: now,
            recentSuggestions: history.suggestions.filter { now.timeIntervalSince($0.createdAt) < Self.noveltyWindow },
            placeHistory: places
        )
    }

    /// Ranks the cached candidates, picks at most one suggestion (when `mayPick`), and explains the result.
    private func evaluate(
        _ result: AnalysisRunResult,
        history: SuggestionHistory,
        now: Date,
        mayPick: Bool
    ) async throws -> (PipelineOutcome, [RankedMoment]) {
        let context = try await context(now: now, since: now.addingTimeInterval(-lookback), history: history)
        let usedIDs = Set(history.suggestions.map(\.assetID))
        let moments = ranker.rank(result.candidates, context: context, excludedAssetIDs: usedIDs)
        let suggestion = mayPick ? engine.pick(from: moments, history: history, now: now) : nil
        let threshold = engine.policy.minimumScore

        let records = result.records
        let analyzed = result.assets.filter { records[$0.id]?.candidate != nil }.count
        let failed = result.assets.filter { records[$0.id].map { $0.candidate == nil && $0.failure != nil } ?? false }.count
        let excluded = result.assets.filter { records[$0.id]?.isExcluded == true || ($0.isScreenshot && records[$0.id] == nil) }.count
        let eligibleMoments = moments.filter(\.best.isEligible)
        let bestScore = eligibleMoments.first?.score
        let gate = engine.gate(history: history, now: now)

        let summary = RunSummary(
            photosFound: result.assets.count,
            analyzed: analyzed,
            failed: failed,
            excluded: excluded,
            eligible: moments.reduce(0) { n, m in n + m.moment.candidates.filter(ranker.scorer.isEligible).count },
            bestScore: bestScore,
            threshold: threshold,
            lookbackDays: Int((lookback / 86_400).rounded()),
            reason: RunSummary.reason(
                suggested: suggestion != nil,
                isComplete: result.isComplete,
                gate: gate,
                photosFound: result.assets.count,
                analyzed: analyzed,
                failed: failed,
                bestScore: bestScore,
                threshold: threshold
            ),
            nextAllowed: gate == .cooldown ? engine.cooldownEnd(history: history) : nil
        )
        let outcome = PipelineOutcome(
            analysis: result,
            suggestion: suggestion,
            summary: summary,
            log: scoringLog(result, moments: moments, context: context, usedIDs: usedIDs, threshold: threshold)
        )
        return (outcome, moments)
    }

    /// Every photo of the window, newest first. Each analyzed photo is scored inside its moment,
    /// the same way the ranker scores it. Duplicates are not collapsed here, so each one shows its own score.
    private func scoringLog(
        _ result: AnalysisRunResult,
        moments: [RankedMoment],
        context: ScoringContext,
        usedIDs: Set<String>,
        threshold: Double
    ) -> [ScoringLogEntry] {
        let scorer = ranker.scorer
        let bestIDs = Set(moments.map(\.best.candidate.assetID))
        let usedDates = result.candidates.filter { usedIDs.contains($0.assetID) }.map(\.captureDate)
        var scored: [String: (ScoredCandidate, newPlace: Bool, used: Bool)] = [:]
        for m in ranker.grouping.group(result.candidates) {
            let used = usedDates.contains { $0 >= m.start && $0 <= m.end }
            for c in m.candidates {
                scored[c.assetID] = (
                    scorer.score(c, momentStart: m.start, context: context),
                    scorer.isNewPlace(c, momentStart: m.start, context: context),
                    used
                )
            }
        }
        return result.assets.map { asset in
            let record = result.records[asset.id]
            var entry = ScoringLogEntry(
                assetID: asset.id,
                captureDate: asset.captureDate,
                isExcluded: record?.isExcluded ?? asset.isScreenshot,
                failure: record?.candidate == nil ? record?.failure : nil,
                hasAdjustments: asset.hasAdjustments
            )
            if let (s, newPlace, used) = scored[asset.id] {
                entry.signals = s.candidate.signals
                entry.score = s.score
                entry.isEligible = s.isEligible
                entry.passesThreshold = s.isEligible && s.score >= threshold
                entry.isNewPlace = newPlace
                entry.isMomentBest = bestIDs.contains(asset.id)
                entry.isAlreadyUsed = used
            }
            return entry
        }
    }
}
