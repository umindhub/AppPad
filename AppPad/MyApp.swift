import AppKit

// App entry point: menu-bar-only agent app with AppKit lifecycle.
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let launchpad: LaunchpadController
    private let clipboard: ClipboardController
    private let workflows: WorkflowPanelController
    private var statusBar: StatusBarController?
    private var settings: SettingsWindowController?
    private var workflowPanelHotKeyID: UInt32?
    private var clipboardHotKeyIDs: [UInt32] = []
    private var appHotKeyIDs: [UInt32] = []
    private var windowHotKeyIDs: [UInt32] = []
    private var prefsTask: Task<Void, Never>?
    // Last other app that was frontmost (gets focus back after a Dock click).
    private let frontmost = FrontmostAppTracker()
    // Dock click → focus handed back to the previous app, then this runs.
    private var handoffAction: (() -> Void)?
    private var handoffObserver: NSObjectProtocol?
    private var handoffToken = 0

    override init() {
        launchpad = LaunchpadController()
        clipboard = ClipboardController()
        workflows = WorkflowPanelController(launchpad: launchpad)
        super.init()
    }

    static func main() {
        // Import data from the old AppsPad bundle id before controllers read it.
        LegacyMigration.runIfNeeded()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        launchpad.onOpenSettings = { [weak self] in self?.showSettings() }
        launchpad.onRequestShortcut = { [weak self] app in self?.addAppShortcut(for: app) }
        // ⌘⇧J / ⌘⇧K: previous / next of Launchpad → Clipboard → Workflows (wraps around).
        launchpad.onSwitchPanel = { [weak self] step in self?.switchPanel(from: .launchpad, step: step) }
        clipboard.onSwitchPanel = { [weak self] step in self?.switchPanel(from: .clipboard, step: step) }
        workflows.onSwitchPanel = { [weak self] step in self?.switchPanel(from: .workflows, step: step) }
        clipboard.onOpenSettings = { [weak self] in self?.showSettings() }
        workflows.onOpenSettings = { [weak self] in self?.showSettings() }
        workflows.onEditWorkflow = { [weak self] id in self?.editWorkflow(id) }
        // Window shortcut without Accessibility permission → Settings › Windows (Grant Access).
        WindowManager.shared.onNeedsAccess = { [weak self] in
            UserDefaults.standard.set(SettingsTab.windows.rawValue, forKey: SettingsTab.storageKey)
            self?.showSettings()
        }
        launchpad.start()
        clipboard.start()
        workflows.start()
        statusBar = StatusBarController(
            onOpen: { [weak self] in self?.launchpad.show() },
            onClipboard: { [weak self] in self?.clipboard.show(.history) },
            onSettings: { [weak self] in self?.showSettings() },
            onWorkflows: { [weak self] in self?.workflows.show() }
        )
        registerHotKeys()
        PinchGestureMonitor.shared.onPinch = { [weak self] event in self?.handlePinch(event) }
        PinchGestureMonitor.shared.setEnabled(Preferences.shared.pinchToOpen)
        // One-time hint: which system gestures to turn off (in order).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            PinchSetupGuide.showOnceIfNeeded()
            // ⌘Space is Spotlight's until the user frees it.
            SpotlightShortcut.showGuideOnceIfNeeded()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesDidChange(_:)),
            name: .preferencesDidChange, object: nil
        )
    }

    // Click on AppPad pinned in the Dock (app already running) toggles Launchpad.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleLaunchpadFromDock()
        return false
    }

    // The Dock click activates AppPad. Without Settings open, focus goes back to the previous
    // app first, so the panel opens non-activating (same state as pinch / menu bar).
    private func toggleLaunchpadFromDock() {
        let settingsOpen = settings?.isVisible == true
        // Panel may already have closed on resign key from the same click.
        if launchpad.isShown || launchpad.didJustCloseFromOutsideClick {
            launchpad.hide()
            if !settingsOpen { handOffActivation() }
            return
        }
        clipboard.hide()
        workflows.hide()
        if settingsOpen {
            launchpad.show()
        } else {
            handOffActivation { [weak self] in self?.launchpad.show() }
        }
    }

    // Activate the previous app, run the action once AppPad resigned active (or after a timeout).
    private func handOffActivation(then action: (() -> Void)? = nil) {
        handoffToken &+= 1
        clearHandoffObserver()
        let target = frontmost.last.flatMap { $0.isTerminated ? nil : $0 } ?? FrontmostAppTracker.finder
        guard NSApp.isActive, let target else {
            handoffAction = nil
            action?()
            return
        }
        handoffAction = action
        let token = handoffToken
        handoffObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            // Next run loop: let the other app finish taking key before the panel does.
            DispatchQueue.main.async { self?.finishHandoff(token) }
        }
        _ = target.activate(from: NSRunningApplication.current, options: [])
        // Fallback if the activation is refused.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finishHandoff(token)
        }
    }

    private func finishHandoff(_ token: Int) {
        guard token == handoffToken else { return }   // stale or already done
        handoffToken &+= 1
        clearHandoffObserver()
        let action = handoffAction
        handoffAction = nil
        action?()
    }

    private func clearHandoffObserver() {
        if let handoffObserver { NotificationCenter.default.removeObserver(handoffObserver) }
        handoffObserver = nil
    }

    // Target of the ⌘, main menu item.
    @objc func openSettingsFromMenu(_ sender: Any?) {
        showSettings()
    }

    // Target of the ⌘Q main menu item (works while Settings has focus).
    @objc func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // ⌘Q only while the Settings window is key, so it never fires from the panels.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(quitFromMenu(_:)) {
            return settings?.isKey == true
        }
        return true
    }

    private func showSettings() {
        launchpad.hide()
        clipboard.hide()
        workflows.hide()
        if settings == nil {
            settings = SettingsWindowController(
                onResetLayout: { [weak self] in self?.launchpad.confirmResetLayout() },
                clipboard: ClipboardMaintenance(
                    count: { [weak self] range in self?.clipboard.historyCount(in: range) ?? 0 },
                    delete: { [weak self] range in self?.clipboard.deleteHistory(in: range) }
                )
            )
        }
        settings?.show()
    }

    private enum Panel: CaseIterable {
        case launchpad, clipboard, workflows
    }

    // Clipboard is skipped while it is turned off in Settings.
    private func switchPanel(from current: Panel, step: Int) {
        let cycle = Panel.allCases.filter { $0 != .clipboard || Preferences.shared.clipboardEnabled }
        guard let index = cycle.firstIndex(of: current) else { return }
        let target = cycle[(index + step + cycle.count) % cycle.count]
        switch target {
        case .launchpad: launchpad.show()
        case .clipboard: clipboard.show(.history)
        case .workflows: workflows.show()
        }
    }

    // ⌘↩ in the Workflow panel: Settings › Workflows with this workflow's editor open.
    private func editWorkflow(_ id: UUID) {
        UserDefaults.standard.set(SettingsTab.workflows.rawValue, forKey: SettingsTab.storageKey)
        WorkflowStore.shared.requestEdit(id)
        showSettings()
    }

    // Pinch in opens, spread closes; the panel follows the fingers (macOS 15 Launchpad).
    private func handlePinch(_ event: PinchEvent) {
        switch event.phase {
        case .began:
            switch event.direction {
            case .pinchIn:
                guard !launchpad.isShown else { return }
                clipboard.hide()
                workflows.hide()
                launchpad.beginInteractiveOpen()
            case .spread:
                launchpad.beginInteractiveClose()
            }
            launchpad.updateInteractive(progress: event.progress)
        case .changed:
            launchpad.updateInteractive(progress: event.progress)
        case .ended:
            launchpad.endInteractive(velocity: event.velocity)
        }
    }

    // "Set Shortcut…" from the launcher: add an empty row, then open the App Shortcuts tab.
    private func addAppShortcut(for app: AppInfo) {
        let prefs = Preferences.shared
        if !prefs.appHotKeys.contains(where: { $0.key == app.key }) {
            prefs.appHotKeys.append(AppHotKey(key: app.key, path: app.url.path, name: app.name, combo: nil))
        }
        UserDefaults.standard.set(SettingsTab.shortcuts.rawValue, forKey: SettingsTab.storageKey)
        showSettings()
    }

    // Debounce bursts of preference changes (sliders, steppers).
    @objc private func preferencesDidChange(_ note: Notification) {
        prefsTask?.cancel()
        prefsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.registerHotKeys()
            PinchGestureMonitor.shared.setEnabled(Preferences.shared.pinchToOpen)
            self.launchpad.applyPreferences()
            self.clipboard.applyPreferences()
        }
    }

    private func registerHotKeys() {
        let center = HotKeyCenter.shared
        if let id = workflowPanelHotKeyID { center.unregister(id) }
        workflowPanelHotKeyID = nil
        appHotKeyIDs.forEach { center.unregister($0) }
        appHotKeyIDs = []
        clipboardHotKeyIDs.forEach { center.unregister($0) }
        clipboardHotKeyIDs = []
        windowHotKeyIDs.forEach { center.unregister($0) }
        windowHotKeyIDs = []

        let prefs = Preferences.shared
        // ⌘Space → Workflow panel. Launchpad has no global shortcut (pinch / menu bar).
        if let combo = prefs.workflowPanelHotKey {
            workflowPanelHotKeyID = center.register(combo) { [weak self] in
                self?.workflows.toggle()
            }
        }
        if prefs.clipboardEnabled {
            if let combo = prefs.clipboardHotKey {
                clipboardHotKeyIDs.append(center.register(combo) { [weak self] in self?.clipboard.toggle(.history) })
            }
            if let combo = prefs.clipboardSavedHotKey {
                clipboardHotKeyIDs.append(center.register(combo) { [weak self] in self?.clipboard.toggle(.saved) })
            }
        }
        if prefs.windowControlEnabled {
            for action in WindowAction.allCases {
                guard let combo = prefs.windowHotKeys[action] else { continue }
                windowHotKeyIDs.append(center.register(combo) { WindowManager.shared.perform(action) })
            }
        }
        for hotKey in prefs.appHotKeys {
            guard let combo = hotKey.combo else { continue }
            appHotKeyIDs.append(center.register(combo) { AppActivator.toggle(hotKey) })
        }

        let ok = workflowPanelHotKeyID.map { center.isInstalled($0) } ?? true
        if !ok { NSLog("Workflow panel hotkey could not be registered (taken by another app?)") }
        statusBar?.hotKeyAvailable = ok
        statusBar?.refresh()
    }
}

// Tracks the last frontmost app other than AppPad.
private final class FrontmostAppTracker {
    private(set) var last: NSRunningApplication?
    private var observer: NSObjectProtocol?

    init() {
        record(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.record(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        last = app
    }

    // Always running; fallback when the previous app is gone.
    static var finder: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    }
}
