import AppKit
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() { }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                AppLogger.shared.log("通知授权失败：\(error.localizedDescription)", category: "notification")
            } else {
                AppLogger.shared.log("通知授权：\(granted)", category: "notification")
            }
        }
    }

    func post(title: String, body: String) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
