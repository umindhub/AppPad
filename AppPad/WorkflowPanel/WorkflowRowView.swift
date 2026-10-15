import AppKit

// One row of the Workflow panel.
enum WorkflowPanelItem {
    case workflow(Workflow)
    case app(AppInfo)
    case calculator(expression: String, result: Calculator.Result)   // pinned first row while typing math

    var title: String {
        switch self {
        case .workflow(let workflow): return workflow.displayName
        case .app(let app): return app.name
        case .calculator(_, let result): return "= " + result.display
        }
    }

    var icon: NSImage {
        switch self {
        case .workflow(let workflow): return WorkflowIcon.image(for: workflow)
        case .app(let app): return IconCache.shared.icon(for: app)
        case .calculator: return Self.calculatorIcon
        }
    }

    var isCalculator: Bool {
        if case .calculator = self { return true }
        return false
    }

    // Rounded orange tile with a white symbol, same footprint as app icons.
    private static let calculatorIcon: NSImage = {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            let tile = rect.insetBy(dx: 40, dy: 40)
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: tile, xRadius: 100, yRadius: 100).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 240, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "plus.forwardslash.minus", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: tile.midX - s.width / 2, y: tile.midY - s.height / 2,
                                       width: s.width, height: s.height))
            }
            return true
        }
    }()
}

// Icon, title + subtitle, in-panel shortcut, ⌘n badge (same metrics as the clipboard rows).
final class WorkflowRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("WorkflowRow")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let keyLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        iconView.imageScaling = .scaleProportionallyUpOrDown
        for label in [titleLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
        }
        subtitleLabel.textColor = .secondaryLabelColor
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.alignment = .right
        badgeLabel.textColor = .tertiaryLabelColor
        badgeLabel.alignment = .right
        [iconView, titleLabel, subtitleLabel, keyLabel, badgeLabel].forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ item: WorkflowPanelItem, index: Int, font: NSFont, isRunning: Bool) {
        iconView.image = item.icon
        titleLabel.font = font
        titleLabel.stringValue = item.title
        let small = NSFont.systemFont(ofSize: max(11, (font.pointSize * 0.78).rounded()))
        subtitleLabel.font = small
        keyLabel.font = small
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: max(11, font.pointSize * 0.75), weight: .regular)
        badgeLabel.stringValue = index < 10 ? "⌘\((index + 1) % 10)" : ""

        switch item {
        case .workflow(let workflow):
            subtitleLabel.stringValue = isRunning ? String(localized: "Running…") : Self.summary(workflow)
            keyLabel.stringValue = workflow.panelKey?.displayString ?? ""
        case .app:
            subtitleLabel.stringValue = String(localized: "Application")
            keyLabel.stringValue = ""
        case .calculator(let expression, _):
            subtitleLabel.stringValue = expression
            keyLabel.stringValue = ""
        }
        // Result in monospaced digits so columns of numbers read cleanly.
        if item.isCalculator {
            titleLabel.font = .monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold)
        }
        needsLayout = true
    }

    // Description if set, else "Shell Script · HTTP Request"
    private static func summary(_ workflow: Workflow) -> String {
        let description = workflow.displaySummary
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !description.isEmpty { return description }
        var kinds: [String] = []
        for step in workflow.steps where !kinds.contains(step.kind.title) {
            kinds.append(step.kind.title)
        }
        let text = kinds.joined(separator: " · ")
        return text.isEmpty ? String(localized: "Workflow") : text
    }

    override func layout() {
        super.layout()
        let b = bounds
        let iconSize = min(40, max(22, b.height - 8))
        iconView.frame = NSRect(x: 10, y: ((b.height - iconSize) / 2).rounded(), width: iconSize, height: iconSize)
        let x = iconView.frame.maxX + 10

        let badgeFont = badgeLabel.font ?? .systemFont(ofSize: 11)
        let badgeWidth = ceil(("⌘0" as NSString).size(withAttributes: [.font: badgeFont]).width) + 4
        let badgeHeight = ceil(badgeLabel.cell?.cellSize.height ?? 16)
        badgeLabel.frame = NSRect(x: b.width - badgeWidth - 12, y: ((b.height - badgeHeight) / 2).rounded(),
                                  width: badgeWidth, height: badgeHeight)
        var right = badgeLabel.frame.minX - 10
        if !keyLabel.stringValue.isEmpty {
            let width = ceil(keyLabel.cell?.cellSize.width ?? 40) + 4
            let height = ceil(keyLabel.cell?.cellSize.height ?? 16)
            keyLabel.frame = NSRect(x: right - width, y: ((b.height - height) / 2).rounded(), width: width, height: height)
            right = keyLabel.frame.minX - 10
        } else {
            keyLabel.frame = .zero
        }

        // Title above subtitle, the pair centered on the row.
        let titleHeight = ceil(titleLabel.cell?.cellSize.height ?? 18)
        let subHeight = ceil(subtitleLabel.cell?.cellSize.height ?? 14)
        let top = ((b.height - titleHeight - subHeight) / 2).rounded()
        let width = max(0, right - x)
        titleLabel.frame = NSRect(x: x, y: top, width: width, height: titleHeight)
        subtitleLabel.frame = NSRect(x: x, y: top + titleHeight, width: width, height: subHeight)
    }
}
