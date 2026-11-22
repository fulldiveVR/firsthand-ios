#if os(iOS)
import CandidCore
import CloudKit
import Foundation

/// Friend alerts through a `CKDatabaseSubscription` on the shared database.
/// Phase P4 tests delivery on real devices. If alerts are unreliable, a push relay replaces
/// this type through `FriendAlertChannel`, and nothing else changes.
struct CloudKitFriendAlerts: FriendAlertChannel {
    static let subscriptionID = "friend-posts"
    private static let savedKey = "friendAlertSubscriptionSaved"

    let container: CKContainer

    func setUp() async throws {
        guard !UserDefaults.standard.bool(forKey: Self.savedKey) else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        // The alert never contains the photo or the caption.
        info.alertBody = String(localized: "A friend shared a moment")
        info.soundName = "default"
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await container.sharedCloudDatabase.modifySubscriptions(saving: [subscription], deleting: [])
        UserDefaults.standard.set(true, forKey: Self.savedKey)
    }

    func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        _ = try await container.sharedCloudDatabase.modifySubscriptions(saving: [], deleting: [Self.subscriptionID])
    }

    /// True for pushes of this subscription. Other pushes are ignored.
    static func isFriendPost(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return false }
        return note.subscriptionID == subscriptionID
    }
}
#endif
