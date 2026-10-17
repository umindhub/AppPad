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
    // Extra top margin when the panel reaches into a notched screen's top area (camera housing).
    var topInset: CGFloat = 0 {
        didSet { if topInset != oldValue { view.needsLayout = true } }
    }
    // Panel fills the screen: search field lower down (fillSearchPosition of the way from the safe top
    // edge to the first icon row), page dots halfway between field and icons.
    var fillsScreen = false {
        didSet { if fillsScreen != oldValue { view.needsLayout = true } }
    }
    private static let fillSearchPosition: CGFloat = 0.42
    var drag: DragState?
    var lastDragEvent: NSEvent?
    var mergeTask: Task<Void, Never>?
    var reorderTask: Task<Void, Never>?
    var settleTask: Task<Void, Never>?
    var systemDrag: DragState?          // app handed over to an NSDraggingSession
    var edgeTask: Task<Void, Never>?
    var edgeDirection = 0
    var optionHoldTask: Task<Void, Never>?   // hold ⌥ → edit mode (+Edit.swift)
    // Drop landed visually but the layout is not committed yet (+Drag.swift); run(immediate).
    var pendingDrop: (token: UUID, run: (Bool) -> Void)?
    // Short quiet time after a drop commits: the pages were just rebuilt, so a click that started
    // on the old cells / grids must not count as "empty space" (+Drag.swift sets it).
    var dropQuietUntil: TimeInterval = 0
    static let dropQuietInterval: TimeInterval = 0.6

    private let emptyLabel = NSTextField(labelWithString: String(localized: "No Results"))

    private(set) var isSearching = false
    // Search results: top-level apps and folders holding a match or matching by name
    // (best = the app that matched best; nil for a folder found only by its name).
    private var results: [(entry: GridEntry, best: AppInfo?)] = []
    private var resultPages: [PageGridView] = []
    private var selection = 0   // index into results
    // Folder opened from the results: its best-matching app is highlighted (↩ launches it).
    private var folderSelection: Int?
    // App just merged into a result (+Drag.swift): ignored when the new folder takes its slot.
    var searchDroppedKey: String?

    var prefs: Preferences { .shared }
    var capacity: Int { max(1, prefs.gridColumns * prefs.gridRows) }
    var activePager: PagerView { isSearching ? resultsPager : pager }

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
        dragImageView.shadow = Self.dragShadow

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
        let top: CGFloat = topInset + 76
        // Breathing room under the last icon row (labels no longer hug the bottom edge).
        let bottom = b.height - Self.bottomPadding
        // Each page adds a small side margin so pages are 1.5× the icon gap apart (PageGridView.pageGapFactor).
        let gridRect = NSRect(x: pad, y: top, width: b.width - 2 * pad, height: max(0, bottom - top))
        pager.frame = gridRect
        resultsPager.frame = gridRect
        let firstIconTop = gridRect.minY + PageGridView.firstIconTop(
            size: gridRect.size, columns: prefs.gridColumns, rows: prefs.gridRows)

        // Field: centered at y 36 below the safe top, or lower when filling the screen
        // (same 32 pt capsule with and without glass).
        let fieldHeight = searchChrome.preferredHeight
        let span = firstIconTop - topInset
        let fieldCenter = fillsScreen ? topInset + span * Self.fillSearchPosition : topInset + 36
        searchChrome.frame = NSRect(x: ((b.width - fieldWidth) / 2).rounded(), y: (fieldCenter - fieldHeight / 2).rounded(),
                                    width: fieldWidth, height: fieldHeight)
        let searchBottom = searchChrome.frame.maxY

        // Indicator: halfway between the field and the first icon row.
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
        let displayPages = controller.displayPages()
        let pages = displayPages.enumerated().map { index, entries in
            makePageGrid(page: index, entries: entries)
        }
        pager.setPages(pages)
        warmFolderIcons(displayPages)
        if isSearching { updateSearch(fromReload: true) }
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

    // Apps inside folders are on no page, so their icons were never rendered at full size:
    // render the first page's worth of each folder in idle slices, so opening never waits.
    private static let warmAppsPerFolder = 24

    private func warmFolderIcons(_ pages: [[GridEntry]]) {
        var apps: [AppInfo] = []
        for entries in pages {
            for case .folder(_, let folderApps) in entries {
                apps.append(contentsOf: folderApps.prefix(Self.warmAppsPerFolder))
            }
        }
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        IconCache.shared.warm(apps, scale: scale)
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
        cancelOptionHold()
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
        if isSearching { highlightSearchMatch(in: overlay, apps: apps) } else { folderSelection = nil }
        if animated && tile != nil { overlay.animateOpen() }
        // Pages stay at full opacity: the overlay's own blur softens them instead.
    }

    // Highlight the app that made this folder show up in the results (none for a name match).
    private func highlightSearchMatch(in overlay: FolderOverlayView, apps: [AppInfo]) {
        let best = results.first { result in
            if case .folder(let folder, _) = result.entry { return folder.id == overlay.folderID }
            return false
        }?.best
        folderSelection = best.flatMap { best in apps.firstIndex { $0.key == best.key } }
        overlay.grid.setSelectedIndex(folderSelection)
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
        folderSelection = nil
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

    // fromReload: layout changed while searching (drop in a folder, uninstall) — keep the open
    // folder, the results page and the selection.
    private func updateSearch(fromReload: Bool = false) {
        guard let controller else { return }
        let text = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            endSearch()
            return
        }
        // Edit mode survives searching (delete straight from the results).
        if !fromReload { discardFolderOverlay() }

        let keepPage = fromReload && isSearching ? resultsPager.currentPage : 0
        let keepSelection = fromReload && isSearching ? selection : 0
        let fresh = controller.searchEntries(text)
        results = fromReload && isSearching ? keepingOrder(fresh, ignoring: searchDroppedKey) : fresh
        searchDroppedKey = nil
        isSearching = true
        selection = min(keepSelection, max(0, results.count - 1))

        let cap = capacity
        resultPages = stride(from: 0, to: results.count, by: cap).map { start in
            let chunk = results[start..<min(start + cap, results.count)]
            let page = PageGridView(columns: prefs.gridColumns, rows: prefs.gridRows, context: .results)
            page.delegate = self
            page.setEntries(chunk.map { $0.entry })
            page.setEditing(isEditingLayout)
            return page
        }
        resultsPager.setPages(resultPages)
        resultsPager.scrollTo(page: min(keepPage, max(0, resultPages.count - 1)), animated: false)

        pager.isHidden = true
        resultsPager.isHidden = false
        emptyLabel.isHidden = !results.isEmpty
        applySelection(scroll: !fromReload)
        syncIndicator()
        view.needsLayout = true
    }

    // Reload while searching (merge, folder edit, uninstall): results keep their previous order
    // instead of being re-ranked. A new folder takes the slot of the app it was made from
    // (ignoring: the app dropped onto it); anything new goes last, in rank order.
    private func keepingOrder(_ fresh: [(entry: GridEntry, best: AppInfo?)],
                              ignoring droppedKey: String?) -> [(entry: GridEntry, best: AppInfo?)] {
        var oldIndex: [String: Int] = [:]
        for (index, result) in results.enumerated() {
            switch result.entry {
            case .app(let app):
                if oldIndex["a:" + app.key] == nil { oldIndex["a:" + app.key] = index }
            case .folder(let folder, let apps):
                oldIndex["f:" + folder.id] = index
                for app in apps where oldIndex["a:" + app.key] == nil { oldIndex["a:" + app.key] = index }
            }
        }
        func slot(_ entry: GridEntry) -> Int {
            switch entry {
            case .app(let app):
                return oldIndex["a:" + app.key] ?? Int.max
            case .folder(let folder, let apps):
                if let index = oldIndex["f:" + folder.id] { return index }
                return apps.filter { $0.key != droppedKey }.compactMap { oldIndex["a:" + $0.key] }.min() ?? Int.max
            }
        }
        return fresh.enumerated()
            .sorted { a, b in
                let sa = slot(a.element.entry), sb = slot(b.element.entry)
                return sa != sb ? sa < sb : a.offset < b.offset
            }
            .map { $0.element }
    }

    // Open folder dropped without animation (search text changed / cleared).
    private func discardFolderOverlay() {
        guard let overlay = folderOverlay else { return }
        overlay.removeFromSuperview()
        folderOverlay = nil
        folderSelection = nil
        setPagesReceded(false, animated: false)
    }

    private func endSearch() {
        guard isSearching || !resultsPager.pages.isEmpty else { return }
        discardFolderOverlay()     // its tile lives in the results
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

    private func applySelection(scroll: Bool = true) {
        let cap = capacity
        for (pageIndex, page) in resultPages.enumerated() {
            page.setSelectedIndex(selection / cap == pageIndex ? selection % cap : nil)
        }
        let page = selection / cap
        if scroll, page != resultsPager.currentPage {
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
            if folderOverlay == nil { moveSelection(.up) }
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard isSearching else { return false }
            if folderOverlay == nil { moveSelection(.down) }
            return true
        default:
            return false
        }
    }

    private func handleHorizontal(_ delta: Int) -> Bool {
        if folderOverlay != nil || confirmOverlay != nil { return true }
        if isSearching {
            moveSelection(delta < 0 ? .left : .right)
            return true
        }
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
        // Open folder / edit mode / confirm still close first; only the search step is optional.
        if prefs.escClearsSearchFirst, !searchField.stringValue.isEmpty {
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
        if let overlay = folderOverlay {
            // Folder opened from the results: launch its highlighted app.
            guard isSearching, let index = folderSelection, overlay.grid.entries.indices.contains(index),
                  case .app(let app) = overlay.grid.entries[index] else { return }
            controller?.launch(app)
            return
        }
        guard isSearching, results.indices.contains(selection) else { return }
        switch results[selection].entry {
        case .app(let app):
            controller?.launch(app)
        case .folder(let folder, let apps):
            let cap = capacity
            let page = selection / cap
            let tile: GridCellView? = resultPages.indices.contains(page) && resultPages[page].cells.indices.contains(selection % cap)
                ? resultPages[page].cells[selection % cap] : nil
            openFolder(folder, apps: apps, fromTile: tile, animated: tile != nil)
        }
    }

    // Empty area click: leave edit mode first; otherwise close the panel (macOS 15 Launchpad)
    // or do nothing, depending on Settings.
    func handleBackgroundClick() {
        if confirmOverlay != nil { return }
        if isDropSettling {
            CloseLog.note("launchpad: background click ignored (drop settling)")
            return
        }
        if isEditingLayout {
            setEditingLayout(false)
            return
        }
        if prefs.backgroundClickAction == .closePanel {
            CloseLog.note("launchpad: background click")
            controller?.hide(animated: true, duration: LaunchpadController.backgroundClickHideDuration)
        }
    }

    // A drop still landing (icon flying, gap closing, folder forming): tiles are drawn away from
    // their final frames (hit testing uses those), so a click on what looks like an icon can land
    // on "empty" space. Such clicks must not close the panel or leave edit mode.
    var isDropInFlight: Bool {
        drag != nil || systemDrag != nil || pendingDrop != nil || dragImageView.superview != nil
    }

    // In flight, or committed so recently that a click may have started on the old layout.
    var isDropSettling: Bool {
        isDropInFlight || ProcessInfo.processInfo.systemUptime < dropQuietUntil
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
