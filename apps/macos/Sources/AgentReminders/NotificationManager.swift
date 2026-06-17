import Foundation
import UserNotifications
import OSLog
import AgentRemindersCore

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.iankar.agentreminders",
    category: "Notifications"
)

/// Thin wrapper over UNUserNotificationCenter. One local notification per fired item.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func bootstrap(onAuthChange: @escaping (Bool) -> Void) {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { onAuthChange(granted) }
        }
    }

    func refreshAuthorization(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func notify(_ item: AgentReminder) {
        let content = UNMutableNotificationContent()
        content.title = item.kind == .todo ? "Todo due" : "Reminder"
        content.body = item.text
        content.sound = .default
        // Stable-ish id keyed to the fire so the same firing isn't duplicated.
        let id = "agent-reminder-\(item.id)-\(item.firedAt ?? item.updatedAt)"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        logger.info("posted \(item.kind == .todo ? "todo" : "reminder", privacy: .public) notification")
    }

    // Present banners even when the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
