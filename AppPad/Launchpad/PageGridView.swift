import AppKit
import QuartzCore

enum GridContext: Equatable {
    case page(Int)          // launcher page index
    case folder(String)     // open folder id
    case results            // search results (no reordering; drag out of the panel only)
}

protocol PageGridDelegate: AnyObject {
    func grid(_ grid: PageGridView, didClick index: Int)
    func grid(_ grid: PageGridView, didLongPress index: Int)
    func grid(_ grid: PageGridView, didBeginDrag index: Int, event: NSEvent, grabPoint: NSPoint)
    func grid(_ grid: PageGridView, dragMoved event: NSEvent)
    func grid(_ grid: PageGridView, dragEnded event: NSEvent)
    func grid(_ grid: PageGridView, didRequestDelete index: Int)
    func grid(_ grid: PageGridView, menuFor index: Int) -> NSMenu?
    func gridDidClickBackground(_ grid: PageGridView)
}

// A columns × rows grid of cells. Used for launcher pages, search results and folders.
// During a drag the owner can override cell→slot placement (live reflow).
final class PageGridView: FlippedView {
    let columns: Int
    let rows: Int
    let context: GridContext
    var fixedCellHeight: CGFloat?    // folders: fixed row height inside a scroll view
    var fixedCellWidth: CGFloat?     // folders: fixed column width
    var fixedIconSize: CGFloat?      // folders: same icon size as the pages
    // Folders: rows per page. The grid is one wide view; page p starts at x = p · pageWidth,
    // and each page's columns are centered in it.
    var pageRows: Int? {
        didSet { if oldValue != pageRows { needsLayout = true } }
    }
    // Empty slots after the cells that still count for paging (spring-loaded folder: room
    // for the icon being dragged in).
    var reservedSlots = 0 {
        didSet { if oldValue != reservedSlots { needsLayout = true } }
    }
    weak var delegate: PageGridDelegate?

    private(set) var cells: [GridCellView] = []
    private(set) var entries: [GridEntry] = []
    private var slotOverride: [Int]?  // slot per cell; -1 = hidden
    private let press = BackgroundPressTracker()

    init(columns: Int, rows: Int, context: GridContext) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.context = context
        super.init(frame: .zero)
        press.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.gridDidClickBackground(self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Metrics

    // While swiping, the gap between the last icon of a page and the first icon of the next
    // page is this many times the gap between two icons on the same page.
    static let pageGapFactor: CGFloat = 1.5

    // Side margin per page that produces pageGapFactor (icon gap g → page gap g + 2·inset).
    static func pageSideInset(size: NSSize, columns: Int, rows: Int) -> CGFloat {
        let base = metrics(size: size, columns: columns, rows: rows)
        let iconGap = base.cellWidth - base.icon
        return floor(max(0, iconGap * (pageGapFactor - 1) / 2))
    }

    var sideInset: CGFloat {
        if case .folder = context { return 0 }
        return Self.pageSideInset(size: bounds.size, columns: columns, rows: rows)
    }

    static func metrics(size: NSSize, columns: Int, rows: Int, fixedCellHeight: CGFloat? = nil,
                        sideInset: CGFloat = 0)
        -> (cellWidth: CGFloat, cellHeight: CGFloat, icon: CGFloat) {
        let contentWidth = size.width - 2 * sideInset
        let cellWidth = contentWidth / CGFloat(max(1, columns))
        let cellHeight = fixedCellHeight ?? size.height / CGFloat(max(1, rows))
        let icon = max(28, floor(min(cellWidth * 0.62, (cellHeight - 22) * 0.82, 96)))
        return (cellWidth, cellHeight, icon)
    }

    // Distance from the grid top to the top of the first icon row.
    static func firstIconTop(size: NSSize, columns: Int, rows: Int) -> CGFloat {
        let m = metrics(size: size, columns: columns, rows: rows,
                        sideInset: pageSideInset(size: size, columns: columns, rows: rows))
        return GridCellView.iconTop(cellHeight: m.cellHeight, iconSize: m.icon)
    }

    private var currentMetrics: (cellWidth: CGFloat, cellHeight: CGFloat, icon: CGFloat) {
        var m = Self.metrics(size: bounds.size, columns: columns, rows: rows,
                             fixedCellHeight: fixedCellHeight, sideInset: sideInset)
        if let fixedCellWidth { m.cellWidth = fixedCellWidth }
        if let fixedIconSize { m.icon = fixedIconSize }
        return m
    }

    // Pages in paged (folder) mode; 1 otherwise.
    var pageCount: Int {
        guard let pageRows else { return 1 }
        let perPage = columns * max(1, pageRows)
        return max(1, (cells.count + reservedSlots + perPage - 1) / perPage)
    }

    private var pageWidth: CGFloat { bounds.width / CGFloat(pageCount) }

    private func pageInset(cellWidth: CGFloat) -> CGFloat {
        max(0, (pageWidth - CGFloat(columns) * cellWidth) / 2)
    }

    func slotRect(_ slot: Int) -> NSRect {
        let m = currentMetrics
        if let pageRows {
            let perPage = columns * max(1, pageRows)
            let page = slot / perPage
            let local = slot % perPage
            let x = CGFloat(page) * pageWidth + pageInset(cellWidth: m.cellWidth) + CGFloat(local % columns) * m.cellWidth
            return NSRect(x: x, y: CGFloat(local / columns) * m.cellHeight,
                          width: m.cellWidth, height: m.cellHeight).integral
        }
        let row = slot / columns
        let col = slot % columns
        return NSRect(x: sideInset + CGFloat(col) * m.cellWidth, y: CGFloat(row) * m.cellHeight,
                      width: m.cellWidth, height: m.cellHeight).integral
    }

    func iconRect(forSlot slot: Int) -> NSRect {
        let m = currentMetrics
        let cell = slotRect(slot)
        let top = GridCellView.iconTop(cellHeight: cell.height, iconSize: m.icon)
        return NSRect(x: cell.midX - m.icon / 2, y: cell.minY + top, width: m.icon, height: m.icon)
    }

    var iconSize: CGFloat { currentMetrics.icon }

    // Slot under a point (grid coordinates), clamped into the grid.
    func slot(at point: NSPoint) -> Int {
        let m = currentMetrics
        if let pageRows {
            let rowsPerPage = max(1, pageRows)
            let page = min(max(0, Int(floor(point.x / max(pageWidth, 1)))), pageCount - 1)
            let localX = point.x - CGFloat(page) * pageWidth - pageInset(cellWidth: m.cellWidth)
            let col = min(max(0, Int(floor(localX / m.cellWidth))), columns - 1)
            let row = min(max(0, Int(floor(point.y / m.cellHeight))), rowsPerPage - 1)
            return page * columns * rowsPerPage + row * columns + col
        }
        let col = min(max(0, Int((point.x - sideInset) / m.cellWidth)), columns - 1)
        let maxRow = fixedCellHeight == nil ? rows - 1 : Int.max
        let row = min(max(0, Int(point.y / m.cellHeight)), maxRow)
        return row * columns + col
    }

    // MARK: - Content

    func setEntries(_ entries: [GridEntry]) {
        self.entries = entries
        slotOverride = nil
        cells.forEach { $0.removeFromSuperview() }
        cells = entries.enumerated().map { index, entry in
            let cell = GridCellView()
            cell.grid = self
            cell.index = index
            cell.configure(entry)
            addSubview(cell)
            return cell
        }
        needsLayout = true
    }

    func setSelectedIndex(_ index: Int?) {
        for (i, cell) in cells.enumerated() {
            cell.isSelected = (i == index)
        }
    }

    func setEditing(_ editing: Bool) {
        for (i, cell) in cells.enumerated() {
            cell.setEditing(editing, badge: badgeKind(for: entries[i]))
        }
    }

    private func badgeKind(for entry: GridEntry) -> DeleteBadgeKind {
        guard case .app(let app) = entry, !app.isSystem, !app.isInstalling,
              app.bundleID != Bundle.main.bundleIdentifier else { return .none }
        return app.isAppStore ? .appStore : .other
    }

    // Grid kept across a reload: natural order, no drag / drop marks left over.
    func resetTransientState() {
        for cell in cells {
            cell.isDragSource = false
            cell.isDropTarget = false
        }
        applyArrangement(nil, animated: false)
    }

    // Live reflow during drags. nil restores natural order.
    // gentle: slower, critically damped spring (used when a gap closes after making a folder).
    func applyArrangement(_ slots: [Int]?, animated: Bool, gentle: Bool = false) {
        slotOverride = slots
        placeCells(animated: animated, gentle: gentle)
    }

    override func layout() {
        super.layout()
        placeCells(animated: false, gentle: false)
    }

    private func placeCells(animated: Bool, gentle: Bool) {
        let icon = currentMetrics.icon
        let limit = fixedCellHeight == nil ? columns * rows : Int.max
        for (index, cell) in cells.enumerated() {
            let slot = slotOverride.map { $0.indices.contains(index) ? $0[index] : index } ?? index
            cell.iconSize = icon
            guard slot >= 0 else { continue }
            let target = slotRect(slot)
            if animated {
                Self.slide(cell, to: target, gentle: gentle)
            } else if cell.frame != target {
                cell.frame = target
            }
            if !cell.isDragSource && !cell.isConcealed {
                cell.alphaValue = slot < limit ? 1 : 0
            }
        }
    }

    // Move the view to its final frame immediately (no relayout during the animation),
    // then animate only a layer translation from where it is currently *displayed*.
    // Done in layer space via position deltas, so it is flip-agnostic and interruptible.
    static func slide(_ view: NSView, to target: NSRect, gentle: Bool = false) {
        guard view.frame != target else { return }
        guard let layer = view.layer else {
            view.frame = target
            return
        }
        let oldPosition = layer.position
        let inFlight = layer.presentation()?.transform ?? CATransform3DIdentity
        view.frame = target
        let newPosition = layer.position
        let dx = oldPosition.x - newPosition.x + inFlight.m41
        let dy = oldPosition.y - newPosition.y + inFlight.m42
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(dx, dy, 0))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.mass = 1
        spring.stiffness = gentle ? 120 : 320
        spring.damping = gentle ? 22 : 30
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "slide")
    }

    // MARK: - Cell callbacks

    func cellDidClick(_ cell: GridCellView) { delegate?.grid(self, didClick: cell.index) }
    func cellDidLongPress(_ cell: GridCellView) { delegate?.grid(self, didLongPress: cell.index) }
    func cellDidRequestDelete(_ cell: GridCellView) { delegate?.grid(self, didRequestDelete: cell.index) }
    func menuForCell(_ cell: GridCellView) -> NSMenu? { delegate?.grid(self, menuFor: cell.index) }

    func cellDidBeginDrag(_ cell: GridCellView, event: NSEvent, grabPoint: NSPoint) {
        delegate?.grid(self, didBeginDrag: cell.index, event: event, grabPoint: grabPoint)
    }
    func cellDragMoved(_ cell: GridCellView, event: NSEvent) { delegate?.grid(self, dragMoved: event) }
    func cellDragEnded(_ cell: GridCellView, event: NSEvent) { delegate?.grid(self, dragEnded: event) }

    // Empty space in the grid (cells only take clicks on their icon).
    override func mouseDown(with event: NSEvent) { press.mouseDown(event) }
    override func mouseDragged(with event: NSEvent) { press.mouseDragged(event) }
    override func mouseUp(with event: NSEvent) { press.mouseUp(event) }
}
