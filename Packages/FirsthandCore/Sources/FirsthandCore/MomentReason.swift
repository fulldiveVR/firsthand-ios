import Foundation

/// Why the AI picked a moment. Built from the scorer signals, shown as chips and in Moment details.
/// Provenance copy is "Likely original" or "Unknown". It never says "verified".
public enum MomentReason: Sendable, Hashable, Codable {
    /// The place bucket was not visited in the new-place window.
    case newPlace
    /// Two or more faces.
    case withFriends
    /// One face.
    case withSomeone
    /// A rewarded scene label, for example "beach".
    case scene(String)
    /// Taken less than 24 hours before the suggestion.
    case today
    case provenance(ProvenanceStatus)

    /// Specific scenes first, generic ones ("outdoor", "sky") last.
    static let scenePriority: [String] = [
        "beach", "mountain", "hiking", "forest", "lake", "ocean", "snow", "park",
        "concert", "party", "celebration", "dancing", "sport", "running", "cycling", "swimming",
        "travel", "sky", "outdoor",
    ]

    /// All reasons for one photo, in display order. Provenance is always last.
    public static func reasons(
        signals: AnalysisSignals,
        isNewPlace: Bool,
        captureDate: Date,
        now: Date
    ) -> [MomentReason] {
        var result: [MomentReason] = []
        if isNewPlace { result.append(.newPlace) }
        if signals.faceCount >= 2 {
            result.append(.withFriends)
        } else if signals.faceCount == 1 {
            result.append(.withSomeone)
        }
        let rewarded = signals.sceneLabels.intersection(MomentScorer.rewardedSceneLabels)
        if let label = scenePriority.first(where: rewarded.contains) ?? rewarded.sorted().first {
            result.append(.scene(label))
        }
        let age = now.timeIntervalSince(captureDate)
        if age >= 0 && age < 24 * 60 * 60 { result.append(.today) }
        switch signals.provenance {
        case .hasReferenceImageData, .likelyCamera, .unknown:
            result.append(.provenance(signals.provenance))
        case .excluded:
            break
        }
        return result
    }

    /// At most `limit` chips for the hero card. The provenance chip is always kept and always last.
    public static func chips(_ reasons: [MomentReason], limit: Int = 3) -> [MomentReason] {
        let provenance = reasons.first { if case .provenance = $0 { true } else { false } }
        let others = reasons.filter { if case .provenance = $0 { false } else { true } }
        let room = max(limit - (provenance == nil ? 0 : 1), 0)
        return Array(others.prefix(room)) + (provenance.map { [$0] } ?? [])
    }

    public var isProvenance: Bool {
        if case .provenance = self { true } else { false }
    }

    /// Short chip text.
    public var title: String {
        switch self {
        case .newPlace: String(localized: "New place")
        case .withFriends: String(localized: "With friends")
        case .withSomeone: String(localized: "With someone")
        case .scene(let label): label.capitalized
        case .today: String(localized: "Today")
        case .provenance(let status): status.originTitle
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .newPlace: "mappin.and.ellipse"
        case .withFriends: "person.2.fill"
        case .withSomeone: "person.fill"
        case .scene(let label): Self.sceneSymbols[label] ?? "sun.max.fill"
        case .today: "clock.fill"
        case .provenance(let status): status.originSymbol
        }
    }

    static let sceneSymbols: [String: String] = [
        "beach": "beach.umbrella.fill", "mountain": "mountain.2.fill", "hiking": "figure.hiking",
        "forest": "tree.fill", "park": "tree.fill", "lake": "water.waves", "ocean": "water.waves",
        "snow": "snowflake", "sport": "sportscourt.fill", "running": "figure.run",
        "cycling": "figure.outdoor.cycle", "swimming": "figure.pool.swim", "concert": "music.mic",
        "party": "party.popper.fill", "celebration": "party.popper.fill", "dancing": "figure.dance",
        "travel": "airplane", "sky": "sun.horizon.fill", "outdoor": "sun.max.fill",
    ]
}

extension ProvenanceStatus {
    /// "Likely original" or "Unknown". Never "verified".
    public var originTitle: String {
        switch self {
        case .hasReferenceImageData, .likelyCamera: String(localized: "Likely original")
        case .unknown, .excluded: String(localized: "Unknown")
        }
    }

    public var originSymbol: String {
        switch self {
        case .hasReferenceImageData: "camera.aperture"
        case .likelyCamera: "camera.fill"
        case .unknown, .excluded: "questionmark.circle"
        }
    }
}
