import AppKit
import SwiftUI

// ⌘W closes Settings (the agent app has no File menu).
// super runs first so text fields and the shortcut recorder still get ⌘-keys.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return false
    }
}

// Settings window (SwiftUI form hosted in AppKit; not performance critical).
final class SettingsWindowController {
    private var window: NSWindow?
    private let onResetLayout: () -> Void
    private let clipboard: ClipboardMaintenance

    init(onResetLayout: @escaping () -> Void, clipboard: ClipboardMaintenance) {
        self.onResetLayout = onResetLayout
        self.clipboard = clipboard
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(
                prefs: .shared, onResetLayout: onResetLayout, clipboard: clipboard))
            let newWindow = SettingsWindow(contentViewController: host)
            newWindow.title = String(localized: "AppPad Settings")
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.unhide(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
