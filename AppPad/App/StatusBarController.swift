import AppKit
import Carbon.HIToolbox

// Menu bar icon + menu (the app has no Dock icon).
// Shortcuts and the login state are drawn in the title with one shared right-aligned
// tab stop, so their right edges line up exactly (AppKit's own key column does not).
// Real key equivalents live on hidden twin items, so ⌘Q / ⌘, still work while the menu is open.
// Global hotkeys (Carbon) are swallowed during menu tracking and only dispatched after it ends,
// so while the menu is open a timer peeks for a pending hotkey and closes the menu right away.
// Actions fired by key equivalents during tracking are deferred until the menu has closed and the
// run loop is back in default mode (GCD main-queue blocks still run inside tracking).
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let openItem = NSMenuItem()
    private let clipboardItem = NSMenuItem()
    private let workflowsItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let updatesItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    // Hidden twins carrying the key equivalents.
    private let launchpadKeyItem = NSMenuItem()
    private let workflowsKeyItem = NSMenuItem()
    private let clipboardKeyItem = NSMenuItem()
    var hotKeyAvailable = true
    var launchpadHotKeyAvailable = true
    private let onOpen: () -> Void
    private let onClipboard: () -> Void
    private let onSettings: () -> Void
    private let onWorkflows: () -> Void
    private let onCheckForUpdates: () -> Void

    // Title + right-hand text for each visible row.
    private var rows: [(item: NSMenuItem, title: String, trailing: String)] = []
    private weak var highlighted: NSMenuItem?
    private var hotKeyWatch: Timer?
    private var isMenuOpen = false
    private var pendingAction: (() -> Void)?

    init(onOpen: @escaping () -> Void, onClipboard: @escaping () -> Void, onSettings: @escaping () -> Void,
         onWorkflows: @escaping () -> Void, onCheckForUpdates: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onClipboard = onClipboard
        self.onSettings = onSettings
        self.onWorkflows = onWorkflows
        self.onCheckForUpdates = onCheckForUpdates
        super.init()

        item.button?.image = Self.makeIcon()

        configure(openItem, action: #selector(openLaunchpad))
        configure(clipboardItem, action: #selector(openClipboard))
        configure(workflowsItem, action: #selector(openWorkflows))
        configure(settingsItem, action: #selector(openSettings))
        configure(loginItem, action: #selector(toggleLogin))
        configure(updatesItem, action: #selector(checkForUpdates))
        configure(quitItem, action: #selector(quit))

        // Same order as ⌘⇧J/K: Launchpad → Workflows → Clipboard.
        menu.addItem(openItem)
        menu.addItem(workflowsItem)
        menu.addItem(clipboardItem)
        menu.addItem(settingsItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let info = NSMenuItem(title: AppEnvironment.versionDescription, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        // Dev builds never update.
        updatesItem.isHidden = !UpdateController.shared.isSupported
        menu.addItem(updatesItem)
        menu.addItem(quitItem)

        // Hidden key-equivalent twins.
        configure(launchpadKeyItem, action: #selector(openLaunchpad))
        configure(workflowsKeyItem, action: #selector(openWorkflows))
        configure(clipboardKeyItem, action: #selector(openClipboard))
        let settingsKey = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        settingsKey.keyEquivalentModifierMask = .command
        settingsKey.target = self
        let quitKey = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
        quitKey.keyEquivalentModifierMask = .command
        quitKey.target = self
        let updatesKey = NSMenuItem(title: "", action: #selector(checkForUpdates), keyEquivalent: "u")
        updatesKey.keyEquivalentModifierMask = .command
        updatesKey.target = self
        for twin in [launchpadKeyItem, workflowsKeyItem, clipboardKeyItem, settingsKey, quitKey, updatesKey] {
            twin.isHidden = true
            twin.allowsKeyEquivalentWhenHidden = true
            menu.addItem(twin)
        }
        // Dev builds never update: no ⌘U either.
        updatesKey.allowsKeyEquivalentWhenHidden = UpdateController.shared.isSupported

        // No system-provided symbols (macOS 27 keeps one on Settings by default).
        if #available(macOS 27.0, *) {
            for menuItem in menu.items { menuItem.preferredImageVisibility = .hidden }
        }
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    private func configure(_ menuItem: NSMenuItem, action: Selector) {
        menuItem.target = self
        menuItem.action = action
    }

    // 2×2 rounded squares, drawn as a template image (tinted by the menu bar).
    // Also used as the AppPad tab icon in Settings (padded: false → glyph fills the canvas).
    static func makeIcon(padded: Bool = true) -> NSImage {
        let tile: CGFloat = 6.5
        let gap: CGFloat = 2
        let radius: CGFloat = 1.8
        let content = tile * 2 + gap
        let canvas: CGFloat = padded ? 18 : content
        let inset = (canvas - content) / 2
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
        // ⚠︎ on Workflows when its shortcut is taken (another app, or Spotlight still on ⌘Space;
        // checked live, the user may change System Settings at any time).
        let available = hotKeyAvailable && !SpotlightShortcut.conflicts(with: prefs.workflowPanelHotKey)
        let workflowsTitle = String(localized: "Workflows") + (available ? "" : "  ⚠︎")
        workflowsItem.toolTip = available ? nil : String(localized: "The shortcut could not be registered. It may be used by Spotlight or another app.", table: "Settings")

        // AppPad shortcut: shown (and usable as a key equivalent) only while turned on.
        let launchpadCombo = prefs.activeLaunchpadHotKey
        let launchpadReady = launchpadCombo == nil || launchpadHotKeyAvailable
        let launchpadTitle = String(localized: "Open AppPad") + (launchpadReady ? "" : "  ⚠︎")
        openItem.toolTip = launchpadReady ? nil : String(localized: "The shortcut could not be registered. It may be used by Spotlight or another app.", table: "Settings")
        apply(launchpadCombo, to: launchpadKeyItem)
        launchpadKeyItem.allowsKeyEquivalentWhenHidden = launchpadCombo != nil
        apply(prefs.workflowPanelHotKey, to: workflowsKeyItem)
        apply(prefs.clipboardHotKey, to: clipboardKeyItem)
        clipboardItem.isHidden = !prefs.clipboardEnabled
        clipboardKeyItem.allowsKeyEquivalentWhenHidden = prefs.clipboardEnabled

        rows = [
            (openItem, launchpadTitle, launchpadCombo?.displayString ?? ""),
            (clipboardItem, String(localized: "Clipboard"), prefs.clipboardHotKey?.displayString ?? ""),
            (workflowsItem, workflowsTitle, prefs.workflowPanelHotKey?.displayString ?? ""),
            (settingsItem, String(localized: "Settings", table: "Settings"), "⌘,"),
            (loginItem, String(localized: "Launch at Login", table: "Settings"), LoginItem.isEnabled ? "✓" : "✕"),
            (updatesItem, String(localized: "Check for Updates…", table: "Settings"), "⌘U"),
            (quitItem, String(localized: "Quit AppPad", table: "Settings"), "⌘Q"),
        ]
        renderTitles()
    }

    // One right-aligned tab stop shared by all rows → trailing texts end at the same x.
    private func renderTitles() {
        let font = NSFont.menuFont(ofSize: 0)
        let measure: (String) -> CGFloat = { ($0 as NSString).size(withAttributes: [.font: font]).width }
        let visible = rows.filter { !$0.item.isHidden }
        let titleWidth = visible.map { measure($0.title) }.max() ?? 0
        let trailingWidth = visible.map { measure($0.trailing) }.max() ?? 0
        let tabLocation = ceil(titleWidth + 36 + trailingWidth)

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabLocation)]

        for row in rows {
            let isHighlighted = row.item === highlighted
            let text = NSMutableAttributedString(string: row.title, attributes: [
                .font: font,
                .foregroundColor: isHighlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
            text.append(NSAttributedString(string: "\t" + row.trailing, attributes: [
                .font: font,
                .foregroundColor: isHighlighted ? NSColor.selectedMenuItemTextColor : NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraph,
            ]))
            row.item.title = row.title   // accessibility / type-select
            row.item.attributedTitle = text
            row.item.keyEquivalent = ""
            row.item.keyEquivalentModifierMask = []
        }
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

    // Explicit colors don't follow the selection, so re-render on highlight change.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard item !== highlighted else { return }
        highlighted = item
        renderTitles()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopHotKeyWatch()
        isMenuOpen = false
        highlighted = nil
        renderTitles()
        // Default mode only: runs once tracking has fully unwound.
        if pendingAction != nil {
            perform(#selector(runPendingAction), with: nil, afterDelay: 0, inModes: [.default])
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(runPendingAction), object: nil)
        pendingAction = nil
        refresh()
        startHotKeyWatch()
    }

    @objc private func runPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    // Key equivalent while tracking → wait for menuDidClose; click (menu already closed) → run now.
    private func perform(_ action: @escaping () -> Void) {
        if isMenuOpen {
            pendingAction = action
        } else {
            action()
        }
    }

    // MARK: - Global hotkeys while the menu is open

    // .common includes the event-tracking mode the menu runs in.
    private func startHotKeyWatch() {
        hotKeyWatch?.invalidate()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfHotKeyPending() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hotKeyWatch = timer
    }

    private func stopHotKeyWatch() {
        hotKeyWatch?.invalidate()
        hotKeyWatch = nil
    }

    // Peek only (no pull): once tracking ends the queued hotkey is dispatched as usual,
    // so every global hotkey (panels, windows, apps) runs its normal handler.
    private func closeIfHotKeyPending() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var event: EventRef?
        guard ReceiveNextEvent(1, &spec, kEventDurationNoWait, false, &event) == OSStatus(noErr) else { return }
        stopHotKeyWatch()
        menu.cancelTracking()
    }

    @objc private func openLaunchpad() { perform(onOpen) }
    @objc private func openClipboard() { perform(onClipboard) }
    @objc private func openSettings() { perform(onSettings) }
    @objc private func openWorkflows() { perform(onWorkflows) }
    @objc private func quit() { AppTermination.quit() }
    @objc private func checkForUpdates() { perform(onCheckForUpdates) }

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
