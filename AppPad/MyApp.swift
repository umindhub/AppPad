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
    // System light / dark switch (Theme: Auto) → re-apply panel backgrounds.
    private var appearanceObservation: NSKeyValueObservation?
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
        // Read while the launch Apple Event is still current.
        let openedByUser = LaunchOrigin.isUserOpen()
        // Theme first: wallpaper prewarm picks blur params for the theme in effect.
        applyTheme()
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
        // Workflow Market link installed something: show it in Settings › Workflows.
        WorkflowLinkImporter.shared.onInstalled = { [weak self] in self?.showWorkflowSettings() }
        // Window shortcut without Accessibility permission → Settings › Windows (Grant Access).
        WindowManager.shared.onNeedsAccess = { [weak self] in
            UserDefaults.standard.set(SettingsTab.windows.rawValue, forKey: SettingsTab.storageKey)
            self?.showSettings()
        }
        launchpad.start()
        clipboard.start()
        workflows.start()
        // Settings › Backup reaches the layout and clipboard store through these hooks.
        BackupService.shared.clipboardStore = clipboard.store
        BackupService.shared.layoutProvider = { [weak self] in self?.launchpad.currentLayout }
        BackupService.shared.layoutRestorer = { [weak self] layout in self?.launchpad.restoreLayout(layout) }
        statusBar = StatusBarController(
            onOpen: { [weak self] in self?.launchpad.show() },
            onClipboard: { [weak self] in self?.clipboard.show(.history) },
            onSettings: { [weak self] in self?.showSettings() },
            onWorkflows: { [weak self] in self?.workflows.show() }
        )
        registerHotKeys()
        PinchGestureMonitor.shared.onPinch = { [weak self] event in self?.handlePinch(event) }
        PinchGestureMonitor.shared.setEnabled(Preferences.shared.pinchToOpen)
        // One-time hints, one after the other, only while no panel is up
        // (a guide under the full-screen Launchpad left nothing clickable).
        Task { @MainActor [weak self] in
            await self?.waitUntilPanelsIdle()
            // Which system gestures to turn off (in order).
            PinchSetupGuide.showOnceIfNeeded {
                Task { @MainActor [weak self] in
                    await self?.waitUntilPanelsIdle()
                    // ⌘Space is Spotlight's until the user frees it.
                    SpotlightShortcut.showGuideOnceIfNeeded()
                }
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesDidChange(_:)),
            name: .preferencesDidChange, object: nil
        )
        // App delegate lives for the whole process; the strong capture here is intended.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor [weak self] in self?.appearanceDidChange() }
        }
        if openedByUser { openLaunchpadAfterColdLaunch() }
    }

    // Returns once no panel has been on screen (or pending) for ~1 s.
    private func waitUntilPanelsIdle() async {
        var idleTicks = 0
        while idleTicks < 2 {
            try? await Task.sleep(for: .milliseconds(500))
            let busy = launchpad.isBusy || clipboard.isActive || workflows.isActive
            idleTicks = busy ? 0 : idleTicks + 1
        }
    }

    // Dock / Finder click while not running: no reopen event comes, so open Launchpad here
    // once apps and wallpaper are loaded (login-item launches stay silent).
    private func openLaunchpadAfterColdLaunch() {
        launchpad.showWhenReady { [weak self] in
            guard let self, !self.launchpad.isShown, self.settings?.isVisible != true else { return }
            self.clipboard.hide()
            self.workflows.hide()
            self.handOffActivation { [weak self] in self?.launchpad.show() }
        }
    }

    // apppad://import-workflow?url=… from the Workflow Market (apppad-dev:// in Dev).
    // Also called on a cold launch by a link; that launch never opens Launchpad.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if !WorkflowLinkImporter.shared.handle(url) {
                NSLog("Unhandled URL: \(url.absoluteString)")
            }
        }
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
        // Second click while the cold-launch show is still loading: cancel it.
        if launchpad.cancelPendingShow() {
            if !settingsOpen { handOffActivation() }
            return
        }
        // Panel may already have closed on resign key from the same click.
        if launchpad.isShown || launchpad.didJustCloseFromOutsideClick {
            launchpad.hide(animated: true)
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
        // Same slow fade as a click on empty space (a plain hide() would cut a running fade short).
        launchpad.hide(animated: true, duration: LaunchpadController.backgroundClickHideDuration)
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

    // Open and focused panel, if any.
    private var activePanel: Panel? {
        if launchpad.isShown { return .launchpad }
        if clipboard.isActive { return .clipboard }
        if workflows.isActive { return .workflows }
        return nil
    }

    // Global hotkey for a panel while another one is open: hand over like ⌘⇧J/K
    // (new panel opaque on top, old one closes after) instead of close + fade in.
    private func handOffIfNeeded(to target: Panel) {
        guard let current = activePanel, current != target else { return }
        switch current {
        case .launchpad: launchpad.beginHandOff()
        case .clipboard: clipboard.beginHandOff()
        case .workflows: workflows.beginHandOff()
        }
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

    private func showWorkflowSettings() {
        UserDefaults.standard.set(SettingsTab.workflows.rawValue, forKey: SettingsTab.storageKey)
        showSettings()
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
            self.applyTheme()
            self.applyBackgrounds()
        }
    }

    // General › Theme: nil follows the system.
    private func applyTheme() {
        let name: NSAppearance.Name?
        switch Preferences.shared.appTheme {
        case .auto: name = nil
        case .light: name = .aqua
        case .dark: name = .darkAqua
        }
        let target = name.flatMap { NSAppearance(named: $0) }
        if NSApp.appearance?.name != target?.name { NSApp.appearance = target }
    }

    // Light / dark switch (system or Theme setting): backgrounds use the other variant's values.
    private var lastVariant: ThemeVariant?

    private func appearanceDidChange() {
        let variant = PanelBackgroundSpec.currentVariant
        guard variant != lastVariant else { return }
        lastVariant = variant
        applyBackgrounds()
    }

    private func applyBackgrounds() {
        lastVariant = PanelBackgroundSpec.currentVariant
        WallpaperBlurCache.shared.prewarm()
        launchpad.applyPreferences()
        clipboard.applyPreferences()
        workflows.applyPreferences()
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
                self?.handOffIfNeeded(to: .workflows)
                self?.workflows.toggle()
            }
        }
        if prefs.clipboardEnabled {
            if let combo = prefs.clipboardHotKey {
                clipboardHotKeyIDs.append(center.register(combo) { [weak self] in
                    self?.handOffIfNeeded(to: .clipboard)
                    self?.clipboard.toggle(.history)
                })
            }
            if let combo = prefs.clipboardSavedHotKey {
                clipboardHotKeyIDs.append(center.register(combo) { [weak self] in
                    self?.handOffIfNeeded(to: .clipboard)
                    self?.clipboard.toggle(.saved)
                })
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

// How this process was started: Dock / Finder open vs. login item.
private enum LaunchOrigin {
    // Login launches within this many seconds of the Dock starting (= user login).
    private static let loginGrace: TimeInterval = 60

    static func isUserOpen() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication)
        else { return false }   // Xcode / launchd: no open event
        if event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return false
        }
        // SMAppService login launches may not carry the login-item flag: also treat
        // a launch right after the session started as a login launch.
        if LoginItem.isEnabled, let started = dockStartDate(),
           Date().timeIntervalSince(started) < loginGrace {
            return false
        }
        return true
    }

    // Dock starts with the user session.
    private static func dockStartDate() -> Date? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
