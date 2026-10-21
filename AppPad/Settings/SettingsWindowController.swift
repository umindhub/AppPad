import AppKit
import SwiftUI

// ⌘W closes Settings (the agent app has no File menu); ⌘F focuses the visible search field.
// super runs first so text fields and the shortcut recorder still get ⌘-keys.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w":
            performClose(nil)
            return true
        case "f":
            guard let search = contentView.flatMap({ Self.visibleSearchField(in: $0) }) else { return false }
            search.field.selectText(nil)   // focus + select existing text, like ⌘F elsewhere
            return true
        default:
            return false
        }
    }

    // First on-screen GlassSearchFieldView of the current tab (e.g. App Shortcuts).
    private static func visibleSearchField(in view: NSView) -> GlassSearchFieldView? {
        if let search = view as? GlassSearchFieldView, !search.isHiddenOrHasHiddenAncestor, search.field.isEnabled {
            return search
        }
        for sub in view.subviews {
            if let found = visibleSearchField(in: sub) { return found }
        }
        return nil
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
    // Keeps the sidebar at its window-width ratio while the window resizes.
    private var resizeObserver: NSObjectProtocol?
    // App that was frontmost before Settings opened; gets focus back on close.
    private var previousApp: NSRunningApplication?
    // Bumped on every show / close; cancels pending activation retries.
    private var activationToken = 0
    private let onResetLayout: () -> Void
    private let clipboard: ClipboardMaintenance

    var isVisible: Bool { window?.isVisible == true }
    // ⌘Q is only enabled while Settings has focus (never from the panels).
    // A sheet or alert on Settings is its own key window: walk up sheetParent so ⌘Q still works there.
    var isKey: Bool {
        guard let window, var key = NSApp.keyWindow else { return false }
        while key !== window {
            guard let parent = key.sheetParent else { return false }
            key = parent
        }
        return true
    }

    init(onResetLayout: @escaping () -> Void, clipboard: ClipboardMaintenance) {
        self.onResetLayout = onResetLayout
        self.clipboard = clipboard
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    // screen: display the request came from (panel / menu bar); nil = keep an open window where it is.
    // returningFocusTo: app to get focus back on close, if AppPad is already frontmost by now.
    func show(on screen: NSScreen? = nil, returningFocusTo fallback: NSRunningApplication? = nil) {
        let window = window ?? makeWindow()
        if !window.isVisible {
            rememberFrontmostApp(fallback: fallback)
            Self.center(window, on: screen ?? Self.mouseScreen)
            ShortcutAppsCache.preload()   // App Shortcuts tab opens with a ready list
        } else if let screen, !Self.isOn(window, screen) {
            Self.center(window, on: screen)   // open on another display: follow the request
        }
        // SwiftUI opens the split view with its own narrow sidebar: set the width after layout,
        // once before showing and once more after SwiftUI's deferred pass.
        window.layoutIfNeeded()
        Self.applySidebarWidth(in: window)
        activationToken &+= 1
        bringToFront(window, attempt: 0, token: activationToken)
        DispatchQueue.main.async { Self.applySidebarWidth(in: window) }
    }

    // NSApp.activate() is cooperative (macOS 14+): it can be refused, e.g. right after the
    // status menu or a non-activating panel closed. orderFrontRegardless puts the window
    // above other apps even then; activation is retried until AppPad is active.
    private func bringToFront(_ window: NSWindow, attempt: Int, token: Int) {
        guard token == activationToken, attempt == 0 || window.isVisible else { return }
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        // Retries fall back to the legacy call, which cooperative activation refuses less often.
        if attempt == 0 { NSApp.activate() } else { LegacyActivation.activate() }
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
        newWindow.title = String(localized: "AppPad Settings", table: "Settings")
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
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: newWindow, queue: .main
        ) { note in
            guard let resized = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { Self.applySidebarWidth(in: resized) }
        }
        window = newWindow
        return newWindow
    }

    // AppPad may already be frontmost (activated with the request): then use the caller's app.
    private func rememberFrontmostApp(fallback: NSRunningApplication?) {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = front
        } else if let fallback {
            previousApp = fallback
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

// MARK: - Placement

@MainActor
extension SettingsWindowController {
    // Display under the mouse (menu bar click, banner click, …).
    static var mouseScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
    }

    // Centered in the display's visible frame; shrinks to fit a smaller display.
    static func center(_ window: NSWindow, on screen: NSScreen?) {
        guard let screen else { window.center(); return }
        let area = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        frame.origin.x = (area.midX - frame.width / 2).rounded()
        frame.origin.y = (area.midY - frame.height / 2).rounded()
        window.setFrame(frame, display: false)
    }

    // NSScreen objects get recreated on display changes: compare by display id.
    static func isOn(_ window: NSWindow, _ screen: NSScreen) -> Bool {
        guard let current = window.screen else { return false }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (current.deviceDescription[key] as? NSNumber) == (screen.deviceDescription[key] as? NSNumber)
    }
}

// Deprecated activate(ignoringOtherApps:) through a protocol requirement (no deprecation warning).
// Still honored in cases where the cooperative NSApp.activate() is refused.
@MainActor
private protocol LegacyActivating {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: LegacyActivating {}

@MainActor
private enum LegacyActivation {
    static func activate() {
        (NSApp as LegacyActivating).activate(ignoringOtherApps: true)
    }
}

// MARK: - Sidebar width

@MainActor
extension SettingsWindowController {
    // Forces the split view divider to the sidebar width computed from the window width
    // (SwiftUI ignores navigationSplitViewColumnWidth here and opens a narrow sidebar).
    static func applySidebarWidth(in window: NSWindow) {
        guard let content = window.contentView,
              let split = firstSplitView(in: content),
              let sidebar = split.arrangedSubviews.first else { return }
        let target = SettingsView.sidebarWidth(for: content.bounds.width)
        guard abs(sidebar.frame.width - target) >= 0.5 else { return }
        split.setPosition(target, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
    }

    // Depth-first; the SwiftUI split view sits inside the hosting view.
    private static func firstSplitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        for sub in view.subviews {
            if let found = firstSplitView(in: sub) { return found }
        }
        return nil
    }
}
