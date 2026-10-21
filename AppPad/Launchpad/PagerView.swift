import AppKit
import QuartzCore

// Horizontal pager driven by trackpad gestures.
// The strip follows the fingers 1:1; on release it snaps (velocity or distance) with a display-link spring.
// Fast page swiping (setting): a short finger distance moves a whole page, so one swipe can cross several pages;
// vertical swipes then track the same way (up = next page). Off: vertical swipes jump one page, like macOS 15.
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
    private var fastSwipe = false   // captured per gesture
    // Indicator scrub in progress: fractional page that layout must keep (not snap to currentPage).
    private var scrubPage: CGFloat?

    // Fast mode: finger travel per page, flick projection time, max extra pages from a flick.
    private static let fastStep: CGFloat = 120
    private static let fastProjection: CGFloat = 0.08
    private static let fastMaxFlickPages: CGFloat = 3

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
    // Where the strip sits when idle: the scrubbed fraction, else the current page.
    private var restingPage: CGFloat { scrubPage ?? CGFloat(currentPage) }
    private var minOffset: CGFloat { -CGFloat(max(0, pageCount - 1)) * pageWidth }

    func setPages(_ newPages: [NSView]) {
        cancelAnimation()
        // Pages kept from the old list stay in the strip (no remove / re-add, no redraw).
        let kept = Set(newPages.map { ObjectIdentifier($0) })
        pages.filter { !kept.contains(ObjectIdentifier($0)) }.forEach { $0.removeFromSuperview() }
        pages = newPages
        pages.forEach { if $0.superview !== strip { strip.addSubview($0) } }
        scrubPage = nil
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
            setOffset(-restingPage * pageWidth)
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
        scrubPage = nil
        currentPage = min(max(0, page), pageCount - 1)
        let target = -CGFloat(currentPage) * pageWidth
        if animated && window != nil {
            startAnimation(to: target)
        } else {
            cancelAnimation()
            setOffset(target)
        }
    }

    // Indicator scrub: jump to a fractional page, no spring. Ignored during a trackpad swipe.
    // Stays fractional (layout keeps it) until scrollTo ends the scrub.
    func scrub(toPage page: CGFloat) {
        guard pageCount > 0, !isTracking else { return }
        cancelAnimationKeepingPosition()
        let clamped = min(max(page, 0), CGFloat(pageCount - 1))
        scrubPage = clamped
        currentPage = Int(clamped.rounded())
        setOffset(-clamped * pageWidth)
    }

    // Stop any spring and settle on the current page.
    func cancelAnimation() {
        link?.invalidate()
        link = nil
        if animationTarget != nil || scrubPage != nil {
            animationTarget = nil
            scrubPage = nil
            setOffset(-CGFloat(currentPage) * pageWidth)
        }
    }

    override func layout() {
        super.layout()
        layoutPages()
        if !isTracking && animationTarget == nil {
            setOffset(-restingPage * pageWidth)
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
            scrubPage = nil
            isTracking = true
            axis = nil
            fastSwipe = Preferences.shared.fastPageSwipe
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
                track(dx, dt: dt)
            case .vertical where fastSwipe:
                track(dy, dt: dt)
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

    // Strip follows the finger delta along the gesture axis.
    private func track(_ delta: CGFloat, dt: TimeInterval) {
        translation += delta
        velocity = velocity * 0.5 + (delta / CGFloat(dt)) * 0.5
        setOffset(trackedOffset())
    }

    // Finger gain: 1 normally, page width / fastStep in fast mode.
    private var gain: CGFloat { fastSwipe ? max(1, pageWidth / Self.fastStep) : 1 }

    // Strip offset for the current translation; edge resistance stays in finger space.
    private func trackedOffset() -> CGFloat {
        let g = gain
        let raw = trackStart + translation * g
        if raw > 0 { return raw / g * 0.3 }
        if raw < minOffset { return minOffset + (raw - minOffset) / g * 0.3 }
        return raw
    }

    private func finishGesture() {
        let width = pageWidth
        let startPage = Int((-trackStart / width).rounded())
        var target = startPage
        switch axis {
        case .horizontal where fastSwipe, .vertical where fastSwipe:
            target = fastTarget(startPage: startPage)
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

    // Fast mode release: current (unclamped) position plus a short flick projection,
    // committing to the next page once 30% of it is crossed in the swipe direction.
    private func fastTarget(startPage: Int) -> Int {
        let position = -(trackStart + translation * gain) / pageWidth
        let flick = abs(velocity) > 500
        var extra = -velocity * Self.fastProjection / Self.fastStep
        extra = min(max(extra, -Self.fastMaxFlickPages), Self.fastMaxFlickPages)
        let projected = position + (flick ? extra : 0)
        let forward = flick ? velocity < 0 : translation < 0
        var target = forward ? Int(floor(projected + 0.7)) : Int(ceil(projected - 0.7))
        // A flick always moves at least one page its way.
        if flick { target = forward ? max(target, startPage + 1) : min(target, startPage - 1) }
        return target
    }

    // Classic mouse wheel: one notch = one page.
    private func handleMouseWheel(_ event: NSEvent) {
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard delta != 0, event.timestamp - lastWheelPageTime > 0.3 else { return }
        lastWheelPageTime = event.timestamp
        scrollTo(page: currentPage + (delta < 0 ? 1 : -1), animated: true)
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
