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
    public var dailyCap: Int
    /// Minimum time between two suggestions.
    public var cooldown: TimeInterval
    /// Candidates below this score are not worth interrupting the user.
    public var minimumScore: Double

    public init(dailyCap: Int = 1, cooldown: TimeInterval = 12 * 60 * 60, minimumScore: Double = 0.3) {
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

    public func pick(from scored: [ScoredCandidate], history: SuggestionHistory, now: Date) -> Suggestion? {
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
            .min {
                $0.score != $1.score ? $0.score > $1.score : $0.candidate.assetID < $1.candidate.assetID
            }

        guard let best else { return nil }
        let c = best.candidate
        return Suggestion(
            assetID: c.assetID,
            score: best.score,
            provenance: c.signals.provenance,
            sceneLabels: c.signals.sceneLabels,
            locationBucket: c.locationBucket,
            createdAt: now
        )
    }
}
