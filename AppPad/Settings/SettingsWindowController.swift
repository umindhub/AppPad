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

// Settings window (SwiftUI split view hosted in AppKit; not performance critical).
// The app stays a menu-bar-only agent (no Dock icon) while it is open.
// Closing it hands focus back to the app that was frontmost before.
final class SettingsWindowController {
    static let defaultSize = NSSize(width: 940, height: 700)

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    // App that was frontmost before Settings opened; gets focus back on close.
    private var previousApp: NSRunningApplication?
    private let onResetLayout: () -> Void
    private let clipboard: ClipboardMaintenance

    var isVisible: Bool { window?.isVisible == true }
    // ⌘Q is only enabled while Settings has focus (never from the panels).
    var isKey: Bool { window?.isKeyWindow == true }

    init(onResetLayout: @escaping () -> Void, clipboard: ClipboardMaintenance) {
        self.onResetLayout = onResetLayout
        self.clipboard = clipboard
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    func show() {
        let window = window ?? makeWindow()
        if !window.isVisible {
            rememberFrontmostApp()
            window.center()
        }
        NSApp.unhide(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation can land a run loop late (e.g. opened from a non-activating panel); retry once.
        DispatchQueue.main.async {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(
            prefs: .shared, onResetLayout: onResetLayout, clipboard: clipboard))
        // SwiftUI drives the toolbar (split view) and title (selected tab).
        host.sceneBridgingOptions = [.toolbars, .title]
        host.sizingOptions = [.minSize]

        let newWindow = SettingsWindow(contentViewController: host)
        newWindow.title = String(localized: "AppPad Settings")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        newWindow.toolbarStyle = .unified
        newWindow.isReleasedWhenClosed = false
        newWindow.setContentSize(Self.defaultSize)
        newWindow.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: newWindow, queue: .main
        ) { [weak self] _ in
            // Run after the window is ordered out.
            DispatchQueue.main.async { self?.restoreFocus() }
        }
        window = newWindow
        return newWindow
    }

    private func rememberFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = front
        }
    }

    // An active agent app with no window would swallow the keyboard: give focus back.
    private func restoreFocus() {
        guard !isVisible else { return }                       // reopened meanwhile
        let target = previousApp.flatMap { $0.isTerminated ? nil : $0 } ?? Self.finder
        previousApp = nil
        guard NSApp.isActive, let target else { return }
        _ = target.activate(from: NSRunningApplication.current, options: [])
    }

    // Always running; fallback when the previous app is gone.
    private static var finder: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    }
}
