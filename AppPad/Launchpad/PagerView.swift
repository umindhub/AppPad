import AppKit
import QuartzCore

// Horizontal pager driven by trackpad gestures.
// The strip follows the fingers 1:1; on release it snaps (velocity or distance) with a display-link spring.
final class PagerView: FlippedView {
    var onProgress: ((CGFloat) -> Void)?   // fractional page index, for the indicator

    private enum Axis { case horizontal, vertical }

    private let strip = FlippedView()
    private(set) var pages: [NSView] = []
    private(set) var currentPage = 0
    var pageCount: Int { content != nil ? contentPageCount : pages.count }

    // Single-view mode (folders): one wide view spanning all pages instead of one view per page.
    private var content: NSView?
    private var contentPageCount = 0

    private var offset: CGFloat = 0
    private var isTracking = false
    private var axis: Axis?
    private var trackStart: CGFloat = 0
    private var translation: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastEventTime: TimeInterval = 0
    private var lastWheelPageTime: TimeInterval = 0
    private var animationTarget: CGFloat?
    private var link: CADisplayLink?

    // Last swipe / momentum / snap frame of any pager. macOS eats a trackpad tap that stops a
    // scroll (no click is sent), so the launcher replays taps that land in this window.
    private static var lastActivity: TimeInterval = 0
    static var isScrollActive: Bool { ProcessInfo.processInfo.systemUptime - lastActivity < 0.5 }
    private static func markActivity() { lastActivity = ProcessInfo.processInfo.systemUptime }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(strip)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var pageWidth: CGFloat { max(1, bounds.width) }
    private var minOffset: CGFloat { -CGFloat(max(0, pageCount - 1)) * pageWidth }

    func setPages(_ newPages: [NSView]) {
        cancelAnimation()
        pages.forEach { $0.removeFromSuperview() }
        pages = newPages
        pages.forEach { strip.addSubview($0) }
        currentPage = min(currentPage, max(0, pages.count - 1))
        layoutPages()
        setOffset(-CGFloat(currentPage) * pageWidth)
    }

    // Single wide content view covering `count` pages (page p starts at x = p · width).
    func setContent(_ view: NSView, pageCount count: Int) {
        let count = max(1, count)
        guard content !== view || contentPageCount != count else { return }
        if content !== view {
            content?.removeFromSuperview()
            content = view
            strip.addSubview(view)
        }
        contentPageCount = count
        currentPage = min(currentPage, count - 1)
        layoutPages()
        if !isTracking && animationTarget == nil {
            cancelAnimation()
            setOffset(-CGFloat(currentPage) * pageWidth)
        }
    }

    // Add a page at the end without touching existing ones (used while dragging).
    func appendPage(_ page: NSView) {
        pages.append(page)
        strip.addSubview(page)
        layoutPages()
    }

    func scrollTo(page: Int, animated: Bool) {
        guard pageCount > 0 else {
            currentPage = 0
            setOffset(0)
            return
        }
        currentPage = min(max(0, page), pageCount - 1)
        let target = -CGFloat(currentPage) * pageWidth
        if animated && window != nil {
            startAnimation(to: target)
        } else {
            cancelAnimation()
            setOffset(target)
        }
    }

    // Stop any spring and settle on the current page.
    func cancelAnimation() {
        link?.invalidate()
        link = nil
        if animationTarget != nil {
            animationTarget = nil
            setOffset(-CGFloat(currentPage) * pageWidth)
        }
    }

    override func layout() {
        super.layout()
        layoutPages()
        if !isTracking && animationTarget == nil {
            setOffset(-CGFloat(currentPage) * pageWidth)
        }
    }

    private func layoutPages() {
        let width = pageWidth
        let height = bounds.height
        for (index, page) in pages.enumerated() {
            page.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
        }
        let total = width * CGFloat(max(1, pageCount))
        content?.frame = NSRect(x: 0, y: 0, width: total, height: height)
        strip.frame = NSRect(x: offset, y: 0, width: total, height: height)
    }

    private func setOffset(_ x: CGFloat) {
        offset = x
        strip.setFrameOrigin(NSPoint(x: x, y: 0))
        onProgress?(-x / pageWidth)
    }

    // MARK: - Gestures

    override func scrollWheel(with event: NSEvent) {
        Self.markActivity()   // momentum events included
        guard pageCount > 0 else { return }
        if !event.hasPreciseScrollingDeltas {
            handleMouseWheel(event)
            return
        }
        // Ignore inertia; we snap ourselves on release.
        if event.momentumPhase != [] { return }

        // Finger-space deltas regardless of the "natural scrolling" setting.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let dx = event.scrollingDeltaX * sign
        let dy = event.scrollingDeltaY * sign

        if event.phase.contains(.began) {
            cancelAnimationKeepingPosition()
            isTracking = true
            axis = nil
            trackStart = offset
            translation = 0
            velocity = 0
            lastEventTime = event.timestamp
        }

        if event.phase.contains(.began) || event.phase.contains(.changed) {
            guard isTracking else { return }
            if axis == nil {
                if abs(dx) > abs(dy) { axis = .horizontal } else if abs(dy) > abs(dx) { axis = .vertical }
            }
            let dt = max(event.timestamp - lastEventTime, 1.0 / 240.0)
            lastEventTime = event.timestamp
            switch axis {
            case .horizontal:
                translation += dx
                velocity = velocity * 0.5 + (dx / CGFloat(dt)) * 0.5
                setOffset(rubberBand(trackStart + translation))
            case .vertical:
                translation += dy
            case nil:
                break
            }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard isTracking else { return }
            isTracking = false
            finishGesture()
        }
    }

    private func finishGesture() {
        let width = pageWidth
        let startPage = Int((-trackStart / width).rounded())
        var target = startPage
        switch axis {
        case .horizontal:
            if abs(velocity) > 500 {
                target += velocity < 0 ? 1 : -1
            } else if translation < -width * 0.3 {
                target += 1
            } else if translation > width * 0.3 {
                target -= 1
            }
        case .vertical:
            if translation < -24 { target += 1 } else if translation > 24 { target -= 1 }
        case nil:
            break
        }
        axis = nil
        scrollTo(page: target, animated: true)
    }

    // Classic mouse wheel: one notch = one page.
    private func handleMouseWheel(_ event: NSEvent) {
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard delta != 0, event.timestamp - lastWheelPageTime > 0.3 else { return }
        lastWheelPageTime = event.timestamp
        scrollTo(page: currentPage + (delta < 0 ? 1 : -1), animated: true)
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        if x > 0 { return x * 0.3 }
        if x < minOffset { return minOffset + (x - minOffset) * 0.3 }
        return x
    }

    // MARK: - Spring animation

    private func startAnimation(to target: CGFloat) {
        animationTarget = target
        if link == nil {
            let newLink = displayLink(target: self, selector: #selector(step(_:)))
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
    }

    private func cancelAnimationKeepingPosition() {
        link?.invalidate()
        link = nil
        animationTarget = nil
    }

    @objc private func step(_ displayLink: CADisplayLink) {
        Self.markActivity()
        guard let target = animationTarget else {
            cancelAnimationKeepingPosition()
            return
        }
        let dt = min(max(displayLink.targetTimestamp - displayLink.timestamp, 1.0 / 240.0), 1.0 / 30.0)
        let factor = CGFloat(1 - exp(-20 * dt))
        let next = offset + (target - offset) * factor
        if abs(target - next) < 0.5 {
            setOffset(target)
            cancelAnimationKeepingPosition()
        } else {
            setOffset(next)
        }
    }
}
