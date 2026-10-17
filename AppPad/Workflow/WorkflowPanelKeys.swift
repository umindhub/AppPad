import AppKit
import Carbon.HIToolbox

extension KeyCombo {
    // Workflow panel: ⌘Space (Spotlight's default, see SpotlightShortcut).
    static let defaultWorkflowPanel = KeyCombo(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey),
        keyLabel: "Space"
    )

    func matches(keyCode code: UInt16, carbonModifiers mods: UInt32) -> Bool {
        keyCode == UInt32(code) && modifiers == mods
    }
}

// Shortcuts that only work while the Workflow panel is open.
enum WorkflowPanelKeys {
    // Panel / text-field shortcuts a workflow may not take.
    private static let reservedCommandKeys: Set<Int> = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Delete,
        kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_W, kVK_ANSI_Comma, kVK_ANSI_Q,
        kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_A, kVK_ANSI_Z,
    ]

    static func isReserved(_ combo: KeyCombo) -> Bool {
        let code = Int(combo.keyCode)
        if combo.modifiers == UInt32(cmdKey) { return reservedCommandKeys.contains(code) }
        if combo.modifiers == UInt32(cmdKey | shiftKey) { return code == kVK_ANSI_Z }
        return false
    }

    // Why this in-panel shortcut can't be used, or nil.
    static func conflict(for combo: KeyCombo?, excluding id: UUID) -> String? {
        guard let combo else { return nil }
        if isReserved(combo) { return String(localized: "Used by the Workflow panel") }
        if let other = WorkflowStore.shared.workflows.first(where: {
            $0.id != id && $0.panelKey?.keyCode == combo.keyCode && $0.panelKey?.modifiers == combo.modifiers
        }) {
            return String(localized: "Same shortcut as \(other.displayName)")
        }
        return nil
    }
}

// macOS reserves ⌘Space for Spotlight (symbolic hotkey 64). While it is on, the system
// gets the key first, so the Workflow panel shortcut never fires.
enum SpotlightShortcut {
    private static let shownKey = "spotlightGuideShown"

    static func conflicts(with combo: KeyCombo?) -> Bool {
        guard let combo else { return false }
        let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        guard let entry = hotKeys?["64"] as? [String: Any] else {
            // Never customized → system default ⌘Space, enabled.
            return combo.keyCode == UInt32(kVK_Space) && combo.modifiers == UInt32(cmdKey)
        }
        let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? true
        guard enabled,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3 else { return false }
        return combo.keyCode == parameters[1].uint32Value && cocoaFlags(combo) == parameters[2].uintValue
    }

    // Carbon modifiers → NSEvent modifier flag bits (format used by symbolichotkeys).
    private static func cocoaFlags(_ combo: KeyCombo) -> UInt {
        var flags: NSEvent.ModifierFlags = []
        if combo.modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if combo.modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if combo.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if combo.modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags.rawValue
    }

    // MARK: - Turning Spotlight's shortcut off / on

    enum ToggleResult {
        case applied        // saved and active right away
        case needsRelogin   // saved; the running session still uses the old state
        case failed         // could not be saved: change it in System Settings
    }

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let hotKeysKey = "AppleSymbolicHotKeys" as CFString
    private static let spotlightID: Int32 = 64
    // ' ', kVK_Space, ⌘ (system default when the entry was never customized).
    private static let defaultParameters: [Int] = [32, Int(kVK_Space), Int(NSEvent.ModifierFlags.command.rawValue)]

    // True while "Show Spotlight search" is turned off (by AppPad or by the user).
    static var isTurnedOff: Bool {
        guard let entry = storedEntry() else { return false }
        return (entry["enabled"] as? NSNumber)?.boolValue == false
    }

    // Live state of the running session, nil if the private API is missing.
    static var isEnabledInSession: Bool? {
        guard let fn = sessionIsEnabled else { return nil }
        return fn(spotlightID)
    }

    // Persists the change in com.apple.symbolichotkeys and applies it to the session,
    // so no log out is needed. A custom Spotlight key combination is kept as it is.
    @discardableResult
    static func setSpotlightSearchEnabled(_ enabled: Bool) -> ToggleResult {
        var all = (CFPreferencesCopyValue(hotKeysKey, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                   as? [String: Any]) ?? [:]
        var entry = all[String(spotlightID)] as? [String: Any] ?? [:]
        if entry["value"] == nil {
            entry["value"] = ["parameters": defaultParameters, "type": "standard"] as [String: Any]
        }
        entry["enabled"] = enabled
        all[String(spotlightID)] = entry
        CFPreferencesSetValue(hotKeysKey, all as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        let stored = (storedEntry()?["enabled"] as? NSNumber)?.boolValue
        guard stored == enabled else { return .failed }

        let sessionOK = applyToSession(enabled)
        runActivateSettings()
        // Re-register the Workflow hotkey now that the key may be free (also refreshes the menu ⚠︎).
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        return sessionOK ? .applied : .needsRelogin
    }

    private static func storedEntry() -> [String: Any]? {
        let all = CFPreferencesCopyValue(hotKeysKey, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String: Any]
        return all?[String(spotlightID)] as? [String: Any]
    }

    // MARK: Session (SkyLight private API)

    private typealias SetEnabledFn = @convention(c) (Int32, Bool) -> Int32
    private typealias IsEnabledFn = @convention(c) (Int32) -> Bool

    private static let skyLight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ names: [String], as type: T.Type) -> T? {
        let handles = [skyLight, UnsafeMutableRawPointer(bitPattern: -2)]   // -2 = RTLD_DEFAULT
        for handle in handles.compactMap({ $0 }) {
            for name in names {
                if let sym = dlsym(handle, name) { return unsafeBitCast(sym, to: type) }
            }
        }
        return nil
    }

    private static let sessionSetEnabled = symbol(
        ["SLSSetSymbolicHotKeyEnabled", "CGSSetSymbolicHotKeyEnabled"], as: SetEnabledFn.self)
    private static let sessionIsEnabled = symbol(
        ["SLSIsSymbolicHotKeyEnabled", "CGSIsSymbolicHotKeyEnabled"], as: IsEnabledFn.self)

    private static func applyToSession(_ enabled: Bool) -> Bool {
        guard let set = sessionSetEnabled, set(spotlightID, enabled) == 0 else { return false }
        if let live = isEnabledInSession { return live == enabled }
        return true
    }

    // Asks running processes to reload the hotkey preferences (best effort, async).
    private static func runActivateSettings() {
        let path = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-u"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func openKeyboardShortcuts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // Once, at launch, only while Spotlight still holds the Workflow shortcut.
    static func showGuideOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard conflicts(with: Preferences.shared.workflowPanelHotKey), !defaults.bool(forKey: shownKey) else { return }
        defaults.set(true, forKey: shownKey)
        showGuide()
    }

    static func showGuide() {
        let combo = Preferences.shared.workflowPanelHotKey?.displayString ?? ""
        let alert = NSAlert()
        alert.messageText = String(localized: "\(combo) is used by Spotlight")
        alert.informativeText = String(localized: "To open AppPad Workflows with \(combo), go to System Settings › Keyboard › Keyboard Shortcuts › Spotlight and turn off “Show Spotlight search” (or give it another shortcut).")
        alert.addButton(withTitle: String(localized: "Open Keyboard Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.unhide(nil)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openKeyboardShortcuts()
        }
    }
}
