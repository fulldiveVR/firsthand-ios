#if os(iOS)
import FirsthandCore
import Foundation
import ImageIO
import Photos
import UIKit
import Vision

/// On-device analysis with the Swift Vision API (iOS 18+). No pixels leave the device.
struct VisionImageAnalyzer: ImageAnalyzer {
    enum AnalyzerError: Error, CustomStringConvertible {
        case assetMissing
        case decodeFailed

        var description: String {
            switch self {
            case .assetMissing: "assetMissing"
            case .decodeFailed: "decodeFailed"
            }
        }
    }

    static let utilityLabels: Set<String> = ["document", "receipt", "text", "paper", "whiteboard", "screenshot"]
    static let maxPixelSize: CGFloat = 1024
    /// One small derivative over a slow connection fits in this time. A timeout is retried on a later run.
    static let imageTimeout: Duration = .seconds(30)
    /// Subtypes that only the camera produces.
    static let cameraSubtypes: PHAssetMediaSubtype = [.photoLive, .photoDepthEffect, .photoHDR, .photoPanorama]

    func analyze(_ asset: PhotoAsset) async throws -> AnalysisSignals {
        guard let phAsset = PhotoKitLibrary.asset(asset.id) else { throw AnalyzerError.assetMissing }
        let image = try await PhotoKitLibrary.analysisImage(
            for: phAsset, maxPixelSize: Self.maxPixelSize, timeout: Self.imageTimeout
        )
        guard let cgImage = image.cgImage else { throw AnalyzerError.decodeFailed }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        try Task.checkCancellation()

        let labels = try await ClassifyImageRequest().perform(on: cgImage, orientation: orientation)
            .filter { $0.confidence >= 0.3 }
            .prefix(10)
            .map(\.identifier)
        let labelSet = Set(labels)
        try Task.checkCancellation()

        let faces = try await DetectFaceRectanglesRequest().perform(on: cgImage, orientation: orientation).count
        try Task.checkCancellation()

        // The aesthetics model is missing on some devices and in the simulator. Fall back to labels.
        var aesthetic = 0.5
        var isUtility = !labelSet.isDisjoint(with: Self.utilityLabels)
        if let scores = try? await CalculateImageAestheticsScoresRequest().perform(on: cgImage, orientation: orientation) {
            aesthetic = (Double(scores.overallScore) + 1) / 2  // -1...1 to 0...1
            isUtility = isUtility || scores.isUtility
        }

        // EXIF only from a local original. An iCloud-only original is never downloaded for it.
        let hasCameraEXIF = await Self.localCameraEXIF(phAsset)
        let provenance: ProvenanceStatus? = if asset.isScreenshot {
            .excluded
        } else if !hasCameraEXIF, Self.looksLikeCameraCapture(phAsset) {
            .likelyCamera
        } else {
            nil  // From EXIF: likely camera or unknown.
        }

        return AnalysisSignals(
            aestheticScore: aesthetic,
            isUtility: isUtility,
            faceCount: faces,
            sceneLabels: labelSet,
            isScreenshot: asset.isScreenshot,
            hasCameraEXIF: hasCameraEXIF,
            // TODO(iOS 27): read PHReferenceImageInfo.imageContainsReferenceImageData.
            // It shows only that the data is present. It does not verify the photo.
            hasReferenceImageData: false,
            provenance: provenance
        )
    }

    /// Camera EXIF of the local original. `false` when the original is only in iCloud:
    /// the request does not use the network and returns no data at once.
    static func localCameraEXIF(_ asset: PHAsset) async -> Bool {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.version = .original
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return hasCameraEXIF(properties)
    }

    /// A hint from cached `PHAsset` metadata when EXIF is not available. Nothing is checked.
    /// A photo in the user's own library that has a camera-only subtype or is part of a burst
    /// came from a camera. An unedited photo with a location is most likely a camera capture too,
    /// because saved web images and most received images carry no location.
    static func looksLikeCameraCapture(_ asset: PHAsset) -> Bool {
        guard asset.sourceType.contains(.typeUserLibrary), !asset.mediaSubtypes.contains(.photoScreenshot) else { return false }
        if !asset.mediaSubtypes.isDisjoint(with: cameraSubtypes) { return true }
        if asset.representsBurst || asset.burstIdentifier != nil { return true }
        return asset.location != nil && !asset.hasAdjustments
    }

    /// Camera-original files carry the maker and model in TIFF and exposure data in EXIF.
    /// This is a hint, not proof: EXIF is easy to edit.
    static func hasCameraEXIF(_ properties: [CFString: Any]) -> Bool {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let hasMaker = tiff[kCGImagePropertyTIFFMake] != nil && tiff[kCGImagePropertyTIFFModel] != nil
        let hasExposure = exif[kCGImagePropertyExifExposureTime] != nil || exif[kCGImagePropertyExifFNumber] != nil
        return hasMaker && hasExposure
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
