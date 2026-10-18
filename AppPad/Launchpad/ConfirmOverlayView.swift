import AppKit

// In-panel dialog (no separate window, so the non-activating panel keeps focus).
// Same look as an open folder: blurred + dimmed pages outside, folder sheet material behind the box.
// Click outside the box cancels. Fades in / out like a folder (blur grows / clears gradually).
// Optional checklist for leftover files. Enter = confirm, Esc = cancel (routed by the view controller).
final class ConfirmOverlayView: FlippedView {
    nonisolated struct CheckItem: Sendable {
        let url: URL
        let checked: Bool
        var locked = false        // always on, cannot be unchecked (the app bundle itself)
    }

    var onConfirm: (([URL]) -> Void)?
    var onCancel: (() -> Void)?

    private let outsideBlur = NSVisualEffectView()
    private let outsideDim = NSView()
    private let backdrop = FolderBackdropView()
    private let box = FolderBoxView()
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let messageLabel: NSTextField
    private let scrollView = VerticalOnlyScrollView()
    private let listView = FlippedView()
    private var checkboxes: [(NSButton, URL)] = []
    // Locked rows: the disabled checkbox has no title (it would be gray); this label keeps label color.
    private var lockedLabels: [Int: NSTextField] = [:]
    private let confirmButton: PillButton
    private let cancelButton: PillButton
    private let showsCancel: Bool
    private var pressedOutside = false
    private(set) var progress: CGFloat = 0     // 0 = hidden, 1 = fully shown
    private(set) var isClosing = false

    private static let rowHeight: CGFloat = 22
    private static let boxWidth: CGFloat = 460
    private static let maxListHeight: CGFloat = 200

    // Where a checkbox draws its title (measured once from a sample checkbox).
    private static let checkboxTitleInset: CGFloat = {
        let sample = NSButton(checkboxWithTitle: "x", target: nil, action: nil)
        sample.font = .systemFont(ofSize: 11)
        let bounds = NSRect(x: 0, y: 0, width: 200, height: rowHeight)
        return (sample.cell?.titleRect(forBounds: bounds).minX ?? 20).rounded()
    }()

    init(icon: NSImage?, title: String, message: String, items: [CheckItem],
         confirmTitle: String, destructive: Bool, showsCancel: Bool = true, cornerRadius: CGFloat) {
        titleLabel = NSTextField(labelWithString: title)
        messageLabel = NSTextField(wrappingLabelWithString: message)
        confirmButton = PillButton(title: confirmTitle, style: destructive ? .destructive : .primary)
        cancelButton = PillButton(title: String(localized: "Cancel"), style: .secondary)
        self.showsCancel = showsCancel
        super.init(frame: .zero)

        // Backdrop: same materials as FolderOverlayView.
        outsideBlur.material = .fullScreenUI
        outsideBlur.blendingMode = .withinWindow
        outsideBlur.state = .active
        outsideDim.wantsLayer = true
        outsideDim.autoresizingMask = [.width, .height]
        outsideBlur.addSubview(outsideDim)
        addSubview(outsideBlur)
        addSubview(backdrop)
        applyContrastColors()

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor

        confirmButton.target = self
        confirmButton.action = #selector(confirm)
        confirmButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.isHidden = !showsCancel

        addSubview(box)
        [iconView, titleLabel, messageLabel, confirmButton, cancelButton].forEach { box.addSubview($0) }

        if !items.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            for item in items {
                let display = item.url.path.replacingOccurrences(of: home, with: "~")
                let checkbox = NSButton(checkboxWithTitle: item.locked ? "" : display, target: nil, action: nil)
                checkbox.state = (item.checked || item.locked) ? .on : .off
                checkbox.isEnabled = !item.locked
                checkbox.font = .systemFont(ofSize: 11)
                checkbox.lineBreakMode = .byTruncatingMiddle
                checkbox.toolTip = item.url.path
                listView.addSubview(checkbox)
                if item.locked {
                    let label = NSTextField(labelWithString: display)
                    label.font = .systemFont(ofSize: 11)
                    label.textColor = .labelColor
                    label.lineBreakMode = .byTruncatingMiddle
                    label.toolTip = item.url.path
                    listView.addSubview(label)
                    lockedLabels[checkboxes.count] = label
                }
                checkboxes.append((checkbox, item.url))
            }
            scrollView.documentView = listView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.horizontalScrollElasticity = .none
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            box.addSubview(scrollView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Fade (same timings as the folder: open 0.46 s spring, close 0.32 s ease-in-out)

    private static let openDuration: Double = 0.46
    private static let closeDuration: Double = 0.32

    // from: start progress (taken over from a dialog that is still fading out).
    func animateIn(from start: CGFloat = 0) {
        isClosing = false
        progress = start
        applyProgress()
        animate(to: 1, duration: Self.openDuration, curve: Self.springOut, completion: nil)
    }

    // Ignores clicks while fading; removes itself at the end.
    func animateOut(completion: (() -> Void)? = nil) {
        isClosing = true
        animate(to: 0, duration: Self.closeDuration, curve: Self.easeInOut) { [weak self] in
            self?.removeFromSuperview()
            completion?()
        }
    }

    // Stop any fade and leave immediately.
    func removeNow() {
        stopTimeline()
        removeFromSuperview()
    }

    private func applyProgress() {
        let p = min(1, max(0, progress))
        outsideBlur.alphaValue = p
        backdrop.alphaValue = p
        box.alphaValue = p
    }

    // MARK: - Timeline

    private var link: CADisplayLink?
    private var timelineStart: CFTimeInterval = 0
    private var timelineDuration: Double = 0
    private var timelineFrom: CGFloat = 0
    private var timelineTo: CGFloat = 0
    private var timelineCurve: (Double) -> Double = { $0 }
    private var timelineDone: (() -> Void)?

    // Duration scales with the remaining distance, so a reversal mid-fade keeps the same speed.
    private func animate(to target: CGFloat, duration: Double, curve: @escaping (Double) -> Double,
                         completion: (() -> Void)?) {
        stopTimeline()
        let distance = abs(target - progress)
        guard distance > 0.001, window != nil else {
            progress = target
            applyProgress()
            completion?()
            return
        }
        timelineStart = CACurrentMediaTime()
        timelineDuration = max(0.12, duration * Double(distance))
        timelineFrom = progress
        timelineTo = target
        timelineCurve = curve
        timelineDone = completion
        let newLink = displayLink(target: self, selector: #selector(tick(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        let t = min(1, (CACurrentMediaTime() - timelineStart) / timelineDuration)
        let eased = CGFloat(t >= 1 ? 1 : timelineCurve(t))
        progress = timelineFrom + (timelineTo - timelineFrom) * eased
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyProgress()
        CATransaction.commit()
        guard t >= 1 else { return }
        let done = timelineDone
        stopTimeline()
        done?()
    }

    private func stopTimeline() {
        link?.invalidate()
        link = nil
        timelineDone = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopTimeline() }
    }

    // Critically damped spring, normalised to reach 1 at t = 1 (same as the folder).
    nonisolated private static func springOut(_ t: Double) -> Double {
        let omega = 9.0
        let value = 1 - (1 + omega * t) * exp(-omega * t)
        let end = 1 - (1 + omega) * exp(-omega)
        return value / end
    }

    nonisolated private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // Fading out: clicks fall through to the pages.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isClosing ? nil : super.hitTest(point)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyContrastColors()
    }

    // Same dim as an open folder's outside area.
    private func applyContrastColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        outsideDim.layer?.backgroundColor = NSColor.black.withAlphaComponent(dark ? 0.28 : 0.14).cgColor
    }

    override func layout() {
        super.layout()
        outsideBlur.frame = bounds
        outsideDim.frame = outsideBlur.bounds

        // Fixed width (never follows path length).
        let width = min(Self.boxWidth, bounds.width - 40).rounded()
        let fullListHeight = CGFloat(checkboxes.count) * Self.rowHeight + 8
        let listHeight = checkboxes.isEmpty ? 0 : min(fullListHeight, Self.maxListHeight)
        let messageHeight = messageLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 40, height: 400)).height ?? 32
        let height = 20 + 56 + 10 + 22 + 6 + messageHeight + (listHeight > 0 ? listHeight + 12 : 0) + 20 + 28 + 20
        let boxFrame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(),
                              width: width, height: height.rounded())
        box.frame = boxFrame
        backdrop.frame = boxFrame

        var y: CGFloat = 20
        iconView.frame = NSRect(x: (width - 56) / 2, y: y, width: 56, height: 56)
        y += 56 + 10
        titleLabel.frame = NSRect(x: 20, y: y, width: width - 40, height: 22)
        y += 22 + 6
        messageLabel.frame = NSRect(x: 20, y: y, width: width - 40, height: messageHeight)
        y += messageHeight
        if listHeight > 0 {
            y += 12
            scrollView.frame = NSRect(x: 20, y: y, width: width - 40, height: listHeight)
            // No bounce when everything fits.
            scrollView.verticalScrollElasticity = fullListHeight > listHeight ? .automatic : .none
            let contentWidth = scrollView.contentSize.width
            listView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: fullListHeight)
            let titleX = Self.checkboxTitleInset
            for (index, (checkbox, _)) in checkboxes.enumerated() {
                let rowY = 4 + CGFloat(index) * Self.rowHeight
                checkbox.frame = NSRect(x: 4, y: rowY, width: contentWidth - 8, height: Self.rowHeight)
                if let label = lockedLabels[index] {
                    // Same text position as a titled checkbox.
                    let labelHeight = label.intrinsicContentSize.height
                    label.frame = NSRect(x: 4 + titleX, y: (rowY + (Self.rowHeight - labelHeight) / 2).rounded(),
                                         width: contentWidth - 8 - titleX, height: labelHeight)
                }
            }
            y += listHeight
        }
        y += 20
        let buttonWidth: CGFloat = 120
        if showsCancel {
            cancelButton.frame = NSRect(x: width / 2 - buttonWidth - 6, y: y, width: buttonWidth, height: 28)
            confirmButton.frame = NSRect(x: width / 2 + 6, y: y, width: buttonWidth, height: 28)
        } else {
            confirmButton.frame = NSRect(x: (width - buttonWidth) / 2, y: y, width: buttonWidth, height: 28)
        }
    }

    // Click outside the box = cancel (on mouseUp, so the release never reaches the grid).
    override func mouseDown(with event: NSEvent) {
        pressedOutside = !box.frame.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedOutside = false }
        guard pressedOutside, !box.frame.contains(convert(event.locationInWindow, from: nil)) else { return }
        cancel()
    }

    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    @objc func confirm() {
        guard !isClosing else { return }
        let urls = checkboxes.filter { $0.0.state == .on }.map(\.1)
        onConfirm?(urls)
    }

    @objc func cancel() {
        guard !isClosing else { return }
        onCancel?()
    }
}

// Capsule button with its own fill (same shape on every macOS version).
final class PillButton: NSButton {
    enum Style { case primary, destructive, secondary }

    private let style: Style

    init(title: String, style: Style) {
        self.style = style
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = true
        (cell as? NSButtonCell)?.highlightsBy = []   // pressed state is drawn by updateFill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: style == .secondary ? NSColor.labelColor : NSColor.white,
            .paragraphStyle: paragraph,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { updateFill() }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        updateFill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        let base: NSColor = switch style {
        case .primary: .controlAccentColor
        case .destructive: .systemRed
        case .secondary: .labelColor.withAlphaComponent(0.12)
        }
        let color = isHighlighted ? base.withSystemEffect(.pressed) : base
        // Resolve dynamic colors for this view's appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }
}

// Vertical scrolling only: horizontal swipes are swallowed (no sideways drift / bounce).
final class VerticalOnlyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { return }
        super.scrollWheel(with: event)
    }
}
