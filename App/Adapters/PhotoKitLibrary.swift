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
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND mediaType == %d",
            since as NSDate,
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: options)

        var assets: [PhotoAsset] = []
        assets.reserveCapacity(result.count)
        for index in 0..<result.count {
            let asset = result.object(at: index)
            assets.append(PhotoAsset(
                id: asset.localIdentifier,
                captureDate: asset.creationDate ?? .distantPast,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                burstIdentifier: asset.burstIdentifier,
                locationBucket: asset.location.map { Self.bucket($0.coordinate) }
            ))
        }
        return assets
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

    /// About 5 km grid cells. Coarse on purpose: novelty needs "same place", not coordinates.
    static func bucket(_ c: CLLocationCoordinate2D) -> String {
        let step = 0.05
        let lat = (c.latitude / step).rounded(.down) * step
        let lon = (c.longitude / step).rounded(.down) * step
        return String(format: "%.2f,%.2f", lat, lon)
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
