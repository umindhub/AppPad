import SwiftUI
import AppKit

// System gestures that collide with AppPad's four-finger pinch.
// Order matters: Show Desktop must be turned off before Apps.
enum PinchSetupGuide {
    struct Step: Identifiable {
        let id: Int
        let title: String
        let gesture: String
    }

    static let steps: [Step] = [
        Step(id: 1,
             title: String(localized: "Show Desktop"),
             gesture: String(localized: "Spread with thumb and three fingers")),
        Step(id: 2,
             title: String(localized: "Apps"),
             gesture: String(localized: "Pinch with thumb and three fingers")),
    ]

    private static let shownKey = "pinchSetupGuideShown"

    static func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // First launch only, and only while pinch-to-open is on.
    @MainActor
    static func showOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard Preferences.shared.pinchToOpen, !defaults.bool(forKey: shownKey) else { return }
        defaults.set(true, forKey: shownKey)
        show()
    }

    @MainActor
    static func show() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Use four-finger pinch for AppPad")
        alert.informativeText = String(localized: "Turn off these macOS gestures so they don't fire together with AppPad.")
        alert.addButton(withTitle: String(localized: "Open Trackpad Settings"))
        alert.addButton(withTitle: String(localized: "Later"))

        let host = NSHostingView(rootView: PinchSetupStepsView(showsButton: false).frame(width: 340))
        host.frame.size = host.fittingSize
        alert.accessoryView = host

        NSApp.unhide(nil)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openTrackpadSettings()
        }
    }
}

// Numbered steps (used inline in Settings and inside the alert).
struct PinchSetupStepsView: View {
    var showsButton: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In System Settings › Trackpad › More Gestures, turn off in this order:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(PinchSetupGuide.steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Text(verbatim: "\(step.id)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.accentColor))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title).fontWeight(.semibold)
                        Text(step.gesture)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Label("The order is important — turn off Show Desktop first.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            if showsButton {
                Button("Open Trackpad Settings…", action: PinchSetupGuide.openTrackpadSettings)
            }
        }
        .padding(.vertical, 2)
    }
}
