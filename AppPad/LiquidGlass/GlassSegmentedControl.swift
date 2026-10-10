import SwiftUI
import AppKit

// Ported from YouMindHub ViewCom/LiquidGlass/GlassSegmentedControl.swift.
// AppPad changes: no ThemeManager (system colors), `glass` flag follows the
// "Liquid Glass controls" setting (false → the pill layout), private FlippedView renamed to SegmentFlippedView.

// MARK: - GlassSegment

struct GlassSegment<Value: Hashable> {
    let value: Value
    let title: String
    var icon:         String? = nil
    /// Icon of the accent (selected) copy; nil → `icon`.
    var selectedIcon: String? = nil
    /// Custom template icon (e.g. the menu bar glyph); wins over `icon` / `selectedIcon`.
    var iconImage:    NSImage? = nil
}

// MARK: - GlassSegmentAxis

enum GlassSegmentAxis: Equatable {
    /// Segmented control: slots left → right, labels centered.
    case horizontal
    /// Sidebar list: slots top → bottom, labels leading, no glass track.
    case vertical
}

// MARK: - GlassSegmentMetrics

struct GlassSegmentMetrics {
    /// SwiftUI font — legacy (< 26) pill.
    var font:           Font
    /// AppKit font — glass control (≥ 26). Keep in sync with `font`.
    var nsFont:         NSFont
    /// Legacy pill only; the glass control keeps ONE weight (one step
    /// heavier only where a label is seen through the lifted lens).
    var selectedWeight: Font.Weight? = nil
    var segmentHeight:  CGFloat
    var labelHPadding:  CGFloat
    var inset:          CGFloat
    var spacing:        CGFloat = 2      // legacy only; glass slots touch
    var iconSpacing:    CGFloat = 6
    /// Fixed icon column width; aligns titles across rows (vertical lists).
    var iconColumnWidth: CGFloat? = nil
    /// SF Symbol point size; nil → same as the font size.
    var iconPointSize:   CGFloat? = nil

    // Computed (not stored statics): NSFont isn't Sendable.

    /// Calendar toggles ("Month / Week / Day", "All / Tagged") — .callout = 12pt on macOS
    static var regular: GlassSegmentMetrics {
        GlassSegmentMetrics(font: .callout.weight(.medium),
                            nsFont: .systemFont(ofSize: 12, weight: .medium),
                            segmentHeight: 24, labelHPadding: 12, inset: 2)
    }
    /// Project picker tabs (icon + title)
    static var large: GlassSegmentMetrics {
        GlassSegmentMetrics(font: .system(size: 15, weight: .medium),
                            nsFont: .systemFont(ofSize: 15, weight: .medium),
                            selectedWeight: .semibold,
                            segmentHeight: 32, labelHPadding: 12, inset: 4)
    }
    /// Vertical sidebar rows (Settings) — 13pt, fixed icon column
    static var sidebar: GlassSegmentMetrics {
        GlassSegmentMetrics(font: .system(size: 13, weight: .medium),
                            nsFont: .systemFont(ofSize: 13, weight: .medium),
                            segmentHeight: 28, labelHPadding: 10, inset: 2,
                            iconSpacing: 8, iconColumnWidth: 18)
    }
}

// MARK: - GlassSegmentedControl (SwiftUI entry point)
//
//   < macOS 26 : SwiftUI flat track + sliding accent pill.
//   ≥ macOS 26 : AppKit GlassSegmentedNSView (NSGlassEffectView track +
//                lifting glass lens), bridged via NSViewRepresentable.
//
// Call sites are unchanged; only the ≥ 26 implementation moved to AppKit.
// axis: .vertical turns it into a sidebar list (Settings): slots top →
// bottom, leading labels, no track glass, lens grows along the list.

struct GlassSegmentedControl<Value: Hashable>: View {

    let segments:  [GlassSegment<Value>]
    let selection: Value
    var metrics:            GlassSegmentMetrics = .regular
    /// true → stretch to the offered width (caller sets the frame).
    var fillsWidth:         Bool   = false
    /// Selected label color; nil → textPrimary (≥ 26: Calendar look, all
    /// labels the same color; < 26: legacy pill).
    var selectedLabelColor: Color? = nil
    /// .vertical → sidebar list (≥ 26: no track, leading labels).
    var axis:               GlassSegmentAxis = .horizontal
    /// false → pill layout (AppPad "Liquid Glass controls" off).
    var glass:              Bool = true
    let onSelect:  (Value) -> Void

    private var theme: SegmentTheme { SegmentTheme(isDark: colorScheme == .dark) }

    @Environment(\.colorScheme)     private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    // Legacy
    @Namespace private var pillNS
    @State private var hoverIndex: Int? = nil

    var body: some View {
        if #available(macOS 26.0, *), glass {
            glassBody
        } else {
            legacyBody
        }
    }

    // MARK: - ≥ macOS 26 (AppKit)

    @available(macOS 26.0, *)
    private var glassBody: some View {
        GlassSegmentedRepresentable(
            items: segments.map {
                .init(title: $0.title, icon: $0.icon, selectedIcon: $0.selectedIcon,
                      iconImage: $0.iconImage)
            },
            selectedIndex: segments.firstIndex { $0.value == selection } ?? 0,
            metrics:       metrics,
            fillsWidth:    fillsWidth,
            axis:          axis,
            labelColor:    theme.textPrimaryNS,
            accentColor:   selectedLabelColor.map { NSColor($0) } ?? theme.textPrimaryNS,
            isDark:        colorScheme == .dark,
            isRTL:         layoutDirection == .rightToLeft,
            onSelectIndex: { i in
                guard segments.indices.contains(i) else { return }
                let value = segments[i].value
                if value != selection { onSelect(value) }
            }
        )
        .accessibilityRepresentation {
            Picker("", selection: Binding(get: { selection }, set: { onSelect($0) })) {
                ForEach(segments.indices, id: \.self) { i in
                    Text(segments[i].title).tag(segments[i].value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - < macOS 26 (pill)

    private var legacyLayout: AnyLayout {
        axis == .vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.spacing))
            : AnyLayout(HStackLayout(spacing: metrics.spacing))
    }

    private var legacyBody: some View {
        legacyLayout {
            ForEach(segments.indices, id: \.self) { i in
                legacyLabel(i)
                    .background {
                        if segments[i].value == selection {
                            Capsule()
                                .fill(theme.accent.opacity(0.18))
                                .matchedGeometryEffect(id: "pill", in: pillNS)
                        }
                    }
                    .onTapGesture { onSelect(segments[i].value) }
                    .onHover { inside in
                        if inside { hoverIndex = i }
                        else if hoverIndex == i { hoverIndex = nil }
                    }
            }
        }
        .padding(metrics.inset)
        // Radius = half the horizontal bar height → capsule when horizontal.
        .background(RoundedRectangle(cornerRadius: metrics.segmentHeight / 2 + metrics.inset,
                                     style: .continuous).fill(theme.hover))
        .animation(.easeInOut(duration: 0.2), value: selection)
    }

    private func legacyLabel(_ i: Int) -> some View {
        let isActive = segments[i].value == selection
        let vertical = axis == .vertical
        return ZStack(alignment: vertical ? .leading : .center) {
            // Hidden copies reserve the widest label → equal widths.
            ForEach(segments.indices, id: \.self) { j in
                legacyContent(segments[j], filled: true)
                    .fontWeight(metrics.selectedWeight).hidden()
            }
            legacyContent(segments[i], filled: isActive)
                .fontWeight(isActive ? metrics.selectedWeight : nil)
                .foregroundStyle(isActive ? (selectedLabelColor ?? theme.textPrimary)
                                          : theme.textSecondary)
        }
        .padding(.horizontal, metrics.labelHPadding)
        .frame(maxWidth: (fillsWidth || vertical) ? .infinity : nil,
               alignment: vertical ? .leading : .center)
        .frame(height: metrics.segmentHeight)
        .background {
            if hoverIndex == i && !isActive {
                Capsule().fill(theme.accent.opacity(0.06))
            }
        }
        .contentShape(Capsule())
    }

    private func legacyContent(_ seg: GlassSegment<Value>, filled: Bool) -> some View {
        let icon = filled ? (seg.selectedIcon ?? seg.icon) : seg.icon
        let side = metrics.iconPointSize ?? metrics.nsFont.pointSize
        return HStack(spacing: metrics.iconSpacing) {
            if let image = seg.iconImage {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: side, height: side)
                    .frame(width: metrics.iconColumnWidth)
            } else if let icon {
                Image(systemName: icon)
                    .font(metrics.iconPointSize.map { Font.system(size: $0, weight: .medium) } ?? metrics.font)
                    .frame(width: metrics.iconColumnWidth)
            }
            Text(seg.title).lineLimit(1)
        }
        .font(metrics.font)
    }
}

// MARK: - SegmentTheme
//
// Stand-in for YouMindHub's ThemeColors. Static (resolved) colors: the AppKit
// control renders into layers, where dynamic system colors would not update.

private struct SegmentTheme {
    let isDark: Bool

    var textPrimaryNS: NSColor { isDark ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.12, alpha: 1) }
    var textPrimary: Color { Color(nsColor: textPrimaryNS) }
    var textSecondary: Color { Color.secondary }
    var accent: Color { Color.accentColor }
    var hover: Color { Color.primary.opacity(isDark ? 0.10 : 0.06) }
}

// MARK: - GlassSegmentedRepresentable

@available(macOS 26.0, *)
private struct GlassSegmentedRepresentable: NSViewRepresentable {

    let items:         [GlassSegmentedNSView.Item]
    let selectedIndex: Int          // logical
    let metrics:       GlassSegmentMetrics
    let fillsWidth:    Bool
    let axis:          GlassSegmentAxis
    let labelColor:    NSColor
    let accentColor:   NSColor
    let isDark:        Bool
    let isRTL:         Bool
    let onSelectIndex: (Int) -> Void

    private var config: GlassSegmentedNSView.Config {
        .init(items:         items,
              font:          metrics.nsFont,
              segmentHeight: metrics.segmentHeight,
              labelHPadding: metrics.labelHPadding,
              inset:         metrics.inset,
              iconSpacing:   metrics.iconSpacing,
              iconColumnWidth: metrics.iconColumnWidth,
              iconPointSize: metrics.iconPointSize,
              axis:          axis,
              labelColor:    labelColor,
              accentColor:   accentColor,
              isDark:        isDark,
              isRTL:         isRTL)
    }

    func makeNSView(context: Context) -> GlassSegmentedNSView {
        let view = GlassSegmentedNSView()
        view.configure(config)
        view.setSelectedIndex(selectedIndex)
        return view
    }

    func updateNSView(_ view: GlassSegmentedNSView, context: Context) {
        view.onSelectIndex = onSelectIndex
        view.configure(config)
        view.setSelectedIndex(selectedIndex)
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: GlassSegmentedNSView,
                      context: Context) -> CGSize? {
        let ideal = nsView.idealSize
        return CGSize(width: fillsWidth ? (proposal.width ?? ideal.width) : ideal.width,
                      height: ideal.height)
    }
}

// MARK: - GlassSegmentedNSView
//
// AppKit port of the iOS SlidingTabBar.
//
// Target look: macOS 26 Calendar "Day / Week / Month / Year".
//
//   trackGlass : NSGlassEffectView(.regular) — the capsule bar
//   overlay    : layer tree above the track (bottom → top)
//     trackGlow   pressed: ONE uniform HDR wash over bar ∪ lens — the
//                 whole control brightens evenly, edges no brighter
//     lensBody    rest: neutral gray pill (label color, low alpha)
//                 lifted: clear body + soft outer shadow
//     baseLabels  labels; hole punched under the lifted lens
//     refraction  LensRefractionLayer (Metal): labels re-sampled through
//                 the lens — 1:1 (no zoom, like Calendar), one weight
//                 heavier, bent rim, RGB fringe, uniform bevel ring, and
//                 light / shadow where it crosses the bar's top / bottom
//                 edge (bent into the rim near the lens ends)
//     magLabels   FALLBACK when Metal is unavailable: same labels,
//                 uniformly scaled about the lens center, masked to the lens
//     lensEdges   lifted only: rim hairline + HDR sheen + concentric
//                 cyan / pink fringe — same all the way round, so the
//                 straight top / bottom read parallel
//
// Horizontal ends: the lens center is clamped so its round cap stays
// concentric with the bar's round cap (no rubber band / bounce bulge).
//
// Labels are drawn PIXEL-ALIGNED at 1× backing in both paths (CA layers
// and the Metal strips), so the hand-off between them when the lens lands
// is pixel-identical — no end-of-release twitch.
//
// The lifted lens is drawn with layers, not a second NSGlassEffectView:
// glass on glass can't sample real content and renders as a white slab.
//
// Motion: own display link + springs.
//   • pos  — lens position in SLOT units; spring when settling, 1:1 with
//            the pointer once a drag has caught up.
//   • lift — 0 rest … 1 lifted; drives size (liftedAlong × liftHeight),
//            rim refraction strength, pill ⇄ glass crossfade.
//   • glow — 0 rest … 1 pressed; drives HDR highlight + whole-control
//            scale (pressScale).
//   • velocity of pos → liquid squash & stretch (wider + flatter).
//
// Mouse:
//   down → lens springs to the pressed slot and lifts;
//   drag → lens catches up to the pointer, then locks 1:1;
//          horizontal: hard stop at the ends, the lens' end cap stays
//          CONCENTRIC with the bar's end cap (no rubber band, no bounce
//          bulging past the bar); vertical sidebar keeps a small rubber band;
//   up   → snaps to the nearest slot (keeping velocity), selects it.

@available(macOS 26.0, *)
final class GlassSegmentedNSView: NSView {

    struct Item: Equatable {
        let title:        String
        let icon:         String?
        let selectedIcon: String?
        var iconImage:    NSImage? = nil
    }

    struct Config: Equatable {
        var items:         [Item]   = []
        var font:          NSFont   = .systemFont(ofSize: 12, weight: .medium)
        var segmentHeight: CGFloat  = 24
        var labelHPadding: CGFloat  = 12
        var inset:         CGFloat  = 2
        var iconSpacing:   CGFloat  = 6
        var iconColumnWidth: CGFloat? = nil
        var iconPointSize: CGFloat? = nil
        var axis:          GlassSegmentAxis = .horizontal
        var labelColor:    NSColor  = .labelColor
        var accentColor:   NSColor  = .controlAccentColor
        var isDark:        Bool     = false
        var isRTL:         Bool     = false
    }

    // MARK: Tuning

    private static let dragThreshold:  CGFloat = 2
    /// Vertical (sidebar) rubber-band. Horizontal has none (hard stop).
    private static let verticalOvershootLimit: CGFloat = 3.75
    /// Lifted lens height vs. rest pill: a fat bubble that clearly overhangs
    /// the bar. Horizontal width grows by the SAME amount (uniform expansion
    /// of the pill, see `liftedAlong`) → narrower than a ratio on wide slots,
    /// stays centered on its label, concentric with the bar at either end.
    private static let liftHeight:     CGFloat = 1.8
    /// Vertical (sidebar) lens: grows along the list, barely across,
    /// so it stays inside the sidebar column.
    private static let verticalLiftAlong: CGFloat = 1.4
    private static let verticalLiftCross: CGFloat = 1.06
    /// Liquid squash & stretch while moving: wider + flatter with speed.
    private static let stretchPerSpeed: CGFloat = 0.04   // per slot/s
    private static let maxStretch:      CGFloat = 0.22
    /// How fast the stretch relaxes once the pointer stops (1/s).
    private static let velocityDecay:   CGFloat = 10
    /// Whole control (track + labels + lens) scale while pressed / dragging.
    private static let pressScale:     CGFloat = 1.05
    /// Rim refraction amplitude = ratio × rim band width. Labels are NOT
    /// magnified; only the rim band warps. Keep < 0.44 (fold-free).
    private static let rimRefraction:  CGFloat = 0.25
    /// Rim band width = ratio × lens half-size; the rest is the flat core.
    private static let bezelRatio:      CGFloat = 0.35
    /// RGB split at the rim (fraction of the total bend).
    private static let dispersion:      CGFloat = 0.16
    /// Glass bevel (Metal): dark ring at the lens edge fading inward,
    /// identical all the way round. Alpha at the edge / falloff width as
    /// a fraction of the lens half-size.
    private static let shadeLight:      CGFloat = 0.14
    private static let shadeDark:       CGFloat = 0.40
    private static let shadeRatio:      CGFloat = 0.16
    /// Light & shadow where the lens crosses the bar's top / bottom edge:
    /// white just outside, black just inside the bar edge, warped toward
    /// the rim (warp = ratio × rim band width, keep < 0.44). Alphas at full lift.
    private static let barLightLight:   CGFloat = 0.70
    private static let barLightDark:    CGFloat = 0.16
    private static let barShadeLight:   CGFloat = 0.10
    private static let barShadeDark:    CGFloat = 0.30
    private static let barRefraction:   CGFloat = 0.40
    /// Heavier lens weight cross-fades only over this top part of lift →
    /// the two weights overlap (ghost) for a short moment only.
    private static let weightFadeStart: CGFloat = 0.5

    private static let travelSpring = (duration: 0.32, bounce: 0.25)
    /// Catch-up to the pointer when a drag starts; no bounce.
    private static let followSpring = (duration: 0.14, bounce: 0.0)
    /// Distance (slots) at which catch-up hands over to 1:1 tracking.
    private static let lockDistance: CGFloat = 0.02
    private static let liftSpring   = (duration: 0.24, bounce: 0.22)
    /// Release: slower settle back into the slot.
    private static let releaseSpring     = (duration: 0.7, bounce: 0.15)
    /// No bounce: an undershoot below 0 would flip the lens on / off again.
    private static let releaseLiftSpring = (duration: 0.7, bounce: 0.0)
    /// Whole-track HDR highlight while pressed / dragging.
    private static let glowOnSpring  = (duration: 0.18, bounce: 0.0)
    private static let glowOffSpring = (duration: 0.7,  bounce: 0.0)

    // MARK: State

    var onSelectIndex: ((Int) -> Void)?

    private var config = Config()
    /// PHYSICAL index (left → right).
    private var selectedIndex = 0
    private var maxLabelWidth: CGFloat = 0
    /// Resolved label color; tints the neutral rest pill.
    private var tintCG: CGColor = NSColor.labelColor.cgColor

    private let trackGlass = NSGlassEffectView()
    private let overlay    = SegmentFlippedView()
    private let trackGlow  = TrackGlowLayer()
    private let lensBody   = LensBodyLayer()
    private let baseLabels = CALayer()
    private let baseMask   = CAShapeLayer()
    private let magLabels  = CALayer()
    private let magMask    = CAShapeLayer()
    private let magContent = CALayer()
    /// Real refraction (Metal); nil → magLabels fallback.
    private let refraction = LensRefractionLayer.make()
    private var labelImages: [GlassLabelImages] = []
    private var labelRevision = 0
    private let lensEdges  = LensEdgeLayer()
    private var baseSlots: [SlotLabelLayer] = []
    private var magSlots:  [SlotLabelLayer] = []

    private var pos  = SpringValue()
    private var lift = SpringValue()
    private var glow = SpringValue()
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var hasPlaced = false

    private var pressedIndex:  Int?
    private var isTracking   = false
    private var downX:         CGFloat = 0
    /// Lens still gliding toward the pointer (before 1:1 lock).
    private var isCatchingUp = false
    private var lastDragTime:  TimeInterval = 0

    override var isFlipped: Bool { true }

    // MARK: Init

    init() {
        super.init(frame: .zero)
        wantsLayer    = true
        clipsToBounds = false          // lifted lens overhangs the track

        trackGlass.style = .regular
        addSubview(trackGlass)

        overlay.wantsLayer    = true
        overlay.clipsToBounds = false
        addSubview(overlay)

        if let root = overlay.layer {
            root.masksToBounds = false
            root.addSublayer(trackGlow)   // bottom: brightens the whole bar
            root.addSublayer(lensBody)
            root.addSublayer(baseLabels)
            root.addSublayer(magLabels)
            if let refraction { root.addSublayer(refraction) }
            root.addSublayer(lensEdges)
        }
        magLabels.addSublayer(magContent)
        magLabels.mask   = magMask
        magLabels.isHidden = true
        baseMask.fillRule  = .evenOdd

        pos.configure(Self.travelSpring)
        lift.configure(Self.liftSpring)
        glow.configure(Self.glowOnSpring)
        setAccessibilityElement(false)  // SwiftUI provides the Picker repr.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Public API

    var idealSize: CGSize {
        if isVertical {
            return CGSize(width:  maxLabelWidth + config.labelHPadding * 2 + config.inset * 2,
                          height: config.segmentHeight * CGFloat(count) + config.inset * 2)
        }
        let slot = maxLabelWidth + config.labelHPadding * 2
        return CGSize(width:  slot * CGFloat(count) + config.inset * 2,
                      height: config.segmentHeight + config.inset * 2)
    }

    override var intrinsicContentSize: NSSize { idealSize }

    func configure(_ new: Config) {
        guard new != config else { return }
        config = new
        renderLabels()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// Selection pushed from SwiftUI (logical index).
    func setSelectedIndex(_ logical: Int) {
        guard count > 0 else { return }
        let p = physical(clampIndex(logical))
        guard p != selectedIndex else { return }
        selectedIndex = p
        // Mid-press the release decides; before first layout, layout snaps.
        guard pressedIndex == nil, hasPlaced else { return }
        pos.configure(Self.travelSpring)   // programmatic change: normal speed
        pos.target = CGFloat(p)
        startAnimating()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        trackGlass.frame        = bounds
        trackGlass.cornerRadius = bounds.height / 2
        trackGlass.isHidden     = !showsTrack   // glass-on-glass in a sidebar
        overlay.frame           = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [trackGlow, lensBody, baseLabels, magLabels, lensEdges] as [CALayer] {
            l.frame = bounds
        }
        baseMask.frame    = bounds
        magMask.frame     = bounds
        magContent.bounds = bounds
        CATransaction.commit()
        syncRefraction()

        if !hasPlaced, slotWidth > 0 {
            pos.snap(CGFloat(selectedIndex))
            lift.snap(0)
            glow.snap(0)
            hasPlaced = true
        }
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

    /// Re-place lens, labels and magnifier from the current pos / lift.
    private func applyFrame() {
        let slot = slotWidth
        guard count > 0, slot > 0 else { return }

        let p  = lift.value                       // may overshoot (bounce)
        let pc = min(max(p, 0), 1)
        // Liquid stretch from speed, only while lifted.
        let stretch = min(abs(pos.velocity) * Self.stretchPerSpeed, Self.maxStretch) * pc
        let along = liftedAlong(slot, p) * (1 + stretch)
        let cross = crossRest * (1 + (liftCross - 1) * p) * (1 - stretch * 0.5)
        let ca    = clampedCenter(config.inset + pos.value * slot + slot / 2,
                                  along: along, cross: cross)
        let lens  = rect(along: ca, cross: crossLength / 2, alongSize: along, crossSize: cross)
        let settled = min(max(pos.value, 0), CGFloat(count - 1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        applyPressScale()
        trackGlow.update(bar: bounds, lens: lens,
                         glow: showsTrack ? min(max(glow.value, 0), 1) : 0,
                         dark: config.isDark)
        lensBody.update(rect: lens, lift: pc, tint: tintCG, dark: config.isDark)
        lensEdges.update(rect: lens, lift: pc, dark: config.isDark)

        var activeness: [CGFloat] = []
        for i in 0..<baseSlots.count {
            let r = labelRect(i)
            let b = CGRect(origin: .zero, size: r.size)
            let c = CGPoint(x: r.midX, y: r.midY)
            // Accent tint crossfades with the lens distance (0…1).
            let t = max(0, 1 - abs(settled - CGFloat(i)))
            activeness.append(t)
            for layer in [baseSlots[i], magSlots[i]] {
                layer.bounds   = b
                layer.position = c
                layer.setActiveness(t)
            }
        }

        // Lens content: hole in the base labels + labels seen THROUGH the lens.
        let lifted = pc > 0.001
        if lifted {
            let lensPath = capsulePath(lens)
            let holed = CGMutablePath()
            holed.addRect(bounds.insetBy(dx: -200, dy: -200))
            holed.addPath(lensPath)
            baseMask.path    = holed
            baseLabels.mask  = baseMask

            magLabels.isHidden = true
            if let refraction {
                // Labels at 1:1 (no zoom), heavier weight; only the rim
                // band bends. Everything follows lift.
                let bezel = min(lens.width, lens.height) / 2 * Self.bezelRatio
                refraction.isHidden = false
                refraction.render(.init(
                    lens:          lens,
                    rimRefraction: bezel * Self.rimRefraction * pc,
                    bezel:         bezel,
                    dispersion:    Self.dispersion,
                    slotOrigin:    config.inset,
                    slotWidth:     slot,
                    activeness:    activeness,
                    vertical:      isVertical,
                    weight:        smoothstep(Self.weightFadeStart, 1, pc),
                    backdrop:      labelBackdrop,
                    shade:         (config.isDark ? Self.shadeDark : Self.shadeLight) * pc,
                    shadeWidth:    min(lens.width, lens.height) / 2 * Self.shadeRatio,
                    track:         showsTrack ? bounds : .zero,
                    barLight:      (config.isDark ? Self.barLightDark : Self.barLightLight) * pc,
                    barShade:      (config.isDark ? Self.barShadeDark : Self.barShadeLight) * pc,
                    barWarp:       bezel * Self.barRefraction * pc))
            } else {
                // No Metal: labels stay as-is, no hole.
                baseLabels.mask = nil
            }
        } else {
            baseLabels.mask     = nil
            magLabels.isHidden  = true
            refraction?.isHidden = true
        }

        CATransaction.commit()
    }

    /// Scales everything about the view center by glow (1 … pressScale).
    /// sublayerTransform pivots on the layer's anchorPoint → compensate.
    private func applyPressScale() {
        guard let root = layer, bounds.width > 0 else { return }
        let g = min(max(glow.value, 0), 1)
        let s = 1 + (pressScaleMax - 1) * g
        let a = root.anchorPoint
        let d = CGPoint(x: bounds.width * (0.5 - a.x), y: bounds.height * (0.5 - a.y))
        var t = CATransform3DMakeTranslation(d.x, d.y, 0)
        t = CATransform3DScale(t, s, s, 1)
        t = CATransform3DTranslate(t, -d.x, -d.y, 0)
        root.sublayerTransform = t
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Whole control is one target; children never take the mouse.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard count > 0 else { return }
        let x = localAlong(event)
        let i = index(at: x)
        pressedIndex  = i
        isTracking    = false
        isCatchingUp  = false
        downX         = x

        pos.configure(Self.travelSpring)
        lift.configure(Self.liftSpring)
        glow.configure(Self.glowOnSpring)
        pos.target  = CGFloat(i)     // glide to the pressed slot
        lift.target = 1              // and lift
        glow.target = 1              // whole bar lights up
        startAnimating()
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedIndex != nil else { return }
        let x    = localAlong(event)
        let slot = slotWidth
        guard slot > 0 else { return }

        if !isTracking {
            guard abs(x - downX) > Self.dragThreshold else { return }
            // Drag starts: lens heads for the pointer from wherever it is.
            isTracking   = true
            isCatchingUp = true
            pos.configure(Self.followSpring)
            lastDragTime = event.timestamp
        }

        // Lens centered under the pointer. Past the ends: hard stop
        // (horizontal) / rubber band (vertical sidebar).
        let raw    = x - config.inset - slot / 2
        let maxX   = CGFloat(count - 1) * slot
        let target = (isVertical ? rubberBand(raw, maxX: maxX) : min(max(raw, 0), maxX)) / slot

        if isCatchingUp {
            // Spring (display link) chases the moving target.
            pos.target = target
            startAnimating()
        } else {
            // Locked: exactly 1:1.
            let dt = event.timestamp - lastDragTime
            if dt > 0 {
                // Smoothed velocity so the release glide carries momentum.
                let v = (target - pos.value) / CGFloat(dt)
                pos.velocity = pos.velocity * 0.5 + v * 0.5
            }
            pos.value  = target
            pos.target = target
            applyFrame()
        }
        lastDragTime = event.timestamp
        startAnimating()   // lets the stretch relax when the pointer stops
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedIndex != nil else { return }
        let landed: Int
        if isTracking {
            let settled = min(max(pos.value, 0), CGFloat(count - 1))
            landed = clampIndex(Int(settled.rounded()))
        } else {
            landed = index(at: localAlong(event))   // plain click
        }

        let wasDragging = isTracking
        pressedIndex = nil
        isTracking   = false
        isCatchingUp = false

        // Drag release: slow (0.7s) glide with kept momentum.
        // Plain click: keep travelSpring from mouseDown → same speed as
        // programmatic / hotkey changes (a quick tap would otherwise hand
        // most of a long trip to the slow release spring).
        if wasDragging {
            pos.configure(Self.releaseSpring)
        }
        lift.configure(Self.releaseLiftSpring)
        glow.configure(Self.glowOffSpring)
        pos.target  = CGFloat(landed)   // velocity kept → natural glide
        lift.target = 0
        glow.target = 0
        startAnimating()

        if landed != selectedIndex {
            selectedIndex = landed
            onSelectIndex?(logical(landed))
        }
    }

    // MARK: Display link

    private func startAnimating() {
        guard window != nil else {
            // Offscreen: no frames to drive, jump to the end state.
            pos.snap(pos.target)
            lift.snap(lift.target)
            glow.snap(glow.target)
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
        let dt  = min(max(now - lastTick, 1.0 / 240), 1.0 / 30)
        lastTick = now

        let posDone: Bool
        if isTracking {
            if isCatchingUp {
                _ = pos.step(dt)
                // Close enough: hand over to 1:1 tracking.
                if abs(pos.value - pos.target) < Self.lockDistance {
                    pos.value    = pos.target
                    isCatchingUp = false
                }
            }
            if !isCatchingUp {
                // Locked: mouse owns `pos`; only relax the stretch.
                pos.velocity *= exp(-Self.velocityDecay * CGFloat(dt))
                if abs(pos.velocity) < 0.01 { pos.velocity = 0 }
            }
            posDone = !isCatchingUp && pos.velocity == 0
        } else {
            posDone = pos.step(dt)
        }
        let liftDone = lift.step(dt)
        let glowDone = glow.step(dt)
        applyFrame()

        if posDone && liftDone && glowDone { stopAnimating() }
    }

    // MARK: Labels

    private func renderLabels() {
        let items = ordered
        sync(&baseSlots, count: items.count, in: baseLabels)
        sync(&magSlots,  count: items.count, in: magContent)

        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let scale   = backing   // 1:1 pixels; positions are pixel-aligned
        var maxW: CGFloat = 0

        var images: [GlassLabelImages] = []
        let font     = config.font
        let lensFont = Self.heavier(font)

        // Resolve dynamic colors against THIS view's appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tintCG = config.labelColor.cgColor
            for (i, item) in items.enumerated() {
                let base   = renderLabel(item, color: config.labelColor,  filled: false, font: font)
                let accent = renderLabel(item, color: config.accentColor, filled: true,  font: font)
                // Seen through the lens: one weight step heavier.
                let lensBase   = renderLabel(item, color: config.labelColor,  filled: false, font: lensFont)
                let lensAccent = renderLabel(item, color: config.accentColor, filled: true,  font: lensFont)
                maxW = max(maxW, base.size.width, accent.size.width)
                baseSlots[i].alignment = labelAlignment
                magSlots[i].alignment  = labelAlignment
                baseSlots[i].setImages(base: base, accent: accent, scale: scale)
                magSlots[i].setImages(base: base, accent: accent, scale: scale)
                images.append(.init(base: base, accent: accent,
                                    lensBase: lensBase, lensAccent: lensAccent))
            }
        }
        maxLabelWidth = ceil(maxW)
        labelImages   = images
        labelRevision &+= 1
        syncRefraction()

        // Crisp vector edges at the current backing scale.
        for l in [trackGlow, lensBody, lensEdges, baseMask, magMask] as [CALayer] {
            Self.setContentsScale(l, backing)
        }
        applyFrame()
    }

    /// Sizes the refraction canvas (covers any lens pose incl. bounce,
    /// stretch and rubber-band) and re-renders its label strips if needed.
    private func syncRefraction() {
        guard let refraction, slotWidth > 0, bounds.height > 0 else { return }
        let slot = slotWidth
        let maxAlong = liftedAlong(slot, 1.1) * (1 + Self.maxStretch)
        let maxCross = crossRest * liftCross * 1.15
        let padAlong = max(0, (maxAlong - slot) / 2) + overshootLimit + 2
        let padCross = max(0, (maxCross - crossLength) / 2) + 2
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        // Whole device pixels: canvas origin + size on the pixel grid →
        // shader pixel centers land exactly on strip texel centers.
        func px(_ v: CGFloat) -> CGFloat { ceil(v * backing) / backing }
        let padX = px(isVertical ? padCross : padAlong)
        let padY = px(isVertical ? padAlong : padCross)
        let canvas = CGRect(x: -padX, y: -padY,
                            width:  px(bounds.width  + padX * 2),
                            height: px(bounds.height + padY * 2))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refraction.setCanvas(frame: canvas, contentsScale: backing)
        CATransaction.commit()

        refraction.updateStrip(
            .init(size:       bounds.size,
                  labelRects: (0..<labelImages.count).map { labelRect($0) },
                  alignment:  labelAlignment,
                  scale:      backing,
                  revision:   labelRevision),
            labels: labelImages)
    }

    private func sync(_ slots: inout [SlotLabelLayer], count n: Int, in parent: CALayer) {
        while slots.count < n {
            let l = SlotLabelLayer()
            parent.addSublayer(l)
            slots.append(l)
        }
        while slots.count > n {
            slots.removeLast().removeFromSuperlayer()
        }
    }

    private static func setContentsScale(_ layer: CALayer, _ scale: CGFloat) {
        layer.contentsScale = scale
        if let mask = layer.mask { setContentsScale(mask, scale) }
        layer.sublayers?.forEach { setContentsScale($0, scale) }
    }

    private func renderLabel(_ item: Item, color: NSColor, filled: Bool, font: NSFont) -> NSImage {
        let name = filled ? (item.selectedIcon ?? item.icon) : item.icon
        let iconSide = config.iconPointSize ?? font.pointSize
        let symbol: NSImage? = item.iconImage.map { Self.tinted($0, color: color, side: iconSide) }
            ?? name.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                    .withSymbolConfiguration(
                        NSImage.SymbolConfiguration(pointSize: iconSide,
                                                    weight: Self.weight(of: font))
                            .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
            }
        let text = NSAttributedString(string: item.title,
                                      attributes: [.font: font, .foregroundColor: color])
        let textSize = text.size()
        let iconSize = symbol?.size ?? .zero
        let gap      = symbol == nil ? 0 : config.iconSpacing
        // Icon box: fixed column (if set) so titles line up across rows.
        let iconBox  = symbol == nil ? 0 : max(iconSize.width, config.iconColumnWidth ?? 0)
        let size = CGSize(width:  ceil(iconBox + gap + textSize.width),
                          height: ceil(max(iconSize.height, textSize.height)))

        return NSImage(size: size, flipped: true) { _ in
            symbol?.draw(in: CGRect(x: (iconBox - iconSize.width) / 2,
                                    y: (size.height - iconSize.height) / 2,
                                    width: iconSize.width, height: iconSize.height),
                         from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: nil)
            text.draw(at: CGPoint(x: iconBox + gap,
                                  y: (size.height - textSize.height) / 2))
            return true
        }
    }

    /// Template image drawn at side × side, filled with `color`.
    private static func tinted(_ image: NSImage, color: NSColor, side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// Standard system weights, light → heavy.
    private static let weightSteps: [NSFont.Weight] = [
        .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black,
    ]

    /// Weight of a system font (regular when unknown).
    private static func weight(of font: NSFont) -> NSFont.Weight {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let raw = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
        // Snap to the nearest standard step.
        return weightSteps.min { abs(Double($0.rawValue) - raw) < abs(Double($1.rawValue) - raw) }
            ?? .regular
    }

    /// Same size, one standard weight step heavier (medium → semibold).
    private static func heavier(_ font: NSFont) -> NSFont {
        let w = weight(of: font)
        let i = weightSteps.firstIndex(of: w) ?? 3
        let next = weightSteps[min(i + 1, weightSteps.count - 1)]
        return .systemFont(ofSize: font.pointSize, weight: next)
    }

    /// Gray guess of what lies under the labels; fills the channels the
    /// rim fringe pulls away, so dark text on a light bar still fringes.
    private var labelBackdrop: CGFloat {
        if config.isDark { return isVertical ? 0.18 : 0.22 }
        return isVertical ? 0.93 : 0.98
    }

    // MARK: Geometry

    private var count: Int { config.items.count }
    /// RTL mirrors the horizontal axis only; vertical lists stay top → bottom.
    private var mirrored: Bool { config.isRTL && !isVertical }
    private var ordered: [Item] { mirrored ? config.items.reversed() : config.items }
    private func physical(_ logical: Int) -> Int { mirrored ? count - 1 - logical : logical }
    private func logical(_ physical: Int) -> Int { mirrored ? count - 1 - physical : physical }

    // MARK: Axis helpers

    private var isVertical: Bool { config.axis == .vertical }
    /// Bounds length along / across the slot axis.
    private var alongLength: CGFloat { isVertical ? bounds.height : bounds.width }
    private var crossLength: CGFloat { isVertical ? bounds.width  : bounds.height }
    /// Rest-pill size across the axis.
    private var crossRest: CGFloat {
        isVertical ? max(0, bounds.width - config.inset * 2) : config.segmentHeight
    }
    /// Drag overshoot past the ends (vertical only; horizontal hard-stops).
    private var overshootLimit: CGFloat { isVertical ? Self.verticalOvershootLimit : 0 }
    private var liftCross: CGFloat { isVertical ? Self.verticalLiftCross : Self.liftHeight }

    /// Lens length along the slot axis at lift p (before stretch).
    ///   horizontal: slot + the same growth as the height → every side of
    ///               the rest pill moves out equally (uniform expansion);
    ///   vertical  : ratio of the slot (sidebar rows).
    private func liftedAlong(_ slot: CGFloat, _ p: CGFloat) -> CGFloat {
        isVertical ? slot * (1 + (Self.verticalLiftAlong - 1) * p)
                   : slot + crossRest * (Self.liftHeight - 1) * p
    }
    /// No whole-control zoom for a sidebar list.
    private var pressScaleMax: CGFloat { isVertical ? 1 : Self.pressScale }
    /// Sidebar already sits on glass → no track / track glow.
    private var showsTrack: Bool { !isVertical }
    private var labelAlignment: GlassLabelAlignment {
        guard isVertical else { return .center }
        return config.isRTL ? .trailing : .leading
    }

    /// Horizontal: clamps the lens center so the lens never reaches past
    /// the bar ends by more than it overhangs top / bottom → at either end
    /// its round cap is concentric with the bar's round cap. Covers drag,
    /// release bounce, lift bounce and stretch alike. Vertical: unchanged.
    private func clampedCenter(_ center: CGFloat, along: CGFloat, cross: CGFloat) -> CGFloat {
        guard !isVertical else { return center }
        let margin = (crossLength - cross) / 2      // < 0 when the lens overhangs
        let lo = margin + along / 2
        let hi = alongLength - margin - along / 2
        return lo <= hi ? min(max(center, lo), hi) : alongLength / 2
    }

    /// Rect from an (along, cross) center and sizes.
    private func rect(along a: CGFloat, cross c: CGFloat,
                      alongSize: CGFloat, crossSize: CGFloat) -> CGRect {
        isVertical
            ? CGRect(x: c - crossSize / 2, y: a - alongSize / 2, width: crossSize, height: alongSize)
            : CGRect(x: a - alongSize / 2, y: c - crossSize / 2, width: alongSize, height: crossSize)
    }

    /// Label box of physical slot i (overlay coords).
    private func labelRect(_ i: Int) -> CGRect {
        let slot = slotWidth
        let a = config.inset + slot * (CGFloat(i) + 0.5)
        if isVertical {
            let w = max(0, bounds.width - (config.inset + config.labelHPadding) * 2)
            return rect(along: a, cross: bounds.width / 2, alongSize: slot, crossSize: w)
        }
        return rect(along: a, cross: bounds.height / 2, alongSize: slot, crossSize: config.segmentHeight)
    }

    private var slotWidth: CGFloat {
        guard count > 0 else { return 0 }
        return max(0, (alongLength - config.inset * 2) / CGFloat(count))
    }

    /// Pointer position along the slot axis (flipped: y grows downward).
    private func localAlong(_ event: NSEvent) -> CGFloat {
        let p = convert(event.locationInWindow, from: nil)
        return isVertical ? p.y : p.x
    }

    private func index(at x: CGFloat) -> Int {
        let slot = slotWidth
        guard slot > 0 else { return selectedIndex }
        return clampIndex(Int(((x - config.inset) / slot).rounded(.down)))
    }

    private func clampIndex(_ i: Int) -> Int { min(max(i, 0), max(count - 1, 0)) }

    /// Past either end each extra point buys less travel (asymptotic).
    /// Vertical sidebar only.
    private func rubberBand(_ x: CGFloat, maxX: CGFloat) -> CGFloat {
        func resist(_ d: CGFloat) -> CGFloat { d / (d / overshootLimit + 1) }
        if x < 0    { return -resist(-x) }
        if x > maxX { return maxX + resist(x - maxX) }
        return x
    }
}

// MARK: - SpringValue
//
// Damped spring, same parameterisation as SwiftUI Spring(duration:bounce:)
// with mass 1. Semi-implicit Euler with 1/240s sub-steps.

private struct SpringValue {
    var value:    CGFloat = 0
    var velocity: CGFloat = 0
    var target:   CGFloat = 0
    private var stiffness: CGFloat = 300
    private var damping:   CGFloat = 30

    mutating func configure(_ s: (duration: Double, bounce: Double)) {
        stiffness = CGFloat(pow(2 * Double.pi / s.duration, 2))
        damping   = CGFloat(4 * Double.pi * (1 - s.bounce) / s.duration)
    }

    mutating func snap(_ v: CGFloat) {
        value = v; target = v; velocity = 0
    }

    /// Advances by dt; returns true once at rest on the target.
    mutating func step(_ dt: Double) -> Bool {
        var remaining = dt
        while remaining > 0 {
            let h = CGFloat(min(remaining, 1.0 / 240))
            let a = -stiffness * (value - target) - damping * velocity
            velocity += a * h
            value    += velocity * h
            remaining -= Double(h)
        }
        if abs(value - target) < 0.0005, abs(velocity) < 0.0005 {
            value = target; velocity = 0
            return true
        }
        return false
    }
}

// MARK: - SegmentFlippedView

private final class SegmentFlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - smoothstep

/// Hermite 0 → 1 as x goes a → b (clamped).
private func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - capsulePath

private func capsulePath(_ r: CGRect) -> CGPath {
    let radius = max(0, min(r.width, r.height) / 2)
    return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - HDR
//
// Extended-linear-sRGB whites above 1.0 render brighter than SDR white on
// EDR displays (headroom permitting) and clip to plain white elsewhere.
// EDR opt-in is set via KVC so older SDKs still compile.

private enum HDR {
    static func white(_ value: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        if let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
           let c = CGColor(colorSpace: space, components: [value, value, value, alpha]) {
            return c
        }
        return NSColor.white.withAlphaComponent(alpha).cgColor
    }

    static func enable(_ layer: CALayer) {
        let key = "wantsExtendedDynamicRangeContent"
        if layer.responds(to: NSSelectorFromString("setWantsExtendedDynamicRangeContent:")) {
            layer.setValue(true, forKey: key)
        }
        // Float backing so rasterized gradients / strokes keep values > 1.
        layer.contentsFormat = .RGBA16Float
    }
}

// MARK: - TrackGlowLayer
//
// Pressed / dragging highlight: ONE uniform HDR wash (two equal gradient
// stops → float backing keeps values > 1) over bar ∪ lens. No rim and no
// vertical gradient: those made the edges brighter than the middle.
// Opacity follows `glow` (0 rest … 1 pressed).

private final class TrackGlowLayer: CALayer {

    private let fill     = CAGradientLayer()
    private let fillMask = CAShapeLayer()
    private var appliedDark: Bool?

    // Tuning: exposure (> 1 = HDR) and opacity of the wash.
    private static let hdrValue:   CGFloat = 1.5
    private static let lightAlpha: CGFloat = 0.26
    private static let darkAlpha:  CGFloat = 0.14   // white reads strong on dark

    override init() {
        super.init()
        masksToBounds = false
        opacity  = 0
        isHidden = true
        addSublayer(fill)
        fill.mask = fillMask
        for l in [self, fill] as [CALayer] { HDR.enable(l) }
    }

    override init(layer: Any) { super.init(layer: layer) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `bar` and `lens` in this layer's coordinates.
    func update(bar: CGRect, lens: CGRect, glow g: CGFloat, dark: Bool) {
        opacity  = Float(g)
        isHidden = g <= 0.001
        guard !isHidden else { return }
        if dark != appliedDark { applyColors(dark: dark) }

        // Union of the two capsules → the overhanging lens glows too,
        // and the overlap is NOT doubled.
        let area = bar.union(lens)
        fill.frame     = area
        fillMask.frame = CGRect(origin: .zero, size: area.size)
        let dx = -area.minX, dy = -area.minY
        fillMask.path = capsulePath(bar.offsetBy(dx: dx, dy: dy))
            .union(capsulePath(lens.offsetBy(dx: dx, dy: dy)))
    }

    private func applyColors(dark: Bool) {
        appliedDark = dark
        let c = HDR.white(Self.hdrValue, dark ? Self.darkAlpha : Self.lightAlpha)
        fill.colors = [c, c]                // uniform: brightness only
    }
}

// MARK: - LensBodyLayer
//
// rest   : neutral pill (label color, low alpha) — macOS 26 Calendar look,
//          no rim, no accent;
// lifted : body stays clear (brightness comes from TrackGlowLayer) + soft
//          shadow OUTSIDE the capsule only → reads as raised glass.

private final class LensBodyLayer: CALayer {

    private let outerShadow = CALayer()
    private let outerMask   = CAShapeLayer()
    private let restFill    = CALayer()
    private var appliedDark: Bool?
    private var appliedTint: CGColor?

    private static let pillAlphaLight:   CGFloat = 0.085
    private static let pillAlphaDark:    CGFloat = 0.14
    private static let shadowRadius:     CGFloat = 5
    private static let shadowAlphaLight: Float   = 0.14
    private static let shadowAlphaDark:  Float   = 0.35

    override init() {
        super.init()
        masksToBounds = false
        addSublayer(outerShadow)
        addSublayer(restFill)

        // Shadow of a clear shape: path-driven, masked to the outside ring.
        outerShadow.shadowColor   = NSColor.black.cgColor
        outerShadow.shadowOffset  = .zero
        outerShadow.shadowRadius  = Self.shadowRadius
        outerShadow.shadowOpacity = 0
        outerShadow.mask   = outerMask
        outerMask.fillRule = .evenOdd
    }

    override init(layer: Any) { super.init(layer: layer) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(rect: CGRect, lift p: CGFloat, tint: CGColor, dark: Bool) {
        restFill.frame        = rect
        restFill.cornerRadius = rect.height / 2
        if dark != appliedDark || tint != appliedTint {
            appliedDark = dark
            appliedTint = tint
            restFill.backgroundColor = tint.copy(alpha: dark ? Self.pillAlphaDark
                                                             : Self.pillAlphaLight) ?? tint
        }
        restFill.opacity = Float(1 - p)

        // Outer shadow ring, fades in with lift.
        let alpha = (dark ? Self.shadowAlphaDark : Self.shadowAlphaLight) * Float(p)
        outerShadow.shadowOpacity = alpha
        outerShadow.isHidden      = alpha <= 0.001
        guard !outerShadow.isHidden else { return }
        let lensPath = capsulePath(rect)
        let pad = Self.shadowRadius * 3
        outerShadow.frame      = bounds
        outerShadow.shadowPath = lensPath
        outerMask.frame        = bounds
        let ring = CGMutablePath()
        ring.addRect(rect.insetBy(dx: -pad, dy: -pad))
        ring.addPath(lensPath)
        outerMask.path = ring
    }
}

// MARK: - LensEdgeLayer
//
// Edge of the lifted lens. Every stroke is a constant color along a
// concentric capsule, so it is the same all the way round and the straight
// top / bottom read parallel (no angle-dependent highlights).
//   rim    hairline outline (dark on light, light on dark)
//   sheen  thin HDR white line just inside the rim → glass specular
//          (uniform gradient stops masked by a stroke → float backing)
//   fringe cyan just outside / pink just inside → chromatic dispersion
// The bevel shading inside the lens is drawn by LensRefractionLayer.
// Whole stack fades with lift; nothing fills the middle.

private final class LensEdgeLayer: CALayer {

    private let rim       = CAShapeLayer()
    private let sheen     = CAGradientLayer()
    private let sheenMask = CAShapeLayer()
    private let cyan      = CAShapeLayer()
    private let pink      = CAShapeLayer()
    private var appliedDark: Bool?

    private static let rimWidth:    CGFloat = 0.8
    private static let sheenWidth:  CGFloat = 1.0
    private static let sheenInset:  CGFloat = 1.3
    private static let fringeWidth: CGFloat = 0.8
    private static let fringeShift: CGFloat = 0.6
    /// Sheen exposure (> 1 = HDR) and opacity.
    private static let sheenHDR:        CGFloat = 1.3
    private static let sheenAlphaLight: CGFloat = 0.85
    private static let sheenAlphaDark:  CGFloat = 0.30

    override init() {
        super.init()
        masksToBounds = false
        opacity = 0
        addSublayer(sheen)
        for l in [pink, cyan, rim] {
            l.fillColor = nil
            addSublayer(l)
        }
        rim.lineWidth  = Self.rimWidth
        cyan.lineWidth = Self.fringeWidth
        pink.lineWidth = Self.fringeWidth

        sheen.mask = sheenMask
        sheenMask.fillColor   = nil
        sheenMask.strokeColor = NSColor.black.cgColor
        sheenMask.lineWidth   = Self.sheenWidth
        for l in [self, sheen] as [CALayer] { HDR.enable(l) }
    }

    override init(layer: Any) { super.init(layer: layer) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(rect: CGRect, lift p: CGFloat, dark: Bool) {
        opacity = Float(p)
        guard p > 0.001 else { return }
        if dark != appliedDark { applyColors(dark: dark) }

        for l in [rim, sheen, cyan, pink] as [CALayer] { l.frame = rect }
        let b = CGRect(origin: .zero, size: rect.size)
        sheenMask.frame = b
        // Concentric insets (negative = outside) → uniform all round.
        rim.path       = capsulePath(b.insetBy(dx: Self.rimWidth / 2, dy: Self.rimWidth / 2))
        let si = Self.sheenInset + Self.sheenWidth / 2
        sheenMask.path = capsulePath(b.insetBy(dx: si, dy: si))
        let c = Self.rimWidth / 2 - Self.fringeShift
        cyan.path      = capsulePath(b.insetBy(dx: c, dy: c))
        let k = Self.rimWidth / 2 + Self.fringeShift
        pink.path      = capsulePath(b.insetBy(dx: k, dy: k))
    }

    private func applyColors(dark: Bool) {
        appliedDark = dark
        rim.strokeColor = dark ? NSColor.white.withAlphaComponent(0.28).cgColor
                               : NSColor.black.withAlphaComponent(0.10).cgColor
        let w = HDR.white(Self.sheenHDR, dark ? Self.sheenAlphaDark : Self.sheenAlphaLight)
        sheen.colors = [w, w]               // uniform: same brightness all round
        let k: CGFloat = dark ? 0.8 : 1
        cyan.strokeColor = NSColor(red: 0.30, green: 0.90, blue: 1.00, alpha: 0.40 * k).cgColor
        pink.strokeColor = NSColor(red: 1.00, green: 0.35, blue: 0.75, alpha: 0.32 * k).cgColor
    }
}

// MARK: - SlotLabelLayer
//
// Base copy + accent copy; the accent copy's opacity is the activeness.
// Image origins are snapped to the device pixel grid of the PARENT
// (overlay) space — same rule as LensRefractionLayer's strips.

private final class SlotLabelLayer: CALayer {

    private let base   = CALayer()
    private let accent = CALayer()
    /// Device pixels per point (the images' contentsScale).
    private var pixelScale: CGFloat = 2
    /// Where the label sits inside the slot box (vertical lists: leading).
    var alignment: GlassLabelAlignment = .center

    override init() {
        super.init()
        addSublayer(base)
        addSublayer(accent)
        accent.opacity = 0
    }

    override init(layer: Any) { super.init(layer: layer) }   // presentation copies

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImages(base b: NSImage, accent a: NSImage, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, image) in [(base, b), (accent, a)] {
            layer.contents      = image.layerContents(forContentsScale: scale)
            layer.contentsScale = scale
            layer.bounds        = CGRect(origin: .zero, size: image.size)
        }
        pixelScale = max(scale, 1)
        recenter()                 // inside: no implicit position animation
        CATransaction.commit()
    }

    func setActiveness(_ t: CGFloat) {
        accent.opacity = Float(t)
        recenter()   // bounds may have changed this frame
    }

    private func recenter() {
        for l in [base, accent] { l.position = snappedPosition(l) }
    }

    /// Center for `l` whose top-left corner sits on a whole device pixel
    /// in the parent's space (parent origin is itself pixel-aligned).
    private func snappedPosition(_ l: CALayer) -> CGPoint {
        let w = l.bounds.width, h = l.bounds.height
        let s = pixelScale
        let ox = ((frame.minX + x(for: l) - w / 2) * s).rounded() / s
        let oy = ((frame.minY + bounds.midY - h / 2) * s).rounded() / s
        return CGPoint(x: ox - frame.minX + w / 2, y: oy - frame.minY + h / 2)
    }

    private func x(for l: CALayer) -> CGFloat {
        switch alignment {
        case .center:   return bounds.midX
        case .leading:  return l.bounds.width / 2
        case .trailing: return bounds.width - l.bounds.width / 2
        }
    }
}
