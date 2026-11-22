import Foundation

/// A moment with its best photo.
public struct RankedMoment: Sendable, Hashable {
    public var moment: Moment
    public var best: ScoredCandidate
    public var isNewPlace: Bool

    /// The moment score is the score of its best photo.
    public var score: Double { best.score }
}

/// Collapses duplicates, groups photos into moments, picks the best photo per moment,
/// then orders moments best first. Deterministic for the same input.
public struct MomentRanker: Sendable {
    public var scorer: MomentScorer
    public var grouping: MomentGrouping

    public init(scorer: MomentScorer = MomentScorer(), grouping: MomentGrouping = MomentGrouping()) {
        self.scorer = scorer
        self.grouping = grouping
    }

    /// Moments that contain any of `excludedAssetIDs` (already suggested, shared, or skipped) are dropped,
    /// so a skipped moment does not come back as another photo of the same scene.
    public func rank(
        _ candidates: [PhotoCandidate],
        context: ScoringContext,
        excludedAssetIDs: Set<String> = []
    ) -> [RankedMoment] {
        let unique = grouping.collapseDuplicates(candidates) { a, b in
            let ea = scorer.isEligible(a), eb = scorer.isEligible(b)
            if ea != eb { return ea }
            let sa = scorer.baseScore(a), sb = scorer.baseScore(b)
            return sa != sb ? sa > sb : a.assetID < b.assetID
        }
        // Dates come from the full input, so an excluded photo that was collapsed away still blocks its moment.
        let excludedDates = candidates.filter { excludedAssetIDs.contains($0.assetID) }.map(\.captureDate)

        return grouping.group(unique)
            .filter { m in !excludedDates.contains { $0 >= m.start && $0 <= m.end } }
            .compactMap { m -> RankedMoment? in
                let scored = m.candidates.map { scorer.score($0, momentStart: m.start, context: context) }
                guard let best = scored.min(by: MomentScorer.ranksHigher) else { return nil }
                let newPlace = scorer.isNewPlace(best.candidate, momentStart: m.start, context: context)
                return RankedMoment(moment: m, best: best, isNewPlace: newPlace)
            }
            .sorted { MomentScorer.ranksHigher($0.best, $1.best) }
    }
}
