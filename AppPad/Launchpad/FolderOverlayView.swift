import AppKit
import QuartzCore

// Opened folder (iOS style).
// - Backdrop: the same material as the panel background; outside the folder the pages get an
//   extra blur that fades in with the opening.
// - Icons keep the page icon size; spacing is half of the page spacing.
// - Too many apps for one sheet → pages (swipe / indicator), like the launcher pages.
// - Name sits above the sheet (outside it), page indicator between name and sheet —
//   the same order as the launcher: search field, indicator, icons.
// - Open: the backdrop grows out of the folder tile while the first 9 mini icons grow into
//   their real positions (one continuous motion); the tile itself is hidden while open.
// - Close: the reverse, ending exactly on the tile's mini icons. Closing while the open morph
//   still runs plays the open morph backwards from where it is (no second set of proxies).
// - Every click counts, no single / double click distinction (a double click is two clicks):
//   open → click → close → click on the tile → open again. A click on the tile while the close
//   morph runs turns it around (reopen from where it is).
final class FolderOverlayView: FlippedView, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    private(set) var isClosing = false
    var onRename: ((String) -> Void)?
    var onEndEditingTitle: (() -> Void)?

    let folderID: String
    let grid: PageGridView
    weak var sourceTile: GridCellView?   // page cell of this folder (hidden while open)

    private let apps: [AppInfo]
    private let outsideBlur = NSVisualEffectView()
    // Dims the blurred pages outside the sheet (child of outsideBlur, so it fades with it):
    // keeps the sheet's edge readable when panel and sheet would otherwise blur to the same tone.
    private let outsideDim = NSView()
    private let backdrop = FolderBackdropView()
    private let content = FolderBoxView()
    private let titleField = FolderTitleField()
    private let pager = PagerView()
    private let indicator = PageIndicatorView()
    // Morph proxies are plain layers here: moving them costs no AppKit view work per frame.
    private let stage = MorphStageView()
    private let columns: Int
    private let cellWidth: CGFloat
    private let rowHeight: CGFloat
    private var originalTitle: String
    private var isAnimating = false
    private(set) var boxFrame: NSRect = .zero
    var initialPage = 0                  // page to show on first layout (kept across reloads)
    var headerGap: CGFloat?              // title bottom → first icon top (set by the launcher)
    private var didApplyInitialPage = false
    // Open morph in flight: its proxies and step function, so a close can run it backwards.
    private var openFlights: [Flight]?
    private var openStep: ((CGFloat) -> Void)?
    private var openProgress: CGFloat = 0
    // Name / title snapshots, reused by the close morph (and the next open of this overlay).
    private var nameSnapshots: [SnapshotKey: CGImage] = [:]
    private var titleSnapshot: (text: String, image: CGImage)?
    // Leftover after a drag out of the folder ended: invisible, must not take clicks.
    var passesClicks = false
    // Click on the tile while the close morph runs: the launcher decides whether to reopen.
    var onReopen: (() -> Void)?
    // Close morph in flight, as a pose by openness (1 = open, 0 = in the tile), so it can turn around.
    private var closePose: ((CGFloat) -> Void)?
    private var closeFlights: [Flight] = []
    private var closeOpenness: CGFloat = 0

    var currentPage: Int { pager.currentPage }

    private static let sidePad: CGFloat = 22
    private static let titleHeight: CGFloat = 32
    private static let titleGap: CGFloat = 14       // name → sheet when there is no indicator
    private static let indicatorHeight: CGFloat = 30
    private static let edgeZone: CGFloat = 30     // drag-to-flip zone at the sheet's sides
    static let cornerRadius: CGFloat = 30

    init(folder: FolderItem, apps: [AppInfo], columns: Int, iconSize: CGFloat, cellWidth: CGFloat, rowHeight: CGFloat) {
        folderID = folder.id
        self.apps = apps
        self.columns = max(1, columns)
        self.cellWidth = cellWidth
        self.rowHeight = rowHeight
        originalTitle = folder.displayName
        let rows = max(1, Int(ceil(Double(apps.count) / Double(max(1, columns)))))
        let gridView = PageGridView(columns: columns, rows: rows, context: .folder(folder.id))
        gridView.fixedCellHeight = rowHeight
        gridView.fixedCellWidth = cellWidth
        gridView.fixedIconSize = iconSize
        grid = gridView
        super.init(frame: .zero)

        titleField.stringValue = folder.displayName
        titleField.font = .systemFont(ofSize: 22, weight: .semibold)
        titleField.alignment = .center
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.isEditable = true
        titleField.delegate = self

        pager.onProgress = { [weak self] progress in self?.indicator.progress = progress }
        indicator.style = Preferences.shared.pageIndicatorStyle
        indicator.isHidden = true      // glass is set up in layout, only for paged folders
        indicator.onSelect = { [weak self] page in self?.pager.scrollTo(page: page, animated: true) }

        outsideBlur.material = .fullScreenUI
        outsideBlur.blendingMode = .withinWindow
        outsideBlur.state = .active
        outsideBlur.alphaValue = 1
        outsideDim.wantsLayer = true
        outsideDim.autoresizingMask = [.width, .height]
        outsideBlur.addSubview(outsideDim)
        addSubview(outsideBlur)
        applyContrastColors()
        addSubview(backdrop)
        addSubview(content)
        content.addSubview(pager)
        addSubview(titleField)       // outside the sheet
        addSubview(indicator)        // between name and sheet
        stage.isHidden = true
        addSubview(stage)            // morph proxies on top of everything

        grid.setEntries(apps.map { GridEntry.app($0) })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Reversible close morph: the tile's whole click area belongs to the overlay (reopen in place,
    // never a second folder from the tile underneath), the rest goes to the pages.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if passesClicks { return nil }
        if closePose != nil {
            guard let tile = sourceTile else { return nil }
            let area = convert(tile.iconRect, from: tile)
            return area.contains(convert(point, from: superview)) ? self : nil
        }
        // Morph running: name / indicator are invisible (alpha 0) but would still take clicks
        // (an invisible rename instead of a close). The overlay itself takes every click then.
        if isAnimating {
            return frame.contains(point) ? self : nil
        }
        // Click on the name (text + small margin) starts renaming; elsewhere outside the sheet closes.
        return super.hitTest(point)
    }

    func boxContains(windowPoint: NSPoint) -> Bool {
        boxFrame.contains(convert(windowPoint, from: nil))
    }

    func beginRenaming() {
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    // Layout (top → bottom): name, [indicator], sheet with the icons; the group is centered.
    // Rows that fit decide the paging: all rows if they fit, otherwise full pages of as many
    // rows as fit. With pages, name → sheet distance = headerGap (half of the launcher's
    // search → icon distance) and the indicator is centered in it.
    // Inside the sheet the first icon is as far from the top edge as from the side edge.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyContrastColors()
        nameSnapshots.removeAll()
        titleSnapshot = nil
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        nameSnapshots.removeAll()
        titleSnapshot = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopTimeline() }
    }

    // Outside darker than the sheet in both appearances (light: subtle, dark: deeper).
    private func applyContrastColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        outsideDim.layer?.backgroundColor = NSColor.black.withAlphaComponent(dark ? 0.28 : 0.14).cgColor
    }

    override func layout() {
        super.layout()
        outsideDim.frame = outsideBlur.bounds
        let icon = grid.fixedIconSize ?? grid.iconSize
        let iconTop = GridCellView.iconTop(cellHeight: rowHeight, iconSize: icon)
        let sideIconInset = Self.sidePad + (cellWidth - icon) / 2
        let sheetPad = max(10, (sideIconInset - iconTop).rounded())
        let indicatorH = Self.indicatorHeight - 6
        let pagedGap = max(headerGap ?? Self.indicatorHeight + 16, indicatorH + 12).rounded()

        let maxGroupHeight = bounds.height * 0.9
        func rowsFitting(gap: CGFloat) -> Int {
            max(1, Int(floor((maxGroupHeight - Self.titleHeight - gap - 2 * sheetPad) / rowHeight)))
        }
        let totalRows = max(1, (apps.count + columns - 1) / columns)
        let isPaged = totalRows > rowsFitting(gap: Self.titleGap)
        let gap = isPaged ? pagedGap : Self.titleGap
        let pageRows = isPaged ? rowsFitting(gap: gap) : totalRows
        let perPage = pageRows * columns
        let pageCount = max(1, (apps.count + perPage - 1) / perPage)

        let gridWidth = CGFloat(columns) * cellWidth
        let pageHeight = CGFloat(pageRows) * rowHeight
        let width = min(bounds.width * 0.9, gridWidth + 2 * Self.sidePad).rounded()
        let height = (pageHeight + 2 * sheetPad).rounded()
        let groupTop = ((bounds.height - (Self.titleHeight + gap + height)) / 2).rounded()
        let boxX = ((bounds.width - width) / 2).rounded()
        boxFrame = NSRect(x: boxX, y: groupTop + Self.titleHeight + gap, width: width, height: height)
        outsideBlur.frame = bounds
        stage.frame = bounds
        if !isAnimating { backdrop.frame = boxFrame }
        content.frame = boxFrame

        let titleWidth = titleFieldWidth()
        titleField.frame = NSRect(x: ((bounds.width - titleWidth) / 2).rounded(), y: groupTop,
                                  width: titleWidth, height: Self.titleHeight)

        // Pager spans the full sheet width so pages slide edge to edge; columns are centered per page.
        grid.pageRows = pageRows
        pager.frame = NSRect(x: 0, y: sheetPad, width: width, height: pageHeight)
        pager.setContent(grid, pageCount: pageCount)
        if !didApplyInitialPage, width > 0 {
            didApplyInitialPage = true
            pager.scrollTo(page: initialPage, animated: false)
        }

        indicator.isHidden = !isPaged
        indicator.style = Preferences.shared.pageIndicatorStyle
        indicator.pageCount = pageCount
        // Glass track is costly to build: only for folders that actually show the indicator.
        indicator.glass = isPaged && Preferences.shared.glassControls
        // Centered between the name's text (its baseline — the field frame has empty space below
        // the glyphs) and the sheet's top edge.
        let textBottom = titleField.frame.minY + titleField.firstBaselineOffsetFromTop
        let center = (textBottom + boxFrame.minY) / 2
        indicator.frame = NSRect(x: boxX + Self.sidePad, y: (center - indicatorH / 2).rounded(),
                                 width: width - 2 * Self.sidePad, height: indicatorH)
    }

    // Name field hugs its text plus a click margin on each side (grows while typing).
    private static let titleHitPad: CGFloat = 15
    private static let titleMinWidth: CGFloat = 30      // keeps an empty name clickable / caret visible

    private func titleFieldWidth() -> CGFloat {
        let text = titleField.currentEditor()?.string ?? titleField.stringValue
        let font = titleField.font ?? .systemFont(ofSize: 22, weight: .semibold)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let width = textWidth + 8 + 2 * Self.titleHitPad      // 8: cell's inner text inset
        return min(max(Self.titleMinWidth, width), max(Self.titleMinWidth, bounds.width - 40)).rounded()
    }

    // Name and indicator live outside the sheet; hidden while the morph runs.
    private func setChromeAlpha(_ alpha: CGFloat) {
        content.alphaValue = alpha
        titleField.alphaValue = alpha
        indicator.alphaValue = alpha
    }

    // MARK: - Paging helpers (used by folder drags)

    // Grid slot under a window point, on the page being shown (or scrolled to).
    func gridSlot(atWindowPoint windowPoint: NSPoint) -> Int {
        let local = pager.convert(windowPoint, from: nil)
        let x = local.x + CGFloat(pager.currentPage) * pager.bounds.width
        return grid.slot(at: NSPoint(x: x, y: local.y))
    }

    // -1 / 1 when the point is in the left / right flip zone and that page exists, else 0.
    func edgeDirection(atWindowPoint windowPoint: NSPoint) -> Int {
        guard pager.pageCount > 1 else { return 0 }
        let x = pager.convert(windowPoint, from: nil).x
        if x < Self.edgeZone, pager.currentPage > 0 { return -1 }
        if x > pager.bounds.width - Self.edgeZone, pager.currentPage < pager.pageCount - 1 { return 1 }
        return 0
    }

    func flipPage(_ direction: Int) {
        pager.scrollTo(page: pager.currentPage + direction, animated: true)
    }

    // Acts on every mouse down, never looks at clickCount: open → close, closing → reopen.
    override func mouseDown(with event: NSEvent) {
        if closePose != nil {
            onReopen?()
            return
        }
        if !boxContains(windowPoint: event.locationInWindow) { onClose?() }
    }

    // Swipes anywhere page the folder; they never leak to the launcher pages underneath.
    override func scrollWheel(with event: NSEvent) {
        pager.scrollWheel(with: event)
    }

    // MARK: - Open / close morph
    // One display-link timeline drives the backdrop, every icon and the outside blur together,
    // so the icons can never run ahead of the folder.
    // Cost per frame is kept to layer geometry: proxies are CALayers with prebuilt contents
    // (cached icon renders, cached name snapshots), not views that resolve images on resize.

    func animateOpen() {
        guard let tile = sourceTile else { return }
        layoutSubtreeIfNeeded()
        flushDeferredCleanup()
        stage.removeAllProxies()
        let plate = convert(tile.visualIconRect, from: tile)
        let box = boxFrame
        let flights = iconFlights(tile: tile, excluding: nil, opening: true)
        let startRadius = plate.width * 0.24

        isAnimating = true
        setChromeAlpha(0)
        // Real grid stays hidden during the morph: its first draw (all icons, all names) is
        // moved off the first frame and lands under the proxies at the end.
        content.isHidden = true
        outsideBlur.alphaValue = 0
        let step: (CGFloat) -> Void = { [weak self, weak tile] p in
            guard let self else { return }
            self.openProgress = p
            self.backdrop.frame = Self.lerp(plate, box, p)
            self.backdrop.setCornerRadius(startRadius + (Self.cornerRadius - startRadius) * p)
            self.outsideBlur.alphaValue = min(1, p)
            tile?.concealedLabelAlpha = 1 - Self.smoothstep(0, 0.4, p)   // page name fades out
            for flight in flights { flight.apply(p, opening: true) }
        }
        openFlights = flights
        openStep = step
        openProgress = 0
        run(duration: 0.46, curve: Self.springOut, step: step, completion: { [weak self] in
            guard let self else { return }
            self.openFlights = nil
            self.openStep = nil
            self.isAnimating = false
            self.backdrop.frame = box
            tile.concealedLabelAlpha = 0
            self.content.isHidden = false
            self.setChromeAlpha(1)
            // Proxies match the real content at its final spots; they stay one more frame so
            // the grid has been drawn before they go (no empty frame in between).
            self.deferredCleanup = flights.map(\.layer)
        })
    }

    // excluding: app index currently dragged out (the tile no longer shows it).
    func animateClose(excludingAppAt excluded: Int? = nil, completion: @escaping () -> Void) {
        guard let tile = sourceTile else {
            completion()
            return
        }
        if let openStep, let openFlights {
            self.openStep = nil
            self.openFlights = nil
            if excluded == nil {
                reverseOpen(step: openStep, flights: openFlights, completion: completion)
                return
            }
            // Drag out while opening (rare): drop the opening proxies, close from the real layout.
            openFlights.forEach { $0.layer.removeFromSuperlayer() }
            content.isHidden = false
        }
        flushDeferredCleanup()
        stage.removeAllProxies()     // no morph is running here: anything left is a stray proxy
        let plate = convert(tile.visualIconRect, from: tile)
        let box = backdrop.frame
        let flights = iconFlights(tile: tile, excluding: excluded, opening: false)
        let endRadius = plate.width * 0.24

        isAnimating = true
        isClosing = true
        setChromeAlpha(0)
        let step: (CGFloat) -> Void = { [weak self, weak tile] p in
            guard let self else { return }
            self.backdrop.frame = Self.lerp(box, plate, p)
            self.backdrop.setCornerRadius(Self.cornerRadius + (endRadius - Self.cornerRadius) * p)
            self.outsideBlur.alphaValue = max(0, 1 - p)
            tile?.concealedLabelAlpha = Self.smoothstep(0.55, 1, p)      // page name fades back in
            for flight in flights { flight.apply(p, opening: false) }
        }
        // Drag-out close (excluded app) is never reopened: the overlay stays for the drag.
        if excluded == nil {
            closePose = { o in step(1 - o) }
            closeFlights = flights
            closeOpenness = 1
        }
        run(duration: 0.32, curve: Self.easeInOut, step: { [weak self] p in
            self?.closeOpenness = 1 - p
            step(p)
        }, completion: { [weak self] in
            guard let self else { return }
            self.endClosing()
            // Hand over to the tile: it reappears exactly where the morph ended.
            self.sourceTile?.isConcealed = false
            self.sourceTile?.concealedLabelAlpha = 0
            self.backdrop.alphaValue = 0
            flights.forEach { $0.layer.removeFromSuperlayer() }
            self.hideStageIfEmpty()
            completion()
        })
    }

    // Close during the open morph: run the open step from its current progress back to 0,
    // so every proxy turns around where it is.
    private func reverseOpen(step: @escaping (CGFloat) -> Void, flights: [Flight], completion: @escaping () -> Void) {
        let from = openProgress
        isAnimating = true
        isClosing = true
        setChromeAlpha(0)
        closePose = step                 // open step is already a pose by openness
        closeFlights = flights
        closeOpenness = from
        run(duration: max(0.16, 0.32 * Double(min(1, from))), curve: Self.easeInOut, step: { [weak self] q in
            let o = from * (1 - q)
            self?.closeOpenness = o
            step(o)
        }, completion: { [weak self] in
            guard let self else { return }
            self.endClosing()
            self.sourceTile?.isConcealed = false
            self.sourceTile?.concealedLabelAlpha = 0
            self.backdrop.alphaValue = 0
            self.outsideBlur.alphaValue = 0
            flights.forEach { $0.layer.removeFromSuperlayer() }
            self.hideStageIfEmpty()
            completion()
        })
    }

    // Click on the tile mid-close: run the close pose back to fully open from where it is.
    // Returns false when this close cannot turn around (drag out / already finished).
    @discardableResult
    func reopen() -> Bool {
        guard let pose = closePose else { return false }
        let from = closeOpenness
        let flights = closeFlights
        endClosing()
        let box = boxFrame
        isAnimating = true
        // Registered as an open in flight: a close during the reopen reuses these proxies
        // (reverseOpen) instead of building a second set on top of them.
        let step: (CGFloat) -> Void = { [weak self] o in
            self?.openProgress = o
            pose(o)
        }
        openStep = step
        openFlights = flights
        openProgress = from
        run(duration: max(0.2, 0.46 * Double(1 - from)), curve: Self.springOut, step: { o in
            step(from + (1 - from) * o)
        }, completion: { [weak self] in
            guard let self else { return }
            self.openStep = nil
            self.openFlights = nil
            self.isAnimating = false
            self.backdrop.frame = box
            self.backdrop.setCornerRadius(Self.cornerRadius)
            self.backdrop.alphaValue = 1
            self.outsideBlur.alphaValue = 1
            self.sourceTile?.concealedLabelAlpha = 0
            self.content.isHidden = false
            self.setChromeAlpha(1)
            // Same hand-over as the open: proxies leave one frame after the real grid shows.
            self.deferredCleanup = flights.map(\.layer)
        })
        return true
    }

    private func endClosing() {
        isClosing = false
        closePose = nil
        closeFlights = []
    }

    // MARK: - Timeline

    private var link: CADisplayLink?
    private var timelineStart: CFTimeInterval?     // set on the first frame
    private var timelineDuration: Double = 0
    private var timelineCurve: (Double) -> Double = { $0 }
    private var timelineStep: ((CGFloat) -> Void)?
    private var timelineDone: (() -> Void)?
    private var deferredCleanup: [CALayer] = []

    private func run(duration: Double, curve: @escaping (Double) -> Double,
                     step: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        link?.invalidate()
        link = nil
        flushDeferredCleanup()
        // The clock starts on the first display frame, not now: setup work and the first
        // commit can take a while, and starting earlier would skip the start of the motion.
        timelineStart = nil
        timelineDuration = duration
        timelineCurve = curve
        timelineStep = step
        timelineDone = completion
        step(0)
        let newLink = displayLink(target: self, selector: #selector(tick(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    // The last step and the completion (proxy → real view swap) share one transaction,
    // so the swap lands in the same frame as the final pose.
    @objc private func tick(_ displayLink: CADisplayLink) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let step = timelineStep else {
            // One frame after the end: leftover proxies go.
            flushDeferredCleanup()
            stopLink()
            return
        }
        let start = timelineStart ?? displayLink.timestamp
        timelineStart = start
        let t = min(1, (displayLink.targetTimestamp - start) / timelineDuration)
        step(CGFloat(t >= 1 ? 1 : timelineCurve(t)))
        if t >= 1 {
            let done = timelineDone
            timelineStep = nil
            timelineDone = nil
            done?()
            if deferredCleanup.isEmpty { stopLink() }
        }
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    private func flushDeferredCleanup() {
        guard !deferredCleanup.isEmpty else { return }
        deferredCleanup.forEach { $0.removeFromSuperlayer() }
        deferredCleanup.removeAll()
        hideStageIfEmpty()
    }

    private func hideStageIfEmpty() {
        if stage.layer?.sublayers?.isEmpty ?? true { stage.isHidden = true }
    }

    // Removed from the window mid-morph: no frames will come, finish without animating.
    private func stopTimeline() {
        stopLink()
        flushDeferredCleanup()
    }

    // Critically damped spring, normalised to reach 1 at t = 1.
    nonisolated private static func springOut(_ t: Double) -> Double {
        let omega = 9.0
        let value = 1 - (1 + omega * t) * exp(-omega * t)
        let end = 1 - (1 + omega) * exp(-omega)
        return value / end
    }

    nonisolated private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // 0 below a, 1 above b, smooth in between.
    fileprivate static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    fileprivate static func lerp(_ a: NSRect, _ b: NSRect, _ p: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * p,
               y: a.minY + (b.minY - a.minY) * p,
               width: a.width + (b.width - a.width) * p,
               height: a.height + (b.height - a.height) * p)
    }

    // How a proxy's opacity follows the morph progress p.
    fileprivate enum Fade {
        case none       // icons landing on their mini slot: always opaque
        case whole      // icons not shown in the tile: linear fade
        case text       // names / title: appear late when opening, vanish early when closing

        func alpha(_ p: CGFloat, opening: Bool) -> CGFloat {
            switch self {
            case .none: return 1
            case .whole: return opening ? min(1, p) : max(0, 1 - p)
            case .text:
                return opening ? FolderOverlayView.smoothstep(0.45, 1, p)
                               : 1 - FolderOverlayView.smoothstep(0, 0.5, p)
            }
        }
    }

    private struct Flight {
        let layer: CALayer
        let start: NSRect
        let end: NSRect
        let fade: Fade
        let fullWidth: CGFloat      // icons: real width (filter choice); 0 for names

        func apply(_ p: CGFloat, opening: Bool) {
            let rect = FolderOverlayView.lerp(start, end, p)
            layer.frame = rect
            layer.opacity = Float(fade.alpha(p, opening: opening))
            // Mipmaps only when strongly shrunk; near full size match the live image view.
            if fullWidth > 0 {
                let filter: CALayerContentsFilter = rect.width < fullWidth * 0.5 ? .trilinear : .linear
                if layer.minificationFilter != filter { layer.minificationFilter = filter }
            }
        }
    }

    private struct SnapshotKey: Hashable {
        let cell: ObjectIdentifier
        let selected: Bool
        let dropTarget: Bool
    }

    // Proxies flying between the folder tile and their real spots.
    // Each cell is split in two proxies with the same motion: the icon part and the name part.
    // The name fades (in late when opening, out early when closing) instead of popping at the
    // tiny end size. The folder title flies and fades the same way.
    // - first 9 apps: the icon part lands exactly on its mini icon in the tile
    // - other apps: mapped from the box onto the tile (uniform scale), fading
    private func iconFlights(tile: GridCellView, excluding excluded: Int?, opening: Bool) -> [Flight] {
        let plate = convert(tile.visualIconRect, from: tile)
        let box = boxFrame
        let boxScale = plate.width / max(box.width, 1)
        let visibleArea = convert(pager.bounds, from: pager)   // cells of the shown page only
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        // Box space → tile space (uniform, centered).
        func collapsed(_ rect: NSRect) -> NSRect {
            NSRect(x: plate.midX + (rect.minX - box.midX) * boxScale,
                   y: plate.midY + (rect.minY - box.midY) * boxScale,
                   width: rect.width * boxScale, height: rect.height * boxScale)
        }

        stage.isHidden = false
        var flights: [Flight] = []
        func addProxy(contents: Any, scale: CGFloat, real: NSRect, small: NSRect, fade: Fade, isIcon: Bool) {
            let layer = MorphStageView.makeLayer(contents: contents, scale: scale, mipmapped: isIcon)
            let start = opening ? small : real
            layer.frame = start
            layer.opacity = Float(fade.alpha(0, opening: opening))
            stage.add(layer)
            flights.append(Flight(layer: layer, start: start, end: opening ? real : small,
                                  fade: fade, fullWidth: isIcon ? real.width : 0))
        }

        for (index, cell) in grid.cells.enumerated() where index != excluded {
            let cellRect = convert(cell.bounds, from: cell)
            guard visibleArea.intersects(cellRect) else { continue }
            let tileIndex = (excluded != nil && index > excluded!) ? index - 1 : index

            // Same mapping for both parts of the cell.
            let shrink: (NSRect) -> NSRect
            if tileIndex < 9 {
                // Scale so the icon matches the mini icon.
                let iconRect = convert(cell.iconRect, from: cell)
                let mini = convert(tile.folderMiniRect(index: tileIndex), from: tile)
                let scale = mini.width / max(iconRect.width, 1)
                shrink = { r in
                    NSRect(x: mini.minX + (r.minX - iconRect.minX) * scale,
                           y: mini.minY + (r.minY - iconRect.minY) * scale,
                           width: r.width * scale, height: r.height * scale)
                }
            } else {
                shrink = collapsed
            }

            // Icon: not a bitmap snapshot (cacheDisplay renders it duller than the live icon).
            // The same NSImage, turned into layer contents the way an image view does it.
            let iconReal = convert(cell.iconRect, from: cell)
            let icon = iconContents(index: index, cell: cell, scale: backingScale)
            addProxy(contents: icon.contents, scale: icon.scale, real: iconReal, small: shrink(iconReal),
                     fade: tileIndex < 9 ? .none : .whole, isIcon: true)
            // Name: snapshot below the middle of the icon → name gap (cell coordinates, flipped).
            let split = (cell.iconRect.maxY + GridCellView.gap / 2).rounded()
            let namePart = NSRect(x: 0, y: split, width: cell.bounds.width, height: cell.bounds.height - split)
            let nameReal = convert(namePart, from: cell)
            if let name = nameSnapshot(cell, part: namePart) {
                addProxy(contents: name, scale: backingScale, real: nameReal, small: shrink(nameReal),
                         fade: .text, isIcon: false)
            }
        }

        let titleRect = convert(titleField.bounds, from: titleField)
        if let title = titleImage() {
            addProxy(contents: title, scale: backingScale, real: titleRect, small: collapsed(titleRect),
                     fade: .text, isIcon: false)
        }
        return flights
    }

    // Apps: cached per app (shared with the launcher warm-up); anything else rendered on the spot.
    private func iconContents(index: Int, cell: GridCellView, scale: CGFloat) -> (contents: Any, scale: CGFloat) {
        if grid.entries.indices.contains(index), case .app(let app) = grid.entries[index] {
            return IconCache.shared.layerContents(for: app, scale: scale)
        }
        let image = cell.snapshotIcon()
        let contentsScale = image.recommendedLayerContentsScale(scale)
        return (image.layerContents(forContentsScale: contentsScale), contentsScale)
    }

    private func nameSnapshot(_ cell: GridCellView, part: NSRect) -> CGImage? {
        let key = SnapshotKey(cell: ObjectIdentifier(cell), selected: cell.isSelected, dropTarget: cell.isDropTarget)
        if let hit = nameSnapshots[key] { return hit }
        guard let image = snapshot(cell, rect: part) else { return nil }
        nameSnapshots[key] = image
        return image
    }

    private func titleImage() -> CGImage? {
        let text = titleField.stringValue
        if let titleSnapshot, titleSnapshot.text == text { return titleSnapshot.image }
        guard let image = snapshot(titleField, rect: titleField.bounds) else { return nil }
        titleSnapshot = (text, image)
        return image
    }

    private func snapshot(_ view: NSView, rect: NSRect) -> CGImage? {
        guard rect.width > 0, rect.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        return rep.cgImage
    }

    // MARK: - Title editing

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            titleField.stringValue = originalTitle
            window?.makeFirstResponder(nil)
            onEndEditingTitle?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        logTitle("begin")
    }

    func controlTextDidChange(_ obj: Notification) {
        needsLayout = true      // re-fit the name field to the typed text
        DispatchQueue.main.async { [weak self] in self?.logTitle("change") }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let name = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            titleField.stringValue = originalTitle
        } else if name != originalTitle {
            originalTitle = name
            onRename?(name)
        }
        needsLayout = true      // name may have been reverted / trimmed
        onEndEditingTitle?()
        DispatchQueue.main.async { [weak self] in self?.logTitle("end") }
    }

    // DEBUG: title geometry while editing vs displayed; remove once the Enter shift is fixed.
    private func logTitle(_ tag: String) {
        let cell = titleField.cell
        let font = titleField.font ?? .systemFont(ofSize: 22, weight: .semibold)
        let textWidth = (titleField.stringValue as NSString).size(withAttributes: [.font: font]).width
        var line = "[FolderTitle] \(tag) text=\(titleField.stringValue) textW=\(textWidth)"
        line += " field=\(convert(titleField.bounds, from: titleField))"
        if let cell { line += " cellTitleRect=\(convert(cell.titleRect(forBounds: titleField.bounds), from: titleField))" }
        line += " align=\(titleField.alignment.rawValue) scroll=\(cell?.isScrollable ?? false) wraps=\(cell?.wraps ?? false)"
        if let tv = titleField.currentEditor() as? NSTextView {
            line += " editor=\(convert(tv.bounds, from: tv)) tvAlign=\(tv.alignment.rawValue) hRes=\(tv.isHorizontallyResizable)"
            if let clip = tv.superview { line += " clip=\(convert(clip.bounds, from: clip))" }
            if let lm = tv.layoutManager, let tc = tv.textContainer {
                let used = lm.usedRect(for: tc).offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y)
                line += " used=\(convert(used, from: tv)) pad=\(tc.lineFragmentPadding)"
            }
        }
        NSLog("%@", line)
    }
}

// Folder name field: AppKit resets the cell alignment to left when editing ends via Enter,
// so the centered alignment is restored right after.
final class FolderTitleField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CrispTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        alignment = .center
    }
}

// Folder backdrop: same material as the panel background (inherits its appearance),
// with a light tint (brighter than the panel) and a hairline edge so the folder reads as a
// separate sheet even over a pale, translucent panel background.
final class FolderBackdropView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = FolderOverlayView.cornerRadius

        blur.material = .fullScreenUI
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)

        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyColors()
    }

    // Light: brighter sheet + faint dark edge; dark: gentle lift + faint light edge.
    private func applyColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        tint.layer?.backgroundColor = NSColor.white.withAlphaComponent(dark ? 0.14 : 0.3).cgColor
        layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.18)
                                   : NSColor.black.withAlphaComponent(0.1)).cgColor
        layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)   // one device pixel
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
    }

    func setCornerRadius(_ radius: CGFloat) {
        layer?.cornerRadius = radius
    }
}

// Content container (transparent); swallows clicks inside the box.
final class FolderBoxView: FlippedView {
    override func mouseDown(with event: NSEvent) {}
}

// Layer-hosting stage for the morph proxies (plain CALayers, no views).
// Sublayer space is made y-down like the flipped overlay; image layers are flipped back
// so their contents stay upright, whatever flip the ancestor layers carry.
final class MorphStageView: NSView {
    private let root = CALayer()

    private static let noActions: [String: CAAction] = {
        var actions: [String: CAAction] = [:]
        for key in ["position", "bounds", "frame", "opacity", "contents", "hidden", "transform",
                    "minificationFilter", "sublayers", "onOrderIn", "onOrderOut"] {
            actions[key] = NSNull()
        }
        return actions
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        root.actions = Self.noActions
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func makeLayer(contents: Any, scale: CGFloat, mipmapped: Bool) -> CALayer {
        let layer = CALayer()
        layer.actions = noActions
        layer.contents = contents
        layer.contentsScale = scale
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .linear
        layer.minificationFilter = mipmapped ? .trilinear : .linear
        return layer
    }

    func removeAllProxies() {
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    func add(_ layer: CALayer) {
        // y-down sublayer space (matches the flipped overlay coordinates).
        if root.superlayer != nil, !root.contentsAreFlipped() { root.isGeometryFlipped.toggle() }
        root.addSublayer(layer)
        // Upright contents.
        if layer.contentsAreFlipped() { layer.isGeometryFlipped.toggle() }
    }
}
