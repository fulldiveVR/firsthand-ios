#if os(iOS)
import CandidCore
import Foundation
import Photos
import UIKit

/// Reads the photo library on device. Never downloads from iCloud, so analysis works offline.
struct PhotoKitLibrary: PhotoLibrary {
    func authorizationStatus() async -> PhotoAuthorization {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotoAuthorization {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    func recentAssets(since: Date, limit: Int) async throws -> [PhotoAsset] {
        let result = PHAsset.fetchAssets(with: Self.recentImagesOptions(since: since, limit: limit))

        var assets: [PhotoAsset] = []
        assets.reserveCapacity(result.count)
        for index in 0..<result.count {
            assets.append(Self.photoAsset(result.object(at: index)))
        }
        return assets
    }

    /// Metadata only. All reads are cached `PHAsset` properties, no file or network access.
    static func photoAsset(_ asset: PHAsset) -> PhotoAsset {
        PhotoAsset(
            id: asset.localIdentifier,
            captureDate: asset.creationDate ?? .distantPast,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            burstIdentifier: asset.burstIdentifier,
            // The precise coordinate is used only here and never stored.
            locationBucket: asset.location.map { bucket($0.coordinate) },
            modificationDate: asset.modificationDate,
            // `hasAdjustments` (iOS 15+) is a cheap property. No adjustment data is loaded.
            hasAdjustments: asset.hasAdjustments
        )
    }

    /// Images since `since`, newest first. `limit` 0 means no limit.
    static func recentImagesOptions(since: Date, limit: Int = 0) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND mediaType == %d",
            since as NSDate,
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        return options
    }

    func imageData(for assetID: String) async throws -> Data? {
        guard let asset = Self.asset(assetID) else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.version = .original
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    @MainActor
    func thumbnail(for assetID: String, side: CGFloat) async -> UIImage? {
        guard let asset = Self.asset(assetID) else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        let size = CGSize(width: side, height: side)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Grid cells of 0.01 degree: about 1.1 km north-south, less east-west far from the equator.
    /// Coarse on purpose: "new place" needs "same area", not coordinates. Only the cell index is kept.
    static func bucket(_ c: CLLocationCoordinate2D) -> String {
        let step = 0.01
        let lat = Int((c.latitude / step).rounded(.down))
        let lon = Int((c.longitude / step).rounded(.down))
        return "\(lat):\(lon)"
    }

    static func map(_ status: PHAuthorizationStatus) -> PhotoAuthorization {
        switch status {
        case .authorized: .authorized
        case .limited: .limited
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}
#endif
