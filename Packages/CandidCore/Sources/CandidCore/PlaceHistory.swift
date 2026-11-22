import Foundation

/// Where and when the user took photos, by coarse location bucket. Built from metadata only.
public struct PlaceHistory: Sendable, Equatable {
    /// Visit dates per bucket, sorted ascending.
    private var visits: [String: [Date]]

    public init(visits: [(bucket: String, date: Date)] = []) {
        var map: [String: [Date]] = [:]
        for v in visits { map[v.bucket, default: []].append(v.date) }
        self.visits = map.mapValues { $0.sorted() }
    }

    public init(assets: [PhotoAsset]) {
        self.init(visits: assets.compactMap { a in a.locationBucket.map { ($0, a.captureDate) } })
    }

    /// `true` when `bucket` has no visit in `[start - window, start)`
    /// and the user took photos at some other place in that time.
    /// Without any other visit there is no evidence that the place is new.
    public func isNew(_ bucket: String, before start: Date, window: TimeInterval) -> Bool {
        let from = start.addingTimeInterval(-window)
        func visited(_ dates: [Date]) -> Bool { dates.contains { $0 >= from && $0 < start } }
        if let own = visits[bucket], visited(own) { return false }
        return visits.contains { $0.key != bucket && visited($0.value) }
    }
}
