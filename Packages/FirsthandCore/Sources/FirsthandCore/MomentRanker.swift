import Foundation

/// A moment with its best photo.
public struct RankedMoment: Sendable, Hashable {
    public var moment: Moment
    public var best: ScoredCandidate
    public var isNewPlace: Bool

    /// The moment score is the score of its best photo.
    public var score: Double { best.score }
}

/// How the ranker scored one photo. For the debug scoring log.
public struct CandidateScoreDetail: Sendable, Hashable {
    public var scored: ScoredCandidate
    public var isNewPlace: Bool
    /// Start of the moment the photo was scored in.
    public var momentStart: Date
    /// The best photo of its moment, the one the engine compares.
    public var isMomentBest: Bool
    /// Its moment contains an excluded (already suggested) photo, so the moment is dropped.
    public var isInExcludedMoment: Bool
    /// A duplicate that was collapsed away. It is scored in the moment of the photo that stayed.
    public var isCollapsedDuplicate: Bool
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
        let excludedDates = Self.excludedDates(candidates, excludedAssetIDs)
        return grouping.group(collapse(candidates))
            .filter { m in !excludedDates.contains { $0 >= m.start && $0 <= m.end } }
            .compactMap { m -> RankedMoment? in
                let scored = m.candidates.map { scorer.score($0, momentStart: m.start, context: context) }
                guard let best = scored.min(by: MomentScorer.ranksHigher) else { return nil }
                let newPlace = scorer.isNewPlace(best.candidate, momentStart: m.start, context: context)
                return RankedMoment(moment: m, best: best, isNewPlace: newPlace)
            }
            .sorted { MomentScorer.ranksHigher($0.best, $1.best) }
    }

    private func collapse(_ candidates: [PhotoCandidate]) -> [PhotoCandidate] {
        grouping.collapseDuplicates(candidates) { a, b in
            let ea = scorer.isEligible(a), eb = scorer.isEligible(b)
            if ea != eb { return ea }
            let sa = scorer.baseScore(a), sb = scorer.baseScore(b)
            return sa != sb ? sa > sb : a.assetID < b.assetID
        }
    }

    /// Dates come from the full input, so an excluded photo that was collapsed away still blocks its moment.
    private static func excludedDates(_ candidates: [PhotoCandidate], _ excludedAssetIDs: Set<String>) -> [Date] {
        candidates.filter { excludedAssetIDs.contains($0.assetID) }.map(\.captureDate)
    }

    /// Every candidate scored exactly as `rank` scores it, keyed by asset id.
    /// Collapsed duplicates are scored in the moment of the nearest kept photo of the same burst or time.
    public func details(
        _ candidates: [PhotoCandidate],
        context: ScoringContext,
        excludedAssetIDs: Set<String> = []
    ) -> [String: CandidateScoreDetail] {
        let unique = collapse(candidates)
        let uniqueIDs = Set(unique.map(\.assetID))
        let excludedDates = Self.excludedDates(candidates, excludedAssetIDs)
        let moments = grouping.group(unique)
        var result: [String: CandidateScoreDetail] = [:]

        func detail(_ c: PhotoCandidate, in m: Moment, best: String?, collapsed: Bool) -> CandidateScoreDetail {
            CandidateScoreDetail(
                scored: scorer.score(c, momentStart: m.start, context: context),
                isNewPlace: scorer.isNewPlace(c, momentStart: m.start, context: context),
                momentStart: m.start,
                isMomentBest: c.assetID == best,
                isInExcludedMoment: excludedDates.contains { $0 >= m.start && $0 <= m.end },
                isCollapsedDuplicate: collapsed
            )
        }

        for m in moments {
            let best = m.candidates.map { scorer.score($0, momentStart: m.start, context: context) }
                .min(by: MomentScorer.ranksHigher)?.candidate.assetID
            for c in m.candidates { result[c.assetID] = detail(c, in: m, best: best, collapsed: false) }
        }
        let window = grouping.config.duplicateWindow
        for c in candidates where !uniqueIDs.contains(c.assetID) {
            let home = moments.first { m in
                m.candidates.contains { k in
                    (c.burstIdentifier != nil && k.burstIdentifier == c.burstIdentifier)
                        || abs(k.captureDate.timeIntervalSince(c.captureDate)) <= window
                }
            } ?? Moment(id: c.assetID, start: c.captureDate, end: c.captureDate, candidates: [c])
            result[c.assetID] = detail(c, in: home, best: nil, collapsed: true)
        }
        return result
    }
}
