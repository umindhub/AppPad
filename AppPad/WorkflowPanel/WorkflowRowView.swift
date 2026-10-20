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

// MARK: - Source badge

extension WorkflowSource {
    // Built-in green, mine blue, third-party orange (unreviewed, not necessarily harmful).
    var tint: NSColor {
        switch category {
        case .builtin: return .systemGreen
        case .mine: return .systemBlue
        case .thirdParty: return .systemOrange
        }
    }
}

enum WorkflowSourceBadge {
    // Capsule with symbol + label in the source's tint (preview header).
    // Drawn lazily, so dynamic colors follow the appearance.
    static func pill(_ source: WorkflowSource, fontSize: CGFloat = 11) -> NSImage {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let label = source.label
        let text = NSAttributedString(string: label, attributes: [.font: font])
        let textSize = text.size()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: fontSize * 0.9, weight: .semibold)
        let symbol = NSImage(systemSymbolName: source.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        let symbolSize = symbol?.size ?? .zero
        let padX: CGFloat = 7, padY: CGFloat = 2, gap: CGFloat = 4
        let height = ceil(textSize.height) + 2 * padY
        let width = ceil(padX + symbolSize.width + gap + textSize.width + padX)
        let tint = source.tint
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let pill = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
            tint.withAlphaComponent(0.14).setFill()
            path.fill()
            tint.withAlphaComponent(0.4).setStroke()
            path.lineWidth = 1
            path.stroke()
            if let symbol {
                // Template symbol → one color: draw the shape, then paint the tint over its pixels only.
                let colored = NSImage(size: symbolSize, flipped: false) { r in
                    symbol.draw(in: r)
                    tint.setFill()
                    r.fill(using: .sourceAtop)
                    return true
                }
                colored.draw(in: NSRect(x: padX, y: ((rect.height - symbolSize.height) / 2).rounded(),
                                        width: symbolSize.width, height: symbolSize.height))
            }
            NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: tint])
                .draw(at: NSPoint(x: padX + symbolSize.width + gap, y: ((rect.height - textSize.height) / 2).rounded()))
            return true
        }
    }

    // Symbol only, for the panel rows (third-party marker).
    static func mark(_ source: WorkflowSource, pointSize: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(paletteColors: [source.tint]))
        return NSImage(systemSymbolName: source.symbol, accessibilityDescription: source.label)?
            .withSymbolConfiguration(config)
    }
}

// Icon, title + subtitle, in-panel shortcut, source mark, ⌘n badge (same metrics as the clipboard rows).
final class WorkflowRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("WorkflowRow")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let keyLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let sourceView = NSImageView()   // third-party workflows only, left of the ⌘n badge

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
        sourceView.imageScaling = .scaleNone
        [iconView, titleLabel, subtitleLabel, keyLabel, badgeLabel, sourceView].forEach { addSubview($0) }
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
        sourceView.image = nil
        sourceView.toolTip = nil

        switch item {
        case .workflow(let workflow):
            subtitleLabel.stringValue = isRunning ? String(localized: "Running…") : Self.summary(workflow)
            keyLabel.stringValue = workflow.panelKey?.displayString ?? ""
            if workflow.source.isThirdParty {
                sourceView.image = WorkflowSourceBadge.mark(workflow.source, pointSize: max(11, font.pointSize * 0.8))
                sourceView.toolTip = workflow.source.longLabel
            }
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
        if let mark = sourceView.image {
            let size = mark.size
            // Close to the badge, like the clipboard's text / image symbol.
            sourceView.frame = NSRect(x: badgeLabel.frame.minX - 6 - size.width, y: ((b.height - size.height) / 2).rounded(),
                                      width: size.width, height: size.height)
            right = sourceView.frame.minX - 10
        } else {
            sourceView.frame = .zero
        }
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
