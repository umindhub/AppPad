import AppKit

// Right-hand side of the Workflow panel: icon, name, details (steps, permissions, last run) and key hints.
// Calculator row: expression and result, ↩ copies (flashCopied shows a short confirmation).
final class WorkflowPreviewView: FlippedView {
    var onEscape: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let sourcePill = NSImageView()   // workflows: built-in / mine / third-party, right of the title
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let textScroll = NSScrollView()
    private let textView = PreviewTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    private let hintLabel = NSTextField(labelWithString: "")
    private var titleText = ""
    private var copiedTask: Task<Void, Never>?

    private static let outputLimit = 4000
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail

        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.drawsBackground = false
        textScroll.borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onEscape = { [weak self] in self?.onEscape?() }
        textScroll.documentView = textView

        sourcePill.imageScaling = .scaleNone
        [iconView, titleLabel, sourcePill, subtitleLabel, textScroll, hintLabel].forEach { addSubview($0) }
        show(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // argument = text after the first space; missingShortcut = a shortcut step not found in Shortcuts.
    func show(_ item: WorkflowPanelItem?, isRunning: Bool = false, lastResult: WorkflowRunResult? = nil,
              argument: String = "", missingShortcut: String? = nil) {
        let views: [NSView] = [iconView, titleLabel, subtitleLabel, textScroll, hintLabel]
        sourcePill.image = nil
        guard let item else {
            views.forEach { $0.isHidden = true }
            needsLayout = true
            return
        }
        views.forEach { $0.isHidden = false }
        copiedTask?.cancel()
        iconView.image = item.icon
        titleText = item.title
        titleLabel.stringValue = titleText

        switch item {
        case .workflow(let workflow):
            let kind = workflow.enabled
                ? String(localized: "Workflow")
                : String(localized: "Workflow (disabled)")
            subtitleLabel.stringValue = "\(kind) · \(workflow.identifier) · \(workflow.version)"
            sourcePill.image = WorkflowSourceBadge.pill(workflow.source)
            sourcePill.toolTip = workflow.source.longLabel
            textView.textStorage?.setAttributedString(details(workflow, isRunning: isRunning, lastResult: lastResult,
                                                              argument: argument, missingShortcut: missingShortcut))
            var hint = String(localized: "↩ Run   ⌘↩ Edit in Settings")
            if let missingShortcut {
                hint = BuiltinWorkflows.bundledShortcut(missingShortcut) != nil
                    ? String(localized: "↩ Install Shortcut   ⌘↩ Edit in Settings")
                    : String(localized: "↩ Open Shortcuts   ⌘↩ Edit in Settings")
            }
            if let key = workflow.panelKey?.displayString { hint += "   " + key }
            hintLabel.stringValue = hint
        case .app(let app):
            subtitleLabel.stringValue = (app.url.path as NSString).abbreviatingWithTildeInPath
            textView.textStorage?.setAttributedString(details(app))
            hintLabel.stringValue = String(localized: "↩ Open")
        case .calculator(let expression, let result):
            subtitleLabel.stringValue = String(localized: "Calculator")
            textView.textStorage?.setAttributedString(details(expression: expression, result: result))
            hintLabel.stringValue = String(localized: "↩ Copy")
        }
        textView.scrollToBeginningOfDocument(nil)
        needsLayout = true
    }

    // MARK: - Text

    private func details(_ workflow: Workflow, isRunning: Bool, lastResult: WorkflowRunResult?,
                         argument: String, missingShortcut: String?) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let description = workflow.displaySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { line(description, in: text) }

        if let missingShortcut {
            section(String(localized: "Setup"), in: text)
            let help = BuiltinWorkflows.setupText(for: missingShortcut)
                ?? String(localized: "The shortcut “\(missingShortcut)” is not in the Shortcuts app.")
            line(help, in: text, color: .systemOrange)
        }

        if workflow.argument != .off {
            usage(workflow, argument: argument, in: text)
        }

        section(String(localized: "Steps"), in: text)
        for (index, step) in workflow.steps.enumerated() {
            line("\(index + 1). " + Self.stepDetail(step), in: text)
        }

        sourceDetails(workflow.source, in: text)

        let items = workflow.requiredPermissions
        if !items.isEmpty {
            section(String(localized: "Permissions"), in: text)
            let store = PermissionStore.shared
            for item in items {
                let mark: String
                switch store.decision(for: item, workflow: workflow.id) {
                case .allow?: mark = "✓"
                case .deny?: mark = "✕"
                case nil: mark = "?"
                }
                line(mark + "  " + item.title, in: text)
            }
        }

        section(String(localized: "Last Run"), in: text)
        if isRunning {
            line(String(localized: "Running…"), in: text)
        } else if let result = lastResult {
            let when = Self.relativeFormatter.localizedString(for: result.finishedAt, relativeTo: Date())
            let status: String
            let state: ResultState
            if result.cancelled {
                status = String(localized: "Cancelled")
                state = .cancelled
            } else if result.success {
                status = String(localized: "Succeeded")
                state = .valid
            } else {
                status = String(localized: "Failed")
                state = .invalid
            }
            lastRun(status + " · " + when, in: text, state: state)
            var output = result.success ? result.finalOutput : result.failureSummary
            if output.count > Self.outputLimit { output = String(output.prefix(Self.outputLimit)) + "\n…" }
            if !output.isEmpty { line(output, in: text, monospaced: true) }
        } else {
            line(String(localized: "Not run yet"), in: text, color: .secondaryLabelColor)
        }
        return text
    }

    // Where it came from: full link / file name and when, plus "edited" once its behavior changed.
    private func sourceDetails(_ source: WorkflowSource, in text: NSMutableAttributedString) {
        section(String(localized: "Source"), in: text)
        let when = source.date.map { Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()) }
        switch source.kind {
        case .builtin:
            line(String(localized: "Included with AppPad"), in: text)
        case .local:
            line(source.client.isEmpty ? String(localized: "Created by you")
                                       : String(localized: "Saved by \(source.client)"), in: text)
        case .link:
            line(String(localized: "Third-party"), in: text, color: .systemOrange)
            line(source.url, in: text, color: .secondaryLabelColor, monospaced: true)
        case .file:
            line(String(localized: "Third-party"), in: text, color: .systemOrange)
            line(source.fileName.isEmpty ? String(localized: "Imported from a file")
                                         : String(localized: "Imported from the file “\(source.fileName)”"),
                 in: text, color: .secondaryLabelColor)
        }
        if source.isThirdParty, let when {
            line(String(localized: "Imported \(when)"), in: text, color: .secondaryLabelColor)
        }
        if source.modified {
            line(String(localized: "Steps or permissions were changed after it was added."), in: text,
                 color: source.isThirdParty ? .systemOrange : .secondaryLabelColor)
        }
    }

    // Briefly replaces the title with "Copied" (calculator row).
    func flashCopied() {
        copiedTask?.cancel()
        titleLabel.stringValue = String(localized: "Copied")
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            self.titleLabel.stringValue = self.titleText
        }
    }

    private func details(expression: String, result: Calculator.Result) -> NSAttributedString {
        let text = NSMutableAttributedString()
        line(expression, in: text, color: .secondaryLabelColor, monospaced: true)
        text.append(NSAttributedString(string: "= " + result.display + "\n", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))
        if result.copyText != result.display {
            line(result.copyText, in: text, color: .secondaryLabelColor, monospaced: true)
        }
        return text
    }

    private func details(_ app: AppInfo) -> NSAttributedString {
        let text = NSMutableAttributedString()
        if let id = app.bundleID {
            line(id, in: text, color: .secondaryLabelColor)
        }
        return text
    }

    private static func stepDetail(_ step: WorkflowStep) -> String {
        switch step.kind {
        case .shortcut: return step.kind.title + " “\(step.shortcutName)”"
        case .builtin: return step.builtin == .openURL ? step.builtin.title + " · " + step.url : step.builtin.title
        case .http: return step.kind.title + " · " + step.http.method.rawValue + " " + (step.http.host ?? "")
        case .appleScript: return step.language == .javaScript ? "JavaScript (JXA)" : step.kind.title
        case .shell: return step.kind.title
        }
    }

    private func section(_ title: String, in text: NSMutableAttributedString) {
        if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
        text.append(NSAttributedString(string: title + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
    }

    private func line(_ string: String, in text: NSMutableAttributedString,
                      color: NSColor = .labelColor, monospaced: Bool = false) {
        let font: NSFont = monospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 13)
        text.append(NSAttributedString(string: string + "\n", attributes: [.font: font, .foregroundColor: color]))
    }

    // "设置倒计时 ‹时长›", one example pill per line with what it means, then the typed argument's result.
    private func usage(_ workflow: Workflow, argument: String, in text: NSMutableAttributedString) {
        section(String(localized: "Usage"), in: text)
        // Same word the field gets when the row is picked ("设置倒计时"), not the short keyword.
        let word = WorkflowPanelViewController.token(workflow.displayName)
        let hint = workflow.displayArgumentHint.isEmpty ? String(localized: "argument") : workflow.displayArgumentHint
        let slot = workflow.argument == .optional ? "[‹\(hint)›]" : "‹\(hint)›"
        text.append(NSAttributedString(string: "\(word) \(slot)\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))

        let examples = WorkflowArguments.examples(for: workflow.argumentType)
        if !examples.isEmpty {
            text.append(NSAttributedString(string: String(localized: "Examples") + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: Self.captionStyle,
            ]))
            let maxWidth = max(0, textScroll.contentSize.width - 12)
            for example in examples {
                let summary = WorkflowArguments.exampleSummary(example, type: workflow.argumentType)
                text.append(exampleRow(word: word, argument: example, summary: summary, maxWidth: maxWidth))
            }
        }

        // Result of what was typed. Placeholder, result and error share one size so the page does not jump.
        let typed = argument.trimmingCharacters(in: .whitespaces)
        switch WorkflowArguments.parse(typed, type: workflow.argumentType, mode: workflow.argument) {
        case .success(let parsed):
            // Optional argument left empty: keep the line's height with a blank.
            if parsed.summary.isEmpty {
                result(" ", in: text, state: .neutral)
            } else {
                result(parsed.summary, in: text, state: .valid)
            }
        case .failure(let error):
            result(error.message, in: text, state: typed.isEmpty ? .neutral : .invalid)
        }
    }

    private enum ResultState {
        case neutral, valid, invalid, cancelled
    }

    private static let resultFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    private static let resultIconSize: CGFloat = 15
    private static let resultIconGap: CGFloat = 6

    // Last Run line: same badges as the argument result, one shade lighter; body text size (13).
    private static let lastRunFont = NSFont.systemFont(ofSize: 13)
    private static let lastRunIconSize: CGFloat = 14
    private static let lastRunAlpha: CGFloat = 0.7

    // Same size as the usage line (14); icon at the left edge (pill edge), text after it.
    // Valid: green ✓ + normal text; invalid: red ✕ + red text; neutral: blank slot, so text never shifts.
    private func result(_ string: String, in text: NSMutableAttributedString, state: ResultState) {
        let textColor: NSColor
        switch state {
        case .neutral, .cancelled: textColor = .secondaryLabelColor
        case .valid: textColor = .labelColor
        case .invalid: textColor = .systemRed
        }
        badgeLine(string, in: text, state: state, iconAlpha: 1, textColor: textColor,
                  font: Self.resultFont, iconSize: Self.resultIconSize, style: Self.resultStyle)
    }

    // Succeeded: lighter green ✓ + secondary text; failed: lighter red ✕ + lighter red text;
    // cancelled: lighter gray – + tertiary text.
    private func lastRun(_ string: String, in text: NSMutableAttributedString, state: ResultState) {
        let textColor: NSColor
        switch state {
        case .neutral: textColor = .secondaryLabelColor
        case .valid: textColor = .secondaryLabelColor
        case .invalid: textColor = NSColor.systemRed.withAlphaComponent(Self.lastRunAlpha)
        case .cancelled: textColor = .tertiaryLabelColor
        }
        badgeLine(string, in: text, state: state, iconAlpha: Self.lastRunAlpha, textColor: textColor,
                  font: Self.lastRunFont, iconSize: Self.lastRunIconSize, style: Self.lastRunStyle)
    }

    private func badgeLine(_ string: String, in text: NSMutableAttributedString, state: ResultState,
                           iconAlpha: CGFloat, textColor: NSColor, font: NSFont, iconSize: CGFloat,
                           style: NSParagraphStyle) {
        let icon = Self.resultIcon(state, alpha: iconAlpha, size: iconSize, font: font, centeredOn: string)
        let line = NSMutableAttributedString(attachment: icon)
        line.append(NSAttributedString(string: "\u{00A0}", attributes: [
            .font: font, .kern: Self.resultIconGap,
        ]))
        line.append(NSAttributedString(string: string + "\n", attributes: [
            .font: font, .foregroundColor: textColor,
        ]))
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        text.append(line)
    }

    // White mark on a green / red / gray circle, or a clear image of the same size for the neutral state.
    private static func resultIcon(_ state: ResultState, alpha: CGFloat, size side: CGFloat, font: NSFont,
                                   centeredOn string: String) -> NSTextAttachment {
        let size = NSSize(width: side, height: side)
        let attachment = NSTextAttachment()
        switch state {
        case .neutral: attachment.image = NSImage(size: size, flipped: false) { _ in true }
        case .valid: attachment.image = badge(mark: "checkmark", color: .systemGreen, alpha: alpha, size: size)
        case .invalid: attachment.image = badge(mark: "xmark", color: .systemRed, alpha: alpha, size: size)
        case .cancelled: attachment.image = badge(mark: "minus", color: .systemGray, alpha: alpha, size: size)
        }
        // Vertically centered on the text's visual middle; half-point steps (Retina) instead of whole points.
        let y = textMiddle(string, font: font) - size.height / 2
        attachment.bounds = NSRect(x: 0, y: (y * 2).rounded() / 2, width: size.width, height: size.height)
        return attachment
    }

    // Middle of the glyph body above the baseline. Latin: half the cap height. CJK / kana / Hangul
    // (fallback font, taller body than capHeight): ink bounds of a full-width reference glyph.
    private static func textMiddle(_ string: String, font: NSFont) -> CGFloat {
        let wide = string.unicodeScalars.contains { $0.value >= 0x2E80 && $0.value <= 0xD7FF }
        guard wide else { return font.capHeight / 2 }
        let ink = ("中" as NSString).boundingRect(with: .zero, options: [.usesDeviceMetrics],
                                                  attributes: [.font: font])
        return ink.height > 0 ? ink.midY : font.capHeight / 2
    }

    // Like checkmark.circle.fill / xmark.circle.fill, but drawn by hand: a symbol image is a template
    // and comes out as one solid color. Drawn lazily, so the dynamic color follows the appearance.
    // alpha < 1 lightens only the circle; the mark stays solid white.
    private static func badge(mark: String, color: NSColor, alpha: CGFloat = 1, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let config = NSImage.SymbolConfiguration(pointSize: rect.height * 0.5, weight: .heavy)
            guard let symbol = NSImage(systemSymbolName: mark, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return true }
            let markSize = symbol.size
            // Template → white: draw the shape, then paint white over its pixels only.
            let white = NSImage(size: markSize, flipped: false) { r in
                symbol.draw(in: r)
                NSColor.white.setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            white.draw(in: NSRect(x: (rect.midX - markSize.width / 2).rounded(),
                                  y: (rect.midY - markSize.height / 2).rounded(),
                                  width: markSize.width, height: markSize.height))
            return true
        }
    }

    // MARK: - Example pills

    // Example rows use the usage line size (14).
    private static let rowFont = NSFont.systemFont(ofSize: 14)

    private static let captionStyle: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 6
        p.paragraphSpacing = 4
        return p
    }()

    private static let exampleStyle: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 6
        p.headIndent = 10          // wrapped explanation sits slightly indented
        p.lineBreakMode = .byWordWrapping
        return p
    }()

    // Inner left padding of a pill.
    private static let pillPadX: CGFloat = 10

    // Icon flush left; wrapped lines continue under the text, not under the icon.
    private static let resultStyle: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 10
        let space = ("\u{00A0}" as NSString).size(withAttributes: [.font: resultFont]).width
        p.headIndent = resultIconSize + space + resultIconGap
        return p
    }()

    // Last Run line sits right under its section title: no extra spacing, wrapped text under the text.
    private static let lastRunStyle: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        let space = ("\u{00A0}" as NSString).size(withAttributes: [.font: lastRunFont]).width
        p.headIndent = lastRunIconSize + space + resultIconGap
        return p
    }()

    // [pill "设置倒计时 1h30m"]  → 1 hour, 30 minutes
    private func exampleRow(word: String, argument: String, summary: String?, maxWidth: CGFloat) -> NSAttributedString {
        let row = NSMutableAttributedString(attachment: Self.pillAttachment(word: word, argument: argument,
                                                                           maxWidth: maxWidth, alignTo: Self.rowFont))
        if let summary {
            row.append(NSAttributedString(string: "  →  ", attributes: [
                .font: Self.rowFont, .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
            row.append(NSAttributedString(string: summary, attributes: [
                .font: Self.rowFont, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        row.append(NSAttributedString(string: "\n", attributes: [.font: Self.rowFont]))
        row.addAttribute(.paragraphStyle, value: Self.exampleStyle, range: NSRange(location: 0, length: row.length))
        return row
    }

    // Capsule image: keyword in secondary, argument in bold; tinted with the accent color.
    // Drawn lazily so dynamic colors follow the current appearance.
    private static func pillAttachment(word: String, argument: String, maxWidth: CGFloat,
                                       alignTo font: NSFont) -> NSTextAttachment {
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let label = NSMutableAttributedString(string: word + " ", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        label.append(NSAttributedString(string: argument, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))
        label.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: label.length))

        let padX = pillPadX, padY: CGFloat = 3
        let textSize = label.size()
        var width = ceil(textSize.width) + 2 * padX
        if maxWidth > 0 { width = min(width, maxWidth) }
        let textHeight = ceil(textSize.height)
        let height = textHeight + 2 * padY
        let drawn = NSAttributedString(attributedString: label)  // immutable copy for the handler

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let pill = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
            NSColor.controlAccentColor.withAlphaComponent(0.13).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
            drawn.draw(in: NSRect(x: padX, y: padY, width: rect.width - 2 * padX, height: textHeight))
            return true
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        // Vertically center the capsule on the explanation text.
        attachment.bounds = NSRect(x: 0, y: ((font.capHeight - height) / 2).rounded(), width: width, height: height)
        return attachment
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let b = bounds
        let icon: CGFloat = 64
        iconView.frame = NSRect(x: 0, y: 0, width: icon, height: icon)
        let textX = icon + 12
        let titleHeight = ceil(titleLabel.cell?.cellSize.height ?? 22)
        let subHeight = ceil(subtitleLabel.cell?.cellSize.height ?? 16)
        let top = ((icon - titleHeight - subHeight) / 2).rounded()
        let available = max(0, b.width - textX)
        if let pill = sourcePill.image {
            // Title shrinks (truncates) before the pill does; the pill sits right after the title text.
            let gap: CGFloat = 8
            let titleWidth = min(ceil(titleLabel.cell?.cellSize.width ?? 0) + 2, max(0, available - pill.size.width - gap))
            titleLabel.frame = NSRect(x: textX, y: top, width: titleWidth, height: titleHeight)
            sourcePill.frame = NSRect(x: textX + titleWidth + gap, y: top + ((titleHeight - pill.size.height) / 2).rounded(),
                                      width: pill.size.width, height: pill.size.height)
        } else {
            titleLabel.frame = NSRect(x: textX, y: top, width: available, height: titleHeight)
            sourcePill.frame = .zero
        }
        subtitleLabel.frame = NSRect(x: textX, y: top + titleHeight, width: max(0, b.width - textX), height: subHeight)

        hintLabel.frame = NSRect(x: 0, y: b.height - 16, width: b.width, height: 16)
        let contentTop = icon + 12
        textScroll.frame = NSRect(x: 0, y: contentTop, width: b.width,
                                  height: max(0, hintLabel.frame.minY - 10 - contentTop))
    }
}
