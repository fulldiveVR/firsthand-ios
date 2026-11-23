#if os(iOS)
import FirsthandCore
import Foundation
import ImageIO
import Photos
import Vision

/// On-device analysis with the Swift Vision API (iOS 18+). No pixels leave the device.
struct VisionImageAnalyzer: ImageAnalyzer {
    enum AnalyzerError: Error {
        case assetMissing
        case notLocal
        case decodeFailed
    }

    static let utilityLabels: Set<String> = ["document", "receipt", "text", "paper", "whiteboard", "screenshot"]
    static let maxPixelSize = 1024

    func analyze(_ asset: PhotoAsset) async throws -> AnalysisSignals {
        guard let data = try await PhotoKitLibrary().imageData(for: asset.id) else { throw AnalyzerError.notLocal }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw AnalyzerError.decodeFailed }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw AnalyzerError.decodeFailed
        }
        try Task.checkCancellation()

        let labels = try await ClassifyImageRequest().perform(on: image)
            .filter { $0.confidence >= 0.3 }
            .prefix(10)
            .map(\.identifier)
        let labelSet = Set(labels)
        try Task.checkCancellation()

        let faces = try await DetectFaceRectanglesRequest().perform(on: image).count
        try Task.checkCancellation()

        // The aesthetics model is missing on some devices and in the simulator. Fall back to labels.
        var aesthetic = 0.5
        var isUtility = !labelSet.isDisjoint(with: Self.utilityLabels)
        if let scores = try? await CalculateImageAestheticsScoresRequest().perform(on: image) {
            aesthetic = (Double(scores.overallScore) + 1) / 2  // -1...1 to 0...1
            isUtility = isUtility || scores.isUtility
        }

        return AnalysisSignals(
            aestheticScore: aesthetic,
            isUtility: isUtility,
            faceCount: faces,
            sceneLabels: labelSet,
            isScreenshot: asset.isScreenshot,
            hasCameraEXIF: Self.hasCameraEXIF(properties),
            // TODO(iOS 27): read PHReferenceImageInfo.imageContainsReferenceImageData.
            // It shows only that the data is present. It does not verify the photo.
            hasReferenceImageData: false
        )
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
#endif
