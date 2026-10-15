import Foundation
import UserNotifications

// Banner with a workflow's result (asks for notification permission on first use).
final class WorkflowNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkflowNotifier()

    private var authorized: Bool?

    func post(title: String, body: String) {
        Task {
            guard await ensureAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body.count > 300 ? String(body.prefix(300)) + "…" : body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func ensureAuthorized() async -> Bool {
        if let authorized { return authorized }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorized = granted
        return granted
    }

    // Show banners even while AppPad is active (e.g. Settings window in front).
    // Completion-handler form: async @objc delegate methods crash the Swift 6.4 compiler here.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
