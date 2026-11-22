#if os(iOS)
import CandidCore
import CloudKit
import Foundation

/// Stub for CloudKit Sharing. Apple hosts all data, there is no own photo server.
///
/// Plan:
/// 1. Create one custom zone `Moments` in the private database.
/// 2. Create a zone-wide `CKShare(recordZoneID:)`. Approved friends are its participants,
///    invited with `UICloudSharingController` or `CKShare.Participant` lookup.
/// 3. A shared photo is a `Post` record in that zone with a `CKAsset` and the provenance value.
/// 4. The feed reads friends' zones from `sharedCloudDatabase`, newest first.
/// 5. A `CKDatabaseSubscription` on the shared database sends a silent push for new posts.
/// 6. `deleteAllData` deletes the zone, which also removes the share for all participants.
actor CloudKitShareService: ShareService {
    static let zoneName = "Moments"

    private let container: CKContainer

    /// Uses the first iCloud container in the entitlements, so the id lives in one place.
    init(container: CKContainer = .default()) {
        self.container = container
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func share(_ suggestion: Suggestion, imageData: Data, with friendIDs: [Friend.ID]) async throws -> Post {
        guard !friendIDs.isEmpty else { throw ShareError.noRecipients }
        // TODO: Plan steps 1-3. Write the image to a temp file, save a Post record with a CKAsset,
        // then delete the temp file.
        throw ShareError.notImplemented
    }

    func feed() async throws -> [Post] {
        // TODO: Plan step 4.
        []
    }

    func deleteAllData() async throws {
        // TODO: Plan step 6. Ignore "zone not found".
        _ = try? await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
    }
}

/// Friends are the participants of the zone share. Stub until CloudKit sharing exists.
actor CloudKitFriendDirectory: FriendDirectory {
    func friends() async throws -> [Friend] {
        // TODO: Read `CKShare.participants` with `acceptanceStatus == .accepted`.
        []
    }

    func makeInviteURL() async throws -> URL {
        // TODO: Return `CKShare.url` after the share record is saved.
        throw ShareError.notImplemented
    }

    func remove(_ friendID: Friend.ID) async throws {
        // TODO: Remove the participant from the CKShare and save it.
        throw ShareError.notImplemented
    }
}
#endif
