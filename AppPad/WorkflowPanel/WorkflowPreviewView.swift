import AppKit

// Right-hand side of the Workflow panel: icon, name, details (steps, permissions, last run) and key hints.
final class WorkflowPreviewView: FlippedView {
    var onEscape: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let textScroll = NSScrollView()
    private let textView = PreviewTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    private let hintLabel = NSTextField(labelWithString: "")

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

    func show(_ item: WorkflowPanelItem?, isRunning: Bool = false, lastResult: WorkflowRunResult? = nil) {
        let views: [NSView] = [iconView, titleLabel, subtitleLabel, textScroll, hintLabel]
        guard let item else {
            views.forEach { $0.isHidden = true }
            return
        }
        views.forEach { $0.isHidden = false }
        iconView.image = item.icon
        titleLabel.stringValue = item.title

        switch item {
        case .workflow(let workflow):
            subtitleLabel.stringValue = workflow.enabled
                ? String(localized: "Workflow")
                : String(localized: "Workflow (disabled)")
            textView.textStorage?.setAttributedString(details(workflow, isRunning: isRunning, lastResult: lastResult))
            var hint = String(localized: "↩ Run   ⌘↩ Edit in Settings")
            if let key = workflow.panelKey?.displayString { hint += "   " + key }
            hintLabel.stringValue = hint
        case .app(let app):
            subtitleLabel.stringValue = (app.url.path as NSString).abbreviatingWithTildeInPath
            textView.textStorage?.setAttributedString(details(app))
            hintLabel.stringValue = String(localized: "↩ Open")
        }
        textView.scrollToBeginningOfDocument(nil)
        needsLayout = true
    }

    // MARK: - Text

    private func details(_ workflow: Workflow, isRunning: Bool, lastResult: WorkflowRunResult?) -> NSAttributedString {
        let text = NSMutableAttributedString()
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
        case .builtin: return step.builtin.title
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
