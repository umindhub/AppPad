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
    // Base hue: pill fill and border.
    var tint: NSColor {
        switch category {
        case .builtin: return .systemGreen
        case .mine: return .systemBlue
        case .thirdParty: return .systemOrange
        }
    }

    // false = original system colors (same as tint); true = darker shade in light mode, brighter in dark mode.
    private static let useDeepInk = false

    // Text / symbol color.
    var ink: NSColor {
        guard Self.useDeepInk else { return tint }
        switch category {
        case .builtin: return Self.inkGreen
        case .mine: return Self.inkBlue
        case .thirdParty: return Self.inkOrange
        }
    }

    private static let inkGreen = dynamic(light: NSColor(srgbRed: 0.10, green: 0.50, blue: 0.22, alpha: 1),
                                          dark: NSColor(srgbRed: 0.30, green: 0.85, blue: 0.40, alpha: 1))
    private static let inkBlue = dynamic(light: NSColor(srgbRed: 0.04, green: 0.37, blue: 0.80, alpha: 1),
                                         dark: NSColor(srgbRed: 0.42, green: 0.69, blue: 1.00, alpha: 1))
    private static let inkOrange = dynamic(light: NSColor(srgbRed: 0.70, green: 0.31, blue: 0.00, alpha: 1),
                                           dark: NSColor(srgbRed: 1.00, green: 0.70, blue: 0.25, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

// Source pill (preview header) or symbol-only mark (panel rows), layer-backed so it can use EDR.
// Same technique as the glass search field's focus glow (SearchGlowView):
//   fill : SDR tinted capsule
//   wash : uniform HDR white over the capsule (brightness only)
//   rim  : tint hairline (plain SDR, HDR or none — see rimMode)
//   ink  : symbol + label, HDR in dark mode (light mode keeps the dark SDR ink for contrast)
// HDR colors go into CAGradientLayers with two equal stops: their float backing keeps values > 1
// (plain backgroundColor / shape colors don't). The root layer opts into EDR too.
final class WorkflowSourceBadgeView: NSView {
    enum Style: Equatable {
        case pill(fontSize: CGFloat)
        case mark(pointSize: CGFloat)
    }

    // Wash: same values as SearchGlowView.
    private static let washHDR: CGFloat = 1.4
    private static let washAlphaLight: CGFloat = 0.18
    private static let washAlphaDark: CGFloat = 0.12
    // Rim: .plain = original SDR stroke (tint 40%), .hdr = brightened stroke, .none = no stroke.
    private enum RimMode { case none, plain, hdr }
    private static let rimMode: RimMode = .plain
    // Linear-light multipliers for the tinted rim / ink, capped by the screen's EDR headroom.
    private static let rimBoostLight: CGFloat = 1.6
    private static let rimBoostDark: CGFloat = 2.0
    private static let inkBoostDark: CGFloat = 1.6

    private(set) var source: WorkflowSource?
    private(set) var style: Style = .pill(fontSize: 13)
    private(set) var contentSize: NSSize = .zero

    private let fillLayer = CAShapeLayer()
    private let washLayer = CAGradientLayer()
    private let rimLayer = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let inkLayer = CAGradientLayer()
    private let inkMask = CALayer()
    private var maskImage: NSImage?

    override var intrinsicContentSize: NSSize { contentSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        washLayer.masksToBounds = true
        washLayer.cornerCurve = .circular
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 1
        rimLayer.mask = rimMask
        inkLayer.mask = inkMask
        for l in [fillLayer, washLayer, rimLayer, inkLayer] as [CALayer] {
            GlassHDR.enable(l)
            layer?.addSublayer(l)
        }
        if let root = layer { GlassHDR.enable(root) }
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ source: WorkflowSource?, style: Style) {
        self.source = source
        self.style = style
        toolTip = source?.longLabel
        isHidden = source == nil
        rebuildContent()
        updateColors()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    // MARK: Content

    private func rebuildContent() {
        guard let source else {
            maskImage = nil
            contentSize = .zero
            return
        }
        switch style {
        case .pill(let fontSize):
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let label = NSAttributedString(string: source.label, attributes: [.font: font, .foregroundColor: NSColor.black])
            let textSize = label.size()
            let symbol = Self.symbol(source, pointSize: fontSize * 0.9)
            let symbolSize = symbol?.size ?? .zero
            let padX = (fontSize * 0.7).rounded(), padY: CGFloat = 3, gap = (fontSize * 0.35).rounded()
            let size = NSSize(width: ceil(padX + symbolSize.width + gap + textSize.width + padX),
                              height: ceil(textSize.height) + 2 * padY)
            contentSize = size
            maskImage = NSImage(size: size, flipped: false) { rect in
                if let symbol {
                    Self.drawBlack(symbol, in: NSRect(x: padX, y: ((rect.height - symbolSize.height) / 2).rounded(),
                                                      width: symbolSize.width, height: symbolSize.height))
                }
                label.draw(at: NSPoint(x: padX + symbolSize.width + gap, y: ((rect.height - textSize.height) / 2).rounded()))
                return true
            }
        case .mark(let pointSize):
            guard let symbol = Self.symbol(source, pointSize: pointSize) else {
                maskImage = nil
                contentSize = .zero
                return
            }
            let size = NSSize(width: ceil(symbol.size.width), height: ceil(symbol.size.height))
            contentSize = size
            maskImage = NSImage(size: size, flipped: false) { rect in
                Self.drawBlack(symbol, in: rect)
                return true
            }
        }
    }

    private static func symbol(_ source: WorkflowSource, pointSize: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        return NSImage(systemSymbolName: source.symbol, accessibilityDescription: source.label)?
            .withSymbolConfiguration(config)
    }

    // Mask only needs alpha: paint the template symbol solid.
    nonisolated private static func drawBlack(_ symbol: NSImage, in rect: NSRect) {
        let solid = NSImage(size: rect.size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.black.setFill()
            r.fill(using: .sourceAtop)
            return true
        }
        solid.draw(in: rect)
    }

    // MARK: Colors

    private func updateColors() {
        guard let source else { return }
        let appearance = effectiveAppearance
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let screen = window?.screen ?? NSScreen.main
        let headroom = max(1, screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1)
        var tint = NSColor.systemGreen.cgColor
        var ink = NSColor.labelColor.cgColor
        appearance.performAsCurrentDrawingAppearance {
            tint = source.tint.cgColor
            ink = source.ink.cgColor
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let isPill: Bool
        if case .pill = style { isPill = true } else { isPill = false }
        fillLayer.isHidden = !isPill
        washLayer.isHidden = !isPill
        rimLayer.isHidden = !isPill || Self.rimMode == .none
        if isPill {
            fillLayer.fillColor = tint.copy(alpha: 0.16)
            let wash = GlassHDR.white(Self.washHDR, dark ? Self.washAlphaDark : Self.washAlphaLight)
            washLayer.colors = [wash, wash]   // uniform: brightness only
            let rim: CGColor
            switch Self.rimMode {
            case .hdr:
                rim = Self.boosted(tint, by: min(dark ? Self.rimBoostDark : Self.rimBoostLight, headroom),
                                   alpha: dark ? 0.8 : 0.7)
            case .plain, .none:
                rim = tint.copy(alpha: 0.4) ?? tint
            }
            rimLayer.colors = [rim, rim]
        }
        let inkColor = dark ? Self.boosted(ink, by: min(Self.inkBoostDark, headroom), alpha: 1) : ink
        inkLayer.colors = [inkColor, inkColor]
        CATransaction.commit()
    }

    // Scale linear RGB by boost; values above 1 only show on EDR displays.
    private static func boosted(_ color: CGColor, by boost: CGFloat, alpha: CGFloat) -> CGColor {
        guard boost > 1,
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let linear = color.converted(to: space, intent: .defaultIntent, options: nil),
              let c = linear.components, c.count >= 3,
              let out = CGColor(colorSpace: space, components: [c[0] * boost, c[1] * boost, c[2] * boost, alpha])
        else { return color.copy(alpha: alpha) ?? color }
        return out
    }

    // MARK: Layout / environment

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        let capsule = b.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: capsule, cornerWidth: capsule.height / 2, cornerHeight: capsule.height / 2,
                          transform: nil)
        fillLayer.frame = b
        fillLayer.path = path
        washLayer.frame = b
        washLayer.cornerRadius = b.height / 2
        rimLayer.frame = b
        rimMask.frame = b
        rimMask.path = path
        inkLayer.frame = b
        inkMask.frame = inkLayer.bounds
        updateMaskContents()
        CATransaction.commit()
    }

    private func updateMaskContents() {
        let scale = window?.backingScaleFactor ?? 2
        for l in [fillLayer, washLayer, rimLayer, rimMask, inkLayer, inkMask] as [CALayer] { l.contentsScale = scale }
        inkMask.contents = maskImage?.layerContents(forContentsScale: scale)
    }

    // Headroom differs per screen: refresh when the window moves to another display.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        if let window { center.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: window) }
        if let newWindow {
            center.addObserver(self, selector: #selector(screenDidChange), name: NSWindow.didChangeScreenNotification,
                               object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
        needsLayout = true
    }

    @objc private func screenDidChange(_ note: Notification) {
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateMaskContents()
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
    private let sourceView = WorkflowSourceBadgeView()   // third-party workflows only, left of the ⌘n badge

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
        var markSource: WorkflowSource?

        switch item {
        case .workflow(let workflow):
            subtitleLabel.stringValue = isRunning ? String(localized: "Running…", table: "Workflow") : Self.summary(workflow)
            keyLabel.stringValue = workflow.panelKey?.displayString ?? ""
            if workflow.source.isThirdParty { markSource = workflow.source }
        case .app:
            subtitleLabel.stringValue = String(localized: "Application", table: "Workflow")
            keyLabel.stringValue = ""
        case .calculator(let expression, _):
            subtitleLabel.stringValue = expression
            keyLabel.stringValue = ""
        }
        sourceView.configure(markSource, style: .mark(pointSize: max(13, font.pointSize)))
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
        return text.isEmpty ? String(localized: "Workflow", table: "Workflow") : text
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
        if sourceView.source != nil {
            let size = sourceView.contentSize
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
