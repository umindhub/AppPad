import AppKit

// Edit mode (wiggle + delete badges, long press or hold ⌥), grid callbacks, context menus, delete / uninstall.
extension LaunchpadViewController: PageGridDelegate {

    // MARK: - Edit mode

    func setEditingLayout(_ editing: Bool) {
        guard editing != isEditingLayout else { return }
        isEditingLayout = editing
        for page in pager.pages + resultsPager.pages {
            (page as? PageGridView)?.setEditing(editing)
        }
        folderOverlay?.grid.setEditing(editing)
    }

    // MARK: - PageGridDelegate

    func grid(_ grid: PageGridView, didClick index: Int) {
        // A drop that landed but is not committed yet: this grid still shows the old layout
        // (e.g. the old contents of a folder that just got an app). Commit, then click the
        // rebuilt cell under the pointer.
        if pendingDrop != nil {
            let location = NSApp.currentEvent?.locationInWindow
            flushPendingDrop(immediate: true)
            view.layoutSubtreeIfNeeded()
            guard let location, let content = view.window?.contentView,
                  let cell = content.hitTest(content.superview?.convert(location, from: nil) ?? location) as? GridCellView,
                  let fresh = cell.grid, fresh !== grid else { return }
            self.grid(fresh, didClick: cell.index)
            return
        }
        guard grid.entries.indices.contains(index) else { return }
        switch grid.entries[index] {
        case .app(let app):
            guard !isEditingLayout else { return }
            controller?.launch(app)
        case .folder(let folder, let apps):
            openFolder(folder, apps: apps, fromTile: grid.cells[index], animated: true)
        }
    }

    func grid(_ grid: PageGridView, didLongPress index: Int) {
        setEditingLayout(true)
    }

    func grid(_ grid: PageGridView, didRequestDelete index: Int) {
        guard grid.entries.indices.contains(index), case .app(let app) = grid.entries[index] else { return }
        presentDelete(app)
    }

    func gridDidClickBackground(_ grid: PageGridView) {
        if case .folder = grid.context {
            // Empty space inside an open folder never closes the panel.
            if isEditingLayout { setEditingLayout(false) }
            return
        }
        handleBackgroundClick()
    }

    func grid(_ grid: PageGridView, menuFor index: Int) -> NSMenu? {
        guard grid.entries.indices.contains(index) else { return nil }
        let menu = NSMenu()
        switch grid.entries[index] {
        case .app(let app):
            menu.addItem(ClosureMenuItem(String(localized: "Open")) { [weak self] in
                self?.controller?.launch(app)
            })
            menu.addItem(ClosureMenuItem(String(localized: "Show in Finder")) { [weak self] in
                self?.controller?.hide()
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            })
            menu.addItem(ClosureMenuItem(String(localized: "Set Shortcut…")) { [weak self] in
                self?.controller?.requestShortcut(for: app)
            })
            if !app.isSystem, app.bundleID != Bundle.main.bundleIdentifier {
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem(String(localized: "Move to Trash…")) { [weak self] in
                    self?.presentDelete(app)
                })
            }
        case .folder(let folder, let apps):
            let cell = grid.cells[index]
            menu.addItem(ClosureMenuItem(String(localized: "Open Folder")) { [weak self] in
                guard let self else { return }
                self.openFolder(folder, apps: apps, fromTile: cell, animated: true)
            })
            menu.addItem(ClosureMenuItem(String(localized: "Rename…")) { [weak self] in
                guard let self else { return }
                self.openFolder(folder, apps: apps, fromTile: cell, animated: true)
                self.folderOverlay?.beginRenaming()
            })
        }
        return menu
    }

    // Drag callbacks → +Drag.swift
    func grid(_ grid: PageGridView, didBeginDrag index: Int, event: NSEvent, grabPoint: NSPoint) {
        beginDrag(grid: grid, index: index, event: event, grabPoint: grabPoint)
    }

    func grid(_ grid: PageGridView, dragMoved event: NSEvent) {
        updateDrag(event)
    }

    func grid(_ grid: PageGridView, dragEnded event: NSEvent) {
        endDrag(event)
    }

    // MARK: - Hold ⌥ (macOS 15 Launchpad)

    static let optionHoldDelay: Duration = .milliseconds(500)

    // ⌥ alone held for a moment enters edit mode (stays after release, like a long press).
    // Any other key / modifier, click or scroll cancels.
    func observeOptionHold(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.type == .flagsChanged, modifiers == .option, canStartOptionHold else {
            cancelOptionHold()
            return
        }
        guard optionHoldTask == nil else { return }   // second ⌥ key while the first is held
        optionHoldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.optionHoldDelay)
            guard let self, !Task.isCancelled else { return }
            self.optionHoldTask = nil
            if self.canStartOptionHold { self.setEditingLayout(true) }
        }
    }

    func cancelOptionHold() {
        optionHoldTask?.cancel()
        optionHoldTask = nil
    }

    private var canStartOptionHold: Bool {
        guard !isEditingLayout, confirmOverlay == nil, drag == nil, systemDrag == nil,
              view.window?.isVisible == true else { return false }
        // Typing in another field (folder rename): ⌥ is for characters there.
        if let editor = view.window?.firstResponder as? NSTextView,
           (editor.delegate as AnyObject?) !== searchField { return false }
        return true
    }

    // MARK: - Delete / uninstall

    // Every deletable app gets the leftover list (App Store apps keep data in their containers).
    // The scan runs off the main thread; the dialog appears when it is done.
    func presentDelete(_ app: AppInfo) {
        let installed = controller?.installedBundleIDs ?? []
        Task { [weak self] in
            let scan = await Task.detached(priority: .userInitiated) {
                AppUninstaller.scan(app, installedIDs: installed)
            }.value
            guard let self, self.view.window?.isVisible == true else { return }
            self.showDeleteConfirm(app, scan: scan)
        }
    }

    private func showDeleteConfirm(_ app: AppInfo, scan: AppUninstaller.Scan) {
        let isRunning = app.bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
        let title = app.isAppStore
            ? String(localized: "Delete “\(app.name)”?")
            : String(localized: "Uninstall “\(app.name)”?")
        let items = scan.leftovers.map { ConfirmOverlayView.CheckItem(url: $0.url, checked: $0.matchedByBundleID) }
        var message = items.isEmpty
            ? String(localized: "The app will be moved to the Trash. No related files were found.")
            : String(localized: "The app and the checked related files will be moved to the Trash.")
        if items.contains(where: { $0.url.path.hasPrefix("/Library/") }) {
            message += "\n" + String(localized: "Files in /Library may require an administrator password.")
        }
        if isRunning {
            message += "\n" + String(localized: "The app is running and will be quit first.")
        }
        showConfirm(
            icon: IconCache.shared.icon(for: app), title: title, message: message, items: items,
            confirmTitle: String(localized: "Move to Trash"), destructive: true
        ) { [weak self] urls in
            self?.performUninstall(app, bundleIDs: scan.bundleIDs, extra: urls)
        }
    }

    private func performUninstall(_ app: AppInfo, bundleIDs: [String], extra: [URL]) {
        dismissConfirm()
        Task { [weak self] in
            guard let controller = self?.controller else { return }
            let result = await controller.uninstall(app, bundleIDs: bundleIDs, extra: extra)
            guard let self else { return }
            let icon = IconCache.shared.icon(for: app)
            if !result.appRemoved {
                self.showConfirm(
                    icon: icon,
                    title: String(localized: "Couldn’t move “\(app.name)” to the Trash."),
                    message: String(localized: "Quit the app and try again. Deleting it may also require an administrator password."),
                    items: [], confirmTitle: String(localized: "OK"), destructive: false, showsCancel: false
                ) { [weak self] _ in self?.dismissConfirm() }
            } else if !result.failed.isEmpty {
                // Usually protected containers (no Full Disk Access): offer to reveal them in Finder.
                self.showConfirm(
                    icon: icon,
                    title: String(localized: "Some related files of “\(app.name)” couldn’t be moved to the Trash."),
                    message: String(localized: "To remove them automatically, allow AppPad Full Disk Access in System Settings › Privacy & Security. You can also delete them in Finder."),
                    items: result.failed.map { ConfirmOverlayView.CheckItem(url: $0, checked: true) },
                    confirmTitle: String(localized: "Show in Finder"), destructive: false
                ) { [weak self] urls in
                    self?.dismissConfirm()
                    guard !urls.isEmpty else { return }
                    self?.controller?.hide()
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            }
        }
    }

    func showConfirm(icon: NSImage?, title: String, message: String, items: [ConfirmOverlayView.CheckItem],
                     confirmTitle: String, destructive: Bool, showsCancel: Bool = true,
                     onConfirm: @escaping ([URL]) -> Void) {
        dismissConfirm()
        let overlay = ConfirmOverlayView(
            icon: icon, title: title, message: message, items: items,
            confirmTitle: confirmTitle, destructive: destructive, showsCancel: showsCancel,
            cornerRadius: LaunchpadController.cornerRadius
        )
        overlay.onConfirm = onConfirm
        overlay.onCancel = { [weak self] in self?.dismissConfirm() }
        overlay.frame = view.bounds
        view.addSubview(overlay)
        confirmOverlay = overlay
    }

    func dismissConfirm() {
        confirmOverlay?.removeFromSuperview()
        confirmOverlay = nil
        focusSearch()
    }
}
