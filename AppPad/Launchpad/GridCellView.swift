import AppKit
import QuartzCore
import SwiftUI   // RoundedRectangle(.continuous) for the app-icon squircle

enum DeleteBadgeKind {
    case none
    case appStore   // gray ×: plain move to Trash
    case other      // orange ×: uninstall with leftover cleanup
}

// One icon + label cell (app or folder).
// Click → open, long press → edit mode, drag → move. Events go to the owning grid.
final class GridCellView: FlippedView {
    weak var grid: PageGridView? {
        didSet { updateLabelShadow() }
    }
    var index = 0

    var iconSize: CGFloat = 64 {
        didSet { if oldValue != iconSize { needsLayout = true } }
    }
    var isSelected = false {
        didSet { if oldValue != isSelected { needsDisplay = true } }
    }
    var isDropTarget = false {
        didSet { if oldValue != isDropTarget { needsDisplay = true } }
    }
    // Dragged away: the spot is simply empty. Only alpha is used — a hidden view would stop
    // receiving the mouseDragged / mouseUp events of the running drag.
    var isDragSource = false {
        didSet { updateVisibility() }
    }
    // Folder tile while its folder is open (the folder "moved" into the overlay):
    // the icon is hidden, the name shows at concealedLabelAlpha (faded by the folder morph).
    var isConcealed = false {
        didSet { updateVisibility() }
    }
    var concealedLabelAlpha: CGFloat = 0 {
        didSet { if isConcealed { label.alphaValue = concealedLabelAlpha } }
    }

    private let iconContainer = FlippedView()
    private let imageView = NSImageView()
    private let folderIcon = FolderIconView()
    private let badge = DeleteBadgeView()
    private let label = CrispTextField(labelWithString: "")

    private var isEditing = false
    private var badgeKind: DeleteBadgeKind = .none
    private var isPressed = false {
        didSet { updateVisibility() }
    }
    private var mouseDownPoint: NSPoint = .zero
    private var isTracking = false      // a mouseDown really started on this cell
    private var isDragging = false
    private var longPressFired = false
    private var longPressTask: Task<Void, Never>?

    static let labelHeight: CGFloat = 16
    static let gap: CGFloat = 6
    private static let badgeSize: CGFloat = 20
    private static let containerInset: CGFloat = 8

    // Top of the icon inside a cell of the given height.
    static func iconTop(cellHeight: CGFloat, iconSize: CGFloat) -> CGFloat {
        max(0, (cellHeight - (iconSize + gap + labelHeight)) / 2)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconContainer.wantsLayer = true
        imageView.wantsLayer = true      // own layer right away: the emerge animation needs it on a fresh cell
        imageView.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        folderIcon.isHidden = true
        badge.isHidden = true
        badge.onTap = { [weak self] in
            guard let self else { return }
            self.grid?.cellDidRequestDelete(self)
        }
        iconContainer.addSubview(imageView)
        iconContainer.addSubview(folderIcon)
        iconContainer.addSubview(badge)
        addSubview(iconContainer)
        addSubview(label)
        updateLabelShadow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateVisibility() {
        alphaValue = isDragSource ? 0 : 1
        iconContainer.alphaValue = isConcealed ? 0 : (isPressed ? 0.6 : 1)
        label.alphaValue = isConcealed ? concealedLabelAlpha : 1
    }

    func configure(_ entry: GridEntry) {
        switch entry {
        case .app(let app):
            imageView.image = IconCache.shared.icon(for: app)
            imageView.isHidden = false
            folderIcon.isHidden = true
            label.stringValue = app.name
        case .folder(let folder, let apps):
            folderIcon.icons = apps.prefix(9).map { IconCache.shared.icon(for: $0) }
            imageView.isHidden = true
            folderIcon.isHidden = false
            label.stringValue = folder.displayName
        }
    }

    // Folder tile preview (e.g. without the app currently dragged out of it).
    func setFolderIcons(_ icons: [NSImage]) {
        folderIcon.hiddenIndex = nil
        folderIcon.icons = icons
    }

    // Show this cell as a folder tile (also for an app that is about to become a folder),
    // with one slot kept empty for the icon landing in it.
    func showFolderPreview(icons: [NSImage], hiddenIndex: Int?) {
        imageView.isHidden = true
        folderIcon.isHidden = false
        folderIcon.icons = icons
        folderIcon.hiddenIndex = hiddenIndex
    }

    // Mini slot rect (cell coordinates); nil index = a mini-sized rect at the tile center.
    func folderMiniRect(index: Int?) -> NSRect {
        let plate = folderIcon.bounds
        var rect = FolderIconView.miniRect(index: index ?? 4, in: plate)
        if index == nil {
            rect.origin = NSPoint(x: plate.midX - rect.width / 2, y: plate.midY - rect.height / 2)
        }
        return convert(rect, from: folderIcon)
    }

    // Hosts the icon flying into this tile (merge drop) so it follows the tile's slide and wiggle.
    // cellFrame is in cell coordinates; returns the host view for converting further rects.
    @discardableResult
    func hostLandingView(_ view: NSView, cellFrame: NSRect) -> NSView {
        view.removeFromSuperview()
        view.frame = iconContainer.convert(cellFrame, from: self)
        iconContainer.addSubview(view)
        return iconContainer
    }

    // Folder dissolve: slow enough to follow the icon growing (a strong ease-out looked instant).
    static let emergeDuration: CFTimeInterval = 0.8

    // Folder with one app left dissolved into this app cell: the icon grows out of the folder's
    // first mini slot while the leftover plate widens and fades, and the app name fades in.
    func animateEmergeFromFolder(duration: CFTimeInterval = GridCellView.emergeDuration) {
        layoutSubtreeIfNeeded()
        guard !imageView.isHidden, let iconLayer = imageView.layer else { return }
        // Gentle ease-in-out: the growth stays visible over the whole duration.
        let timing = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.25, 1)
        let mini = iconContainer.convert(folderMiniRect(index: 0), from: self)

        let plate = FolderIconView(frame: folderIcon.frame)
        plate.wantsLayer = true
        iconContainer.addSubview(plate, positioned: .below, relativeTo: imageView)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let iconStart = Self.transform(for: imageView, showingAt: mini)
        let plateEnd = Self.transform(for: plate, showingAt: imageView.frame)

        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: iconStart)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = duration
        grow.timingFunction = timing
        grow.fillMode = .both
        iconLayer.add(grow, forKey: "emerge")

        if let plateLayer = plate.layer {
            let widen = CABasicAnimation(keyPath: "transform")
            widen.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            widen.toValue = NSValue(caTransform3D: plateEnd)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [widen, fade]
            group.duration = duration
            group.timingFunction = timing
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            plateLayer.add(group, forKey: "dissolve")
        }
        CATransaction.commit()

        label.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            label.animator().alphaValue = 1
        }
        Task { [weak plate] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 50))
            plate?.removeFromSuperview()
        }
    }

    // Layer transform that makes `view` (at its current frame) appear at `rect` (same superview).
    // Start / end are read in layer space by briefly setting the frame, so flipping cannot matter.
    private static func transform(for view: NSView, showingAt rect: NSRect) -> CATransform3D {
        guard let layer = view.layer else { return CATransform3DIdentity }
        let original = view.frame
        let end = layer.frame
        view.frame = rect
        let start = layer.frame
        view.frame = original
        let scale = start.width / max(end.width, 1)
        let anchor = layer.anchorPoint
        let dx = (start.minX - end.minX) - (1 - scale) * anchor.x * end.width
        let dy = (start.minY - end.minY) - (1 - scale) * anchor.y * end.height
        return CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), scale, scale, 1)
    }

    func setEditing(_ editing: Bool, badge kind: DeleteBadgeKind) {
        badgeKind = kind
        isEditing = editing
        badge.kind = kind
        badge.isHidden = !editing || kind == .none
        if editing { startWiggle() } else { iconContainer.layer?.removeAnimation(forKey: "wiggle") }
    }

    // Image for the floating drag icon. Rendered the same way as the live cell (no bitmap
    // snapshot), so the landing can swap to the real cell without any visible change:
    // app → the very same NSImage; folder → drawn by the same code as FolderIconView.
    func snapshotIcon() -> NSImage {
        if !imageView.isHidden, let image = imageView.image { return image }
        let icons = Array(folderIcon.icons.prefix(9))
        let appearance = folderIcon.effectiveAppearance
        let size = folderIcon.bounds.size
        return NSImage(size: size, flipped: true) { rect in
            appearance.performAsCurrentDrawingAppearance {
                FolderIconView.drawTile(in: rect, icons: icons, hiddenIndex: nil)
            }
            return true
        }
    }

    // Icon rect in this cell's coordinates.
    var iconRect: NSRect {
        let top = Self.iconTop(cellHeight: bounds.height, iconSize: iconSize)
        return NSRect(x: (bounds.width - iconSize) / 2, y: top, width: iconSize, height: iconSize)
    }

    // What is actually drawn: folders are a plate inset 6% inside the icon rect.
    static let folderInset: CGFloat = 0.06

    var visualIconRect: NSRect {
        folderIcon.isHidden ? iconRect : iconRect.insetBy(dx: iconSize * Self.folderInset, dy: iconSize * Self.folderInset)
    }

    override func layout() {
        super.layout()
        let icon = iconRect
        let inset = Self.containerInset
        iconContainer.frame = icon.insetBy(dx: -inset, dy: -inset)
        let inner = NSRect(x: inset, y: inset, width: iconSize, height: iconSize)
        imageView.frame = inner
        folderIcon.frame = inner.insetBy(dx: iconSize * Self.folderInset, dy: iconSize * Self.folderInset)
        badge.frame = NSRect(x: inset - 6, y: inset - 6, width: Self.badgeSize, height: Self.badgeSize)
        label.frame = NSRect(x: 4, y: icon.maxY + Self.gap, width: bounds.width - 8, height: Self.labelHeight)
        if isEditing { startWiggle() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let icon = iconRect
        if isDropTarget {
            let plate = icon.insetBy(dx: -iconSize * 0.12, dy: -iconSize * 0.12)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.24, yRadius: plate.width * 0.24).fill()
        }
        guard isSelected, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = selectionRect(icon: icon)
        let shape = RoundedRectangle(cornerRadius: (rect.width * Self.plateCornerRatio).rounded(), style: .continuous)
        context.addPath(shape.path(in: rect).cgPath)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(0.12).cgColor)
        context.fillPath()
    }

    // Corner as a share of the plate side: 22.5% (icon shape) looks too round, the icon's own radius too square.
    private static let plateCornerRatio: CGFloat = 0.16

    // Square plate around icon + label; shrinks evenly (stays square) when the cell is too small.
    private func selectionRect(icon: NSRect) -> NSRect {
        let content = iconSize + Self.gap + Self.labelHeight
        let side = floor(min(content + 16, bounds.width - 4, bounds.height - 2))
        let centerY = icon.minY + content / 2
        let y = min(max(1, centerY - side / 2), bounds.height - 1 - side)
        return NSRect(x: ((bounds.width - side) / 2).rounded(), y: y.rounded(), width: side, height: side)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLabelShadow()
    }

    // White labels on the wallpaper background get a soft shadow like Launchpad.
    // Not inside folders: the lighter folder sheet needs no shadow, and the open/close morph
    // uses snapshots (which never contain layer shadows) — so names keep the same brightness.
    // Folder names also force font smoothing so the live text matches the morph snapshots.
    private func updateLabelShadow() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var inFolder = false
        if case .folder? = grid?.context { inFolder = true }
        if let cell = label.cell as? CrispTextFieldCell, cell.forcesSmoothing != inFolder {
            cell.forcesSmoothing = inFolder
            label.needsDisplay = true
        }
        if isDark && !inFolder {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            label.shadow = shadow
        } else {
            label.shadow = nil
        }
    }

    // Rotate around the container center (layer anchor is the origin on macOS).
    private func startWiggle() {
        guard let layer = iconContainer.layer else { return }
        let center = NSPoint(x: iconContainer.bounds.midX, y: iconContainer.bounds.midY)
        func rotation(_ degrees: CGFloat) -> NSValue {
            var t = CATransform3DMakeTranslation(center.x, center.y, 0)
            t = CATransform3DRotate(t, degrees * .pi / 180, 0, 0, 1)
            t = CATransform3DTranslate(t, -center.x, -center.y, 0)
            return NSValue(caTransform3D: t)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [rotation(-1.6), rotation(1.6), rotation(-1.6)]
        animation.duration = 0.28
        animation.repeatCount = .infinity
        animation.timeOffset = Double.random(in: 0..<0.28)
        layer.add(animation, forKey: "wiggle")
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Only the icon (plus the delete badge in edit mode) is interactive;
    // clicks elsewhere in the cell fall through to the grid background.
    // The cell itself (not its image subviews) takes the click, so the whole drag's
    // mouseDragged / mouseUp events always arrive here.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let active = isEditing ? iconContainer.frame : iconRect
        guard active.contains(local) else { return nil }
        if !badge.isHidden, badge.bounds.contains(badge.convert(point, from: superview)) {
            return badge
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        isTracking = true
        isDragging = false
        longPressFired = false
        mouseDownPoint = event.locationInWindow
        guard grid != nil else { return }
        longPressTask?.cancel()
        longPressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.isPressed, !self.isDragging else { return }
            // Button must really still be down (a system gesture can swallow the mouseUp).
            guard NSEvent.pressedMouseButtons & 1 != 0 else {
                self.isPressed = false
                return
            }
            self.longPressFired = true
            self.isPressed = false
            self.grid?.cellDidLongPress(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Drags bubbling up from a subview (delete badge) never start a move.
        guard let grid, isTracking else { return }
        if isDragging {
            grid.cellDragMoved(self, event: event)
            return
        }
        let dx = event.locationInWindow.x - mouseDownPoint.x
        let dy = event.locationInWindow.y - mouseDownPoint.y
        guard dx * dx + dy * dy > 25 else { return }
        longPressTask?.cancel()
        isPressed = false
        isDragging = true
        grid.cellDidBeginDrag(self, event: event, grabPoint: mouseDownPoint)
    }

    override func mouseUp(with event: NSEvent) {
        longPressTask?.cancel()
        let wasPressed = isPressed
        isPressed = false
        isTracking = false
        if isDragging {
            isDragging = false
            grid?.cellDragEnded(self, event: event)
            return
        }
        guard wasPressed, !longPressFired, iconRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        grid?.cellDidClick(self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        grid?.menuForCell(self)
    }
}

// Round × badge shown in edit mode.
final class DeleteBadgeView: FlippedView {
    var kind: DeleteBadgeKind = .none { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 1, dy: 1)
        let fill: NSColor = kind == .other ? .systemOrange : NSColor(white: 0.35, alpha: 0.95)
        fill.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: circle)
        ring.lineWidth = 1
        ring.stroke()

        let inset = bounds.width * 0.32
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: inset, y: inset))
        cross.line(to: NSPoint(x: bounds.width - inset, y: bounds.height - inset))
        cross.move(to: NSPoint(x: bounds.width - inset, y: inset))
        cross.line(to: NSPoint(x: inset, y: bounds.height - inset))
        cross.lineWidth = 2
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    // Swallow: otherwise the drag reaches the cell (stale mouseDownPoint) and starts a move
    // whose mouseUp never arrives → the cell stays invisible as a drag source.
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?() }
    }
}

// Folder tile: rounded plate with a 3×3 grid of mini icons.
final class FolderIconView: FlippedView {
    var icons: [NSImage] = [] {
        didSet { needsDisplay = true }
    }
    // Slot left empty (an icon is flying into it).
    var hiddenIndex: Int? {
        didSet { needsDisplay = true }
    }

    // Mini icon rect for slot 0…8 of the 3×3 preview (flipped coordinates of `bounds`).
    static func miniRect(index: Int, in bounds: NSRect) -> NSRect {
        let pad = bounds.width * 0.12
        let gap = bounds.width * 0.05
        let cell = (bounds.width - 2 * pad - 2 * gap) / 3
        let row = index / 3
        let col = index % 3
        return NSRect(x: bounds.minX + pad + CGFloat(col) * (cell + gap),
                      y: bounds.minY + pad + CGFloat(row) * (cell + gap),
                      width: cell, height: cell)
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.drawTile(in: bounds, icons: icons, hiddenIndex: hiddenIndex)
    }

    // Plate + mini icons; shared with the drag image so both render identically.
    static func drawTile(in b: NSRect, icons: [NSImage], hiddenIndex: Int?) {
        let radius = b.width * 0.24
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: b, xRadius: radius, yRadius: radius).fill()

        for (index, image) in icons.prefix(9).enumerated() where index != hiddenIndex {
            image.draw(in: miniRect(index: index, in: b), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

// Text field that renders with font smoothing forced on.
// AppKit turns smoothing off for text in transparent layers, while bitmap snapshots
// (cacheDisplay) keep it on — the snapshot text looks bolder / brighter, so swapping the
// morph proxies for the live views made names visibly dim. Forcing it on matches both.
final class CrispTextFieldCell: NSTextFieldCell {
    var forcesSmoothing = true

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard forcesSmoothing, let context = NSGraphicsContext.current?.cgContext else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }
        context.saveGState()
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        super.drawInterior(withFrame: cellFrame, in: controlView)
        context.restoreGState()
    }
}

final class CrispTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CrispTextFieldCell.self }
        set { super.cellClass = newValue }
    }
}
