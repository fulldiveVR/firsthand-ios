import Foundation

/// Where a photo most likely came from. No case proves authenticity, so UI copy never says "verified".
public enum ProvenanceStatus: String, Sendable, Codable, CaseIterable {
    /// The asset contains Apple reference image data (`PHReferenceImageInfo`, iOS 27+).
    /// This proves the data is present, not that it was cryptographically checked.
    case hasReferenceImageData
    /// Camera-original signals are present (camera EXIF, not a screenshot). Nothing is checked.
    case likelyCamera
    /// No reliable signal either way.
    case unknown
    /// Never suggest this asset (screenshots, screen recordings).
    case excluded

    public var isShareable: Bool { self != .excluded }

    /// `hasReferenceImageData` must come from the Photos API. Pass `false` where it is unavailable.
    public static func classify(
        isScreenshot: Bool,
        hasCameraEXIF: Bool,
        hasReferenceImageData: Bool = false
    ) -> ProvenanceStatus {
        if isScreenshot { return .excluded }
        if hasReferenceImageData { return .hasReferenceImageData }
        return hasCameraEXIF ? .likelyCamera : .unknown
    }
}

public struct AnalysisSignals: Sendable, Hashable, Codable {
    /// Normalized to 0...1.
    public var aestheticScore: Double
    /// Receipts, documents, whiteboards and similar "utility" images.
    public var isUtility: Bool
    public var faceCount: Int
    public var sceneLabels: Set<String>
    public var isScreenshot: Bool
    public var hasCameraEXIF: Bool
    public var provenance: ProvenanceStatus

    public init(
        aestheticScore: Double,
        isUtility: Bool,
        faceCount: Int,
        sceneLabels: Set<String>,
        isScreenshot: Bool,
        hasCameraEXIF: Bool,
        hasReferenceImageData: Bool = false,
        provenance: ProvenanceStatus? = nil
    ) {
        self.aestheticScore = min(max(aestheticScore, 0), 1)
        self.isUtility = isUtility
        self.faceCount = max(faceCount, 0)
        self.sceneLabels = sceneLabels
        self.isScreenshot = isScreenshot
        self.hasCameraEXIF = hasCameraEXIF
        self.provenance = provenance
            ?? ProvenanceStatus.classify(
                isScreenshot: isScreenshot,
                hasCameraEXIF: hasCameraEXIF,
                hasReferenceImageData: hasReferenceImageData
            )
    }
}

/// Minimal photo metadata from the library, before analysis.
public struct PhotoAsset: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var captureDate: Date
    public var isScreenshot: Bool
    /// Photos from one burst share this value. Used to detect duplicates.
    public var burstIdentifier: String?
    /// A coarse place key (about 1 km grid cell). Never raw coordinates.
    public var locationBucket: String?
    /// Last change in the library. A new value means the asset must be analyzed again.
    public var modificationDate: Date?
    /// The photo was edited in Photos or another app. Edited photos are less likely camera originals.
    public var hasAdjustments: Bool

    public init(
        id: String,
        captureDate: Date,
        isScreenshot: Bool = false,
        burstIdentifier: String? = nil,
        locationBucket: String? = nil,
        modificationDate: Date? = nil,
        hasAdjustments: Bool = false
    ) {
        self.id = id
        self.captureDate = captureDate
        self.isScreenshot = isScreenshot
        self.burstIdentifier = burstIdentifier
        self.locationBucket = locationBucket
        self.modificationDate = modificationDate
        self.hasAdjustments = hasAdjustments
    }

    /// Changes when the asset changes in a way that needs new analysis.
    public var revision: String {
        let modified = modificationDate.map { String($0.timeIntervalSince1970) } ?? "-"
        return "\(modified)|\(hasAdjustments ? 1 : 0)"
    }
}

public struct PhotoCandidate: Sendable, Hashable, Codable, Identifiable {
    public var assetID: String
    public var captureDate: Date
    public var locationBucket: String?
    public var burstIdentifier: String?
    public var hasAdjustments: Bool
    public var signals: AnalysisSignals

    public var id: String { assetID }

    public init(
        assetID: String,
        captureDate: Date,
        locationBucket: String? = nil,
        burstIdentifier: String? = nil,
        hasAdjustments: Bool = false,
        signals: AnalysisSignals
    ) {
        self.assetID = assetID
        self.captureDate = captureDate
        self.locationBucket = locationBucket
        self.burstIdentifier = burstIdentifier
        self.hasAdjustments = hasAdjustments
        self.signals = signals
    }

    public init(asset: PhotoAsset, signals: AnalysisSignals) {
        self.init(
            assetID: asset.id,
            captureDate: asset.captureDate,
            locationBucket: asset.locationBucket,
            burstIdentifier: asset.burstIdentifier,
            hasAdjustments: asset.hasAdjustments,
            signals: signals
        )
    }
}

public enum ShareDecision: String, Sendable, Codable {
    case share
    case skip
}

public struct Suggestion: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var assetID: String
    public var caption: String?
    public var score: Double
    public var provenance: ProvenanceStatus
    public var sceneLabels: Set<String>
    public var locationBucket: String?
    public var createdAt: Date
    public var decision: ShareDecision?
    /// Why the AI picked this photo, in display order. Empty for suggestions saved by older versions.
    public var reasons: [MomentReason]
    /// When the photo was taken. `nil` for suggestions saved by older versions.
    public var captureDate: Date?

    public init(
        id: UUID = UUID(),
        assetID: String,
        caption: String? = nil,
        score: Double,
        provenance: ProvenanceStatus,
        sceneLabels: Set<String> = [],
        locationBucket: String? = nil,
        createdAt: Date,
        decision: ShareDecision? = nil,
        reasons: [MomentReason] = [],
        captureDate: Date? = nil
    ) {
        self.id = id
        self.assetID = assetID
        self.caption = caption
        self.score = score
        self.provenance = provenance
        self.sceneLabels = sceneLabels
        self.locationBucket = locationBucket
        self.createdAt = createdAt
        self.decision = decision
        self.reasons = reasons
        self.captureDate = captureDate
    }

    private enum CodingKeys: String, CodingKey {
        case id, assetID, caption, score, provenance, sceneLabels, locationBucket, createdAt, decision, reasons, captureDate
    }

    /// Old history files have no `reasons` and no `captureDate`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        assetID = try c.decode(String.self, forKey: .assetID)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        score = try c.decode(Double.self, forKey: .score)
        provenance = try c.decode(ProvenanceStatus.self, forKey: .provenance)
        sceneLabels = try c.decodeIfPresent(Set<String>.self, forKey: .sceneLabels) ?? []
        locationBucket = try c.decodeIfPresent(String.self, forKey: .locationBucket)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        decision = try c.decodeIfPresent(ShareDecision.self, forKey: .decision)
        reasons = try c.decodeIfPresent([MomentReason].self, forKey: .reasons) ?? []
        captureDate = try c.decodeIfPresent(Date.self, forKey: .captureDate)
    }

    /// The reasons to show. Older suggestions without reasons still show their provenance.
    public var displayReasons: [MomentReason] {
        reasons.isEmpty ? [.provenance(provenance)] : reasons
    }
}

public struct Friend: Sendable, Hashable, Codable, Identifiable {
    public enum Status: String, Sendable, Codable {
        case invited
        case accepted
    }

    public var id: String
    public var displayName: String
    public var status: Status

    public init(id: String, displayName: String, status: Status = .accepted) {
        self.id = id
        self.displayName = displayName
        self.status = status
    }
}

public struct Post: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var authorID: String
    public var authorName: String
    public var caption: String?
    public var provenance: ProvenanceStatus
    public var createdAt: Date
    /// Local file URL of the downloaded image, if available.
    public var imageURL: URL?

    public init(
        id: UUID = UUID(),
        authorID: String,
        authorName: String,
        caption: String? = nil,
        provenance: ProvenanceStatus,
        createdAt: Date,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.caption = caption
        self.provenance = provenance
        self.createdAt = createdAt
        self.imageURL = imageURL
    }

    /// Feed order: newest first, ties broken by id for stable output. No ranking.
    public static func chronological(_ posts: [Post]) -> [Post] {
        posts.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id.uuidString < $1.id.uuidString
        }
    }
}
