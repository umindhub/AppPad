import AppKit
import CoreText
import QuartzCore

// MARK: - GlassDotIndicatorView
//
// Liquid Glass page indicator — port of YouMindHub GlassSegmentedNSView, with a CIRCULAR lens.
//
//   trackGlass : NSGlassEffectView capsule around the dots (off: showsTrack = false)
//   overlay    : (bottom → top)
//     glowFill    pressed: one uniform HDR wash over track ∪ lens
//     outerShadow lifted: soft shadow outside the lens
//     restFill    rest: faint circle around the current dot
//     dotsLayer   dots / numbers; hole punched under the lifted lens
//     refraction  Metal lens: dots re-sampled 1:1, bent rim, RGB fringe, bevel, bar edge light
//     edges       lifted: rim hairline + HDR sheen + cyan / pink fringe
//
// Motion (own display link + springs):
//   • pos  — lens position in page units. Follows the pager progress 1:1 (trackpad swipe,
//            keys, clicks) while not pressed.
//   • lift — 0 rest … 1 lifted (lens grows, glass edges fade in).
//   • glow — 0 rest … 1 pressed (HDR wash + whole control scale).
//
// Mouse: down → page switches at once, lens springs there and lifts;
//        drag → lens catches up with the pointer then tracks 1:1, and the page switches
//               IMMEDIATELY whenever the pointer crosses into another dot (not on release);
//        up   → lens settles on the current page and drops.
// The lens stays a circle at all times (no squash & stretch).

final class GlassDotIndicatorView: FlippedView {

    enum Content: Equatable { case dots, numbers }

    var onSelect: ((Int) -> Void)?

    // MARK: Tuning

    private static let inset: CGFloat = 2              // track padding around the slots
    private static let dotSize: CGFloat = 7
    private static let lensDotSize: CGFloat = 8         // dot seen through the lifted lens
    private static let dotPitch: CGFloat = 16           // slot = rest lens diameter
    private static let numberPitch: CGFloat = 22
    private static let restDotAlpha: CGFloat = 0.28
    private static let hitPadding: CGFloat = 16
    private static let showsTrack = false               // no glass pill behind the dots

    private static let liftScale: CGFloat = 1.7         // lifted lens diameter vs rest
    private static let pressScale: CGFloat = 1.05       // whole control while pressed
    private static let rimRefraction: CGFloat = 0.25    // keep < 0.44 (fold-free)
    private static let bezelRatio: CGFloat = 0.35
    private static let dispersion: CGFloat = 0.16
    private static let shadeLight: CGFloat = 0.14
    private static let shadeDark: CGFloat = 0.40
    private static let shadeRatio: CGFloat = 0.16
    private static let barLightLight: CGFloat = 0.70
    private static let barLightDark: CGFloat = 0.16
    private static let barShadeLight: CGFloat = 0.10
    private static let barShadeDark: CGFloat = 0.30
    private static let barRefraction: CGFloat = 0.40
    private static let weightFadeStart: CGFloat = 0.5

    private static let pillAlphaLight: CGFloat = 0.085
    private static let pillAlphaDark: CGFloat = 0.14
    private static let shadowRadius: CGFloat = 5
    private static let shadowAlphaLight: Float = 0.14
    private static let shadowAlphaDark: Float = 0.35
    private static let glowHDR: CGFloat = 1.5
    private static let glowAlphaLight: CGFloat = 0.26
    private static let glowAlphaDark: CGFloat = 0.14
    private static let rimWidth: CGFloat = 0.8
    private static let sheenWidth: CGFloat = 1.0
    private static let sheenInset: CGFloat = 1.3
    private static let fringeWidth: CGFloat = 0.8
    private static let fringeShift: CGFloat = 0.6
    private static let sheenHDR: CGFloat = 1.3
    private static let sheenAlphaLight: CGFloat = 0.85
    private static let sheenAlphaDark: CGFloat = 0.30

    private static let dragThreshold: CGFloat = 2
    private static let lockDistance: CGFloat = 0.02
    private static let velocityDecay: CGFloat = 10

    private static let travelSpring = (duration: 0.32, bounce: 0.25)
    private static let followSpring = (duration: 0.14, bounce: 0.0)
    private static let liftSpring = (duration: 0.24, bounce: 0.22)
    private static let releaseSpring = (duration: 0.7, bounce: 0.15)
    private static let releaseLiftSpring = (duration: 0.7, bounce: 0.0)
    private static let glowOnSpring = (duration: 0.18, bounce: 0.0)
    private static let glowOffSpring = (duration: 0.7, bounce: 0.0)

    // MARK: State

    private var content: Content = .dots
    private var pageCount = 0
    private var progress: CGFloat = 0
    private var isDark = false
    private var tintCG: CGColor = NSColor.labelColor.cgColor

    private let trackGlass = NSGlassEffectView()
    private let overlay = FlippedView()
    private let glowFill = CAGradientLayer()
    private let glowMask = CAShapeLayer()
    private let outerShadow = CALayer()
    private let outerMask = CAShapeLayer()
    private let restFill = CALayer()
    private let dotsLayer = CALayer()
    private let dotsMask = CAShapeLayer()
    private let refraction = LensRefraction.make()
    private let edges = CALayer()
    private let rim = CAShapeLayer()
    private let sheen = CAGradientLayer()
    private let sheenMask = CAShapeLayer()
    private let cyan = CAShapeLayer()
    private let pink = CAShapeLayer()
    private var baseSlots: [CALayer] = []
    private var accentSlots: [CALayer] = []
    private var labels: [GlassLabelSet] = []
    private var labelRevision = 0

    private var pos = GlassSpring()
    private var lift = GlassSpring()
    private var glow = GlassSpring()
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    private var isPressed = false
    private var isSettling = false      // release spring still owns the lens
    private var isTracking = false
    private var isCatchingUp = false
    private var downX: CGFloat = 0
    private var lastDragTime: TimeInterval = 0
    private var lastEmitted = 0

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = false          // lifted lens overhangs the track

        trackGlass.style = .regular
        addSubview(trackGlass)

        overlay.wantsLayer = true
        overlay.clipsToBounds = false
        addSubview(overlay)

        if let root = overlay.layer {
            root.masksToBounds = false
            root.addSublayer(glowFill)
            root.addSublayer(outerShadow)
            root.addSublayer(restFill)
            root.addSublayer(dotsLayer)
            if let refraction { root.addSublayer(refraction.layer) }
            root.addSublayer(edges)
        }

        glowFill.mask = glowMask
        glowFill.opacity = 0
        glowFill.isHidden = true

        outerShadow.shadowColor = NSColor.black.cgColor
        outerShadow.shadowOffset = .zero
        outerShadow.shadowRadius = Self.shadowRadius
        outerShadow.shadowOpacity = 0
        outerShadow.mask = outerMask
        outerMask.fillRule = .evenOdd

        dotsMask.fillRule = .evenOdd

        edges.opacity = 0
        edges.addSublayer(sheen)
        for l in [pink, cyan, rim] {
            l.fillColor = nil
            edges.addSublayer(l)
        }
        rim.lineWidth = Self.rimWidth
        cyan.lineWidth = Self.fringeWidth
        pink.lineWidth = Self.fringeWidth
        sheen.mask = sheenMask
        sheenMask.fillColor = nil
        sheenMask.strokeColor = NSColor.black.cgColor
        sheenMask.lineWidth = Self.sheenWidth

        for l in [glowFill, edges, sheen] as [CALayer] { GlassHDR.enable(l) }

        pos.configure(Self.travelSpring)
        lift.configure(Self.liftSpring)
        glow.configure(Self.glowOnSpring)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public API

    func configure(content newContent: Content, pageCount newCount: Int) {
        guard newContent != content || newCount != pageCount else { return }
        content = newContent
        pageCount = max(0, newCount)
        if !ownsLens { pos.snap(progress) }
        renderLabels()
        needsLayout = true
    }

    // Fractional page from the pager; ignored while the pointer / release owns the lens.
    func setProgress(_ value: CGFloat) {
        progress = value
        guard !ownsLens else { return }
        pos.snap(value)
        applyFrame()
    }

    // Area that takes clicks (track plus a margin), view coordinates.
    var hitRect: CGRect {
        guard pageCount > 0 else { return .zero }
        return trackRect.insetBy(dx: -Self.hitPadding, dy: -4)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let track = trackRect
        trackGlass.frame = track
        trackGlass.cornerRadius = track.height / 2
        trackGlass.isHidden = !Self.showsTrack || pageCount == 0
        overlay.frame = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [dotsLayer, edges, outerShadow] as [CALayer] { l.frame = overlay.bounds }
        dotsMask.frame = overlay.bounds
        outerMask.frame = overlay.bounds
        placeLabels()
        CATransaction.commit()
        syncRefraction()
        applyFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderLabels()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderLabels()   // dynamic colors resolve per appearance
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimating() } else { renderLabels() }
    }

    // MARK: Geometry

    private var pitch: CGFloat { content == .dots ? Self.dotPitch : Self.numberPitch }
    private var maxIndex: CGFloat { CGFloat(max(pageCount - 1, 0)) }
    private var ownsLens: Bool { isPressed || isSettling }
    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    // Capsule around all slots, centered in the view (pixel-rounded).
    private var trackRect: CGRect {
        guard pageCount > 0 else { return .zero }
        let w = CGFloat(pageCount) * pitch + Self.inset * 2
        let h = pitch + Self.inset * 2
        return CGRect(x: ((bounds.width - w) / 2).rounded(), y: ((bounds.height - h) / 2).rounded(),
                      width: w, height: h)
    }

    private func slotRect(_ i: Int, in track: CGRect) -> CGRect {
        CGRect(x: track.minX + Self.inset + pitch * CGFloat(i), y: track.midY - pitch / 2,
               width: pitch, height: pitch)
    }

    private func index(at x: CGFloat) -> Int {
        guard pageCount > 0 else { return 0 }
        let raw = Int(((x - trackRect.minX - Self.inset) / pitch).rounded(.down))
        return min(max(raw, 0), pageCount - 1)
    }

    private func clampedPage(_ v: CGFloat) -> CGFloat { min(max(v, 0), maxIndex) }

    // MARK: Frame

    private func applyFrame() {
        guard pageCount > 0, bounds.width > 0 else { return }
        let track = trackRect
        let slot = pitch
        let p = lift.value                                   // may overshoot (bounce)
        let pc = glassClamp01(p)
        let g = glassClamp01(glow.value)
        let d = max(1, slot * (1 + (Self.liftScale - 1) * p))
        let settled = clampedPage(pos.value)
        // Lens center stays between the first / last dot → concentric with the track ends.
        let cx = track.minX + Self.inset + slot * (settled + 0.5)
        let lens = CGRect(x: cx - d / 2, y: track.midY - d / 2, width: d, height: d)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        applyPressScale(g)
        updateGlow(track: track, lens: lens, glow: g)
        updateBody(lens: lens, lift: pc)

        var activeness: [CGFloat] = []
        for i in 0..<accentSlots.count {
            let t = max(0, 1 - abs(settled - CGFloat(i)))
            activeness.append(t)
            accentSlots[i].opacity = Float(t)
        }

        // Lifted: hole in the dots + dots seen THROUGH the lens (Metal).
        if pc > 0.001, let refraction, pageCount <= LensRefraction.maxSlots {
            let holed = CGMutablePath()
            holed.addRect(bounds.insetBy(dx: -200, dy: -200))
            holed.addPath(glassCapsulePath(lens))
            dotsMask.path = holed
            dotsLayer.mask = dotsMask

            let half = d / 2
            let bezel = half * Self.bezelRatio
            refraction.layer.isHidden = false
            refraction.render(.init(
                lens: lens,
                rimRefraction: bezel * Self.rimRefraction * pc,
                bezel: bezel,
                dispersion: Self.dispersion,
                slotOrigin: track.minX + Self.inset,
                slotWidth: slot,
                activeness: activeness,
                weight: glassSmoothstep(Self.weightFadeStart, 1, pc),
                backdrop: isDark ? 0.22 : 0.98,
                shade: (isDark ? Self.shadeDark : Self.shadeLight) * pc,
                shadeWidth: half * Self.shadeRatio,
                track: Self.showsTrack ? track : .zero,   // no bar edge light without the pill
                barLight: (isDark ? Self.barLightDark : Self.barLightLight) * pc,
                barShade: (isDark ? Self.barShadeDark : Self.barShadeLight) * pc,
                barWarp: bezel * Self.barRefraction * pc))
        } else {
            dotsLayer.mask = nil
            refraction?.layer.isHidden = true
        }

        updateEdges(lens: lens, lift: pc)
        CATransaction.commit()
    }

    // Whole control scales about the view center while pressed.
    private func applyPressScale(_ g: CGFloat) {
        guard let root = layer, bounds.width > 0 else { return }
        let s = 1 + (Self.pressScale - 1) * g
        let a = root.anchorPoint
        let dx = bounds.width * (0.5 - a.x), dy = bounds.height * (0.5 - a.y)
        var t = CATransform3DMakeTranslation(dx, dy, 0)
        t = CATransform3DScale(t, s, s, 1)
        t = CATransform3DTranslate(t, -dx, -dy, 0)
        root.sublayerTransform = t
    }

    // Uniform HDR wash over track ∪ lens (overlap not doubled).
    private func updateGlow(track: CGRect, lens: CGRect, glow g: CGFloat) {
        glowFill.opacity = Float(g)
        glowFill.isHidden = g <= 0.001
        guard !glowFill.isHidden else { return }
        let area = Self.showsTrack ? track.union(lens) : lens
        glowFill.frame = area
        glowMask.frame = CGRect(origin: .zero, size: area.size)
        let dx = -area.minX, dy = -area.minY
        let lensPath = glassCapsulePath(lens.offsetBy(dx: dx, dy: dy))
        glowMask.path = Self.showsTrack
            ? glassCapsulePath(track.offsetBy(dx: dx, dy: dy)).union(lensPath)
            : lensPath
    }

    // Rest circle fades out with lift; outer shadow fades in.
    private func updateBody(lens: CGRect, lift p: CGFloat) {
        restFill.frame = lens
        restFill.cornerRadius = lens.height / 2
        restFill.opacity = Float(1 - p)

        let alpha = (isDark ? Self.shadowAlphaDark : Self.shadowAlphaLight) * Float(p)
        outerShadow.shadowOpacity = alpha
        outerShadow.isHidden = alpha <= 0.001
        guard !outerShadow.isHidden else { return }
        let lensPath = glassCapsulePath(lens)
        let pad = Self.shadowRadius * 3
        outerShadow.shadowPath = lensPath
        let ring = CGMutablePath()
        ring.addRect(lens.insetBy(dx: -pad, dy: -pad))
        ring.addPath(lensPath)
        outerMask.path = ring
    }

    // Concentric rim / sheen / fringe → identical all the way round.
    private func updateEdges(lens: CGRect, lift p: CGFloat) {
        edges.opacity = Float(p)
        guard p > 0.001 else { return }
        for l in [rim, sheen, cyan, pink] as [CALayer] { l.frame = lens }
        let b = CGRect(origin: .zero, size: lens.size)
        sheenMask.frame = b
        rim.path = glassCapsulePath(b.insetBy(dx: Self.rimWidth / 2, dy: Self.rimWidth / 2))
        let si = Self.sheenInset + Self.sheenWidth / 2
        sheenMask.path = glassCapsulePath(b.insetBy(dx: si, dy: si))
        let c = Self.rimWidth / 2 - Self.fringeShift
        cyan.path = glassCapsulePath(b.insetBy(dx: c, dy: c))
        let k = Self.rimWidth / 2 + Self.fringeShift
        pink.path = glassCapsulePath(b.insetBy(dx: k, dy: k))
    }

    // MARK: Colors & labels

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let wash = GlassHDR.white(Self.glowHDR, isDark ? Self.glowAlphaDark : Self.glowAlphaLight)
        glowFill.colors = [wash, wash]
        restFill.backgroundColor = tintCG.copy(alpha: isDark ? Self.pillAlphaDark : Self.pillAlphaLight) ?? tintCG
        rim.strokeColor = isDark ? NSColor.white.withAlphaComponent(0.28).cgColor
                                 : NSColor.black.withAlphaComponent(0.10).cgColor
        let w = GlassHDR.white(Self.sheenHDR, isDark ? Self.sheenAlphaDark : Self.sheenAlphaLight)
        sheen.colors = [w, w]
        let k: CGFloat = isDark ? 0.8 : 1
        cyan.strokeColor = NSColor(red: 0.30, green: 0.90, blue: 1.00, alpha: 0.40 * k).cgColor
        pink.strokeColor = NSColor(red: 1.00, green: 0.35, blue: 0.75, alpha: 0.32 * k).cgColor
        CATransaction.commit()
    }

    private func renderLabels() {
        let scale = backingScale
        isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Resolve dynamic colors against THIS view's appearance.
        var tint = NSColor.labelColor.cgColor
        var baseColor = tint
        var accentColor = tint
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let label = NSColor.labelColor
            tint = label.cgColor
            baseColor = label.withAlphaComponent(Self.restDotAlpha).cgColor
            accentColor = label.withAlphaComponent(1).cgColor
        }
        tintCG = tint

        var made: [GlassLabelSet] = []
        for i in 0..<pageCount {
            guard let b = makeLabel(i, color: baseColor, lens: false, scale: scale),
                  let a = makeLabel(i, color: accentColor, lens: false, scale: scale),
                  let lb = makeLabel(i, color: baseColor, lens: true, scale: scale),
                  let la = makeLabel(i, color: accentColor, lens: true, scale: scale) else { continue }
            made.append(GlassLabelSet(base: b, accent: a, lensBase: lb, lensAccent: la))
        }
        labels = made
        labelRevision &+= 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncSlotLayers(count: made.count)
        for (i, set) in made.enumerated() {
            setContents(baseSlots[i], set.base, scale: scale)
            setContents(accentSlots[i], set.accent, scale: scale)
        }
        for l in [glowFill, outerShadow, restFill, rim, sheen, sheenMask, cyan, pink, glowMask, dotsMask, outerMask] as [CALayer] {
            l.contentsScale = scale
        }
        placeLabels()
        CATransaction.commit()

        applyColors()
        syncRefraction()
        applyFrame()
    }

    // Dot or page number; lens copy is one step heavier.
    private func makeLabel(_ i: Int, color: CGColor, lens: Bool, scale: CGFloat) -> GlassLabelImage? {
        switch content {
        case .dots:
            let d = lens ? Self.lensDotSize : Self.dotSize
            return GlassLabelImage.render(size: CGSize(width: d, height: d), scale: scale) { ctx in
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
            }
        case .numbers:
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: lens ? .bold : .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(i + 1)", attributes: attrs))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let size = CGSize(width: ceil(width), height: ceil(ascent + descent))
            return GlassLabelImage.render(size: size, scale: scale) { ctx in
                ctx.textPosition = CGPoint(x: (size.width - width) / 2, y: descent)
                CTLineDraw(line, ctx)
            }
        }
    }

    private func syncSlotLayers(count n: Int) {
        while baseSlots.count < n {
            let base = CALayer(), accent = CALayer()
            accent.opacity = 0
            dotsLayer.addSublayer(base)
            dotsLayer.addSublayer(accent)
            baseSlots.append(base)
            accentSlots.append(accent)
        }
        while baseSlots.count > n {
            baseSlots.removeLast().removeFromSuperlayer()
            accentSlots.removeLast().removeFromSuperlayer()
        }
    }

    private func setContents(_ layer: CALayer, _ image: GlassLabelImage, scale: CGFloat) {
        layer.contents = image.image
        layer.contentsScale = scale
        layer.bounds = CGRect(origin: .zero, size: image.size)
    }

    // Image top-left snapped to whole device pixels (same rule as the Metal strips).
    private func placeLabels() {
        let track = trackRect
        let s = backingScale
        for i in 0..<min(baseSlots.count, labels.count) {
            let box = slotRect(i, in: track)
            for (layer, img) in [(baseSlots[i], labels[i].base), (accentSlots[i], labels[i].accent)] {
                let x = ((box.midX - img.size.width / 2) * s).rounded() / s
                let y = ((box.midY - img.size.height / 2) * s).rounded() / s
                layer.position = CGPoint(x: x + img.size.width / 2, y: y + img.size.height / 2)
            }
        }
    }

    // Canvas covers any lens pose (incl. bounce); strips re-render when labels change.
    private func syncRefraction() {
        guard let refraction, pageCount > 0, bounds.width > 0 else { return }
        let track = trackRect
        let s = backingScale
        let maxD = pitch * Self.liftScale * 1.15
        let pad = max(0, (maxD - track.height) / 2) + 2
        let x = floor((track.minX - pad) * s) / s
        let y = floor((track.minY - pad) * s) / s
        let canvas = CGRect(x: x, y: y,
                            width: ceil((track.width + pad * 2) * s) / s,
                            height: ceil((track.height + pad * 2) * s) / s)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refraction.setCanvas(frame: canvas, contentsScale: s)
        CATransaction.commit()

        refraction.updateStrip(
            .init(size: bounds.size,
                  labelRects: (0..<labels.count).map { slotRect($0, in: track) },
                  scale: s,
                  revision: labelRevision),
            labels: labels)
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard pageCount > 0 else { return }
        let x = localX(event)
        let i = index(at: x)
        isPressed = true
        isSettling = false
        isTracking = false
        isCatchingUp = false
        downX = x
        lastEmitted = Int(clampedPage(progress).rounded())

        pos.configure(Self.travelSpring)
        lift.configure(Self.liftSpring)
        glow.configure(Self.glowOnSpring)
        pos.target = CGFloat(i)       // glide to the pressed dot
        lift.target = 1               // and lift
        glow.target = 1               // whole bar lights up
        startAnimating()
        emit(i)                       // page switches right away
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed, pageCount > 0 else { return }
        let x = localX(event)

        if !isTracking {
            guard abs(x - downX) > Self.dragThreshold else { return }
            // Drag starts: lens heads for the pointer from wherever it is.
            isTracking = true
            isCatchingUp = true
            pos.configure(Self.followSpring)
            lastDragTime = event.timestamp
        }

        // Lens centered under the pointer, hard stop at the first / last dot.
        let raw = (x - trackRect.minX - Self.inset - pitch / 2) / pitch
        let target = clampedPage(raw)

        if isCatchingUp {
            pos.target = target
        } else {
            let dt = event.timestamp - lastDragTime
            if dt > 0 {
                // Smoothed velocity so the release glide carries momentum.
                let v = (target - pos.value) / CGFloat(dt)
                pos.velocity = pos.velocity * 0.5 + v * 0.5
            }
            pos.value = target
            pos.target = target
            applyFrame()
        }
        lastDragTime = event.timestamp
        startAnimating()

        // Immediate paging: the dot under the pointer becomes the page now.
        emit(Int(target.rounded()))
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        let landed = isTracking ? lastEmitted : index(at: localX(event))
        let wasDragging = isTracking
        isPressed = false
        isTracking = false
        isCatchingUp = false
        isSettling = true

        if wasDragging { pos.configure(Self.releaseSpring) }
        lift.configure(Self.releaseLiftSpring)
        glow.configure(Self.glowOffSpring)
        pos.target = CGFloat(landed)   // velocity kept → natural glide
        lift.target = 0
        glow.target = 0
        startAnimating()
        emit(landed)
    }

    private func emit(_ i: Int) {
        guard i != lastEmitted else { return }
        lastEmitted = i
        onSelect?(i)
    }

    private func localX(_ event: NSEvent) -> CGFloat {
        convert(event.locationInWindow, from: nil).x
    }

    // MARK: Display link

    private func startAnimating() {
        guard window != nil else {
            // Offscreen: jump to the end state.
            pos.snap(pos.target)
            lift.snap(lift.target)
            glow.snap(glow.target)
            isSettling = false
            applyFrame()
            return
        }
        guard link == nil else { return }
        lastTick = CACurrentMediaTime()
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)   // keeps running during mouse tracking
        link = l
    }

    private func stopAnimating() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 1.0 / 240), 1.0 / 30)
        lastTick = now

        let posDone: Bool
        if isTracking {
            if isCatchingUp {
                _ = pos.step(dt)
                // Close enough: hand over to 1:1 tracking.
                if abs(pos.value - pos.target) < Self.lockDistance {
                    pos.value = pos.target
                    isCatchingUp = false
                }
            }
            if !isCatchingUp {
                pos.velocity *= exp(-Self.velocityDecay * CGFloat(dt))
                if abs(pos.velocity) < 0.01 { pos.velocity = 0 }
            }
            posDone = !isCatchingUp && pos.velocity == 0
        } else {
            posDone = pos.step(dt)
        }
        let liftDone = lift.step(dt)
        let glowDone = glow.step(dt)

        // Release finished: hand the lens back to the pager progress.
        if !isPressed && isSettling && posDone {
            isSettling = false
            pos.snap(progress)
        }
        applyFrame()

        if posDone && liftDone && glowDone { stopAnimating() }
    }
}
