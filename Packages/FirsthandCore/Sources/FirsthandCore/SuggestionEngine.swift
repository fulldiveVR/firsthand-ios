import Foundation

/// Everything the engine needs to remember between runs.
public struct SuggestionHistory: Sendable, Codable, Equatable {
    public var suggestions: [Suggestion]

    public init(suggestions: [Suggestion] = []) {
        self.suggestions = suggestions
    }

    public var skippedAssetIDs: Set<String> {
        Set(suggestions.filter { $0.decision == .skip }.map(\.assetID))
    }

    public var pending: Suggestion? {
        suggestions.last { $0.decision == nil }
    }

    public mutating func record(_ decision: ShareDecision, for suggestionID: Suggestion.ID) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestionID }) else { return }
        suggestions[index].decision = decision
    }
}

public struct SuggestionPolicy: Sendable {
    /// Product rule: at most one suggestion per calendar day.
    public var dailyCap: Int
    /// Minimum time between two suggestions.
    public var cooldown: TimeInterval
    /// Minimum quality threshold. Candidates below this score are not worth interrupting the user.
    /// When nothing passes, there is no suggestion and Today stays empty.
    /// With default weights a plain, decent photo (aesthetic 0.6, likely camera, taken now) scores about 0.49.
    /// It needs people, an outdoor or activity scene, or a new place to pass.
    public var minimumScore: Double

    public init(dailyCap: Int = 1, cooldown: TimeInterval = 12 * 60 * 60, minimumScore: Double = 0.55) {
        self.dailyCap = dailyCap
        self.cooldown = cooldown
        self.minimumScore = minimumScore
    }
}

/// Picks at most one suggestion. The user can only share or skip it.
public struct SuggestionEngine: Sendable {
    public var policy: SuggestionPolicy
    public var calendar: Calendar

    public init(policy: SuggestionPolicy = SuggestionPolicy(), calendar: Calendar = .current) {
        self.policy = policy
        self.calendar = calendar
    }

    /// Picks the best photo of the best qualifying moment.
    public func pick(from moments: [RankedMoment], history: SuggestionHistory, now: Date) -> Suggestion? {
        let newPlaces = Set(moments.filter(\.isNewPlace).map(\.best.candidate.assetID))
        return pick(from: moments.map(\.best), history: history, now: now, newPlaceAssetIDs: newPlaces)
    }

    /// `newPlaceAssetIDs` marks photos whose moment is at a new place, for the "New place" reason.
    public func pick(
        from scored: [ScoredCandidate],
        history: SuggestionHistory,
        now: Date,
        newPlaceAssetIDs: Set<String> = []
    ) -> Suggestion? {
        // An undecided suggestion blocks new ones. There is never a second option.
        if history.pending != nil { return nil }

        let today = history.suggestions.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        if today.count >= policy.dailyCap { return nil }

        if let last = history.suggestions.map(\.createdAt).max(), now.timeIntervalSince(last) < policy.cooldown {
            return nil
        }

        let usedAssets = Set(history.suggestions.map(\.assetID))
        let best = scored
            .filter { $0.isEligible && $0.score >= policy.minimumScore && !usedAssets.contains($0.candidate.assetID) }
            .min(by: MomentScorer.ranksHigher)

        guard let best else { return nil }
        let c = best.candidate
        return Suggestion(
            assetID: c.assetID,
            score: best.score,
            provenance: c.signals.provenance,
            sceneLabels: c.signals.sceneLabels,
            locationBucket: c.locationBucket,
            createdAt: now,
            reasons: MomentReason.reasons(
                signals: c.signals,
                isNewPlace: newPlaceAssetIDs.contains(c.assetID),
                captureDate: c.captureDate,
                now: now
            ),
            captureDate: c.captureDate
        )
    }
}
