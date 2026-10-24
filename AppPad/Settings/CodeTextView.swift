import AppKit
import SwiftUI

// Monospaced plain-text editor for scripts / JSON / headers.
// SwiftUI's TextEditor follows the system "smart quotes and dashes" setting, which breaks code.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 12
    var isEditable = true   // false: read-only but still selectable / scrollable

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false
        textView.string = text
        textView.isEditable = isEditable
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        guard textView.string != text else { return }
        // Keep the caret where it was when the model changes from outside.
        let selection = textView.selectedRanges
        textView.string = text
        let length = (text as NSString).length
        let kept = selection.filter { $0.rangeValue.upperBound <= length }
        textView.selectedRanges = kept.isEmpty ? [NSValue(range: NSRange(location: length, length: 0))] : kept
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// Rounded field look around CodeTextView.
struct CodeEditorBox: View {
    @Binding var text: String
    var minHeight: CGFloat = 90
    var isEditable = true

    var body: some View {
        CodeTextView(text: $text, isEditable: isEditable)
            .frame(minHeight: minHeight, maxHeight: max(minHeight, 220))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

// Read-only, selectable text that wraps to the proposed width.
// SwiftUI's .textSelection is unreliable inside grouped Forms on macOS.
// Backed by a selectable wrapping NSTextField; size is measured via its cell
// so the live view is never mutated during layout probing.
struct SelectableText: NSViewRepresentable {
    let text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var color: NSColor = .labelColor

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.isEditable = false
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.allowsEditingTextAttributes = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.truncatesLastVisibleLine = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        apply(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        guard field.stringValue != text || field.font != font || field.textColor != color else { return }
        apply(to: field)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        guard let cell = nsView.cell else { return nil }
        let bounded = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let probeWidth = bounded ?? 10_000
        let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: probeWidth, height: 10_000))
        return CGSize(width: bounded ?? ceil(size.width), height: ceil(size.height))
    }

    private func apply(to field: NSTextField) {
        field.stringValue = text
        field.font = font
        field.textColor = color
    }
}
