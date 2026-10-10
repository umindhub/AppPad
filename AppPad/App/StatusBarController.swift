import AppKit
import Carbon.HIToolbox

// Menu bar icon + menu (the app has no Dock icon).
// Shortcuts use real key equivalents so AppKit draws them right-aligned.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let openItem = NSMenuItem()
    private let clipboardItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    var hotKeyAvailable = true
    private let onOpen: () -> Void
    private let onClipboard: () -> Void
    private let onSettings: () -> Void

    init(onOpen: @escaping () -> Void, onClipboard: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onClipboard = onClipboard
        self.onSettings = onSettings
        super.init()

        item.button?.image = Self.makeIcon()

        openItem.target = self
        openItem.action = #selector(openLaunchpad)
        menu.addItem(openItem)

        clipboardItem.title = String(localized: "Open Clipboard")
        clipboardItem.target = self
        clipboardItem.action = #selector(openClipboard)
        menu.addItem(clipboardItem)

        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Checkmark sits in the shortcut column (right side) instead of the left state column.
        loginItem.title = String(localized: "Launch at Login")
        loginItem.target = self
        loginItem.action = #selector(toggleLogin)
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let info = NSMenuItem(title: AppEnvironment.versionDescription, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(NSMenuItem(title: String(localized: "Quit AppPad"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        item.menu = menu
        refresh()
    }

    // 2×2 rounded squares, drawn as a template image (tinted by the menu bar).
    private static func makeIcon() -> NSImage {
        let canvas: CGFloat = 18
        let tile: CGFloat = 6.5
        let gap: CGFloat = 2
        let radius: CGFloat = 1.8
        let inset = (canvas - tile * 2 - gap) / 2
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            NSColor.black.setFill()
            for row in 0..<2 {
                for col in 0..<2 {
                    let rect = NSRect(x: inset + CGFloat(col) * (tile + gap),
                                      y: inset + CGFloat(row) * (tile + gap),
                                      width: tile, height: tile)
                    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AppPad"
        return image
    }

    func refresh() {
        let prefs = Preferences.shared

        openItem.title = String(localized: "Open AppPad") + (hotKeyAvailable ? "" : "  ⚠︎")
        openItem.toolTip = hotKeyAvailable ? nil : String(localized: "The shortcut could not be registered. It may be used by another app.")
        apply(prefs.launcherHotKey, to: openItem)

        apply(prefs.clipboardHotKey, to: clipboardItem)
        clipboardItem.isHidden = !prefs.clipboardEnabled

        let enabled = LoginItem.isEnabled
        loginItem.state = .off
        loginItem.keyEquivalent = enabled ? "✓" : ""
        loginItem.keyEquivalentModifierMask = []
    }

    private func apply(_ combo: KeyCombo?, to menuItem: NSMenuItem) {
        if let equivalent = combo?.menuKeyEquivalent {
            menuItem.keyEquivalent = equivalent.key
            menuItem.keyEquivalentModifierMask = equivalent.modifiers
        } else {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func openLaunchpad() { onOpen() }
    @objc private func openClipboard() { onClipboard() }
    @objc private func openSettings() { onSettings() }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        refresh()
    }
}

// Carbon combo → NSMenuItem key equivalent (display only; global hotkeys stay in HotKeyCenter).
extension KeyCombo {
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        var mods: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { mods.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { mods.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { mods.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { mods.insert(.command) }
        guard let key = Self.menuKey(code: Int(keyCode), label: keyLabel) else { return nil }
        return (key, mods)
    }

    private static let functionKeyIndex: [Int: Int] = [
        kVK_F1: 0, kVK_F2: 1, kVK_F3: 2, kVK_F4: 3, kVK_F5: 4, kVK_F6: 5, kVK_F7: 6, kVK_F8: 7,
        kVK_F9: 8, kVK_F10: 9, kVK_F11: 10, kVK_F12: 11, kVK_F13: 12, kVK_F14: 13, kVK_F15: 14,
    ]

    private static func menuKey(code: Int, label: String) -> String? {
        if let index = functionKeyIndex[code] { return scalar(NSF1FunctionKey + index) }
        switch code {
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Delete: return "\u{8}"
        case kVK_Escape: return "\u{1B}"
        case kVK_ForwardDelete: return scalar(NSDeleteFunctionKey)
        case kVK_LeftArrow: return scalar(NSLeftArrowFunctionKey)
        case kVK_RightArrow: return scalar(NSRightArrowFunctionKey)
        case kVK_UpArrow: return scalar(NSUpArrowFunctionKey)
        case kVK_DownArrow: return scalar(NSDownArrowFunctionKey)
        case kVK_Home: return scalar(NSHomeFunctionKey)
        case kVK_End: return scalar(NSEndFunctionKey)
        case kVK_PageUp: return scalar(NSPageUpFunctionKey)
        case kVK_PageDown: return scalar(NSPageDownFunctionKey)
        default:
            // Lowercase: an uppercase key equivalent would imply ⇧.
            return label.isEmpty ? nil : label.lowercased()
        }
    }

    private static func scalar(_ value: Int) -> String? {
        UnicodeScalar(UInt32(value)).map { String(Character($0)) }
    }
}
