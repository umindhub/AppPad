import AppKit

// ⌘Space panel: workflows + apps, same window style as the launcher / clipboard.
final class WorkflowPanelController: NSObject, NSWindowDelegate {
    var onOpenSettings: (() -> Void)?
    var onEditWorkflow: ((UUID) -> Void)?
    // ⌘⇧J (-1) / ⌘⇧K (+1): previous / next panel (Launchpad → Clipboard → Workflows).
    var onSwitchPanel: ((Int) -> Void)?

    let launchpad: LaunchpadController

    private let prefs = Preferences.shared
    private let panel: LaunchpadPanel
    private let container = FlippedView()
    private let background = LaunchpadBackgroundView()
    private let viewController = WorkflowPanelViewController()
    private var isHiding = false

    var isVisible: Bool { panel.isVisible }

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

        panel.delegate = self
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
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            viewController.focusSearch()
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        applyAppearance()
        applyFrame(targetFrame(on: screen), on: screen, display: false)
        viewController.prepareForShow()

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        if prefs.switchToEnglishInput { InputSourceSwitcher.switchToASCII() }
        viewController.focusSearch()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.panel.animator().alphaValue = 1
        }
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
        hide()
    }

    // MARK: - Actions

    func run(_ workflow: Workflow) {
        hide()
        WorkflowRunner.shared.start(id: workflow.id, trigger: .panel)
    }

    func open(_ app: AppInfo) {
        hide()
        launchpad.launch(app)
    }

    func edit(_ workflow: Workflow) {
        hide()
        onEditWorkflow?(workflow.id)
    }

    func switchPanel(_ step: Int) {
        hide()
        onSwitchPanel?(step)
    }

    func openSettings() {
        hide()
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

    // Same background as the launcher: wallpaper → dark, white → light.
    private func applyAppearance() {
        panel.appearance = NSAppearance(named: prefs.backgroundStyle == .white ? .aqua : .darkAqua)
    }

    // Clipboard-sized panel, centered on the screen with the pointer.
    private func targetFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(max(visible.width * 0.6, 720), visible.width)
        let height = min(max(visible.height * 0.6, 460), visible.height)
        return NSRect(
            x: (visible.midX - width / 2).rounded(),
            y: (visible.midY - height / 2).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    private func applyFrame(_ frame: NSRect, on screen: NSScreen, display: Bool) {
        panel.setFrame(frame, display: display)
        container.layer?.cornerRadius = LaunchpadController.cornerRadius
        viewController.root.layer?.cornerRadius = LaunchpadController.cornerRadius
        panel.hasShadow = true
        background.update(style: prefs.backgroundStyle, screen: screen, panelFrame: frame)
    }
}
