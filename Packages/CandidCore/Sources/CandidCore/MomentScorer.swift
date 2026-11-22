import Foundation

public struct ScoredCandidate: Sendable, Hashable {
    public var candidate: PhotoCandidate
    public var score: Double
    /// `false` for assets that must never be suggested (for example, screenshots).
    public var isEligible: Bool

    public init(candidate: PhotoCandidate, score: Double, isEligible: Bool) {
        self.candidate = candidate
        self.score = score
        self.isEligible = isEligible
    }
}

/// Deterministic, additive scoring. The same inputs always give the same scores.
///
/// score = aesthetic * aestheticWeight
///       + people bonus (one or more faces, extra for groups)
///       + scene bonus (any outdoor or activity label)
///       + provenance bonus (likely camera / reference image data)
///       - utility penalty
///       - duplicate penalty (not the best photo of its burst)
///       - novelty penalty (scene overlap and same place as recent suggestions)
///
/// Screenshots and other `excluded` assets are ineligible.
public struct MomentScorer: Sendable {
    public struct Weights: Sendable {
        public var aesthetic = 0.4
        public var people = 0.3
        public var group = 0.1
        public var scene = 0.2
        public var likelyCamera = 0.1
        public var referenceImageData = 0.15
        public var utilityPenalty = 0.5
        public var duplicatePenalty = 0.3
        public var sceneRepeatPenalty = 0.2
        public var placeRepeatPenalty = 0.1

        public init() {}
    }

    public static let rewardedSceneLabels: Set<String> = [
        "outdoor", "sky", "beach", "mountain", "hiking", "forest", "park", "lake", "ocean", "snow",
        "sport", "running", "cycling", "swimming", "concert", "party", "celebration", "dancing", "travel",
    ]

    public var weights: Weights

    public init(weights: Weights = Weights()) {
        self.weights = weights
    }

    /// Base score of one candidate, without duplicate or novelty context.
    public func baseScore(_ candidate: PhotoCandidate) -> Double {
        let s = candidate.signals
        var score = s.aestheticScore * weights.aesthetic
        if s.faceCount > 0 { score += weights.people }
        if s.faceCount > 1 { score += weights.group }
        if !s.sceneLabels.isDisjoint(with: Self.rewardedSceneLabels) { score += weights.scene }
        switch s.provenance {
        case .hasReferenceImageData: score += weights.referenceImageData
        case .likelyCamera: score += weights.likelyCamera
        case .unknown, .excluded: break
        }
        if s.isUtility { score -= weights.utilityPenalty }
        return score
    }

    /// Scores a batch. Results are sorted best first, ties broken by asset id.
    public func score(_ candidates: [PhotoCandidate], recentSuggestions: [Suggestion] = []) -> [ScoredCandidate] {
        let recentLabels = recentSuggestions.map(\.sceneLabels)
        let recentPlaces = Set(recentSuggestions.compactMap(\.locationBucket))

        // Within a burst, only the best photo avoids the duplicate penalty.
        var bestInBurst: [String: (assetID: String, score: Double)] = [:]
        for c in candidates {
            guard let burst = c.burstIdentifier else { continue }
            let base = baseScore(c)
            if let best = bestInBurst[burst], best.score > base || (best.score == base && best.assetID < c.assetID) {
                continue
            }
            bestInBurst[burst] = (c.assetID, base)
        }

        let scored = candidates.map { c -> ScoredCandidate in
            var score = baseScore(c)
            if let burst = c.burstIdentifier, bestInBurst[burst]?.assetID != c.assetID {
                score -= weights.duplicatePenalty
            }
            let maxOverlap = recentLabels.map { Self.jaccard(c.signals.sceneLabels, $0) }.max() ?? 0
            score -= maxOverlap * weights.sceneRepeatPenalty
            if let place = c.locationBucket, recentPlaces.contains(place) {
                score -= weights.placeRepeatPenalty
            }
            let eligible = c.signals.provenance.isShareable && !c.signals.isScreenshot
            return ScoredCandidate(candidate: c, score: score, isEligible: eligible)
        }

        return scored.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.candidate.assetID < $1.candidate.assetID
        }
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }
}
