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

    // Dock icon click (only exists while Settings is open) brings Settings forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let settings, settings.isVisible {
            settings.show()
        } else {
            launchpad.show()
        }
        return false
    }

    // Target of the ⌘, main menu item.
    @objc func openSettingsFromMenu(_ sender: Any?) {
        showSettings()
    }

    // Target of the ⌘Q main menu item (visible menu bar while Settings is open).
    @objc func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // ⌘Q in the main menu only works in regular mode, so it never fires from the panels.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(quitFromMenu(_:)) {
            return NSApp.activationPolicy() == .regular
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
