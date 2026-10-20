import AppKit

// NSAlert look, without activating AppPad. NSAlert.runModal() needs NSApp.activate() to come to the
// front, which brings every AppPad window (e.g. Settings) in front of the app the user is working
// in, and macOS may refuse the activation and leave the alert behind it.
// Here NSAlert still builds icon, texts, accessory view and buttons (layout()); that content is
// moved into a non-activating panel with the alert window's own style, shown above other apps on
// the current Space. It takes key focus (Return / Esc) while the other app stays active, and runs
// modally like before, so callers keep their synchronous flow.
enum FloatingAlert {
    static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.layout()
        let source = alert.window
        let panel = FloatingAlertPanel(
            contentRect: source.contentRect(forFrameRect: source.frame),
            styleMask: source.styleMask.union(.nonactivatingPanel),
            backing: .buffered, defer: false
        )
        copyLook(from: source, to: panel)
        let content = source.contentView
        source.contentView = NSView()
        panel.contentView = content

        // NSAlert's own button action only works in its own modal session: answer here instead.
        let handler = ButtonHandler()
        for (index, button) in alert.buttons.enumerated() {
            button.tag = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index
            button.target = handler
            button.action = #selector(ButtonHandler.pressed(_:))
        }

        position(panel)
        panel.makeKeyAndOrderFront(nil)
        let response = withExtendedLifetime(handler) { NSApp.runModal(for: panel) }
        panel.orderOut(nil)
        panel.contentView = nil
        return response
    }

    private static func copyLook(from source: NSWindow, to panel: NSPanel) {
        panel.titleVisibility = source.titleVisibility
        panel.titlebarAppearsTransparent = source.titlebarAppearsTransparent
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = source.standardWindowButton(kind)?.isHidden ?? true
        }
        panel.backgroundColor = source.backgroundColor
        panel.isOpaque = source.isOpaque
        panel.hasShadow = source.hasShadow
        panel.appearance = source.appearance
        panel.title = source.title
        panel.level = .modalPanel
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .alertPanel
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    // Display under the mouse, centered a bit above the middle (where system alerts appear).
    private static func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.midY + visible.height * 0.12 - size.height / 2))
    }

    private final class ButtonHandler: NSObject {
        @objc func pressed(_ sender: NSButton) {
            NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: sender.tag))
        }
    }
}

// Key focus without activating AppPad; never the main window.
private final class FloatingAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // After the user clicked another app the panel is no longer key: take focus first, so the
    // same click still presses the button.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}
