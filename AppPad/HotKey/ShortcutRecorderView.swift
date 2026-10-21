import AppKit
import Carbon.HIToolbox
import SwiftUI

// Click to record a shortcut; Esc cancels, Delete clears.
// Only takes focus on an explicit click, so opening Settings never suspends the global hotkeys.
final class ShortcutRecorderView: NSView {
    var combo: KeyCombo? { didSet { needsDisplay = true } }
    var onChange: ((KeyCombo?) -> Void)?
    // Called (async) when a recording session ends or an auto-start fails.
    var onEnd: (() -> Void)?
    // Start recording as soon as the view lands in a window (one-shot).
    var autoStart = false
    private var isRecording = false { didSet { needsDisplay = true } }
    private var allowFocus = false

    override var acceptsFirstResponder: Bool { allowFocus }
    override var canBecomeKeyView: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 24) }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            window?.makeFirstResponder(nil)
        } else {
            allowFocus = true
            window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard allowFocus else { return false }
        isRecording = true
        HotKeyCenter.shared.suspend()
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    // Window closed / lost focus while recording → stop, so hotkeys resume.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let old = window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: old)
        }
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification, object: window
        )
        guard autoStart else { return }
        autoStart = false
        // Next turn: SwiftUI may still be attaching the hierarchy.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.allowFocus = true
            if !window.makeFirstResponder(self) || !self.isRecording {
                self.allowFocus = false
                self.notifyEnd()
            }
        }
    }

    @objc private func windowDidResignKey(_ note: Notification) {
        if isRecording { window?.makeFirstResponder(nil) }
        stopRecording()
    }

    private func stopRecording() {
        allowFocus = false
        guard isRecording else { return }
        isRecording = false
        HotKeyCenter.shared.resume()
        notifyEnd()
    }

    // Async: may fire during a SwiftUI update (view removal).
    private func notifyEnd() {
        guard let onEnd else { return }
        DispatchQueue.main.async { onEnd() }
    }

    // ⌘-combos arrive here before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        if (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) && flags.isEmpty {
            combo = nil
            onChange?(nil)
            window?.makeFirstResponder(nil)
            return
        }
        guard let newCombo = KeyCombo.from(event: event) else {
            NSSound.beep()
            return
        }
        combo = newCombo
        onChange?(newCombo)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = String(localized: "Press shortcut…", table: "HotKey")
        } else {
            text = combo?.displayString ?? String(localized: "Click to record", table: "HotKey")
        }
        let color: NSColor = (combo == nil && !isRecording) ? .secondaryLabelColor : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color]
        let string = text as NSString
        let size = string.size(withAttributes: attrs)
        string.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

// SwiftUI bridge for the settings window.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    var autoStart = false
    var onEnd: (() -> Void)? = nil

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.combo = combo
        view.autoStart = autoStart
        let binding = $combo
        view.onChange = { binding.wrappedValue = $0 }
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.combo = combo
        let binding = $combo
        view.onChange = { binding.wrappedValue = $0 }
        view.onEnd = onEnd
    }

    // Take the .frame size; otherwise the 170 pt intrinsic width overflows narrower frames
    // and the recording box draws under neighbouring buttons.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ShortcutRecorderView, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural.width
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? natural.height
        return CGSize(width: width, height: height)
    }
}
