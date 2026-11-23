import Foundation

/// Photos taken close together in time (and place). One moment gives at most one suggestion.
public struct Moment: Sendable, Hashable, Identifiable {
    /// The asset id of the first photo. Stable for the same input.
    public var id: String
    public var start: Date
    public var end: Date
    /// Sorted by capture date, then asset id.
    public var candidates: [PhotoCandidate]

    /// The first non-nil bucket.
    public var locationBucket: String? { candidates.lazy.compactMap(\.locationBucket).first }
}

public struct MomentGrouping: Sendable {
    public struct Config: Sendable {
        /// A gap longer than this starts a new moment.
        public var maxGap: TimeInterval = 45 * 60
        /// Two known, different location buckets also start a new moment.
        public var splitOnPlaceChange = true
        /// Photos closer than this are one shot (same scene, repeated shutter).
        public var duplicateWindow: TimeInterval = 3

        public init() {}
    }

    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    static func chronological(_ a: PhotoCandidate, _ b: PhotoCandidate) -> Bool {
        a.captureDate != b.captureDate ? a.captureDate < b.captureDate : a.assetID < b.assetID
    }

    /// Keeps one candidate per burst or per run of photos within `duplicateWindow`.
    /// `isBetter(a, b)` decides which one stays. It must be a strict, deterministic order.
    public func collapseDuplicates(
        _ candidates: [PhotoCandidate],
        isBetter: (PhotoCandidate, PhotoCandidate) -> Bool
    ) -> [PhotoCandidate] {
        var clusters: [[PhotoCandidate]] = []
        var clusterOfBurst: [String: Int] = [:]

        for c in candidates.sorted(by: Self.chronological) {
            var index: Int?
            if let burst = c.burstIdentifier, let existing = clusterOfBurst[burst] {
                index = existing
            } else if let last = clusters.last?.last,
                      c.captureDate.timeIntervalSince(last.captureDate) <= config.duplicateWindow {
                index = clusters.count - 1
            }
            if let index {
                clusters[index].append(c)
            } else {
                clusters.append([c])
                index = clusters.count - 1
            }
            if let burst = c.burstIdentifier, clusterOfBurst[burst] == nil {
                clusterOfBurst[burst] = index
            }
        }

        return clusters
            .map { cluster in cluster.dropFirst().reduce(cluster[0]) { isBetter($1, $0) ? $1 : $0 } }
            .sorted(by: Self.chronological)
    }

    /// Splits candidates into moments by time gap and, optionally, by place change.
    public func group(_ candidates: [PhotoCandidate]) -> [Moment] {
        var moments: [Moment] = []
        var currentPlace: String?

        for c in candidates.sorted(by: Self.chronological) {
            if var last = moments.last {
                let gap = c.captureDate.timeIntervalSince(last.end)
                let placeChanged = config.splitOnPlaceChange
                    && currentPlace != nil && c.locationBucket != nil && currentPlace != c.locationBucket
                if gap <= config.maxGap && !placeChanged {
                    last.candidates.append(c)
                    last.end = c.captureDate
                    moments[moments.count - 1] = last
                    currentPlace = c.locationBucket ?? currentPlace
                    continue
                }
            }
            moments.append(Moment(id: c.assetID, start: c.captureDate, end: c.captureDate, candidates: [c]))
            currentPlace = c.locationBucket
        }
        return moments
    }
}
