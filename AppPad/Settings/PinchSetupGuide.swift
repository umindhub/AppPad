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

    // First launch only, and only while pinch-to-open is on. completion runs when the
    // guide closes (or right away if it isn't needed), so the next guide can follow.
    @MainActor
    static func showOnceIfNeeded(then completion: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        guard Preferences.shared.pinchToOpen, !defaults.bool(forKey: shownKey) else {
            completion()
            return
        }
        defaults.set(true, forKey: shownKey)
        show(then: completion)
    }

    @MainActor private static var controller: PinchGuideWindowController?

    // Non-modal window (not NSAlert.runModal): a modal session blocks clicks on every
    // other window, so a Launchpad opened over it (pinch / cold launch) froze everything.
    @MainActor
    static func show(then completion: (() -> Void)? = nil) {
        if let controller {
            controller.present()
            return
        }
        let controller = PinchGuideWindowController { [completion] in
            PinchSetupGuide.controller = nil
            completion?()
        }
        self.controller = controller
        controller.present()
    }
}

// Window hosting the guide; onClose fires once (button, Esc or close box).
@MainActor
private final class PinchGuideWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private var onClose: (() -> Void)?

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let content = PinchGuideContent(
            onOpen: { [weak self] in
                PinchSetupGuide.openTrackpadSettings()
                self?.panel.close()
            },
            onLater: { [weak self] in self?.panel.close() }
        )
        let host = NSHostingView(rootView: content)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
    }

    func present() {
        // Center on the display under the mouse (same screen the panels use).
        if !panel.isVisible, let screen = PanelScreen.target() {
            let area = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                         y: area.midY - size.height / 2 + area.height * 0.1))
        }
        NSApp.unhide(nil)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        onClose = nil
        callback?()
    }
}

private struct PinchGuideContent: View {
    let onOpen: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: String(localized: "Use four-finger pinch for AppPad"))
                        .font(.headline)
                    Text(verbatim: String(localized: "Turn off these macOS gestures so they don't fire together with AppPad."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PinchSetupStepsView(showsButton: false)
            HStack {
                Spacer()
                Button(String(localized: "Later"), action: onLater)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Open Trackpad Settings"), action: onOpen)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)   // clear of the close box (full-size content view)
        .padding(.bottom, 18)
        .frame(width: 420)
    }
}

// Numbered steps (used inline in Settings and inside the guide window).
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
