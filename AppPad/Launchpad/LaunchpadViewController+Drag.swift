import AppKit
import QuartzCore

// Drag & drop of icons:
// - reorder with live reflow on the hovered page
// - hold at the left/right edge → change page (past the last page → new page)
// - merge only when moving SLOWLY: dragged icon touching another icon (≥40% overlap)
//   at low pointer speed for 250 ms → target highlights → drop makes / extends a folder.
//   Passing over icons quickly never merges (and does not reorder either).
//   When the pointer stops, speed is treated as 0 after 90 ms.
// - reorder only after the pointer stops (speed < 40 pt/s) for 280 ms, outside an icon's aim zone;
//   left half of a cell = before that icon, right half = after it.
// - drags that start in a folder reorder inside it (hold at the sheet's side → folder page flips),
//   or leave the box to go back to the pages
// - an app dragged out of the panel becomes a system file drag (drop on the Dock to add it)
struct DragState {
    let source: DragSource
    let sourceCell: GridCellView
    let item: LayoutItem
    let grabOffset: NSSize          // drag image origin − cursor (root coordinates)
    var hoverPage: Int?
    var insertIndex: Int?           // placeholder index on hoverPage (items without the dragged one)
    var pendingInsert: Int?         // placeholder waiting for the reorder dwell
    var mergeCandidate: Int?
    var mergeTarget: Int?
    var leftFolder = false
    var lastPoint: NSPoint?
    var lastTime: TimeInterval = 0
    var speed: CGFloat = 0          // smoothed pointer speed, pt/s
    var folderInsert: Int?
}

extension LaunchpadViewController {
    static let mergeSpeedLimit: CGFloat = 260     // pt/s; faster = passing through
    static let mergeDwell: Duration = .milliseconds(250)
    static let reorderSpeedLimit: CGFloat = 40   // pt/s; reorder only when (almost) stopped
    static let reorderDwell: Duration = .milliseconds(280)

    func beginDrag(grid: PageGridView, index: Int, event: NSEvent, grabPoint: NSPoint) {
        // dragImageView still attached = previous drop is landing; wait for it.
        guard drag == nil, dragImageView.superview == nil, let controller,
              grid.cells.indices.contains(index) else { return }
        let source: DragSource
        let item: LayoutItem
        switch grid.context {
        case .page(let page):
            let items = controller.layoutItems(onPage: page)
            guard items.indices.contains(index) else { return }
            source = .page(page, index)
            item = items[index]
        case .folder(let id):
            guard let folder = controller.folder(id: id), folder.apps.indices.contains(index) else { return }
            source = .folder(id, index)
            item = .app(folder.apps[index])
        case .results:
            return
        }

        let cell = grid.cells[index]
        let iconRect = root.convert(cell.visualIconRect, from: cell)
        let frame = iconRect.insetBy(dx: -iconRect.width * 0.06, dy: -iconRect.height * 0.06)
        let grab = root.convert(grabPoint, from: nil)
        dragImageView.image = cell.snapshotIcon()
        dragImageView.layer?.removeAllAnimations()   // clear a previous landing transform
        dragImageView.alphaValue = 1
        dragImageView.frame = frame
        root.addSubview(dragImageView)
        cell.isDragSource = true

        var state = DragState(
            source: source, sourceCell: cell, item: item,
            grabOffset: NSSize(width: frame.minX - grab.x, height: frame.minY - grab.y)
        )
        // Start with the placeholder where the icon was, so nothing jumps.
        if case .page(let page, let i) = source {
            state.hoverPage = page
            state.insertIndex = i
        }
        drag = state
        updateDrag(event)
    }

    func updateDrag(_ event: NSEvent) {
        guard var state = drag else { return }
        lastDragEvent = event

        // Smoothed pointer speed.
        let windowPoint = event.locationInWindow
        if let last = state.lastPoint {
            let dt = max(event.timestamp - state.lastTime, 0.001)
            let velocity = hypot(windowPoint.x - last.x, windowPoint.y - last.y) / CGFloat(dt)
            state.speed = state.speed * 0.4 + velocity * 0.6
        }
        state.lastPoint = windowPoint
        state.lastTime = event.timestamp
        drag = state
        scheduleSettle()

        let point = root.convert(event.locationInWindow, from: nil)
        dragImageView.setFrameOrigin(NSPoint(x: point.x + state.grabOffset.width, y: point.y + state.grabOffset.height))

        // Left the panel with an app → hand over to a real file drag (Dock, Finder, other apps).
        if case .app(let key) = state.item, !root.bounds.insetBy(dx: -6, dy: -6).contains(point),
           let app = controller?.app(forKey: key) {
            beginSystemDrag(app: app, state: state, event: event)
            return
        }

        if case .folder = state.source, let overlay = folderOverlay, !state.leftFolder {
            if overlay.boxContains(windowPoint: event.locationInWindow) {
                drag = state
                updateFolderHover(event)
                return
            }
            // Left the box (iOS style): the folder shrinks back into its tile and the tile
            // stops showing the dragged app right away. The overlay stays in the view tree
            // (invisible) because the source cell inside it still receives the drag events.
            state.leftFolder = true
            state.folderInsert = nil
            if case .folder(_, let index) = state.source {
                overlay.animateClose(excludingAppAt: index) {}   // overlay stays (source cell lives in it)
            }
            setPagesReceded(false, animated: true)
            if case .folder(let id, let index) = state.source {
                showFolderTile(id: id, withoutAppAt: index)
            }
        }
        drag = state
        updatePageHover(event)
    }

    // Reorder inside the open folder; the slot is taken on the page being shown (or scrolled to).
    func updateFolderHover(_ event: NSEvent) {
        guard var state = drag, case .folder(_, let sourceIndex) = state.source,
              let overlay = folderOverlay else { return }
        scheduleEdgeFlip(overlay.edgeDirection(atWindowPoint: event.locationInWindow))
        let folderGrid = overlay.grid
        let insert = min(overlay.gridSlot(atWindowPoint: event.locationInWindow), folderGrid.cells.count - 1)
        if insert != state.folderInsert {
            state.folderInsert = insert
            folderGrid.applyArrangement(
                Self.arrangement(cellCount: folderGrid.cells.count, sourceIndex: sourceIndex, placeholder: insert),
                animated: true)
        }
        drag = state
    }

    func updatePageHover(_ event: NSEvent) {
        guard var state = drag else { return }
        let pagerPoint = pager.convert(event.locationInWindow, from: nil)
        let edge = pagerPoint.x < 36 ? -1 : (pagerPoint.x > pager.bounds.width - 36 ? 1 : 0)
        scheduleEdgeFlip(edge)

        let page = pager.currentPage
        guard let grid = pageGrid(page) else { return }

        if state.hoverPage != page {
            if let old = state.hoverPage, let oldGrid = pageGrid(old) {
                clearMerge(&state, grid: oldGrid, page: old)
                oldGrid.applyArrangement(arrangement(forPage: old, grid: oldGrid, placeholder: nil, state: state), animated: true)
            }
            state.hoverPage = page
            state.insertIndex = nil
            cancelPendingReorder(&state)
        }

        let baseCount = baseItemCount(page: page, grid: grid, state: state)
        let gridPoint = grid.convert(event.locationInWindow, from: nil)
        let dragRect = grid.convert(dragImageView.frame, from: root)

        // Which icon is touched by the dragged icon, and which icon's aim zone holds the cursor.
        var touched: Int?
        var aimed: Int?
        for j in 0..<baseCount {
            let target = grid.iconRect(forSlot: Self.slot(forBase: j, placeholder: state.insertIndex))
            if aimed == nil, target.insetBy(dx: target.width * 0.15, dy: target.height * 0.15).contains(gridPoint) {
                aimed = j
            }
            let overlap = target.intersection(dragRect)
            if touched == nil, !overlap.isNull,
               overlap.width * overlap.height >= target.width * target.height * 0.4 {
                touched = j
            }
        }

        var canMerge = false
        if case .app = state.item { canMerge = true }   // folders cannot nest

        // 1. Merge: touching + slow.
        if canMerge, let candidate = touched {
            cancelPendingReorder(&state)
            if state.speed > Self.mergeSpeedLimit {
                clearMerge(&state, grid: grid, page: page)          // too fast: just passing over
            } else if candidate != state.mergeCandidate {
                clearMerge(&state, grid: grid, page: page)
                state.mergeCandidate = candidate
                startMergeTimer(candidate: candidate, page: page)
            }
            drag = state
            return
        }
        clearMerge(&state, grid: grid, page: page)

        // 2. Aiming at an icon (cursor over its center area): never reorder, wait for the merge.
        if canMerge, aimed != nil {
            cancelPendingReorder(&state)
            drag = state
            return
        }

        // 3. Reorder only after the pointer has (almost) stopped; moving — even slowly — never reorders.
        guard state.speed < Self.reorderSpeedLimit else {
            cancelPendingReorder(&state)
            drag = state
            return
        }
        let insert = insertIndex(at: gridPoint, grid: grid, baseCount: baseCount, placeholder: state.insertIndex)
        if insert == state.insertIndex {
            cancelPendingReorder(&state)
        } else if insert != state.pendingInsert {
            state.pendingInsert = insert
            scheduleReorder(insert, page: page)
        }
        drag = state
    }

    // Insert position from the cell under the cursor: left half → before that icon, right half → after it.
    private func insertIndex(at point: NSPoint, grid: PageGridView, baseCount: Int, placeholder: Int?) -> Int {
        let slot = grid.slot(at: point)
        // Base item shown in that slot (nil = the placeholder itself or an empty slot).
        var item: Int?
        for j in 0..<baseCount where Self.slot(forBase: j, placeholder: placeholder) == slot {
            item = j
            break
        }
        guard let item else {
            if let placeholder, Self.slot(forBase: placeholder, placeholder: nil) == slot { return placeholder }
            return baseCount
        }
        let cell = grid.slotRect(slot)
        return point.x < cell.midX ? item : min(item + 1, baseCount)
    }

    private func cancelPendingReorder(_ state: inout DragState) {
        reorderTask?.cancel()
        state.pendingInsert = nil
    }

    private func scheduleReorder(_ insert: Int, page: Int) {
        reorderTask?.cancel()
        reorderTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reorderDwell)
            guard !Task.isCancelled, let self, var state = self.drag,
                  state.hoverPage == page, state.pendingInsert == insert,
                  state.speed < Self.reorderSpeedLimit,
                  let grid = self.pageGrid(page) else { return }
            state.insertIndex = insert
            state.pendingInsert = nil
            self.drag = state
            grid.applyArrangement(self.arrangement(forPage: page, grid: grid, placeholder: insert, state: state), animated: true)
        }
    }

    func endDrag(_ event: NSEvent) {
        guard let state = drag else { return }
        stopDragTimers()
        drag = nil
        lastDragEvent = nil

        var target: DropTarget?
        if case .folder(_, let sourceIndex) = state.source, !state.leftFolder {
            target = .reorderInFolder(index: state.folderInsert ?? sourceIndex)   // folder reopens on reload
        } else if let page = state.hoverPage, let grid = pageGrid(page) {
            let pagerPoint = pager.convert(event.locationInWindow, from: nil)
            if pagerPoint.y > -60, pagerPoint.y < pager.bounds.height + 60 {
                if let merge = state.mergeTarget {
                    target = .merge(page: page, index: merge)
                    // The dragged icon's spot closes slowly while it flies into the target.
                    grid.applyArrangement(arrangement(forPage: page, grid: grid, placeholder: nil, state: state),
                                          animated: true, gentle: true)
                } else {
                    let index = state.pendingInsert ?? state.insertIndex ?? baseItemCount(page: page, grid: grid, state: state)
                    target = .insert(page: page, index: index)
                    // Make room now if the last reorder was still pending.
                    if index != state.insertIndex {
                        grid.applyArrangement(arrangement(forPage: page, grid: grid, placeholder: index, state: state), animated: true)
                    }
                }
            }
        }

        // Fly the icon to where it lands, then commit the layout.
        let finalTarget = target
        var isMerge = false
        if case .merge? = finalTarget { isMerge = true }
        let duration = isMerge ? Self.mergeLandingMilliseconds : Self.landingMilliseconds

        // Where the icon lands; into a folder it shrinks to its exact mini slot (first 9)
        // or to a mini-sized spot at the tile center (fading) when it will not be visible.
        var landing: (rect: NSRect?, fade: Bool) = (landingRect(for: finalTarget, state: state), false)
        if case .merge(let page, let index)? = finalTarget {
            landing = prepareMergeLanding(page: page, index: index, state: state)
        } else if finalTarget == nil, case .folder(let id, let appIndex) = state.source, state.leftFolder {
            landing = prepareFolderReturn(folderID: id, appIndex: appIndex)   // cancelled: back into its tile
        }
        animateLanding(to: landing.rect, fade: landing.fade, milliseconds: duration)
        // Merges wait for the gentle gap-closing spring so the reload does not cut it short.
        let commitDelay = isMerge ? Self.mergeCommitMilliseconds : duration + 10
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(commitDelay))
            guard let self else { return }
            self.dragImageView.removeFromSuperview()
            self.dragImageView.layer?.removeAllAnimations()
            state.sourceCell.isDragSource = false
            if case .folder = state.source, state.leftFolder {
                self.closeFolder()
            }
            if let finalTarget, let controller = self.controller {
                controller.moveItem(from: state.source, to: finalTarget)   // reloads pages (+ open folder)
            } else {
                self.reloadAll()                                       // cancelled: restore
            }
        }
    }

    static let landingMilliseconds = 240
    static let mergeLandingMilliseconds = 340
    static let mergeCommitMilliseconds = 650

    // Final icon rect in root coordinates (nil → just fade out).
    private func landingRect(for target: DropTarget?, state: DragState) -> NSRect? {
        switch target {
        case .insert(let page, let index):
            guard let grid = pageGrid(page), index < capacity else { return nil }
            var rect = grid.iconRect(forSlot: index)
            if case .folder = state.item {
                // Land exactly on the folder plate so nothing shrinks after the reload.
                let inset = rect.width * GridCellView.folderInset
                rect = rect.insetBy(dx: inset, dy: inset)
            }
            return root.convert(rect, from: grid)
        case .merge(let page, let index):
            guard let grid = pageGrid(page) else { return nil }
            let slot = Self.slot(forBase: index, placeholder: nil)   // gap is closing
            return root.convert(grid.iconRect(forSlot: slot), from: grid)
        case .reorderInFolder(let index):
            guard let folderGrid = folderOverlay?.grid else { return nil }
            return root.convert(folderGrid.iconRect(forSlot: index), from: folderGrid)
        case nil:
            // Cancelled after leaving a folder: back into the folder tile.
            if case .folder(let id, _) = state.source, state.leftFolder {
                guard let tile = folderTileCell(id: id) else { return nil }
                return root.convert(tile.visualIconRect, from: tile)
            }
            // Cancelled: back to the original cell if it is on screen.
            let cell = state.sourceCell
            guard cell.window != nil else { return nil }
            let rect = root.convert(cell.visualIconRect, from: cell)
            return root.bounds.intersects(rect) ? rect : nil
        }
    }

    // Ease the floating icon from where it was released into place, shrinking if needed.
    // Pure layer transform (model frame stays at the release spot): no view-frame animation,
    // so the image keeps its full-resolution contents and cannot drift while it scales.
    private func animateLanding(to rect: NSRect?, fade: Bool, milliseconds: Int) {
        guard let layer = dragImageView.layer else {
            dragImageView.alphaValue = 0
            return
        }
        let duration = Double(milliseconds) / 1000
        var animations: [CABasicAnimation] = []

        if let rect {
            // Start / end in layer space (read by briefly setting the frame), so flipping cannot matter.
            let releaseFrame = dragImageView.frame
            let start = layer.frame
            dragImageView.frame = rect
            let end = layer.frame
            dragImageView.frame = releaseFrame

            let scale = end.width / max(start.width, 1)
            let anchor = layer.anchorPoint
            let dx = (end.minX - start.minX) - (1 - scale) * anchor.x * start.width
            let dy = (end.minY - start.minY) - (1 - scale) * anchor.y * start.height
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            move.toValue = NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), scale, scale, 1))
            animations.append(move)
        }
        if fade || rect == nil {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1
            opacity.toValue = 0
            animations.append(opacity)
        }
        for animation in animations {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }
    }

    // Merge drop: turn the target tile into its final look with the landing slot empty,
    // and return that slot (root coordinates).
    private func prepareMergeLanding(page: Int, index: Int, state: DragState) -> (rect: NSRect?, fade: Bool) {
        guard let grid = pageGrid(page), case .app(let draggedKey) = state.item,
              let dragged = controller?.app(forKey: draggedKey) else { return (nil, true) }
        let tileIndex = cellIndex(forBase: index, page: page, state: state)
        guard grid.cells.indices.contains(tileIndex), grid.entries.indices.contains(tileIndex) else { return (nil, true) }
        let tile = grid.cells[tileIndex]
        tile.isDropTarget = false

        let apps: [AppInfo]
        switch grid.entries[tileIndex] {
        case .app(let targetApp): apps = [targetApp, dragged]           // app + app → new folder
        case .folder(_, let folderApps): apps = folderApps + [dragged]   // appended at the end
        }
        let slot = apps.count - 1
        let visible = slot < 9
        tile.showFolderPreview(icons: apps.prefix(9).map { IconCache.shared.icon(for: $0) },
                               hiddenIndex: visible ? slot : nil)
        // The tile also moves while the gap closes: aim at its final frame.
        let finalTile = grid.slotRect(Self.slot(forBase: index, placeholder: nil))
        let mini = tile.folderMiniRect(index: visible ? slot : nil)
        let rectInGrid = mini.offsetBy(dx: finalTile.minX, dy: finalTile.minY)
        return (root.convert(rectInGrid, from: grid), !visible)
    }

    // Cancelled drag out of a folder: show the tile complete again except the returning slot.
    private func prepareFolderReturn(folderID: String, appIndex: Int) -> (rect: NSRect?, fade: Bool) {
        guard let tile = folderTileCell(id: folderID), let grid = tile.grid,
              grid.entries.indices.contains(tile.index),
              case .folder(_, let apps) = grid.entries[tile.index] else { return (nil, true) }
        let visible = appIndex < 9
        tile.showFolderPreview(icons: apps.prefix(9).map { IconCache.shared.icon(for: $0) },
                               hiddenIndex: visible ? appIndex : nil)
        let mini = tile.folderMiniRect(index: visible ? appIndex : nil)
        return (root.convert(mini, from: tile), !visible)
    }

    func cancelDrag() {
        guard let state = drag else { return }
        stopDragTimers()
        dragImageView.removeFromSuperview()
        state.sourceCell.isDragSource = false
        drag = nil
        lastDragEvent = nil
        reloadAll(refreshFolder: false)
    }

    // MARK: - Helpers

    // slot per cell: source hidden (-1), others shifted around the placeholder.
    static func arrangement(cellCount: Int, sourceIndex: Int?, placeholder: Int?) -> [Int] {
        var slots = [Int](repeating: -1, count: cellCount)
        var base = 0
        for cell in 0..<cellCount {
            if cell == sourceIndex { continue }
            slots[cell] = slot(forBase: base, placeholder: placeholder)
            base += 1
        }
        return slots
    }

    static func slot(forBase base: Int, placeholder: Int?) -> Int {
        if let placeholder, base >= placeholder { return base + 1 }
        return base
    }

    private func sourceIndex(onPage page: Int, state: DragState) -> Int? {
        if case .page(let p, let i) = state.source, p == page { return i }
        return nil
    }

    private func baseItemCount(page: Int, grid: PageGridView, state: DragState) -> Int {
        grid.cells.count - (sourceIndex(onPage: page, state: state) == nil ? 0 : 1)
    }

    private func arrangement(forPage page: Int, grid: PageGridView, placeholder: Int?, state: DragState) -> [Int] {
        Self.arrangement(cellCount: grid.cells.count, sourceIndex: sourceIndex(onPage: page, state: state), placeholder: placeholder)
    }

    private func cellIndex(forBase base: Int, page: Int, state: DragState) -> Int {
        if let source = sourceIndex(onPage: page, state: state), base >= source { return base + 1 }
        return base
    }

    private func clearMerge(_ state: inout DragState, grid: PageGridView, page: Int) {
        mergeTask?.cancel()
        if let target = state.mergeTarget {
            let cell = cellIndex(forBase: target, page: page, state: state)
            if grid.cells.indices.contains(cell) { grid.cells[cell].isDropTarget = false }
        }
        state.mergeCandidate = nil
        state.mergeTarget = nil
    }

    private func startMergeTimer(candidate: Int, page: Int) {
        mergeTask?.cancel()
        mergeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.mergeDwell)
            guard !Task.isCancelled, let self, var state = self.drag,
                  state.mergeCandidate == candidate, state.hoverPage == page,
                  state.speed <= Self.mergeSpeedLimit,
                  let grid = self.pageGrid(page) else { return }
            state.mergeTarget = candidate
            self.drag = state
            let cell = self.cellIndex(forBase: candidate, page: page, state: state)
            if grid.cells.indices.contains(cell) { grid.cells[cell].isDropTarget = true }
        }
    }

    private func scheduleEdgeFlip(_ direction: Int) {
        guard direction != edgeDirection else { return }
        edgeDirection = direction
        edgeTask?.cancel()
        guard direction != 0 else { return }
        edgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, let self, self.drag != nil else { return }
                self.flipPage(direction)
            }
        }
    }

    private func flipPage(_ direction: Int) {
        guard let state = drag else { return }
        // Inside an open folder: flip the folder's pages instead.
        if case .folder = state.source, !state.leftFolder, let overlay = folderOverlay {
            overlay.flipPage(direction)
            if let event = lastDragEvent { updateFolderHover(event) }
            return
        }
        let target = pager.currentPage + direction
        guard target >= 0 else { return }
        if target >= pager.pageCount {
            // Past the last page: add an empty page, but never two empty ones in a row.
            guard let last = pageGrid(pager.pageCount - 1),
                  baseItemCount(page: pager.pageCount - 1, grid: last, state: state) > 0 else { return }
            pager.appendPage(makePageGrid(page: pager.pageCount, entries: []))
        }
        pager.scrollTo(page: target, animated: true)
        syncIndicator()
        if let event = lastDragEvent { updatePageHover(event) }
    }

    // Pointer stopped (no events) → speed 0, re-evaluate so a resting icon can merge.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self, var state = self.drag, let event = self.lastDragEvent else { return }
            state.speed = 0
            self.drag = state
            if case .folder = state.source, !state.leftFolder { return }
            self.updatePageHover(event)
        }
    }

    private func stopDragTimers() {
        mergeTask?.cancel()
        reorderTask?.cancel()
        settleTask?.cancel()
        edgeTask?.cancel()
        edgeDirection = 0
    }
}

// MARK: - System drag (outside the panel)

extension LaunchpadViewController: NSDraggingSource {

    func beginSystemDrag(app: AppInfo, state: DragState, event: NSEvent) {
        stopDragTimers()
        drag = nil
        lastDragEvent = nil

        let cell = state.sourceCell
        let frameInCell = cell.convert(dragImageView.frame, from: root)
        let image = dragImageView.image ?? IconCache.shared.icon(for: app)
        dragImageView.removeFromSuperview()

        // Put the page back as it was while the system drag runs (source spot stays empty).
        if case .page(let page, _) = state.source, let grid = pageGrid(page) {
            grid.applyArrangement(arrangement(forPage: page, grid: grid, placeholder: state.insertIndexForRestore, state: state),
                                  animated: true)
        }
        if let hover = state.hoverPage, hover != state.sourcePage, let grid = pageGrid(hover) {
            grid.applyArrangement(nil, animated: true)
        }

        systemDrag = state
        let item = NSDraggingItem(pasteboardWriter: app.url as NSURL)
        item.setDraggingFrame(frameInCell, contents: image)
        let session = cell.beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let state = systemDrag else { return }
        systemDrag = nil
        state.sourceCell.isDragSource = false
        if case .folder = state.source, state.leftFolder {
            closeFolder()
        }
        reloadAll()   // layout is unchanged; restore the page
    }
}

// MARK: - Folder tile helpers

extension LaunchpadViewController {
    // The page cell showing a folder (searches all pages).
    func folderTileCell(id: String) -> GridCellView? {
        for case let grid as PageGridView in pager.pages {
            for (index, entry) in grid.entries.enumerated() {
                if case .folder(let folder, _) = entry, folder.id == id, grid.cells.indices.contains(index) {
                    return grid.cells[index]
                }
            }
        }
        return nil
    }

    // Redraw the tile without one app; the real layout changes only on drop (reload restores on cancel).
    func showFolderTile(id: String, withoutAppAt appIndex: Int) {
        for case let grid as PageGridView in pager.pages {
            for (index, entry) in grid.entries.enumerated() {
                guard case .folder(let folder, var apps) = entry, folder.id == id,
                      grid.cells.indices.contains(index) else { continue }
                if apps.indices.contains(appIndex) { apps.remove(at: appIndex) }
                grid.cells[index].setFolderIcons(apps.prefix(9).map { IconCache.shared.icon(for: $0) })
                return
            }
        }
    }
}

extension DragState {
    var sourcePage: Int? {
        if case .page(let page, _) = source { return page }
        return nil
    }

    // Original index on the source page (keeps the empty spot where the icon came from).
    var insertIndexForRestore: Int? {
        if case .page(_, let index) = source { return index }
        return nil
    }
}
