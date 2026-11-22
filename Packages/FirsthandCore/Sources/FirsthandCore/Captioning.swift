import Foundation

/// Text facts about a moment. No pixels: on iOS 26 the on-device model takes text only.
public struct CaptionContext: Sendable, Equatable {
    /// Sorted, so the same moment gives the same prompt.
    public var sceneLabels: [String]
    public var faceCount: Int
    public var isNewPlace: Bool
    public var photoCount: Int

    public init(sceneLabels: [String], faceCount: Int, isNewPlace: Bool, photoCount: Int) {
        self.sceneLabels = sceneLabels.sorted()
        self.faceCount = faceCount
        self.isNewPlace = isNewPlace
        self.photoCount = photoCount
    }

    public init(_ ranked: RankedMoment) {
        let s = ranked.best.candidate.signals
        self.init(
            sceneLabels: Array(s.sceneLabels),
            faceCount: s.faceCount,
            isNewPlace: ranked.isNewPlace,
            photoCount: ranked.moment.candidates.count
        )
    }
}

/// Optional short caption. Implementations must run on the device. Return `nil` when unavailable.
public protocol MomentCaptioner: Sendable {
    func caption(for context: CaptionContext) async -> String?
}
