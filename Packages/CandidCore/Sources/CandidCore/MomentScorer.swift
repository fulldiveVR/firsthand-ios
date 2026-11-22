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

/// What the scorer knows besides the photo itself.
public struct ScoringContext: Sendable {
    public var now: Date
    public var recentSuggestions: [Suggestion]
    public var placeHistory: PlaceHistory

    public init(now: Date, recentSuggestions: [Suggestion] = [], placeHistory: PlaceHistory = PlaceHistory()) {
        self.now = now
        self.recentSuggestions = recentSuggestions
        self.placeHistory = placeHistory
    }
}

/// Deterministic, additive scoring. The same inputs always give the same scores.
///
/// base  = aesthetic * aesthetic weight
///       + people (first face, then a small bonus per extra face up to a cap)
///       + scene (any outdoor or activity label)
///       + provenance (likely camera / reference image data)
///       - utility, screenshot, low aesthetics, edited (hasAdjustments)
/// score = base
///       + recency (linear from full at capture to zero after `recencyWindow`)
///       + new place (bucket not seen in `newPlaceWindow` before the moment)
///       - novelty (scene overlap and same place as recent suggestions)
///
/// Screenshots and other `excluded` assets are ineligible.
public struct MomentScorer: Sendable {
    /// All tuning values in one place.
    public struct Weights: Sendable {
        public var aesthetic = 0.4
        public var people = 0.2
        public var perExtraFace = 0.05
        /// Extra faces above this count give nothing, so group selfies do not dominate.
        public var maxExtraFaces = 2
        public var scene = 0.2
        public var likelyCamera = 0.1
        public var referenceImageData = 0.15
        public var recency = 0.15
        public var recencyWindow: TimeInterval = 48 * 60 * 60
        public var newPlace = 0.25
        public var newPlaceWindow: TimeInterval = 30 * 24 * 60 * 60
        public var utilityPenalty = 0.5
        public var screenshotPenalty = 1.0
        public var lowAestheticThreshold = 0.35
        public var lowAestheticPenalty = 0.2
        public var adjustedPenalty = 0.15
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

    public func isEligible(_ candidate: PhotoCandidate) -> Bool {
        candidate.signals.provenance.isShareable && !candidate.signals.isScreenshot
    }

    /// Score of the photo alone, without time, place, or history.
    public func baseScore(_ candidate: PhotoCandidate) -> Double {
        let s = candidate.signals
        var score = s.aestheticScore * weights.aesthetic
        if s.faceCount > 0 {
            score += weights.people + Double(min(s.faceCount - 1, weights.maxExtraFaces)) * weights.perExtraFace
        }
        if !s.sceneLabels.isDisjoint(with: Self.rewardedSceneLabels) { score += weights.scene }
        switch s.provenance {
        case .hasReferenceImageData: score += weights.referenceImageData
        case .likelyCamera: score += weights.likelyCamera
        case .unknown, .excluded: break
        }
        if s.isUtility { score -= weights.utilityPenalty }
        if s.isScreenshot { score -= weights.screenshotPenalty }
        if s.aestheticScore < weights.lowAestheticThreshold { score -= weights.lowAestheticPenalty }
        if candidate.hasAdjustments { score -= weights.adjustedPenalty }
        return score
    }

    /// 0...1, full for a photo taken now, zero after `recencyWindow`.
    public func recencyFactor(_ captureDate: Date, now: Date) -> Double {
        guard weights.recencyWindow > 0 else { return 0 }
        let age = max(now.timeIntervalSince(captureDate), 0)
        return max(1 - age / weights.recencyWindow, 0)
    }

    public func isNewPlace(_ candidate: PhotoCandidate, momentStart: Date, context: ScoringContext) -> Bool {
        guard let bucket = candidate.locationBucket else { return false }
        return context.placeHistory.isNew(bucket, before: momentStart, window: weights.newPlaceWindow)
    }

    /// Full score of one candidate inside a moment that starts at `momentStart`.
    public func score(_ c: PhotoCandidate, momentStart: Date, context: ScoringContext) -> ScoredCandidate {
        var score = baseScore(c)
        score += recencyFactor(c.captureDate, now: context.now) * weights.recency
        if isNewPlace(c, momentStart: momentStart, context: context) { score += weights.newPlace }

        let maxOverlap = context.recentSuggestions.map { Self.jaccard(c.signals.sceneLabels, $0.sceneLabels) }.max() ?? 0
        score -= maxOverlap * weights.sceneRepeatPenalty
        if let place = c.locationBucket, context.recentSuggestions.contains(where: { $0.locationBucket == place }) {
            score -= weights.placeRepeatPenalty
        }
        return ScoredCandidate(candidate: c, score: score, isEligible: isEligible(c))
    }

    /// Scores single photos, each as its own moment. Sorted best first, ties broken by asset id.
    public func score(_ candidates: [PhotoCandidate], context: ScoringContext) -> [ScoredCandidate] {
        candidates
            .map { score($0, momentStart: $0.captureDate, context: context) }
            .sorted(by: Self.ranksHigher)
    }

    /// Strict order: eligible first, then higher score, then smaller asset id.
    public static func ranksHigher(_ a: ScoredCandidate, _ b: ScoredCandidate) -> Bool {
        if a.isEligible != b.isEligible { return a.isEligible }
        if a.score != b.score { return a.score > b.score }
        return a.candidate.assetID < b.candidate.assetID
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }
}
