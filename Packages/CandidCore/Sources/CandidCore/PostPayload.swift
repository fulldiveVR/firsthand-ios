import Foundation

/// Pure rules for the photo that leaves the device. The app does the pixel work with ImageIO.
public enum PostPayloadRules {
    /// Long edge of the uploaded image, in pixels.
    public static let maxLongEdge = 2048
    /// Compression quality for HEIC and JPEG.
    public static let compressionQuality = 0.8
    /// Maximum caption length, in characters.
    public static let maxCaptionLength = 280

    public struct PixelSize: Sendable, Hashable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public var longEdge: Int { max(width, height) }
    }

    /// Keeps the aspect ratio, never upscales, every side at least 1 pixel.
    /// Pass the size after orientation is applied.
    public static func targetSize(for source: PixelSize, maxLongEdge: Int = maxLongEdge) -> PixelSize {
        guard source.width > 0, source.height > 0, maxLongEdge > 0 else { return PixelSize(width: 0, height: 0) }
        guard source.longEdge > maxLongEdge else { return source }
        let scale = Double(maxLongEdge) / Double(source.longEdge)
        let w = max(1, Int((Double(source.width) * scale).rounded()))
        let h = max(1, Int((Double(source.height) * scale).rounded()))
        return source.width >= source.height
            ? PixelSize(width: maxLongEdge, height: h)
            : PixelSize(width: w, height: maxLongEdge)
    }

    public enum Encoding: String, Sendable, Hashable {
        case heic = "public.heic"
        case jpeg = "public.jpeg"

        public var fileExtension: String { self == .heic ? "heic" : "jpg" }
    }

    /// HEIC when the device can encode it, JPEG otherwise.
    public static func encoding(heicAvailable: Bool) -> Encoding { heicAvailable ? .heic : .jpeg }

    // MARK: Metadata

    /// Top-level ImageIO property dictionaries that are removed completely.
    /// Values are the raw strings of the `kCGImageProperty...Dictionary` constants.
    /// GPS is location. IPTC and XMP can hold place names. MakerApple can hold location and device data.
    public static let strippedDictionaries: Set<String> = ["{GPS}", "{IPTC}", "{MakerApple}", "{ExifAux}"]
    /// Keys removed from the `{Exif}` dictionary: serial numbers identify a device.
    public static let strippedExifKeys: Set<String> = ["BodySerialNumber", "LensSerialNumber", "CameraOwnerName"]
    /// Keys removed from the `{TIFF}` dictionary.
    public static let strippedTIFFKeys: Set<String> = ["HostComputer", "Artist"]
    /// The pixels are already rotated, so orientation is reset to "up" (1).
    public static let orientationKey = "Orientation"

    /// Returns the properties to write into the output file.
    /// Camera make, model and exposure stay, because they are a provenance hint. Location never stays.
    public static func sanitizedProperties(_ properties: [String: Any]) -> [String: Any] {
        var out = properties.filter { !strippedDictionaries.contains($0.key) }
        if var exif = out["{Exif}"] as? [String: Any] {
            for key in strippedExifKeys { exif[key] = nil }
            out["{Exif}"] = exif
        }
        if var tiff = out["{TIFF}"] as? [String: Any] {
            for key in strippedTIFFKeys { tiff[key] = nil }
            tiff[orientationKey] = 1
            out["{TIFF}"] = tiff
        }
        out[orientationKey] = 1
        return out
    }

    /// True when no location data is left. The app asserts this before upload.
    public static func containsLocation(_ properties: [String: Any]) -> Bool {
        properties["{GPS}"] != nil || properties["{IPTC}"] != nil || properties["{MakerApple}"] != nil
    }

    // MARK: Caption and provenance

    /// Trims whitespace, caps the length, returns `nil` for an empty caption.
    public static func normalizedCaption(_ caption: String?) -> String? {
        guard let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed.count > maxCaptionLength ? String(trimmed.prefix(maxCaptionLength)) : trimmed
    }

    public enum PayloadError: Error, Equatable, Sendable {
        /// Screenshots and other excluded assets are never uploaded.
        case notShareable
    }

    /// The label stored in the record. `.excluded` is rejected.
    public static func provenanceLabel(for status: ProvenanceStatus) throws -> String {
        guard status.isShareable else { throw PayloadError.notShareable }
        return status.rawValue
    }

    /// Reads a label from a friend's record. Unknown or excluded values become `.unknown`,
    /// so a crafted record cannot show a stronger label than the app supports.
    public static func provenance(fromLabel label: String?) -> ProvenanceStatus {
        guard let label, let status = ProvenanceStatus(rawValue: label), status.isShareable else { return .unknown }
        return status
    }
}

/// Record type and field names of a post in CloudKit. One place, so app and tests agree.
public enum PostRecordSchema {
    public static let recordType = "Post"
    public static let image = "image"
    public static let caption = "caption"
    public static let createdAt = "createdAt"
    public static let provenance = "provenance"
    /// Name of each user's custom zone. The default zone cannot be shared.
    public static let zoneName = "Posts"
}
