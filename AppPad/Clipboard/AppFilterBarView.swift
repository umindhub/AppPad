import AppKit

// Top source apps under the search field; click toggles the "AppName::" filter.
final class AppFilterBarView: FlippedView {
    struct Chip {
        let bundleID: String
        let name: String
        let icon: NSImage?
        let count: Int
    }

    var onToggle: ((String) -> Void)?
    private var buttons: [AppChipView] = []

    static let chipSize: CGFloat = 34
    static let gap: CGFloat = 8

    func set(chips: [Chip], selected: String?) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = chips.map { chip in
            let view = AppChipView()
            view.icon.image = chip.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            view.toolTip = "\(chip.name)  (\(chip.count))"
            view.isSelected = chip.bundleID == selected
            view.isDimmed = selected != nil && chip.bundleID != selected
            view.onClick = { [weak self] in self?.onToggle?(chip.bundleID) }
            addSubview(view)
            return view
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = Self.chipSize
        let total = CGFloat(buttons.count) * size + CGFloat(max(0, buttons.count - 1)) * Self.gap
        var x = ((bounds.width - total) / 2).rounded()
        for button in buttons {
            button.frame = NSRect(x: x, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
            x += size + Self.gap
        }
    }
}

final class AppChipView: NSView {
    let icon = NSImageView()
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }
    var isDimmed = false { didSet { alphaValue = isDimmed ? 0.55 : 1 } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        icon.frame = bounds.insetBy(dx: 5, dy: 5)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        } else {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            path.fill()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

// "★ Saved" capsule right of the search field, same height; follows the Liquid Glass setting.
// on = show the saved library only.
final class SavedToggleView: NSView {
    var onToggle: (() -> Void)?
    var isOn = false { didSet { if oldValue != isOn { updateStyle() } } }
    var isGlass = false { didSet { if oldValue != isGlass { updateStyle() } } }

    private let glass = GlassBackdropView()
    private let fill = NSView()          // tint / plain background above the glass
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: String(localized: "Saved"))
    private(set) var height: CGFloat = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fill.wantsLayer = true
        fill.layer?.cornerCurve = .circular
        icon.imageScaling = .scaleNone
        [glass, fill, icon, label].forEach { addSubview($0) }
        setHeight(32)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Font and icon scale with the search field height.
    func setHeight(_ newHeight: CGFloat) {
        height = newHeight
        let pointSize = max(12, (newHeight * 0.4).rounded())
        label.font = .systemFont(ofSize: pointSize, weight: .medium)
        icon.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize - 1, weight: .semibold))
        updateStyle()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private var hPadding: CGFloat { (height * 0.4).rounded() }

    override var intrinsicContentSize: NSSize {
        let iconWidth = icon.image?.size.width ?? 14
        return NSSize(width: ceil(hPadding * 2 + iconWidth + 5 + label.intrinsicContentSize.width), height: height)
    }

    private func updateStyle() {
        glass.isHidden = !isGlass
        icon.contentTintColor = isOn ? .systemYellow : .secondaryLabelColor
        label.textColor = isOn ? .labelColor : .secondaryLabelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isOn {
                fill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
                fill.layer?.borderColor = NSColor.controlAccentColor.cgColor
                fill.layer?.borderWidth = 1
            } else if isGlass {
                fill.layer?.backgroundColor = NSColor.clear.cgColor
                fill.layer?.borderWidth = 0
            } else {
                // Same look as the plain (non-glass) search pill.
                fill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
                fill.layer?.borderColor = NSColor.separatorColor.cgColor
                fill.layer?.borderWidth = 0.5
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    override func layout() {
        super.layout()
        let b = bounds
        glass.frame = b
        glass.cornerRadius = b.height / 2
        fill.frame = b
        fill.layer?.cornerRadius = b.height / 2
        let iconSize = icon.image?.size ?? NSSize(width: 14, height: 14)
        icon.frame = NSRect(x: hPadding, y: ((b.height - iconSize.height) / 2).rounded(),
                            width: iconSize.width, height: iconSize.height)
        let h = ceil(label.cell?.cellSize.height ?? 15)
        label.frame = NSRect(x: icon.frame.maxX + 5, y: ((b.height - h) / 2).rounded(),
                             width: max(0, b.width - icon.frame.maxX - 5 - hPadding + 2), height: h)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Whole capsule is one button (subviews never take the click).
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onToggle?() }
    }
}
