import AppKit
import QuartzCore
import SwiftUI

// MARK: - GlassSearchFieldView
//
// Search field chrome — port of YouMindHub pickerSearchChrome (macOS 26 branch):
//   glass : GlassBackdropView capsule            (isGlass = true, macOS 26+)
//   pill  : plain filled capsule, same size      (isGlass = false)
//   glow  : uniform HDR wash over the capsule while the field has focus (glass only)
//   field : borderless NSSearchField, same frame / padding in both modes, no magnifier
//   clear : own × button at the trailing end; the field stops before it, so typed text
//           never runs under it (the native cancel button is removed)
// Frame changes while editing restart the field editor, otherwise it keeps the old
// text rect and stops scrolling to the caret on long input.

final class GlassSearchFieldView: FlippedView {
    let field = FocusSearchField()
    var isGlass = false {
        didSet { if oldValue != isGlass { applyStyle() } }
    }

    static let height: CGFloat = 32
    // Capsule grows with a larger custom font (clipboard panel); launcher keeps 32 pt.
    var preferredHeight: CGFloat {
        guard let textFont else { return Self.height }
        return max(Self.height, ceil(textFont.ascender - textFont.descender + textFont.leading) + 14)
    }

    // nil = default system font.
    var textFont: NSFont? {
        didSet {
            guard oldValue != textFont else { return }
            field.font = textFont ?? .systemFont(ofSize: NSFont.systemFontSize)
            needsLayout = true
            scheduleEditorRefresh()
        }
    }

    private let glass = GlassBackdropView()
    private let pill = PlainPillView()
    private let glow = SearchGlowView()
    private let clearButton = NSButton()
    private static let hPadding: CGFloat = 12          // same as YouMindHub pickerSearchChrome
    private static let clearSize: CGFloat = 16
    private static let clearTrailing: CGFloat = 8      // capsule edge → × button
    private static let clearGap: CGFloat = 6           // text end → × button

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Borderless single line that scrolls horizontally with the caret; chrome draws the pill.
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        searchCell?.searchButtonCell = nil      // no magnifier in either mode
        searchCell?.cancelButtonCell = nil      // replaced by clearButton

        let symbol = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")?
            .withSymbolConfiguration(symbol)
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.imageScaling = .scaleNone
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.refusesFirstResponder = true   // keep the caret in the field
        clearButton.target = self
        clearButton.action = #selector(clearText)
        clearButton.isHidden = true

        glass.isHidden = true
        glow.isHidden = true
        addSubview(pill)
        addSubview(glass)
        addSubview(glow)       // above the glass, below the text
        addSubview(field)
        addSubview(clearButton)

        field.onTextChange = { [weak self] in self?.updateClearButton() }
        field.onFocusChange = { [weak self] focused in
            guard let self else { return }
            self.glow.setActive(focused && self.isGlass, animated: true)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Only the background changes; the field itself is untouched → no editor restart.
    private func applyStyle() {
        glass.isHidden = !isGlass
        pill.isHidden = isGlass
        glow.isHidden = !isGlass
        glow.setActive(isGlass && field.hasFocus, animated: false)
    }

    // MARK: Clear button

    private func updateClearButton() {
        clearButton.isHidden = field.stringValue.isEmpty
    }

    // Deletes through the field editor → normal textDidChange → controlTextDidChange.
    @objc private func clearText() {
        guard let window = field.window else { return }
        if field.currentEditor() == nil { window.makeFirstResponder(field) }
        if let editor = field.currentEditor() as? NSTextView {
            editor.selectAll(nil)
            editor.delete(nil)
        } else {
            field.stringValue = ""
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        }
        updateClearButton()
    }

    // MARK: Field editor

    private var editorRefreshPending = false

    // Coalesced; runs after layout so the editor picks up the final text rect.
    private func scheduleEditorRefresh() {
        guard field.currentEditor() != nil, !editorRefreshPending else { return }
        editorRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.editorRefreshPending = false
            self.refreshEditor()
        }
    }

    // End and restart editing (commits the text), keeping the caret / selection.
    private func refreshEditor() {
        guard let window = field.window, let editor = field.currentEditor() as? NSTextView else { return }
        layoutSubtreeIfNeeded()
        let range = editor.selectedRange()
        window.makeFirstResponder(nil)
        window.makeFirstResponder(field)
        if let restarted = field.currentEditor() as? NSTextView {
            let length = (restarted.string as NSString).length
            let location = min(range.location, length)
            restarted.setSelectedRange(NSRange(location: location, length: min(range.length, length - location)))
            restarted.scrollRangeToVisible(restarted.selectedRange())
        }
    }

    private var searchCell: NSSearchFieldCell? { field.cell as? NSSearchFieldCell }

    override func layout() {
        super.layout()
        let b = bounds
        glass.frame = b
        glass.cornerRadius = b.height / 2
        pill.frame = b
        glow.frame = b
        // × button at the trailing end, vertically centered.
        let c = Self.clearSize
        let clearX = b.width - Self.clearTrailing - c
        clearButton.frame = NSRect(x: clearX, y: ((b.height - c) / 2).rounded(), width: c, height: c)
        // Borderless field at its natural height, vertically centered; always stops before the ×
        // (constant width → no editor restart when the button shows / hides).
        let natural = field.intrinsicContentSize.height
        let h = natural > 0 ? min(natural, b.height) : 22
        setFieldFrame(NSRect(x: Self.hPadding, y: ((b.height - h) / 2).rounded(),
                             width: max(0, clearX - Self.clearGap - Self.hPadding), height: h))
    }

    private func setFieldFrame(_ frame: NSRect) {
        guard field.frame != frame else { return }
        field.frame = frame
        scheduleEditorRefresh()
    }
}

// MARK: - PlainPillView

// Non-glass background: filled capsule with a hairline edge (dynamic colors per appearance).
final class PlainPillView: NSView {
    private static let fillAlphaLight: CGFloat = 0.08
    private static let fillAlphaDark: CGFloat = 0.14

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .circular
        layer?.borderWidth = 0.5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor
                .withAlphaComponent(dark ? Self.fillAlphaDark : Self.fillAlphaLight).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

// MARK: - FocusSearchField

// NSSearchField that reports focus in / out (field editor begins / ends).
final class FocusSearchField: NSSearchField {
    var onFocusChange: ((Bool) -> Void)?
    var onTextChange: (() -> Void)?
    private(set) var hasFocus = false

    // Typing and programmatic changes (e.g. cleared on Esc / show) both update the × button.
    override var stringValue: String {
        didSet { onTextChange?() }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { setFocused(true) }
        return ok
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        setFocused(false)
    }

    private func setFocused(_ on: Bool) {
        guard on != hasFocus else { return }
        hasFocus = on
        onFocusChange?(on)
    }
}

// MARK: - SearchGlowView
//
// Port of YouMindHub PickerSearchGlowNSView: brightness only, same shape as the capsule
// (no rim, no gradient). Fades in / out with focus. Clicks pass through.

final class SearchGlowView: NSView {
    private let fill = CAGradientLayer()
    private var isActive = false
    private var isDark = false

    private static let hdrValue: CGFloat = 1.4
    private static let lightAlpha: CGFloat = 0.18
    private static let darkAlpha: CGFloat = 0.12      // white reads strong on dark
    private static let fadeIn: CFTimeInterval = 0.18
    private static let fadeOut: CFTimeInterval = 0.35

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        fill.opacity = 0
        fill.masksToBounds = true
        fill.cornerCurve = .circular
        layer?.addSublayer(fill)
        GlassHDR.enable(fill)
        if let root = layer { GlassHDR.enable(root) }
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Never intercept clicks meant for the field.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setActive(_ on: Bool, animated: Bool) {
        guard on != isActive else { return }
        isActive = on
        let target: Float = on ? 1 : 0
        if animated {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = fill.presentation()?.opacity ?? fill.opacity
            a.toValue = target
            a.duration = on ? Self.fadeIn : Self.fadeOut
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fill.add(a, forKey: "fade")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.opacity = target
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        fill.cornerRadius = min(bounds.width, bounds.height) / 2
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        fill.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let c = GlassHDR.white(Self.hdrValue, isDark ? Self.darkAlpha : Self.lightAlpha)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.colors = [c, c]                 // uniform: brightness only
        CATransaction.commit()
    }
}

// MARK: - GlassSearchField (SwiftUI bridge)

// Same chrome as the clipboard panel search, for SwiftUI settings pages.
// Fills the proposed width; height is fixed at GlassSearchFieldView.height.
struct GlassSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isGlass: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> GlassSearchFieldView {
        let view = GlassSearchFieldView()
        view.field.placeholderString = placeholder
        view.field.focusRingType = .none
        view.field.delegate = context.coordinator
        view.field.stringValue = text
        view.isGlass = isGlass
        return view
    }

    func updateNSView(_ view: GlassSearchFieldView, context: Context) {
        context.coordinator.text = $text
        view.isGlass = isGlass
        if view.field.placeholderString != placeholder { view.field.placeholderString = placeholder }
        // Only push external changes; never fight the field editor while typing.
        if view.field.stringValue != text { view.field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlassSearchFieldView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 240
        return CGSize(width: width, height: GlassSearchFieldView.height)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            if text.wrappedValue != field.stringValue { text.wrappedValue = field.stringValue }
        }

        // Esc while focused clears the search (binding and × button synced); on an empty field it drops focus.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            if textView.string.isEmpty {
                control.window?.makeFirstResponder(nil)
            } else {
                textView.selectAll(nil)
                textView.delete(nil)   // undoable
                if !control.stringValue.isEmpty { control.stringValue = "" }
                if !text.wrappedValue.isEmpty { text.wrappedValue = "" }
            }
            return true
        }
    }
}
