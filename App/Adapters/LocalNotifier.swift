#if os(iOS)
import CandidCore
import Foundation
import UserNotifications

struct LocalNotifier: Notifier {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// The notification never contains the photo, so nothing shows on the lock screen.
    func notifySuggestionReady(_ suggestion: Suggestion) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "A moment is ready")
        content.body = String(localized: "Open \(AppInfo.name) to share it or skip it.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: suggestion.id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
#endif
