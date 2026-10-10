import AppKit

// Calculator row shown above search results. Enter / click copies the result.
final class CalcResultView: FlippedView {
    var onClick: (() -> Void)?
    var isSelected = false {
        didSet { if oldValue != isSelected { needsDisplay = true } }
    }

    private let expressionLabel = NSTextField(labelWithString: "")
    private let resultLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: String(localized: "↩ Copy"))
    private var resultText = ""
    private var copiedTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        expressionLabel.font = .systemFont(ofSize: 13)
        expressionLabel.textColor = .secondaryLabelColor
        expressionLabel.lineBreakMode = .byTruncatingTail
        resultLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        resultLabel.alignment = .right
        resultLabel.lineBreakMode = .byTruncatingHead
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .right
        addSubview(expressionLabel)
        addSubview(resultLabel)
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(expression: String, result: String) {
        copiedTask?.cancel()
        expressionLabel.stringValue = expression
        resultText = "= " + result
        resultLabel.stringValue = resultText
    }

    func flashCopied() {
        copiedTask?.cancel()
        resultLabel.stringValue = String(localized: "Copied")
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            self.resultLabel.stringValue = self.resultText
        }
    }

    override func layout() {
        super.layout()
        let b = bounds
        let hintWidth: CGFloat = 56
        let exprWidth = min(b.width * 0.4, 180)
        expressionLabel.frame = NSRect(x: 16, y: (b.height - 18) / 2, width: exprWidth, height: 18)
        hintLabel.frame = NSRect(x: b.width - hintWidth - 14, y: (b.height - 14) / 2, width: hintWidth, height: 14)
        let resultX = 16 + exprWidth + 8
        resultLabel.frame = NSRect(x: resultX, y: (b.height - 26) / 2,
                                   width: max(0, hintLabel.frame.minX - 8 - resultX), height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isSelected ? 0.14 : 0.06
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }
}
