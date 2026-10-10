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
// While it is open the app is a regular app with a Dock icon; closing it
// (⌘W or the close button) turns the app back into a menu-bar-only agent.
final class SettingsWindowController {
    static let defaultSize = NSSize(width: 940, height: 700)

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    // Pending switch back to .accessory, waiting for the app to lose focus.
    private var resignObserver: NSObjectProtocol?
    // When the app last became .regular; the menu bar needs time to settle.
    private var regularSince = Date.distantPast
    // Bumped on every show → stale delayed closes are dropped.
    private var generation = 0
    // Min time between .regular and handing the menu bar back. A quick ⌘W right
    // after opening would otherwise restart the menu bar switch mid-animation
    // and every status item jumps.
    private static let settleDelay: TimeInterval = 0.6
    // App that was frontmost before Settings opened; gets focus back on close.
    private var previousApp: NSRunningApplication?
    private let onResetLayout: () -> Void
    private let clipboard: ClipboardMaintenance

    var isVisible: Bool { window?.isVisible == true }

    init(onResetLayout: @escaping () -> Void, clipboard: ClipboardMaintenance) {
        self.onResetLayout = onResetLayout
        self.clipboard = clipboard
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func show() {
        generation &+= 1
        let window = window ?? makeWindow()
        if !window.isVisible {
            rememberFrontmostApp()
            window.center()
        }
        // Dock icon + visible menu bar only while Settings is open.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            regularSince = Date()
        }
        NSApp.unhide(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Policy change can leave the window behind the previous app; retry next run loop.
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
            self?.scheduleClose()
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

    // Back to menu-bar-only. Focus goes to the previous app FIRST and the policy
    // switches only after AppPad resigned active: the menu bar changes once
    // (AppPad menus → that app's menus) instead of AppPad → empty → that app (flicker).
    // Wait until the open transition has settled, then hand the menu bar back once.
    private func scheduleClose() {
        let token = generation
        let wait = max(0, Self.settleDelay - Date().timeIntervalSince(regularSince))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.generation == token else { return }   // reopened meanwhile
            self.didClose()
        }
    }

    private func didClose() {
        guard !isVisible else { return }
        if let pending = resignObserver {           // closed again before the last switch ran
            NotificationCenter.default.removeObserver(pending)
            resignObserver = nil
        }
        let target = previousApp.flatMap { $0.isTerminated ? nil : $0 } ?? Self.finder
        previousApp = nil

        guard NSApp.isActive, let target else {
            NSApp.setActivationPolicy(.accessory)
            return
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            self?.finishClose()
        }
        _ = target.activate(from: NSRunningApplication.current, options: [])
        // Fallback if the activation is refused.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finishClose()
        }
    }

    private func finishClose() {
        guard let observer = resignObserver else { return }   // already done
        NotificationCenter.default.removeObserver(observer)
        resignObserver = nil
        guard !isVisible else { return }                       // reopened meanwhile
        NSApp.setActivationPolicy(.accessory)
    }

    // Always running; what macOS activates when an app hides with nothing behind it.
    private static var finder: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    }
}
