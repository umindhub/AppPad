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
    // Re-check delays after show(): cooperative activation may be denied or land late.
    private static let retryDelays: [TimeInterval] = [0, 0.05, 0.15, 0.3]

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    // App that was frontmost before Settings opened; gets focus back on close.
    private var previousApp: NSRunningApplication?
    // Bumped on every show / close; cancels pending activation retries.
    private var activationToken = 0
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
        activationToken &+= 1
        bringToFront(window, attempt: 0, token: activationToken)
    }

    // NSApp.activate() is cooperative (macOS 14+): it can be refused, e.g. right after the
    // status menu or a non-activating panel closed. orderFrontRegardless puts the window
    // above other apps even then; activation is retried until AppPad is active.
    private func bringToFront(_ window: NSWindow, attempt: Int, token: Int) {
        guard token == activationToken, attempt == 0 || window.isVisible else { return }
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        guard attempt < Self.retryDelays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) { [weak self] in
            guard let self, token == self.activationToken, window.isVisible else { return }
            if NSApp.isActive {
                // Active but key landed elsewhere: just take key, no more retries.
                if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
                return
            }
            self.bringToFront(window, attempt: attempt + 1, token: token)
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
        // Follow the user to the current Space (also over a full-screen app)
        // instead of staying on the Space it was first opened on.
        newWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        newWindow.setContentSize(Self.defaultSize)
        newWindow.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: newWindow, queue: .main
        ) { [weak self] _ in
            self?.activationToken &+= 1   // stop pending activation retries
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
