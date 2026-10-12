import AppKit

// Layout (top → bottom): search field, page indicator (centered between search and first icon row), grid.
// The calculator lives in the Workflow panel now.
// Edit mode / grid delegate live in +Edit.swift, drag & drop in +Drag.swift.
final class LaunchpadViewController: NSViewController, NSSearchFieldDelegate {
    weak var controller: LaunchpadController?

    // Shared with the +Edit / +Drag extensions.
    let root = LaunchpadRootView()
    let searchChrome = GlassSearchFieldView()
    var searchField: NSSearchField { searchChrome.field }
    let indicator = PageIndicatorView()
    let pager = PagerView()
    let resultsPager = PagerView()
    let dragImageView = NSImageView()
    var folderOverlay: FolderOverlayView?
    var confirmOverlay: ConfirmOverlayView?
    var isEditingLayout = false
    var drag: DragState?
    var lastDragEvent: NSEvent?
    var mergeTask: Task<Void, Never>?
    var reorderTask: Task<Void, Never>?
    var settleTask: Task<Void, Never>?
    var systemDrag: DragState?          // app handed over to an NSDraggingSession
    var edgeTask: Task<Void, Never>?
    var edgeDirection = 0

    private let emptyLabel = NSTextField(labelWithString: String(localized: "No Results"))

    private(set) var isSearching = false
    private var results: [AppInfo] = []
    private var resultPages: [PageGridView] = []
    private var selection = 0   // index into results

    var prefs: Preferences { .shared }
    var capacity: Int { max(1, prefs.gridColumns * prefs.gridRows) }
    private var activePager: PagerView { isSearching ? resultsPager : pager }

    private enum Direction { case left, right, up, down }

    static let bottomPadding: CGFloat = 40

    // MARK: - View

    override func loadView() {
        root.wantsLayer = true
        root.layer?.cornerRadius = LaunchpadController.cornerRadius
        root.layer?.masksToBounds = true
        root.onScroll = { [weak self] event in self?.activePager.scrollWheel(with: event) }
        root.onEscape = { [weak self] in self?.handleEscape() }
        root.press.onClick = { [weak self] in self?.handleBackgroundClick() }
        view = root

        searchField.placeholderString = String(localized: "Search")
        searchField.delegate = self
        searchField.focusRingType = .none

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.isHidden = true
        resultsPager.isHidden = true

        dragImageView.imageScaling = .scaleProportionallyUpOrDown
        dragImageView.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        dragImageView.shadow = shadow

        [pager, resultsPager, searchChrome, indicator, emptyLabel].forEach {
            root.addSubview($0)
        }

        pager.onProgress = { [weak self] progress in
            guard let self, !self.isSearching else { return }
            self.indicator.progress = progress
        }
        resultsPager.onProgress = { [weak self] progress in
            guard let self, self.isSearching else { return }
            self.indicator.progress = progress
        }
        indicator.onSelect = { [weak self] index in
            self?.activePager.scrollTo(page: index, animated: true)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let b = view.bounds
        let pad: CGFloat = 28
        let fieldWidth = min(320, b.width - 2 * pad)
        // Field centered at y 36 (same 32 pt capsule with and without glass).
        let fieldHeight = searchChrome.preferredHeight
        searchChrome.frame = NSRect(x: ((b.width - fieldWidth) / 2).rounded(), y: 36 - fieldHeight / 2,
                                    width: fieldWidth, height: fieldHeight)
        let searchBottom = searchChrome.frame.maxY

        let top: CGFloat = 76
        // Breathing room under the last icon row (labels no longer hug the bottom edge).
        let bottom = b.height - Self.bottomPadding
        // Each page adds a small side margin so pages are 1.5× the icon gap apart (PageGridView.pageGapFactor).
        let gridRect = NSRect(x: pad, y: top, width: b.width - 2 * pad, height: max(0, bottom - top))
        pager.frame = gridRect
        resultsPager.frame = gridRect

        // Indicator sits halfway between the search field and the first icon row.
        let firstIconTop = gridRect.minY + PageGridView.firstIconTop(
            size: gridRect.size, columns: prefs.gridColumns, rows: prefs.gridRows)
        let center = (searchBottom + firstIconTop) / 2
        indicator.frame = NSRect(x: pad, y: (center - 12).rounded(), width: b.width - 2 * pad, height: 24)

        emptyLabel.frame = NSRect(x: pad, y: top + 40, width: b.width - 2 * pad, height: 22)
        folderOverlay?.frame = b
        confirmOverlay?.frame = b
    }

    // MARK: - Data

    func reloadAll(refreshFolder: Bool = true) {
        _ = view
        guard let controller, drag == nil else { return }
        let pages = controller.displayPages().enumerated().map { index, entries in
            makePageGrid(page: index, entries: entries)
        }
        pager.setPages(pages)
        if isSearching { updateSearch() }
        if let overlay = folderOverlay {
            if refreshFolder {
                reopenFolder(id: overlay.folderID)
            } else if let tile = folderTileCell(id: overlay.folderID) {
                overlay.sourceTile = tile          // cells were rebuilt: keep the new tile hidden
                tile.isConcealed = true
            }
        }
        syncIndicator()
        view.needsLayout = true
    }

    func makePageGrid(page: Int, entries: [GridEntry]) -> PageGridView {
        let grid = PageGridView(columns: prefs.gridColumns, rows: prefs.gridRows, context: .page(page))
        grid.delegate = self
        grid.setEntries(entries)
        grid.setEditing(isEditingLayout)
        return grid
    }

    func pageGrid(_ page: Int) -> PageGridView? {
        pager.pages.indices.contains(page) ? pager.pages[page] as? PageGridView : nil
    }

    func prepareForShow(resetToFirstPage: Bool) {
        _ = view
        dismissConfirm()
        closeFolder()
        setEditingLayout(false)
        searchField.stringValue = ""
        endSearch()
        if resetToFirstPage { pager.scrollTo(page: 0, animated: false) }
        syncIndicator()
    }

    func focusSearch() {
        guard searchField.currentEditor() == nil else { return }
        view.window?.makeFirstResponder(searchField)
    }

    func didHide() {
        cancelDrag()
        dismissConfirm()
        setEditingLayout(false)
        pager.cancelAnimation()
        resultsPager.cancelAnimation()
    }

    func syncIndicator() {
        let active = activePager
        applyGlassStyle()
        indicator.style = prefs.pageIndicatorStyle
        indicator.pageCount = active.pageCount
        indicator.progress = CGFloat(active.currentPage)
        indicator.isHidden = isSearching && active.pageCount <= 1
    }

    // Liquid Glass on / off for the search field and the page indicator (Settings).
    private func applyGlassStyle() {
        let on = prefs.glassControls
        guard searchChrome.isGlass != on || indicator.glass != on else { return }
        searchChrome.isGlass = on
        indicator.glass = on
        view.needsLayout = true
    }

    // MARK: - Folder

    // tile: the folder's page cell (hidden while open, morph origin). animated: grow out of it.
    func openFolder(_ folder: FolderItem, apps: [AppInfo], fromTile tile: GridCellView? = nil, animated: Bool = false) {
        // Reopening the same folder (reload after a reorder / rename) stays on its current page.
        let keepPage = folderOverlay?.folderID == folder.id ? (folderOverlay?.currentPage ?? 0) : 0
        folderOverlay?.removeFromSuperview()
        let metrics = folderMetrics()
        let overlay = FolderOverlayView(
            folder: folder, apps: apps, columns: metrics.columns,
            iconSize: metrics.icon, cellWidth: metrics.cellWidth, rowHeight: metrics.rowHeight
        )
        overlay.grid.delegate = self
        overlay.grid.setEditing(isEditingLayout)
        overlay.onClose = { [weak self] in self?.closeFolder(animated: true) }
        overlay.onRename = { [weak self] name in
            self?.controller?.renameFolder(id: folder.id, name: name)
        }
        overlay.onEndEditingTitle = { [weak self] in self?.focusSearch() }
        overlay.initialPage = keepPage
        overlay.headerGap = folderHeaderGap()
        overlay.frame = view.bounds
        if let confirmOverlay {
            view.addSubview(overlay, positioned: .below, relativeTo: confirmOverlay)
        } else {
            view.addSubview(overlay)
        }
        folderOverlay = overlay
        overlay.sourceTile = tile
        tile?.isConcealed = true      // the folder "moved" into the overlay
        if animated && tile != nil { overlay.animateOpen() }
        // Pages stay at full opacity: the overlay's own blur softens them instead.
    }

    // Folder title → first icon row: half of the launcher's search field → first icon row distance.
    private func folderHeaderGap() -> CGFloat? {
        let firstIconTop = pager.frame.minY + PageGridView.firstIconTop(
            size: pager.bounds.size, columns: prefs.gridColumns, rows: prefs.gridRows)
        let gap = firstIconTop - searchChrome.frame.maxY
        return gap > 0 ? (gap / 2).rounded() : nil
    }

    // Folder grid: page icon size, half of the page's horizontal / vertical icon spacing.
    private func folderMetrics() -> (columns: Int, icon: CGFloat, cellWidth: CGFloat, rowHeight: CGFloat) {
        let size = pager.bounds.size
        let columns = prefs.gridColumns
        let rows = prefs.gridRows
        let inset = PageGridView.pageSideInset(size: size, columns: columns, rows: rows)
        let m = PageGridView.metrics(size: size, columns: columns, rows: rows, sideInset: inset)
        let labelBlock = GridCellView.gap + GridCellView.labelHeight
        let gapH = max(0, m.cellWidth - m.icon)
        let gapV = max(0, m.cellHeight - m.icon - labelBlock)
        return (max(3, min(columns, 6)), m.icon, m.icon + gapH / 2, m.icon + labelBlock + gapV / 2)
    }

    // iOS style: page icons recede (fade) while a folder is open; no dimming layer.
    func setPagesReceded(_ receded: Bool, animated: Bool) {
        let alpha: CGFloat = receded ? 0.3 : 1
        for target in [pager, resultsPager] as [NSView] {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    target.animator().alphaValue = alpha
                }
            } else {
                target.alphaValue = alpha
            }
        }
    }

    func reopenFolder(id: String) {
        guard let controller, let folder = controller.folder(id: id) else {
            closeFolder()
            return
        }
        let apps = controller.folderApps(folder)
        guard apps.count > 1 else {
            closeFolder()
            return
        }
        openFolder(folder, apps: apps, fromTile: folderTileCell(id: id))
    }

    // animated: shrink back into the folder icon (Esc / click outside).
    func closeFolder(animated: Bool = false) {
        guard let overlay = folderOverlay else { return }
        folderOverlay = nil
        if animated && overlay.sourceTile != nil {
            overlay.animateClose { overlay.removeFromSuperview() }
        } else {
            overlay.sourceTile?.isConcealed = false
            overlay.removeFromSuperview()
        }
        setPagesReceded(false, animated: animated)
        focusSearch()
    }

    // MARK: - Search

    func controlTextDidChange(_ obj: Notification) {
        updateSearch()
    }

    private func updateSearch() {
        guard let controller else { return }
        let text = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            endSearch()
            return
        }
        setEditingLayout(false)
        if folderOverlay != nil {
            folderOverlay?.removeFromSuperview()
            folderOverlay = nil
            setPagesReceded(false, animated: false)
        }

        isSearching = true
        results = controller.search(text)
        selection = 0

        let cap = capacity
        resultPages = stride(from: 0, to: results.count, by: cap).map { start in
            let chunk = results[start..<min(start + cap, results.count)]
            let page = PageGridView(columns: prefs.gridColumns, rows: prefs.gridRows, context: .results)
            page.delegate = self
            page.setEntries(chunk.map { GridEntry.app($0) })
            return page
        }
        resultsPager.setPages(resultPages)
        resultsPager.scrollTo(page: 0, animated: false)

        pager.isHidden = true
        resultsPager.isHidden = false
        emptyLabel.isHidden = !results.isEmpty
        applySelection()
        syncIndicator()
        view.needsLayout = true
    }

    private func endSearch() {
        guard isSearching || !resultsPager.pages.isEmpty else { return }
        isSearching = false
        results = []
        resultPages = []
        selection = 0
        resultsPager.setPages([])
        resultsPager.isHidden = true
        pager.isHidden = false
        emptyLabel.isHidden = true
        syncIndicator()
        view.needsLayout = true
    }

    private func applySelection() {
        let cap = capacity
        for (pageIndex, page) in resultPages.enumerated() {
            page.setSelectedIndex(selection / cap == pageIndex ? selection % cap : nil)
        }
        let page = selection / cap
        if page != resultsPager.currentPage {
            resultsPager.scrollTo(page: page, animated: true)
        }
    }

    private func moveSelection(_ direction: Direction) {
        guard isSearching else { return }
        let columns = prefs.gridColumns
        let count = results.count
        var s = selection
        switch direction {
        case .left:
            if s > 0 { s -= 1 }
        case .right:
            if s + 1 < count { s += 1 }
        case .up:
            if s >= columns { s -= columns }
        case .down:
            if s + columns < count { s += columns }
        }
        selection = s
        applySelection()
    }

    // MARK: - Keyboard (routed from the search field editor)

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            handleEscape()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            handleEnter()
            return true
        case #selector(NSResponder.moveLeft(_:)):
            return handleHorizontal(-1)
        case #selector(NSResponder.moveRight(_:)):
            return handleHorizontal(1)
        case #selector(NSResponder.moveUp(_:)):
            guard isSearching else { return false }
            moveSelection(.up)
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard isSearching else { return false }
            moveSelection(.down)
            return true
        default:
            return false
        }
    }

    private func handleHorizontal(_ delta: Int) -> Bool {
        if isSearching {
            moveSelection(delta < 0 ? .left : .right)
            return true
        }
        if folderOverlay != nil || confirmOverlay != nil { return true }
        pager.scrollTo(page: pager.currentPage + delta, animated: true)
        return true
    }

    func handleEscape() {
        if let confirmOverlay {
            confirmOverlay.cancel()
            return
        }
        if folderOverlay != nil {
            closeFolder(animated: true)
            return
        }
        if isEditingLayout {
            setEditingLayout(false)
            return
        }
        if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            endSearch()
            return
        }
        controller?.hide()
    }

    private func handleEnter() {
        if let confirmOverlay {
            confirmOverlay.confirm()
            return
        }
        guard isSearching, results.indices.contains(selection) else { return }
        controller?.launch(results[selection])
    }

    // Empty area click: leave edit mode first; otherwise close the panel (macOS 15 Launchpad)
    // or do nothing, depending on Settings.
    func handleBackgroundClick() {
        if confirmOverlay != nil { return }
        if isEditingLayout {
            setEditingLayout(false)
            return
        }
        if prefs.backgroundClickAction == .closePanel {
            controller?.hide()
        }
    }

    // Empty space for a replayed trackpad tap: page / grid gaps, the root, outside an open folder.
    // Icons and controls are excluded (a tap that stops a swipe must not launch or edit anything).
    func isEmptySpace(atWindowPoint point: NSPoint) -> Bool {
        guard let content = view.window?.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        else { return false }
        var node: NSView? = hit
        while let current = node {
            switch current {
            case is GridCellView, is NSControl, is NSText, is PageIndicatorView,
                 is ConfirmOverlayView, is GlassSearchFieldView:
                return false
            default:
                node = current.superview
            }
        }
        return true
    }
}
