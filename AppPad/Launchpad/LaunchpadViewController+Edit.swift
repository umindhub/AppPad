import AppKit

// Edit mode (wiggle + delete badges), grid callbacks, context menus, delete / uninstall.
extension LaunchpadViewController: PageGridDelegate {

    // MARK: - Edit mode

    func setEditingLayout(_ editing: Bool) {
        guard editing != isEditingLayout else { return }
        isEditingLayout = editing
        for page in pager.pages {
            (page as? PageGridView)?.setEditing(editing)
        }
        folderOverlay?.grid.setEditing(editing)
    }

    // MARK: - PageGridDelegate

    func grid(_ grid: PageGridView, didClick index: Int) {
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

    // MARK: - Delete / uninstall

    // App Store apps: plain move to Trash. Others: uninstall with leftover file list.
    func presentDelete(_ app: AppInfo) {
        let isRunning = app.bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
        var items: [ConfirmOverlayView.CheckItem] = []
        let title: String
        var message: String
        if app.isAppStore {
            title = String(localized: "Delete “\(app.name)”?")
            message = String(localized: "The app will be moved to the Trash.")
        } else {
            title = String(localized: "Uninstall “\(app.name)”?")
            let leftovers = AppUninstaller.findLeftovers(for: app)
            items = leftovers.map { ConfirmOverlayView.CheckItem(url: $0.url, checked: $0.matchedByBundleID) }
            message = leftovers.isEmpty
                ? String(localized: "The app will be moved to the Trash. No related files were found.")
                : String(localized: "The app and the checked related files will be moved to the Trash.")
        }
        if isRunning {
            message += "\n" + String(localized: "The app is running and will be quit first.")
        }
        showConfirm(
            icon: IconCache.shared.icon(for: app), title: title, message: message, items: items,
            confirmTitle: String(localized: "Move to Trash"), destructive: true
        ) { [weak self] urls in
            self?.performUninstall(app, extra: urls)
        }
    }

    private func performUninstall(_ app: AppInfo, extra: [URL]) {
        dismissConfirm()
        Task { [weak self] in
            guard let controller = self?.controller else { return }
            let ok = await controller.uninstall(app, extra: extra)
            guard !ok, let self else { return }
            self.showConfirm(
                icon: IconCache.shared.icon(for: app),
                title: String(localized: "Couldn’t move “\(app.name)” to the Trash."),
                message: String(localized: "Quit the app and try again."),
                items: [], confirmTitle: String(localized: "OK"), destructive: false, showsCancel: false
            ) { [weak self] _ in self?.dismissConfirm() }
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
