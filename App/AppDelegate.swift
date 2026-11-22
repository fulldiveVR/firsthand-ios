#if os(iOS)
import CloudKit
import UIKit
import UserNotifications

/// Hands system events (accepted share links, friend pushes) to the UI model.
/// Events that arrive before the model attaches wait in a queue.
@MainActor
final class SharingInbox {
    static let shared = SharingInbox()

    private var pendingShares: [CKShare.Metadata] = []
    private var feedChanged = false
    private var onShare: ((CKShare.Metadata) async -> Void)?
    private var onFeedChange: (() async -> Void)?

    func attach(onShare: @escaping (CKShare.Metadata) async -> Void, onFeedChange: @escaping () async -> Void) {
        self.onShare = onShare
        self.onFeedChange = onFeedChange
        let queued = pendingShares
        pendingShares = []
        let refresh = feedChanged
        feedChanged = false
        Task {
            for metadata in queued { await onShare(metadata) }
            if refresh { await onFeedChange() }
        }
    }

    func receive(_ metadata: CKShare.Metadata) {
        guard let onShare else {
            pendingShares.append(metadata)
            return
        }
        Task { await onShare(metadata) }
    }

    func feedDidChange() {
        guard let onFeedChange else {
            feedChanged = true
            return
        }
        Task { await onFeedChange() }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // CloudKit pushes need APNs registration. Alerts show only if the user allowed notifications.
        application.registerForRemoteNotifications()
        Task { try? await AppServices.live.alerts.setUp() }
        return true
    }

    /// A custom scene delegate is the only way to receive accepted CloudKit share links in a SwiftUI app.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// Database subscription pushes coalesce and can drop data, so a push only triggers a full change fetch.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard CloudKitFriendAlerts.isFriendPost(userInfo) else { return .noData }
        do {
            _ = try await AppServices.live.shareService.feed()
            SharingInbox.shared.feedDidChange()
            return .newData
        } catch {
            return .failed
        }
    }

    /// Shows friend alerts while the app is open, too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold start from a share link.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            MainActor.assumeIsolated { SharingInbox.shared.receive(metadata) }
        }
    }

    /// Share link opened while the app runs.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        MainActor.assumeIsolated { SharingInbox.shared.receive(cloudKitShareMetadata) }
    }
}
#endif
