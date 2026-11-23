#if os(iOS)
import FirsthandCore
import Foundation
import Photos
import Synchronization
import UIKit

/// Reads the photo library on device. Analysis and thumbnails may download small derivatives of
/// iCloud-only photos ("Optimize iPhone Storage"). Full originals are never downloaded.
struct PhotoKitLibrary: PhotoLibrary {
    enum ImageError: Error, CustomStringConvertible {
        case assetMissing
        case noImage
        case timedOut
        case photos(String)

        var description: String {
            switch self {
            case .assetMissing: "assetMissing"
            case .noImage: "noImage"
            case .timedOut: "timedOut"
            case .photos(let message): "photos: \(message)"
            }
        }
    }

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

    /// A downsized image of at most about `maxPixelSize` on the long edge, for on-device analysis.
    /// For an iCloud-only photo, Photos downloads only this small derivative, not the original.
    /// Degraded first results are ignored. Throws `ImageError.timedOut` after `timeout`.
    static func analysisImage(for asset: PHAsset, maxPixelSize: CGFloat, timeout: Duration) async throws -> UIImage {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.version = .current
        let size = CGSize(width: maxPixelSize, height: maxPixelSize)
        let request = OneShotRequest<UIImage>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.start(continuation, timeout: timeout)
                let id = PHImageManager.default().requestImage(
                    for: asset, targetSize: size, contentMode: .aspectFit, options: options
                ) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    if let image {
                        request.finish(.success(image))
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        request.finish(.failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        request.finish(.failure(ImageError.photos(String(describing: error))))
                    } else {
                        request.finish(.failure(ImageError.noImage))
                    }
                }
                request.setCancel { PHImageManager.default().cancelImageRequest(id) }
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
        }
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
        // A suggested photo may be iCloud-only. Its small derivative is downloaded for display.
        options.isNetworkAccessAllowed = true
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

    /// The center of a bucket from `bucket(_:)`, for "Near ..." place names.
    static func bucketCenter(_ bucket: String) -> CLLocationCoordinate2D? {
        let parts = bucket.split(separator: ":")
        guard parts.count == 2, let lat = Int(parts[0]), let lon = Int(parts[1]) else { return nil }
        let step = 0.01
        return CLLocationCoordinate2D(latitude: (Double(lat) + 0.5) * step, longitude: (Double(lon) + 0.5) * step)
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
/// Resumes a continuation exactly once: on the first result, on timeout, or on cancellation.
/// The losers cancel the Photos request and are ignored.
final class OneShotRequest<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Error>?
        var early: Result<Value, Error>?
        var done = false
        var cancel: (@Sendable () -> Void)?
        var timer: Task<Void, Never>?
    }

    private let state = Mutex(State())

    func start(_ continuation: CheckedContinuation<Value, Error>, timeout: Duration) {
        let early = state.withLock { s -> Result<Value, Error>? in
            if let early = s.early { return early }
            s.continuation = continuation
            s.timer = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(PhotoKitLibrary.ImageError.timedOut))
            }
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func setCancel(_ cancel: @escaping @Sendable () -> Void) {
        let finished = state.withLock { s -> Bool in
            if s.done { return true }
            s.cancel = cancel
            return false
        }
        if finished { cancel() }
    }

    func finish(_ result: Result<Value, Error>) {
        let (continuation, cancel, timer) = state.withLock { s -> (CheckedContinuation<Value, Error>?, (@Sendable () -> Void)?, Task<Void, Never>?) in
            guard !s.done else { return (nil, nil, nil) }
            s.done = true
            guard let c = s.continuation else {
                // Cancelled before the request started.
                s.early = result
                return (nil, nil, nil)
            }
            s.continuation = nil
            return (c, s.cancel, s.timer)
        }
        timer?.cancel()
        guard let continuation else { return }
        if case .failure = result { cancel?() }
        continuation.resume(with: result)
    }
}
#endif
