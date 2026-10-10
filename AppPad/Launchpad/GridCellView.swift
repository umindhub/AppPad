import AppKit
import QuartzCore

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

    func setEditing(_ editing: Bool, badge kind: DeleteBadgeKind) {
        badgeKind = kind
        isEditing = editing
        badge.kind = kind
        badge.isHidden = !editing || kind == .none
        if editing { startWiggle() } else { iconContainer.layer?.removeAnimation(forKey: "wiggle") }
    }

    // Icon snapshot for the floating drag image.
    func snapshotIcon() -> NSImage {
        let view: NSView = imageView.isHidden ? folderIcon : imageView
        let wasHidden = badge.isHidden
        badge.isHidden = true
        defer { badge.isHidden = wasHidden }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return NSImage() }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
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
        guard isSelected else { return }
        let width = min(bounds.width - 4, iconSize + 36)
        let rect = NSRect(x: (bounds.width - width) / 2, y: icon.minY - 8,
                          width: width, height: iconSize + Self.gap + Self.labelHeight + 16)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
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
        isDragging = false
        longPressFired = false
        mouseDownPoint = event.locationInWindow
        guard grid?.allowsEditing == true else { return }
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
        guard let grid, grid.allowsEditing else { return }
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
        let b = bounds
        let radius = b.width * 0.24
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: b, xRadius: radius, yRadius: radius).fill()

        for (index, image) in icons.prefix(9).enumerated() where index != hiddenIndex {
            image.draw(in: Self.miniRect(index: index, in: b), from: .zero, operation: .sourceOver,
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
