import AppKit

// Page dots or numbers; brightness follows the fractional page while swiping.
// glass = true → GlassDotIndicatorView (Liquid Glass track + circular lens); false → plain drawing.
final class PageIndicatorView: FlippedView {
    var style: PageIndicatorStyle = .dots {
        didSet { if oldValue != style { needsDisplay = true; syncGlass() } }
    }
    var pageCount = 0 {
        didSet { if oldValue != pageCount { needsDisplay = true; syncGlass() } }
    }
    var progress: CGFloat = 0 {
        didSet {
            guard oldValue != progress else { return }
            if let glassView { glassView.setProgress(progress) } else { needsDisplay = true }
        }
    }
    var glass = false {
        didSet { if oldValue != glass { applyGlass() } }
    }
    var onSelect: ((Int) -> Void)?

    private var glassView: GlassDotIndicatorView?

    // MARK: - Glass mode

    private func applyGlass() {
        if glass {
            let view = GlassDotIndicatorView(frame: bounds)
            view.onSelect = { [weak self] index in self?.onSelect?(index) }
            addSubview(view)
            glassView = view
            syncGlass()
        } else {
            glassView?.removeFromSuperview()
            glassView = nil
        }
        needsDisplay = true
    }

    private func syncGlass() {
        guard let glassView else { return }
        glassView.configure(content: style == .dots ? .dots : .numbers, pageCount: pageCount)
        glassView.setProgress(progress)
    }

    override func layout() {
        super.layout()
        glassView?.frame = bounds
    }

    // Only the dots row takes clicks; the rest falls through to the background.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let glassView {
            return glassView.hitRect.contains(local) ? glassView : nil
        }
        let rects = itemRects()
        guard let first = rects.first, let last = rects.last,
              local.x >= first.minX - 16, local.x <= last.maxX + 16 else { return nil }
        return self
    }

    // MARK: - Plain mode

    private func itemRects() -> [NSRect] {
        guard pageCount > 0 else { return [] }
        let size: CGFloat = style == .dots ? 7 : 18
        let spacing: CGFloat = style == .dots ? 9 : 4
        let total = CGFloat(pageCount) * size + CGFloat(pageCount - 1) * spacing
        let y = (bounds.height - size) / 2
        var x = (bounds.width - total) / 2
        var rects: [NSRect] = []
        for _ in 0..<pageCount {
            rects.append(NSRect(x: x, y: y, width: size, height: size))
            x += size + spacing
        }
        return rects
    }

    private func alpha(for index: Int) -> CGFloat {
        0.28 + 0.72 * max(0, 1 - abs(CGFloat(index) - progress))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard glassView == nil else { return }
        for (index, rect) in itemRects().enumerated() {
            let color = NSColor.labelColor.withAlphaComponent(alpha(for: index))
            switch style {
            case .dots:
                color.setFill()
                NSBezierPath(ovalIn: rect).fill()
            case .numbers:
                let text = "\(index + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: color,
                ]
                let size = text.size(withAttributes: attrs)
                text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
            }
        }
    }

    // MARK: - Tap & scrub (plain mode)

    private var isScrubbing = false
    private var lastScrubIndex: Int?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let rects = itemRects()
        guard let first = rects.first, let last = rects.last else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Generous hit band around the whole row.
        guard point.x >= first.minX - 16, point.x <= last.maxX + 16 else { return }
        isScrubbing = true
        lastScrubIndex = nil
        select(atX: point.x)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isScrubbing else { return }
        select(atX: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        isScrubbing = false
        lastScrubIndex = nil
    }

    // Nearest page to x (clamped), fired only when it changes.
    private func select(atX x: CGFloat) {
        let rects = itemRects()
        guard !rects.isEmpty else { return }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, rect) in rects.enumerated() {
            let distance = abs(rect.midX - x)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        guard best != lastScrubIndex else { return }
        lastScrubIndex = best
        onSelect?(best)
    }
}
