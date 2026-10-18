import AppKit
import ApplicationServices
import Combine
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
    // Red Dock badge at the top-right; folders show the total of their apps.
    private let appBadge = AppBadgeView()
    private var appBadgeKeys: [String] = []
    private var appBadgeShown = false
    private var appBadgeFadeToken = 0
    private let label = CrispTextField(labelWithString: "")
    private let uninstallPill = UninstallPillView()

    // App shown by this cell (nil for folders); drives the uninstall / install progress pill.
    private(set) var appKey: String?
    private var installingURL: URL?          // App Store download in progress
    private var uninstallFrame: UninstallProgress.Frame?
    private var uninstallLink: CADisplayLink?
    var isUninstalling: Bool { appKey.map { UninstallProgress.shared.isActive($0) } ?? false }

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
    // App badge height as a share of the icon size, and the transparent margin around
    // a standard macOS app icon (the visible squircle starts ~10% in).
    private static let appBadgeRatio: CGFloat = 0.28
    private static let iconShapeInset: CGFloat = 0.098

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
        uninstallPill.isHidden = true
        appBadge.isHidden = true
        appBadge.alphaValue = 0
        badge.onTap = { [weak self] in
            guard let self else { return }
            self.grid?.cellDidRequestDelete(self)
        }
        iconContainer.addSubview(imageView)
        iconContainer.addSubview(folderIcon)
        iconContainer.addSubview(appBadge)   // inside the container: wiggles and moves with the icon
        iconContainer.addSubview(badge)
        addSubview(iconContainer)
        addSubview(label)
        addSubview(uninstallPill)
        updateLabelShadow()
        NotificationCenter.default.addObserver(self, selector: #selector(appBadgesDidChange),
                                               name: .appBadgesDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateVisibility() {
        alphaValue = isDragSource ? 0 : 1
        let vanish = CGFloat(uninstallFrame?.vanish ?? 0)
        let dim = CGFloat(uninstallFrame?.iconAlpha ?? 1)
        iconContainer.alphaValue = isConcealed ? 0 : (isPressed ? 0.6 : 1) * (1 - vanish) * dim
        label.alphaValue = isConcealed ? concealedLabelAlpha : CGFloat(uninstallFrame?.labelAlpha ?? 1)
    }

    // MARK: - Uninstall progress

    // Re-reads the shared progress state (a rebuilt cell picks up a running uninstall seamlessly).
    func refreshUninstallState() {
        if isUninstalling || installingURL != nil {
            if uninstallLink == nil, window != nil {
                let link = displayLink(target: self, selector: #selector(uninstallStep(_:)))
                link.add(to: .main, forMode: .common)
                uninstallLink = link
            }
            applyUninstallFrame()
        } else {
            stopUninstallProgress()
        }
    }

    @objc private func uninstallStep(_ link: CADisplayLink) {
        applyUninstallFrame()
    }

    private var progressFrame: UninstallProgress.Frame? {
        guard let appKey else { return nil }
        if let frame = UninstallProgress.shared.frame(for: appKey) { return frame }
        if let installingURL { return InstallProgressMonitor.shared.frame(for: installingURL, key: appKey) }
        return nil
    }

    private func applyUninstallFrame() {
        guard let frame = progressFrame else {
            stopUninstallProgress()
            return
        }
        let wasActive = uninstallFrame != nil
        uninstallFrame = frame
        uninstallPill.isHidden = false
        uninstallPill.alphaValue = CGFloat(frame.pillAlpha)
        uninstallPill.progress = frame.progress
        uninstallPill.failed = frame.failed
        setIconScale(1 - 0.4 * CGFloat(frame.vanish))
        if !wasActive { badge.isHidden = true }
        updateVisibility()
    }

    private func stopUninstallProgress() {
        uninstallLink?.invalidate()
        uninstallLink = nil
        guard uninstallFrame != nil else { return }
        uninstallFrame = nil
        uninstallPill.isHidden = true
        setIconScale(1)
        badge.isHidden = !isEditing || badgeKind == .none
        updateVisibility()
    }

    // Shrinks the app icon around its center (vanish after a successful uninstall).
    private func setIconScale(_ scale: CGFloat) {
        guard let layer = imageView.layer else { return }
        // Pivot relative to the anchor point (AppKit layers usually anchor at the origin).
        let size = layer.bounds.size
        let cx = (0.5 - layer.anchorPoint.x) * size.width
        let cy = (0.5 - layer.anchorPoint.y) * size.height
        var t = CATransform3DIdentity
        if scale < 1 {
            t = CATransform3DMakeTranslation(cx, cy, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            t = CATransform3DTranslate(t, -cx, -cy, 0)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = t
        CATransaction.commit()
    }

    // The display link retains its target: only keep it while the cell is in a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            uninstallLink?.invalidate()
            uninstallLink = nil
        } else if appKey != nil {
            refreshUninstallState()
        }
    }

    func configure(_ entry: GridEntry) {
        switch entry {
        case .app(let app):
            imageView.image = IconCache.shared.icon(for: app)
            imageView.isHidden = false
            folderIcon.isHidden = true
            label.stringValue = app.name
            appKey = app.key
            installingURL = app.isInstalling ? app.url : nil
            appBadgeKeys = app.isInstalling ? [] : [app.key]
        case .folder(let folder, let apps):
            folderIcon.icons = apps.prefix(9).map { IconCache.shared.icon(for: $0) }
            imageView.isHidden = true
            folderIcon.isHidden = false
            label.stringValue = folder.displayName
            appKey = nil
            installingURL = nil
            appBadgeKeys = apps.filter { !$0.isInstalling }.map(\.key)
        }
        refreshUninstallState()
        updateAppBadge(animated: false)
    }

    // MARK: - App badge

    @objc private func appBadgesDidChange() {
        updateAppBadge(animated: true)
    }

    private func updateAppBadge(animated: Bool) {
        let content = AppBadgeMonitor.shared.content(for: appBadgeKeys)
        if let content {
            appBadge.content = content
            layoutAppBadge()
        }
        let show = content != nil
        guard show != appBadgeShown else { return }
        appBadgeShown = show
        appBadgeFadeToken += 1
        let token = appBadgeFadeToken
        if show { appBadge.isHidden = false }
        guard animated, window != nil else {
            appBadge.alphaValue = show ? 1 : 0
            appBadge.isHidden = !show
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            appBadge.animator().alphaValue = show ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, token == self.appBadgeFadeToken, !show else { return }
            self.appBadge.isHidden = true
        }
    }

    // Top-right corner of what is drawn (app squircle or folder plate), poking out a little;
    // wider badges grow to the left.
    private func layoutAppBadge() {
        let height = max(14, (iconSize * Self.appBadgeRatio).rounded())
        let shape = folderIcon.isHidden
            ? imageView.frame.insetBy(dx: iconSize * Self.iconShapeInset, dy: iconSize * Self.iconShapeInset)
            : folderIcon.frame
        let size = appBadge.fittingSize(height: height)
        let overhang = (height * 0.22).rounded()
        appBadge.frame = NSRect(x: (shape.maxX + overhang - size.width).rounded(),
                                y: shape.minY - overhang,
                                width: size.width, height: size.height)
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
        layoutAppBadge()
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
        // The app badge fades in with the name instead of popping at full size.
        if appBadgeShown { appBadge.alphaValue = 0 }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            label.animator().alphaValue = 1
            if appBadgeShown { appBadge.animator().alphaValue = 1 }
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
        badge.isHidden = !editing || kind == .none || isUninstalling
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
        layoutAppBadge()
        label.frame = NSRect(x: 4, y: icon.maxY + Self.gap, width: bounds.width - 8, height: Self.labelHeight)
        // Pill sits where the name is (the name fades out while it shows).
        let pillWidth = min(bounds.width - 8, (iconSize * 0.86).rounded())
        let pillHeight = max(4, (iconSize * 0.075).rounded())
        uninstallPill.frame = NSRect(x: ((bounds.width - pillWidth) / 2).rounded(),
                                     y: (label.frame.midY - pillHeight / 2).rounded(),
                                     width: pillWidth, height: pillHeight)
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
        guard !isUninstalling else { return }
        isPressed = true
        isTracking = true
        isDragging = false
        longPressFired = false
        mouseDownPoint = event.locationInWindow
        guard grid != nil else { return }
        longPressTask?.cancel()
        longPressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            // A concealed tile (its folder is open on top) never starts edit mode.
            guard !Task.isCancelled, let self, self.isPressed, !self.isDragging, !self.isConcealed else { return }
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
        guard let grid, isTracking, !isUninstalling else { return }
        if isDragging {
            grid.cellDragMoved(self, event: event)
            return
        }
        let dx = event.locationInWindow.x - mouseDownPoint.x
        let dy = event.locationInWindow.y - mouseDownPoint.y
        guard dx * dx + dy * dy > 25, !isConcealed else { return }
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
        isUninstalling || installingURL != nil ? nil : grid?.menuForCell(self)
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

// MARK: - Uninstall progress

// Shared, time-based progress of running uninstalls (keyed by app key), so cells rebuilt by a
// reload continue exactly where the old cell was. Running: 80% at 2.5 s, then creeping toward 97%.
// Success: fill to 100%, then the icon shrinks away. Failure: stops red, then fades out.
@MainActor
final class UninstallProgress {
    static let shared = UninstallProgress()

    nonisolated struct Frame: Sendable {
        var progress: Double      // 0…1 fill
        var failed: Bool
        var pillAlpha: Double
        var labelAlpha: Double    // app name, hidden while the pill shows
        var vanish: Double        // 0…1 icon shrinking away after success
        var iconAlpha: Double = 1 // dimmed while an App Store download runs
    }

    private enum Phase {
        case running
        case succeeded(at: CFTimeInterval, from: Double)
        case failed(at: CFTimeInterval, value: Double)
    }

    private struct Entry {
        let start: CFTimeInterval
        var phase: Phase
    }

    static let fillDuration: Double = 0.3
    static let vanishDuration: Double = 0.3
    static let failHold: Double = 0.7
    static let failFade: Double = 0.3
    private static let labelFade: Double = 0.2
    static var successDuration: Double { fillDuration + vanishDuration }
    static var failureDuration: Double { failHold + failFade }

    private var entries: [String: Entry] = [:]

    func isActive(_ key: String) -> Bool { entries[key] != nil }

    func begin(_ key: String) {
        entries[key] = Entry(start: CACurrentMediaTime(), phase: .running)
    }

    func finish(_ key: String, success: Bool) {
        guard var entry = entries[key], case .running = entry.phase else { return }
        let now = CACurrentMediaTime()
        let value = Self.runningProgress(now - entry.start)
        entry.phase = success ? .succeeded(at: now, from: value) : .failed(at: now, value: value)
        entries[key] = entry
    }

    func clear(_ key: String) {
        entries[key] = nil
    }

    // nil once nothing is shown any more (finished failure, cleared entry).
    func frame(for key: String, now: CFTimeInterval = CACurrentMediaTime()) -> Frame? {
        guard let entry = entries[key] else { return nil }
        let labelOut = 1 - min(1, (now - entry.start) / Self.labelFade)
        switch entry.phase {
        case .running:
            return Frame(progress: Self.runningProgress(now - entry.start), failed: false,
                         pillAlpha: 1, labelAlpha: labelOut, vanish: 0)
        case .succeeded(let at, let from):
            let t = now - at
            let fill = Self.easeOut(min(1, t / Self.fillDuration))
            let vanish = Self.easeInOut(min(1, max(0, (t - Self.fillDuration) / Self.vanishDuration)))
            return Frame(progress: from + (1 - from) * fill, failed: false,
                         pillAlpha: 1 - vanish, labelAlpha: 0, vanish: vanish)
        case .failed(let at, let value):
            let t = now - at
            guard t < Self.failureDuration else { return nil }
            let fade = Self.easeInOut(min(1, max(0, (t - Self.failHold) / Self.failFade)))
            return Frame(progress: value, failed: true, pillAlpha: 1 - fade,
                         labelAlpha: max(labelOut, fade), vanish: 0)
        }
    }

    // Ease-out to 80% at 2.5 s (slope matched at the joint), then 80% → 97% with a 6 s time constant.
    private static func runningProgress(_ t: Double) -> Double {
        let head = 2.5, headValue = 0.8, tail = 0.17, tau = 6.0
        if t <= head {
            let x = max(0, t / head)
            let w = tail / tau * head / headValue      // linear share giving the joint slope
            return headValue * ((1 - w) * (2 * x - x * x) + w * x)
        }
        return headValue + tail * (1 - exp(-(t - head) / tau))
    }

    private static func easeOut(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }
    private static func easeInOut(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

// MARK: - App badges

nonisolated enum AppBadgeContent: Equatable, Sendable {
    case text(String)   // count or short label
    case dot            // non-numeric label, or a folder with only non-numeric badges
}

// Red capsule badge (like the Dock's), white text centered on the cap height.
final class AppBadgeView: NSView {
    var content: AppBadgeContent = .dot {
        didSet { if oldValue != content { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    func fittingSize(height: CGFloat) -> NSSize {
        switch content {
        case .dot:
            let side = (height * 0.62).rounded()
            return NSSize(width: side, height: side)
        case .text(let text):
            let width = (text as NSString).size(withAttributes: Self.attributes(height: height)).width
            return NSSize(width: max(height, (width + height * 0.55).rounded()), height: height)
        }
    }

    private static func font(height: CGFloat) -> NSFont {
        .systemFont(ofSize: (height * 0.6).rounded(), weight: .semibold)
    }

    private static func attributes(height: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: font(height: height), .foregroundColor: NSColor.white]
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let radius = rect.height / 2
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        guard case .text(let text) = content else { return }
        let font = Self.font(height: rect.height)
        let string = text as NSString
        let width = string.size(withAttributes: Self.attributes(height: rect.height)).width
        // Flipped: the line box starts at the ascender; put the cap center on the middle.
        let y = rect.midY + font.capHeight / 2 - font.ascender
        string.draw(at: NSPoint(x: rect.midX - width / 2, y: y),
                    withAttributes: Self.attributes(height: rect.height))
    }

    // Never takes clicks (the cell decides).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension Notification.Name {
    static let appBadgesDidChange = Notification.Name("AppPad.appBadgesDidChange")
}

// Dock badges of all apps, keyed by AppInfo key. Read from the Dock's accessibility tree:
// every app showing a badge is in the Dock (running apps always are), so no private API.
// Polls only while AppPad is visible; the last result stays cached between opens.
// Needs Accessibility permission; without it there are simply no badges (no prompt).
@MainActor
final class AppBadgeMonitor {
    static let shared = AppBadgeMonitor()

    private(set) var labels: [String: String] = [:]   // AppInfo key → raw label
    private var timer: Timer?
    private var isFetching = false
    private var prefsToken: AnyCancellable?
    private static let pollInterval: TimeInterval = 1.5

    private init() {
        // @Published emits before the stored value changes: the new value is passed along.
        prefsToken = Preferences.shared.$showAppBadges.dropFirst().removeDuplicates().sink { [weak self] on in
            if on { self?.refresh(enabled: true) } else { self?.apply([:]) }
        }
    }

    // AppPad shown / hidden.
    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        refresh()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)   // keeps firing during drags
        self.timer = timer
    }

    // Reads the Dock off the main thread; cells update via .appBadgesDidChange.
    func refresh(enabled: Bool? = nil) {
        guard enabled ?? Preferences.shared.showAppBadges, AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            apply([:])
            return
        }
        guard !isFetching else { return }
        isFetching = true
        let pid = dock.processIdentifier
        Task {
            let result = await Task.detached(priority: .utility) { DockBadgeReader.read(dockPID: pid) }.value
            isFetching = false
            guard Preferences.shared.showAppBadges else {   // turned off meanwhile
                apply([:])
                return
            }
            if let result { apply(result) }   // read failed: keep the last labels
        }
    }

    private func apply(_ new: [String: String]) {
        guard new != labels else { return }
        labels = new
        NotificationCenter.default.post(name: .appBadgesDidChange, object: nil)
    }

    // One key: the app's own badge. Several (folder): sum of the counts, a dot when only
    // non-numeric badges are inside. nil = no badge.
    func content(for keys: [String]) -> AppBadgeContent? {
        guard !labels.isEmpty, !keys.isEmpty else { return nil }
        var total = 0
        var hasOther = false
        for key in keys {
            guard let raw = labels[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            if let count = Self.count(raw) {
                total += count
            } else if keys.count == 1 {
                return raw.count <= 3 ? .text(raw) : .dot
            } else {
                hasOther = true
            }
        }
        if total > 0 { return .text(total > 99 ? "99+" : String(total)) }
        return hasOther ? .dot : nil
    }

    // "12", "1,234", "1 234" → number; anything else is a text label.
    private static func count(_ raw: String) -> Int? {
        let digits = raw.filter { !$0.isWhitespace && $0 != "," && $0 != "." && $0 != "'" }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }
}

// Dock → AXList → AXDockItem (subrole AXApplicationDockItem): AXStatusLabel is the badge,
// AXURL the app bundle.
nonisolated enum DockBadgeReader {
    private static let timeout: Float = 0.5   // a busy Dock must not stall the read

    // AppInfo key → label; nil when the Dock could not be read.
    static func read(dockPID: pid_t) -> [String: String]? {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, timeout)
        guard let lists = elements(dock, kAXChildrenAttribute) else { return nil }
        var result: [String: String] = [:]
        for list in lists where string(list, kAXRoleAttribute) == kAXListRole {
            AXUIElementSetMessagingTimeout(list, timeout)
            for item in elements(list, kAXChildrenAttribute) ?? [] {
                guard string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
                      let label = string(item, "AXStatusLabel"), !label.isEmpty,
                      let url = url(item) else { continue }
                result[key(for: url)] = label
            }
        }
        return result
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        value(element, attribute) as? [AXUIElement]
    }

    private static func url(_ element: AXUIElement) -> URL? {
        (value(element, kAXURLAttribute) as? NSURL).map { $0 as URL }
    }

    // Same identity as AppInfo.key: bundle id, else the path.
    private static func key(for url: URL) -> String {
        Bundle(url: url)?.bundleIdentifier ?? url.path
    }
}

// Thin rounded progress bar under an app icon while it is being uninstalled.
final class UninstallPillView: NSView {
    var progress: Double = 0 {
        didSet { if oldValue != progress { needsDisplay = true } }
    }
    var failed = false {
        didSet { if oldValue != failed { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds
        let radius = track.height / 2
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        var fill = track
        fill.size.width = max(track.height, track.width * CGFloat(min(1, max(0, progress))))
        (failed ? NSColor.systemRed : NSColor.controlAccentColor).setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }

    // Never takes clicks (the cell decides).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - App Store install progress

// Download progress of App Store install placeholders. The App Store publishes an NSProgress
// for the bundle (Finder draws its pie from it): subscribe to the application folders and to
// each placeholder. Without a published progress the pill creeps slowly toward 85%.
// The App Store runs phases one after another (download 0→100%, then install 0→100%): the first
// phase fills 0–85%, later ones the rest, and what is shown never goes back.
@MainActor
final class InstallProgressMonitor {
    static let shared = InstallProgressMonitor()

    private var folderTokens: [Any] = []
    private var appTokens: [String: Any] = [:]                 // placeholder path → subscriber
    private struct Track {
        var phase = 0
        var base = 0.0       // shown value when the current phase started
        var lastRaw = 0.0    // last fraction of the current phase
        var shown = 0.0      // monotonic value for the pill
    }
    private var tracks: [String: Track] = [:]                  // path → phases so far
    private static let firstPhaseShare = 0.85                  // download phase share of the pill
    private var observations: [String: NSKeyValueObservation] = [:]
    private var firstSeen: [String: CFTimeInterval] = [:]      // app key → first shown

    func start(folders: [URL]) {
        guard folderTokens.isEmpty else { return }
        folderTokens = folders.map(Self.subscribe)
    }

    // Called after every scan with the current placeholders.
    func sync(installing urls: [URL]) {
        let paths = Set(urls.map(Self.pathKey))
        for (path, token) in appTokens where !paths.contains(path) {
            Progress.removeSubscriber(token)
            appTokens[path] = nil
        }
        for path in tracks.keys where !paths.contains(path) { tracks[path] = nil }
        for url in urls where appTokens[Self.pathKey(url)] == nil {
            appTokens[Self.pathKey(url)] = Self.subscribe(url)
        }
        if urls.isEmpty { firstSeen.removeAll() }
    }

    func frame(for url: URL, key: String, now: CFTimeInterval = CACurrentMediaTime()) -> UninstallProgress.Frame {
        let seen = firstSeen[key] ?? now
        if firstSeen[key] == nil { firstSeen[key] = now }
        let progress = tracks[Self.pathKey(url)].map { max(0.03, $0.shown) }
            ?? Self.firstPhaseShare * (1 - exp(-(now - seen) / 45))
        return UninstallProgress.Frame(progress: progress, failed: false, pillAlpha: 1,
                                       labelAlpha: 0, vanish: 0, iconAlpha: 0.45)
    }

    // raw: fraction of the published progress (nil = indeterminate, keeps what is shown).
    private func update(_ path: String, raw: Double?) {
        guard let raw else { return }
        var track = tracks[path] ?? Track()
        // A big drop means the next phase started (a new progress, or the same one reset).
        if raw + 0.2 < track.lastRaw {
            track.phase += 1
            track.base = track.shown
        }
        track.lastRaw = raw
        let value = track.phase == 0 ? Self.firstPhaseShare * raw : track.base + (1 - track.base) * raw
        track.shown = max(track.shown, min(1, value))
        tracks[path] = track
    }

    nonisolated private static func pathKey(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()   // APFS is case-insensitive by default
    }

    // The publishing handler runs on an arbitrary thread: state changes hop to the main actor.
    nonisolated private static func subscribe(_ url: URL) -> Any {
        Progress.addSubscriber(forFileURL: url) { progress in
            let fileURL = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
            guard let fileURL, fileURL.pathExtension.lowercased() == "app" else { return nil }
            let path = pathKey(fileURL)
            NSLog("Install progress published: \(fileURL.path)")
            let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                let value: Double? = progress.isIndeterminate ? nil : progress.fractionCompleted
                Task { @MainActor in InstallProgressMonitor.shared.update(path, raw: value) }
            }
            Task { @MainActor in InstallProgressMonitor.shared.observations[path] = observation }
            // Unpublished: keep the track (the next phase continues from it); sync() drops it.
            return {
                Task { @MainActor in InstallProgressMonitor.shared.observations[path] = nil }
            }
        }
    }
}
