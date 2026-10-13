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
final class FolderOverlayView: FlippedView, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onEndEditingTitle: (() -> Void)?

    let folderID: String
    let grid: PageGridView
    weak var sourceTile: GridCellView?   // page cell of this folder (hidden while open)

    private let apps: [AppInfo]
    private let outsideBlur = NSVisualEffectView()
    private let backdrop = FolderBackdropView()
    private let content = FolderBoxView()
    private let titleField = CrispTextField()
    private let pager = PagerView()
    private let indicator = PageIndicatorView()
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
    // Leftover after a drag out of the folder ended: invisible, must not take clicks.
    var passesClicks = false

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
        indicator.glass = Preferences.shared.glassControls
        indicator.isHidden = true
        indicator.onSelect = { [weak self] page in self?.pager.scrollTo(page: page, animated: true) }

        outsideBlur.material = .fullScreenUI
        outsideBlur.blendingMode = .withinWindow
        outsideBlur.state = .active
        outsideBlur.alphaValue = 1
        addSubview(outsideBlur)
        addSubview(backdrop)
        addSubview(content)
        content.addSubview(pager)
        addSubview(titleField)       // outside the sheet
        addSubview(indicator)        // between name and sheet

        grid.setEntries(apps.map { GridEntry.app($0) })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesClicks ? nil : super.hitTest(point)
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
    override func layout() {
        super.layout()
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
        indicator.glass = Preferences.shared.glassControls
        indicator.pageCount = pageCount
        // Centered between the name's text (its baseline — the field frame has empty space below
        // the glyphs) and the sheet's top edge.
        let textBottom = titleField.frame.minY + titleField.firstBaselineOffsetFromTop
        let center = (textBottom + boxFrame.minY) / 2
        indicator.frame = NSRect(x: boxX + Self.sidePad, y: (center - indicatorH / 2).rounded(),
                                 width: width - 2 * Self.sidePad, height: indicatorH)
    }

    // Name field hugs its text plus a click margin on each side (grows while typing).
    private static let titleHitPad: CGFloat = 20
    private static let titleMinWidth: CGFloat = 80

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

    // The 2nd click of a double click on the folder tile lands here (same spot, clickCount ≥ 2):
    // it belongs to the opening, so it must not close the folder again.
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else { return }
        if !boxContains(windowPoint: event.locationInWindow) { onClose?() }
    }

    // Swipes anywhere page the folder; they never leak to the launcher pages underneath.
    override func scrollWheel(with event: NSEvent) {
        pager.scrollWheel(with: event)
    }

    // MARK: - Open / close morph
    // One display-link timeline drives the backdrop, every icon and the outside blur together,
    // so the icons can never run ahead of the folder.

    func animateOpen() {
        guard let tile = sourceTile else { return }
        layoutSubtreeIfNeeded()
        let plate = convert(tile.visualIconRect, from: tile)
        let box = boxFrame
        let flights = iconFlights(tile: tile, excluding: nil, opening: true)
        let startRadius = plate.width * 0.24

        isAnimating = true
        setChromeAlpha(0)
        outsideBlur.alphaValue = 0
        let step: (CGFloat) -> Void = { [weak self, weak tile] p in
            guard let self else { return }
            self.openProgress = p
            self.backdrop.frame = Self.lerp(plate, box, p)
            self.backdrop.setCornerRadius(startRadius + (Self.cornerRadius - startRadius) * p)
            self.outsideBlur.alphaValue = min(1, p)
            tile?.concealedLabelAlpha = 1 - Self.smoothstep(0, 0.4, p)   // page name fades out
            for flight in flights {
                flight.view.frame = Self.lerp(flight.start, flight.end, p)
                flight.view.alphaValue = flight.fade.alpha(p, opening: true)
            }
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
            // Proxies are pixel snapshots of the real content at its final spots: swap instantly.
            self.setChromeAlpha(1)
            flights.forEach { $0.view.removeFromSuperview() }
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
            openFlights.forEach { $0.view.removeFromSuperview() }
        }
        let plate = convert(tile.visualIconRect, from: tile)
        let box = backdrop.frame
        let flights = iconFlights(tile: tile, excluding: excluded, opening: false)
        let endRadius = plate.width * 0.24

        isAnimating = true
        setChromeAlpha(0)
        run(duration: 0.32, curve: Self.easeInOut, step: { [weak self] p in
            guard let self else { return }
            self.backdrop.frame = Self.lerp(box, plate, p)
            self.backdrop.setCornerRadius(Self.cornerRadius + (endRadius - Self.cornerRadius) * p)
            self.outsideBlur.alphaValue = max(0, 1 - p)
            tile.concealedLabelAlpha = Self.smoothstep(0.55, 1, p)       // page name fades back in
            for flight in flights {
                flight.view.frame = Self.lerp(flight.start, flight.end, p)
                flight.view.alphaValue = flight.fade.alpha(p, opening: false)
            }
        }, completion: { [weak self] in
            guard let self else { return }
            // Hand over to the tile: it reappears exactly where the morph ended.
            self.sourceTile?.isConcealed = false
            self.sourceTile?.concealedLabelAlpha = 0
            self.backdrop.alphaValue = 0
            flights.forEach { $0.view.removeFromSuperview() }
            completion()
        })
    }

    // Close during the open morph: run the open step from its current progress back to 0,
    // so every proxy turns around where it is.
    private func reverseOpen(step: @escaping (CGFloat) -> Void, flights: [Flight], completion: @escaping () -> Void) {
        let from = openProgress
        isAnimating = true
        setChromeAlpha(0)
        run(duration: max(0.16, 0.32 * Double(min(1, from))), curve: Self.easeInOut, step: { q in
            step(from * (1 - q))
        }, completion: { [weak self] in
            guard let self else { return }
            self.sourceTile?.isConcealed = false
            self.sourceTile?.concealedLabelAlpha = 0
            self.backdrop.alphaValue = 0
            self.outsideBlur.alphaValue = 0
            flights.forEach { $0.view.removeFromSuperview() }
            completion()
        })
    }

    // MARK: - Timeline

    private var link: CADisplayLink?
    private var timelineStart: CFTimeInterval = 0
    private var timelineDuration: Double = 0
    private var timelineCurve: (Double) -> Double = { $0 }
    private var timelineStep: ((CGFloat) -> Void)?
    private var timelineDone: (() -> Void)?

    private func run(duration: Double, curve: @escaping (Double) -> Double,
                     step: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        link?.invalidate()
        timelineStart = CACurrentMediaTime()
        timelineDuration = duration
        timelineCurve = curve
        timelineStep = step
        timelineDone = completion
        step(0)
        let newLink = displayLink(target: self, selector: #selector(tick(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        let t = min(1, (CACurrentMediaTime() - timelineStart) / timelineDuration)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        timelineStep?(CGFloat(t >= 1 ? 1 : timelineCurve(t)))
        CATransaction.commit()
        guard t >= 1 else { return }
        link?.invalidate()
        link = nil
        let done = timelineDone
        timelineStep = nil
        timelineDone = nil
        done?()
    }

    // Critically damped spring, normalised to reach 1 at t = 1.
    private static func springOut(_ t: Double) -> Double {
        let omega = 9.0
        let value = 1 - (1 + omega * t) * exp(-omega * t)
        let end = 1 - (1 + omega) * exp(-omega)
        return value / end
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // 0 below a, 1 above b, smooth in between.
    fileprivate static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: NSRect, _ b: NSRect, _ p: CGFloat) -> NSRect {
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
        let view: NSView
        let start: NSRect
        let end: NSRect
        let fade: Fade
    }

    // Snapshot proxies flying between the folder tile and their real spots.
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

        // Box space → tile space (uniform, centered).
        func collapsed(_ rect: NSRect) -> NSRect {
            NSRect(x: plate.midX + (rect.minX - box.midX) * boxScale,
                   y: plate.midY + (rect.minY - box.midY) * boxScale,
                   width: rect.width * boxScale, height: rect.height * boxScale)
        }

        var flights: [Flight] = []
        func addFlight(snapshotOf view: NSView, part: NSRect, real: NSRect, small: NSRect, fade: Fade) {
            guard let image = snapshot(view, rect: part) else { return }
            let proxy = IconProxyView(image: image)
            proxy.frame = opening ? small : real
            proxy.alphaValue = fade.alpha(0, opening: opening)
            addSubview(proxy)
            proxy.fixOrientation()
            flights.append(Flight(view: proxy, start: opening ? small : real, end: opening ? real : small, fade: fade))
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

            // Split at the middle of the icon → name gap (cell coordinates, flipped).
            let split = (cell.iconRect.maxY + GridCellView.gap / 2).rounded()
            let iconPart = NSRect(x: 0, y: 0, width: cell.bounds.width, height: split)
            let namePart = NSRect(x: 0, y: split, width: cell.bounds.width, height: cell.bounds.height - split)
            let iconReal = convert(iconPart, from: cell)
            let nameReal = convert(namePart, from: cell)
            addFlight(snapshotOf: cell, part: iconPart, real: iconReal, small: shrink(iconReal),
                      fade: tileIndex < 9 ? .none : .whole)
            addFlight(snapshotOf: cell, part: namePart, real: nameReal, small: shrink(nameReal), fade: .text)
        }

        let titleRect = convert(titleField.bounds, from: titleField)
        addFlight(snapshotOf: titleField, part: titleField.bounds, real: titleRect, small: collapsed(titleRect), fade: .text)
        return flights
    }

    private func snapshot(_ view: NSView, rect: NSRect) -> NSImage? {
        guard rect.width > 0, rect.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
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

    func controlTextDidChange(_ obj: Notification) {
        needsLayout = true      // re-fit the name field to the typed text
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
    }
}

// Folder backdrop: same material as the panel background (inherits its appearance),
// with a light tint (brighter than the panel) so the folder reads as a separate sheet.
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
        tint.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
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

// Layer-hosting image view: contents scale with the frame (no NSImageView layout drift).
final class IconProxyView: NSView {
    init(image: NSImage) {
        super.init(frame: .zero)
        let hosted = CALayer()
        hosted.contents = image
        hosted.contentsGravity = .resizeAspect
        hosted.magnificationFilter = .linear
        hosted.minificationFilter = .trilinear
        layer = hosted
        wantsLayer = true
    }

    // A hosted layer inside flipped AppKit views renders its contents upside down;
    // flip it back once it is in the layer tree.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        fixOrientation()
    }

    func fixOrientation() {
        guard let layer, layer.superlayer != nil, layer.contentsAreFlipped() else { return }
        layer.isGeometryFlipped.toggle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
