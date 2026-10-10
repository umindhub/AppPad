import AppKit
import Carbon.HIToolbox
import SwiftUI

// Click to record a shortcut; Esc cancels, Delete clears.
// Only takes focus on an explicit click, so opening Settings never suspends the global hotkeys.
final class ShortcutRecorderView: NSView {
    var combo: KeyCombo? { didSet { needsDisplay = true } }
    var onChange: ((KeyCombo?) -> Void)?
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
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification, object: window
            )
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
            text = String(localized: "Press shortcut…")
        } else {
            text = combo?.displayString ?? String(localized: "Click to record")
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

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.combo = combo
        let binding = $combo
        view.onChange = { binding.wrappedValue = $0 }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.combo = combo
        let binding = $combo
        view.onChange = { binding.wrappedValue = $0 }
    }
}
