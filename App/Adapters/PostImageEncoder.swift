#if os(iOS)
import CandidCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns the original photo into the uploaded file: at most 2048 px long edge, HEIC or JPEG,
/// no location data. The rules live in `PostPayloadRules`.
enum PostImageEncoder {
    enum EncoderError: Error {
        case decodeFailed
        case encodeFailed
        case locationLeft
    }

    /// Returns a temporary file. The caller deletes it after upload.
    static func encode(_ data: Data) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { throw EncoderError.decodeFailed }

        let width = raw[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = raw[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let orientation = raw[kCGImagePropertyOrientation as String] as? Int ?? 1
        // Orientations 5-8 rotate by 90 degrees, so width and height swap.
        let upright = orientation >= 5
            ? PostPayloadRules.PixelSize(width: height, height: width)
            : PostPayloadRules.PixelSize(width: width, height: height)
        let target = PostPayloadRules.targetSize(for: upright)
        guard target.longEdge > 0 else { throw EncoderError.decodeFailed }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target.longEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw EncoderError.decodeFailed
        }

        let available = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let encoding = PostPayloadRules.encoding(heicAvailable: available.contains(UTType.heic.identifier))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(encoding.fileExtension)")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, encoding.rawValue as CFString, 1, nil) else {
            throw EncoderError.encodeFailed
        }
        var properties = PostPayloadRules.sanitizedProperties(raw)
        properties[kCGImageDestinationLossyCompressionQuality as String] = PostPayloadRules.compressionQuality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncoderError.encodeFailed }

        // Check the written file, not only the input dictionary.
        if let written = CGImageSourceCreateWithURL(url as CFURL, nil),
           let check = CGImageSourceCopyPropertiesAtIndex(written, 0, nil) as? [String: Any],
           PostPayloadRules.containsLocation(check) {
            try? FileManager.default.removeItem(at: url)
            throw EncoderError.locationLeft
        }
        return url
    }
}
#endif
