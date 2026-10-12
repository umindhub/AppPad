import AppKit

// Right-hand side of the Workflow panel: icon, name, details (steps, permissions, last run) and key hints.
// Calculator row: expression and result, ↩ copies (flashCopied shows a short confirmation).
final class WorkflowPreviewView: FlippedView {
    var onEscape: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
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

        [iconView, titleLabel, subtitleLabel, textScroll, hintLabel].forEach { addSubview($0) }
        show(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // argument = text after the first space; missingShortcut = a shortcut step not found in Shortcuts.
    func show(_ item: WorkflowPanelItem?, isRunning: Bool = false, lastResult: WorkflowRunResult? = nil,
              argument: String = "", missingShortcut: String? = nil) {
        let views: [NSView] = [iconView, titleLabel, subtitleLabel, textScroll, hintLabel]
        guard let item else {
            views.forEach { $0.isHidden = true }
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
            if result.cancelled {
                status = String(localized: "Cancelled")
            } else if result.success {
                status = String(localized: "Succeeded")
            } else {
                status = String(localized: "Failed")
            }
            line(status + " · " + when, in: text, color: result.success ? .secondaryLabelColor : .systemRed)
            var output = result.success ? result.finalOutput : result.failureSummary
            if output.count > Self.outputLimit { output = String(output.prefix(Self.outputLimit)) + "\n…" }
            if !output.isEmpty { line(output, in: text, monospaced: true) }
        } else {
            line(String(localized: "Not run yet"), in: text, color: .secondaryLabelColor)
        }
        return text
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

    // "time ‹duration›", examples, and what the typed argument parses to.
    private func usage(_ workflow: Workflow, argument: String, in text: NSMutableAttributedString) {
        section(String(localized: "Usage"), in: text)
        let word = workflow.keyword.isEmpty ? WorkflowPanelViewController.token(workflow.displayName) : workflow.keyword
        let hint = workflow.displayArgumentHint.isEmpty ? String(localized: "argument") : workflow.displayArgumentHint
        let slot = workflow.argument == .optional ? "[‹\(hint)›]" : "‹\(hint)›"
        line("\(word) \(slot)", in: text, monospaced: true)
        let examples = WorkflowArguments.examples(for: workflow.argumentType)
        if !examples.isEmpty {
            line(examples.map { "\(word) \($0)" }.joined(separator: "   "), in: text,
                 color: .secondaryLabelColor, monospaced: true)
        }
        let typed = argument.trimmingCharacters(in: .whitespaces)
        switch WorkflowArguments.parse(typed, type: workflow.argumentType, mode: workflow.argument) {
        case .success(let parsed):
            if !parsed.summary.isEmpty { line("→ " + parsed.summary, in: text, color: .systemGreen) }
        case .failure(let error):
            line(error.message, in: text, color: typed.isEmpty ? .secondaryLabelColor : .systemRed)
        }
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
        titleLabel.frame = NSRect(x: textX, y: top, width: max(0, b.width - textX), height: titleHeight)
        subtitleLabel.frame = NSRect(x: textX, y: top + titleHeight, width: max(0, b.width - textX), height: subHeight)

        hintLabel.frame = NSRect(x: 0, y: b.height - 16, width: b.width, height: 16)
        let contentTop = icon + 12
        textScroll.frame = NSRect(x: 0, y: contentTop, width: b.width,
                                  height: max(0, hintLabel.frame.minY - 10 - contentTop))
    }
}
