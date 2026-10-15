import AppKit
import SwiftUI

// Monospaced plain-text editor for scripts / JSON / headers.
// SwiftUI's TextEditor follows the system "smart quotes and dashes" setting, which breaks code.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 12

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
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
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

    var body: some View {
        CodeTextView(text: $text)
            .frame(minHeight: minHeight, maxHeight: max(minHeight, 220))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
