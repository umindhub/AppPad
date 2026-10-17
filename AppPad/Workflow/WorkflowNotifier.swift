import Foundation
import UserNotifications

// Banner with a workflow's result (asks for notification permission on first use).
// A click opens Settings › Workflows instead of Launchpad.
final class WorkflowNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkflowNotifier()

    // A reopen event this soon after a banner click belongs to that click.
    private static let clickGrace: TimeInterval = 1.5

    // Banner clicked. A click before this is set is kept until it is.
    var onOpen: (() -> Void)? {
        didSet { flushPendingClick() }
    }

    private var authorized: Bool?
    private var posted: Set<String> = []      // banners of this session not yet seen gone
    private var handled: Set<String> = []     // clicks already acted on (launch + delegate)
    private var pendingClick = false
    private var lastClick: TimeInterval = -.infinity

    // Call before launch finishes so a click that launched the app is delivered too.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func post(title: String, body: String) {
        Task {
            guard await ensureAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body.count > 300 ? String(body.prefix(300)) + "…" : body
            let id = UUID().uuidString
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
                posted.insert(id)
            } catch {
                NSLog("Workflow notification failed: \(error.localizedDescription)")
            }
        }
    }

    var clickedRecently: Bool {
        ProcessInfo.processInfo.systemUptime - lastClick < Self.clickGrace
    }

    // False: a reopen event can't be a banner click, toggle Launchpad right away.
    var mayHaveBeenClicked: Bool { clickedRecently || !posted.isEmpty }

    // Reopen event (Dock or banner click): true if a banner was just clicked.
    // A clicked banner leaves Notification Center; its response may arrive after the reopen.
    func reopenCameFromClick() async -> Bool {
        if clickedRecently { return true }
        guard !posted.isEmpty else { return false }
        let delivered = await Self.deliveredIDs()
        let gone = posted.subtracting(delivered)
        posted.subtract(gone)
        guard !gone.isEmpty else { return clickedRecently }
        for _ in 0..<8 {
            if clickedRecently { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return clickedRecently   // banner was just dismissed, not clicked
    }

    // Request id of a clicked banner (default action only, not Dismiss).
    nonisolated static func clickedRequestID(_ response: UNNotificationResponse) -> String? {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return nil }
        return response.notification.request.identifier
    }

    func handleClick(requestID: String) {
        lastClick = ProcessInfo.processInfo.systemUptime
        posted.remove(requestID)
        guard handled.insert(requestID).inserted else { return }
        if let onOpen {
            onOpen()
        } else {
            pendingClick = true
        }
    }

    private func flushPendingClick() {
        guard let onOpen, pendingClick else { return }
        pendingClick = false
        onOpen()
    }

    private func ensureAuthorized() async -> Bool {
        if let authorized { return authorized }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorized = granted
        return granted
    }

    nonisolated private static func deliveredIDs() async -> Set<String> {
        let list = await UNUserNotificationCenter.current().deliveredNotifications()
        return Set(list.map(\.request.identifier))
    }

    // Show banners even while AppPad is active (e.g. Settings window in front).
    // Completion-handler form: async @objc delegate methods crash the Swift 6.4 compiler here.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Banner clicked while running (or right after a launch by the click).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let requestID = Self.clickedRequestID(response)
        completionHandler()
        guard let requestID else { return }
        Task { @MainActor in
            WorkflowNotifier.shared.handleClick(requestID: requestID)
        }
    }
}
