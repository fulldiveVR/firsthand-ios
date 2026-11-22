#if os(iOS)
import FirsthandCore
import Foundation
import Photos
import Synchronization

/// New, changed, and deleted images since the last library change.
struct PhotoLibraryDelta: Sendable {
    /// Inserted and changed assets. The queue still skips the ones whose revision is unchanged.
    var updated: [PhotoAsset]
    var removedIDs: Set<String>
}

/// Watches recent images and reports changes. Photos calls `photoLibraryDidChange` only while the app runs.
/// Work in background tasks still finds new photos through the normal fetch and the analysis cache.
final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let lookback: TimeInterval
    private let onChange: @Sendable (PhotoLibraryDelta) -> Void
    private let fetch = Mutex<PHFetchResult<PHAsset>?>(nil)

    init(lookback: TimeInterval, onChange: @escaping @Sendable (PhotoLibraryDelta) -> Void) {
        self.lookback = lookback
        self.onChange = onChange
    }

    /// Call after full or limited access is granted. Calling it again has no effect.
    func start() {
        let started = fetch.withLock { current -> Bool in
            guard current == nil else { return false }
            current = PHAsset.fetchAssets(with: PhotoKitLibrary.recentImagesOptions(since: Date(timeIntervalSinceNow: -lookback)))
            return true
        }
        if started { PHPhotoLibrary.shared().register(self) }
    }

    func stop() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        fetch.withLock { $0 = nil }
    }

    /// Runs on an arbitrary serial queue.
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let delta = fetch.withLock { current -> PhotoLibraryDelta? in
            guard let old = current, let details = changeInstance.changeDetails(for: old) else { return nil }
            current = details.fetchResultAfterChanges
            guard details.hasIncrementalChanges else {
                // No details: report every asset. Unchanged revisions cost only a dictionary lookup.
                let after = details.fetchResultAfterChanges
                let all = (0..<after.count).map { PhotoKitLibrary.photoAsset(after.object(at: $0)) }
                return PhotoLibraryDelta(updated: all, removedIDs: [])
            }
            let updated = (details.insertedObjects + details.changedObjects).map(PhotoKitLibrary.photoAsset)
            let removed = Set(details.removedObjects.map(\.localIdentifier))
            return PhotoLibraryDelta(updated: updated, removedIDs: removed)
        }
        guard let delta, !delta.updated.isEmpty || !delta.removedIDs.isEmpty else { return }
        onChange(delta)
    }
}
#endif
