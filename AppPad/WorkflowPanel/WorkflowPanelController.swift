import AppKit

// ⌘Space panel: workflows + apps, same window style as the launcher / clipboard.
final class WorkflowPanelController: NSObject, NSWindowDelegate {
    var onOpenSettings: (() -> Void)?
    var onEditWorkflow: ((UUID) -> Void)?
    // ⌘⇧K (-1) / ⌘⇧J (+1): previous / next panel (Launchpad → Workflows → Clipboard).
    var onSwitchPanel: ((Int) -> Void)?

    let launchpad: LaunchpadController

    private let prefs = Preferences.shared
    private let panel: LaunchpadPanel
    private let container = FlippedView()
    private let background = LaunchpadBackgroundView()
    private let viewController = WorkflowPanelViewController()
    private var isHiding = false
    // Closes on a Space switch, like the Launchpad.
    private var spaceGuard: PanelSpaceGuard?

    var isVisible: Bool { panel.isVisible }
    // Open and focused (a global hotkey for another panel hands over from it).
    var isActive: Bool { panel.isVisible && panel.isKeyWindow && !isHiding }

    init(launchpad: LaunchpadController) {
        self.launchpad = launchpad
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
        // Late wallpaper (cache miss) may change light / dark text.
        background.onWallpaperApplied = { [weak self] in self?.applyAppearance() }

        panel.delegate = self
        spaceGuard = PanelSpaceGuard(panel: panel) { [weak self] in self?.hide() }
        panel.keyHandler = { [weak self] event in
            self?.viewController.handleKeyEquivalent(event) ?? false
        }
        panel.keyDownHandler = { [weak self] event in
            self?.viewController.handlePanelShortcut(event) ?? false
        }
        applyPreferences()
    }

    // MARK: - Show / hide

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let handOff = PanelSwitch.prepareIncoming(panel)
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            viewController.focusSearch()
            return
        }
        guard let screen = PanelScreen.target() else { return }
        applyAppearance()
        applyFrame(targetFrame(on: screen), on: screen, display: false)
        viewController.prepareForShow()

        // ⌘⇧J/K switch: opaque over the previous panel, or morph from it (different size).
        panel.alphaValue = handOff ? PanelSwitch.incomingAlpha(for: panel) : 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        spaceGuard?.panelDidShow()
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
        if prefs.workflowSwitchToEnglishInput { InputSourceSwitcher.switchToASCII() }
    }

    func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        panel.orderOut(nil)
        viewController.didHide()
        InputSourceSwitcher.restore()
        isHiding = false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !PanelSwitch.isOutgoing(panel) else { return }   // next panel took key
        hide()
    }

    // MARK: - Actions

    // argument = text after the first space in the search field (apps ignore it).
    // confirmed: the panel's own dialog was answered, so the runner does not ask again.
    func run(_ workflow: Workflow, argument: String, confirmed: Bool = false) {
        hide()
        launchpad.recordUse(workflow.statsKey)   // same frecency as app launches
        WorkflowRunner.shared.start(id: workflow.id, trigger: .panel, argument: argument, confirmed: confirmed)
    }

    // ⌘S / Run button: same run, but the panel stays open and its preview shows the result.
    func runInPlace(_ workflow: Workflow, argument: String, confirmed: Bool = false) {
        launchpad.recordUse(workflow.statsKey)
        WorkflowRunner.shared.start(id: workflow.id, trigger: .panel, argument: argument, confirmed: confirmed)
    }

    func open(_ app: AppInfo) {
        hide()
        launchpad.launch(app)   // records the launch
    }

    // A workflow's shortcut is missing: import the bundled one, or open Shortcuts to create it.
    func installShortcut(_ name: String) {
        hide()
        if let file = BuiltinWorkflows.bundledShortcut(name) {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }

    // Settings hides this panel itself (after requesting activation).
    func edit(_ workflow: Workflow) {
        onEditWorkflow?(workflow.id)
    }

    func switchPanel(_ step: Int) {
        beginHandOff()
        onSwitchPanel?(step)
    }

    // Next panel shows opaque on top, then this one closes (no flash).
    func beginHandOff() {
        PanelSwitch.begin(from: panel) { [weak self] in self?.hide() }
    }

    // No hide() here: Settings requests activation first, while this panel still has key.
    func openSettings() {
        onOpenSettings?()
    }

    // MARK: - Preferences / frame

    func applyPreferences() {
        applyAppearance()
        viewController.applyPreferences()
        if panel.isVisible, let screen = panel.screen {
            applyFrame(targetFrame(on: screen), on: screen, display: true)
            panel.invalidateShadow()
        }
    }

    // Light / dark text from the composed background brightness (own or AppPad's background).
    private func applyAppearance() {
        let screen = panel.isVisible ? panel.screen : PanelScreen.target()
        panel.appearance = PanelBackgroundSpec.current(for: .workflows).appearance(on: screen)
    }

    // Same size / position as the Clipboard by default, or its own percentages.
    private func targetFrame(on screen: NSScreen) -> NSRect {
        let size = prefs.workflowPanelPercent
        return PanelFrame.centered(on: screen, widthPercent: size.width, heightPercent: size.height)
    }

    private func applyFrame(_ frame: NSRect, on screen: NSScreen, display: Bool) {
        panel.setFrame(frame, display: display)
        let filled = PanelFrame.isFilled(frame, on: screen)
        let radius = filled ? LaunchpadController.filledCornerRadius : LaunchpadController.cornerRadius
        container.layer?.cornerRadius = radius
        viewController.root.layer?.cornerRadius = radius
        panel.cornerMaskRadius = radius
        panel.dropsShadow = !filled
        let spec = PanelBackgroundSpec.current(for: .workflows)
        background.update(spec: spec, screen: screen, panelFrame: frame)
        panel.appearance = spec.appearance(on: screen)
    }
}
