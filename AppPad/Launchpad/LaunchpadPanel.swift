import AppKit

// Borderless, non-activating floating panel (Spotlight style):
// it takes keyboard focus without activating AppPad, so the hotkey works from any app
// and closing it leaves the previous app frontmost.
final class LaunchpadPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    // Sees every keyDown before the field editor (Workflow panel: ⌥ / ⌃ in-panel shortcuts).
    var keyDownHandler: ((NSEvent) -> Bool)?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style.union(.nonactivatingPanel), backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Replayed trackpad taps
    // A tap that stops a running swipe is eaten by macOS (no click). The controller replays it
    // here; whichever of the replay / a real click comes second is dropped, so it acts once.

    private static let replayWindow: TimeInterval = 0.35
    private var lastRealMouseDown: TimeInterval = -1
    private var lastReplay: TimeInterval = -1
    private var dropNextMouseUp = false
    private var isReplaying = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let keyDownHandler, keyDownHandler(event) { return }
        if !isReplaying {
            switch event.type {
            case .leftMouseDown:
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastReplay < Self.replayWindow {
                    dropNextMouseUp = true
                    return
                }
                lastRealMouseDown = now
            case .leftMouseUp where dropNextMouseUp:
                dropNextMouseUp = false
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    // Synthesized single click (down + up) at a window point.
    func replayClick(atWindowPoint point: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRealMouseDown >= Self.replayWindow else { return }   // real click already came
        lastReplay = now
        isReplaying = true
        defer { isReplaying = false }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard isVisible,
                  let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: now, windowNumber: windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1,
                                                 pressure: type == .leftMouseDown ? 1 : 0)
            else { return }
            sendEvent(event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        // AppPad is not the active app, so route standard edit shortcuts ourselves.
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if let key = event.charactersIgnoringModifiers?.lowercased(), flags.contains(.command) {
            let action: Selector?
            switch (key, flags) {
            case ("x", .command): action = #selector(NSText.cut(_:))
            case ("c", .command): action = #selector(NSText.copy(_:))
            case ("v", .command): action = #selector(NSText.paste(_:))
            case ("a", .command): action = #selector(NSText.selectAll(_:))
            case ("z", .command): action = Selector(("undo:"))
            case ("z", [.command, .shift]): action = Selector(("redo:"))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// Flipped container helper (top-left origin).
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// Click on empty space: fires on mouse up if not moved and released within 0.5 s.
// Empty space never starts edit mode (only a long press on an app icon does).
final class BackgroundPressTracker {
    var onClick: (() -> Void)?

    private static let maxClickDuration: TimeInterval = 0.5

    private var start: NSPoint = .zero
    private var downTime: TimeInterval = 0
    private var isActive = false

    func mouseDown(_ event: NSEvent) {
        isActive = true
        start = event.locationInWindow
        downTime = event.timestamp
    }

    func mouseDragged(_ event: NSEvent) {
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        if dx * dx + dy * dy > 25 { isActive = false }
    }

    func mouseUp(_ event: NSEvent) {
        defer { isActive = false }
        guard isActive, event.timestamp - downTime <= Self.maxClickDuration else { return }
        onClick?()
    }
}

// Root content view: forwards stray scroll events to the pager, Esc when no field is focused,
// and clicks on empty space.
final class LaunchpadRootView: FlippedView {
    var onScroll: ((NSEvent) -> Void)?
    var onEscape: (() -> Void)?
    let press = BackgroundPressTracker()

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    override func mouseDown(with event: NSEvent) { press.mouseDown(event) }
    override func mouseDragged(with event: NSEvent) { press.mouseDragged(event) }
    override func mouseUp(with event: NSEvent) { press.mouseUp(event) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Panel switch (⌘⇧J / ⌘⇧K)
// Gap-free hand-over: the outgoing panel stays on screen until the incoming one is drawn
// opaque on top of it, then orders out on the next run-loop turn.
// (Hiding first and fading in from alpha 0 briefly showed the desktop → flash.)
@MainActor
enum PanelSwitch {
    private static var outgoing: NSWindow?
    private static var hideOutgoing: (() -> Void)?
    private static var token = 0
    private static let fallbackDelay: TimeInterval = 0.3

    // Outgoing panel: call instead of hide(), then ask for the next panel.
    static func begin(from window: NSWindow, hide: @escaping () -> Void) {
        finish()
        token += 1
        let current = token
        outgoing = window
        hideOutgoing = hide
        // Next panel never showed (e.g. unavailable): close anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay) {
            if current == token { finish() }
        }
    }

    // Outgoing panel ignores its own resign-key while handing over.
    static func isOutgoing(_ window: NSWindow) -> Bool {
        outgoing === window
    }

    // Incoming panel, before ordering in: true → show opaque, no fade.
    // Switching to the same panel just cancels the hand-over.
    static func prepareIncoming(_ window: NSWindow) -> Bool {
        guard let outgoing else { return false }
        if outgoing === window {
            token += 1
            self.outgoing = nil
            hideOutgoing = nil
            return false
        }
        return true
    }

    // Incoming panel, right after makeKeyAndOrderFront.
    // afterHandOff runs once the old panel is gone (keeps input restore → switch order).
    static func takeOver(_ window: NSWindow, afterHandOff: @escaping () -> Void = {}) {
        token += 1
        let current = token
        // Commit the new panel's first frame before the old one leaves.
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        DispatchQueue.main.async {
            guard current == token else { return }
            finish()
            afterHandOff()
        }
    }

    private static func finish() {
        let hide = hideOutgoing
        outgoing = nil
        hideOutgoing = nil
        hide?()
    }
}

// MARK: - Target display
// Shared by Launchpad, Clipboard and Workflow panel.
@MainActor
enum PanelScreen {
    // Display under the mouse, or the main display (menu bar) when the setting is off.
    static func target() -> NSScreen? {
        if Preferences.shared.panelsFollowMouseScreen {
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
                return screen
            }
        }
        // screens[0] holds the menu bar; NSScreen.main is just the key window's screen.
        return NSScreen.screens.first ?? NSScreen.main
    }
}
