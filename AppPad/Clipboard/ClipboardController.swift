import AppKit

// Owns the clipboard panel, store and monitor. Panel style matches the launcher.
final class ClipboardController: NSObject, NSWindowDelegate {
    // ⌘⇧J (-1) / ⌘⇧K (+1): previous / next panel (Launchpad → Clipboard → Workflows).
    var onSwitchPanel: ((Int) -> Void)?
    var onOpenSettings: (() -> Void)?

    let store: ClipboardStore?
    private(set) var monitor: ClipboardMonitor?

    private let prefs = Preferences.shared
    private let panel: LaunchpadPanel
    private let container = FlippedView()
    private let background = LaunchpadBackgroundView()
    private let viewController = ClipboardViewController()
    private var isHiding = false
    private var didPromptAccess = false

    var scope: ClipScope { viewController.scope }
    var isVisible: Bool { panel.isVisible }
    // Open and focused (a global hotkey for another panel hands over from it).
    var isActive: Bool { panel.isVisible && panel.isKeyWindow && !isHiding }

    override init() {
        let dir = AppEnvironment.supportDirectory.appendingPathComponent("Clipboard", isDirectory: true)
        do {
            store = try ClipboardStore(directory: dir)
        } catch {
            NSLog("Clipboard store unavailable: \(error)")
            store = nil
        }
        panel = LaunchpadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        super.init()
    }

    func start() {
        viewController.controller = self
        container.wantsLayer = true
        container.layer?.cornerRadius = LaunchpadController.cornerRadius
        container.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        let content = viewController.view
        content.autoresizingMask = [.width, .height]
        container.addSubview(background)
        container.addSubview(content)
        panel.contentView = container
        background.frame = container.bounds
        content.frame = container.bounds
        panel.morphBackground = background
        panel.morphContent = content

        panel.delegate = self
        panel.keyHandler = { [weak self] event in
            self?.viewController.handleKeyEquivalent(event) ?? false
        }
        if let store {
            SourceAppDirectory.shared.reload(from: store)
            monitor = ClipboardMonitor(store: store)
        }
        applyPreferences()
    }

    // MARK: - Show / hide

    // Hotkey: same scope while open → close; otherwise open / switch scope.
    func toggle(_ scope: ClipScope) {
        if panel.isVisible && panel.isKeyWindow && self.scope == scope {
            hide()
        } else {
            show(scope)
        }
    }

    func show(_ scope: ClipScope) {
        guard store != nil else {
            NSSound.beep()
            return
        }
        let handOff = PanelSwitch.prepareIncoming(panel)
        if panel.isVisible {
            viewController.setScope(scope)
            panel.makeKeyAndOrderFront(nil)
            viewController.focusSearch()
            return
        }
        guard let screen = PanelScreen.target() else { return }
        applyAppearance()
        applyFrame(targetFrame(on: screen), on: screen, display: false)
        viewController.prepareForShow(scope: scope)

        // ⌘⇧J/K switch: opaque over the previous panel, or morph from it (different size).
        panel.alphaValue = handOff ? PanelSwitch.incomingAlpha(for: panel) : 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        viewController.focusSearch()
        if handOff {
            // After the old panel's hide() restored the input source.
            PanelSwitch.takeOver(panel) { [weak self] in self?.switchInputIfNeeded() }
            return
        }
        switchInputIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.panel.animator().alphaValue = 1
        }
    }

    private func switchInputIfNeeded() {
        if prefs.clipboardSwitchToEnglishInput { InputSourceSwitcher.switchToASCII() }
    }

    func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        panel.orderOut(nil)
        viewController.didHide()
        InputSourceSwitcher.restore()   // no-op unless we switched on show
        isHiding = false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !PanelSwitch.isOutgoing(panel) else { return }   // next panel took key
        hide()
    }

    // ⌘⇧J / ⌘⇧K: previous / next panel. Saved is a filter of the clipboard, not a panel.
    func switchPanel(_ step: Int) {
        beginHandOff()
        onSwitchPanel?(step)
    }

    // Next panel shows opaque on top, then this one closes (no flash).
    func beginHandOff() {
        PanelSwitch.begin(from: panel) { [weak self] in self?.hide() }
    }

    // MARK: - Paste

    func paste(_ item: ClipItem, autoPaste: Bool) {
        guard let store else { return }
        hide()
        // Images: decode / re-encode in the background at default QoS (no main-thread hang).
        if item.kind == .image, let url = store.imageURL(for: item) {
            Task { [weak self] in
                let data = await Task.detached(priority: .medium) { PasteService.imageData(url: url) }.value
                guard let data else {
                    NSSound.beep()
                    return
                }
                self?.finishPaste(item, image: data, autoPaste: autoPaste)
            }
        } else {
            finishPaste(item, image: nil, autoPaste: autoPaste)
        }
    }

    private func finishPaste(_ item: ClipItem, image: PasteImageData?, autoPaste: Bool) {
        guard let store else { return }
        let changeCount = PasteService.write(item, image: image)
        monitor?.ignore(changeCount: changeCount)
        if let id = item.id { store.markUsed(id: id) }
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        guard autoPaste else { return }
        if PasteService.isTrusted {
            PasteService.sendPasteKeystroke()
        } else if !didPromptAccess {
            // Content is already on the pasteboard; ⌘V works manually until access is granted.
            didPromptAccess = true
            PasteService.requestAccess()
        }
    }

    // range nil = all history. Saved items are never deleted here.
    func deleteHistory(in range: ClipAgeRange?) {
        store?.deleteHistory(in: range)
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
    }

    func historyCount(in range: ClipAgeRange?) -> Int {
        store?.historyCount(in: range) ?? 0
    }

    // MARK: - Preferences / frame

    func applyPreferences() {
        if prefs.clipboardEnabled { monitor?.start() } else { monitor?.stop() }
        applyAppearance()
        viewController.applyPreferences()
        if panel.isVisible, let screen = panel.screen {
            applyFrame(targetFrame(on: screen), on: screen, display: true)
            panel.invalidateShadow()
        }
    }

    private enum Background {
        case style(PanelBackgroundStyle)
        case color(NSColor)
    }

    private var resolvedBackground: Background {
        switch prefs.clipboardBackground {
        case .followLaunchpad: return .style(prefs.backgroundStyle)
        case .wallpaper, .heavyBlur: return .style(.wallpaper)
        case .white: return .color(.white)
        case .lightGray: return .color(ClipboardColors.lightGray)
        case .darkGray: return .color(ClipboardColors.darkGray)
        case .custom: return .color(ClipboardColors.color(hex: prefs.clipboardBackgroundColor) ?? ClipboardColors.darkGray)
        }
    }

    // Wallpaper / dark colors → dark appearance; white / light colors → light appearance.
    private func applyAppearance() {
        let dark: Bool
        switch resolvedBackground {
        case .style(let style): dark = style == .wallpaper
        case .color(let color): dark = ClipboardColors.isDark(color)
        }
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let w = CGFloat(min(max(prefs.clipboardWidthPercent, 30), 100)) / 100
        let h = CGFloat(min(max(prefs.clipboardHeightPercent, 30), 100)) / 100
        let width = min(max(visible.width * w, 520), visible.width)
        let height = min(max(visible.height * h, 360), visible.height)
        return NSRect(
            x: (visible.midX - width / 2).rounded(),
            y: (visible.midY - height / 2).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    private func applyFrame(_ frame: NSRect, on screen: NSScreen, display: Bool) {
        panel.setFrame(frame, display: display)
        let visible = screen.visibleFrame
        let filled = frame.width >= visible.width - 1 && frame.height >= visible.height - 1
        let radius = filled ? LaunchpadController.filledCornerRadius : LaunchpadController.cornerRadius
        container.layer?.cornerRadius = radius
        viewController.root.layer?.cornerRadius = radius
        panel.hasShadow = !filled
        switch resolvedBackground {
        case .style(let style):
            background.update(style: style, screen: screen, panelFrame: frame,
                              heavyBlur: prefs.clipboardBackground == .heavyBlur)
        case .color(let color): background.update(solid: color)
        }
    }
}
