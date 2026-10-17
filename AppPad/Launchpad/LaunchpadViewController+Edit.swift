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
        folderOverlay?.allowsTitleClicks = editing
    }

    // MARK: - PageGridDelegate

    func grid(_ grid: PageGridView, didClick index: Int) {
        // A drop that landed but is not committed yet: this grid still shows the old layout
        // (e.g. the old contents of a folder that just got an app). Commit, then click the
        // rebuilt cell under the pointer. Same when the drop committed between mouse down and up:
        // the click then arrives from a grid that is no longer in the window.
        if pendingDrop != nil || grid.window == nil {
            let location = NSApp.currentEvent?.locationInWindow
            flushPendingDrop(immediate: true)
            view.layoutSubtreeIfNeeded()
            guard let location, let content = view.window?.contentView,
                  let cell = content.hitTest(content.superview?.convert(location, from: nil) ?? location) as? GridCellView,
                  let fresh = cell.grid, fresh !== grid, fresh.window != nil else { return }
            self.grid(fresh, didClick: cell.index)
            return
        }
        guard grid.entries.indices.contains(index) else { return }
        switch grid.entries[index] {
        case .app(let app):
            guard !isEditingLayout else { return }
            controller?.launch(app)
        case .folder(let folder, let apps):
            if let overlay = folderOverlay {
                // The open folder's own (hidden) tile got the click instead of the overlay:
                // it is a click outside the sheet, so it closes the folder (never swallowed).
                CloseLog.note("folder: click on its hidden tile → close (same folder: \(overlay.folderID == folder.id))")
                closeFolder(animated: true)
                return
            }
            openFolder(folder, apps: apps, fromTile: grid.cells[index], animated: true)
        }
    }

    func grid(_ grid: PageGridView, didLongPress index: Int) {
        setEditingLayout(true)
    }

    func grid(_ grid: PageGridView, didRequestDelete index: Int) {
        guard grid.entries.indices.contains(index), case .app(let app) = grid.entries[index],
              !UninstallProgress.shared.isActive(app.key) else { return }
        presentDelete(app)
    }

    func gridDidClickBackground(_ grid: PageGridView) {
        // Pressed on a grid that a drop commit has since replaced: not a click on empty space.
        guard grid.window != nil else {
            CloseLog.note("launchpad: background click ignored (stale grid)")
            return
        }
        guard !isDropSettling else { return }     // see isDropSettling
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
        let title = app.isAppStore
            ? String(localized: "Delete “\(app.name)”?")
            : String(localized: "Uninstall “\(app.name)”?")
        let leftovers = scan.leftovers.map { ConfirmOverlayView.CheckItem(url: $0.url, checked: $0.matchedByBundleID) }
        // App bundle first, always on (it is what gets deleted).
        let items = [ConfirmOverlayView.CheckItem(url: app.url, checked: true, locked: true)] + leftovers
        let message = String(localized: "The app will be moved to the Trash.")
        showConfirm(
            icon: IconCache.shared.icon(for: app), title: title, message: message, items: items,
            confirmTitle: String(localized: "Move to Trash"), destructive: true
        ) { [weak self] urls in
            // The app row is only shown; the bundle is trashed by uninstall() itself.
            let appPath = app.url.standardizedFileURL.path
            let extra = urls.filter { $0.standardizedFileURL.path != appPath }
            self?.performUninstall(app, bundleIDs: scan.bundleIDs, extra: extra)
        }
    }

    // Progress pill under the icon while the uninstall runs; the layout changes only after the
    // success animation (icon shrinks away, the gap closes). Failure: pill stops red, then the dialog.
    private func performUninstall(_ app: AppInfo, bundleIDs: [String], extra: [URL]) {
        dismissConfirm(animated: true)
        let progress = UninstallProgress.shared
        guard let controller, !progress.isActive(app.key) else { return }
        progress.begin(app.key)
        refreshUninstallCells(key: app.key)
        controller.beginUninstall()
        Task { [weak self] in
            let result = await AppUninstaller.uninstall(app, bundleIDs: bundleIDs, extra: extra) { on in
                controller.setAuthorizing(on)
            }
            progress.finish(app.key, success: result.appRemoved)
            let visible = self?.view.window?.isVisible == true
            if result.appRemoved {
                if visible {
                    try? await Task.sleep(for: .seconds(UninstallProgress.successDuration))
                    self?.closeUninstallGap(key: app.key)
                    try? await Task.sleep(for: .milliseconds(350))
                }
                progress.clear(app.key)
                controller.endUninstall(removing: app)
            } else {
                controller.endUninstall(removing: nil)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(UninstallProgress.failureDuration))
                    progress.clear(app.key)
                    self?.refreshUninstallCells(key: app.key)
                }
                // Let the red pill be seen before the dialog covers the grid.
                if visible, result.failure != .cancelled { try? await Task.sleep(for: .milliseconds(450)) }
            }
            self?.reportUninstall(app, result: result)
        }
    }

    private func reportUninstall(_ app: AppInfo, result: AppUninstaller.Result) {
        let icon = IconCache.shared.icon(for: app)
        if !result.appRemoved {
            let title = String(localized: "Couldn’t move “\(app.name)” to the Trash.")
            switch result.failure ?? .other("") {
            case .cancelled:
                return   // password prompt cancelled by the user
            case .automationDenied:
                showConfirm(
                    icon: icon, title: title,
                    message: String(localized: "This app belongs to the system administrator, so AppPad asks Finder to delete it. Allow AppPad to control Finder in System Settings › Privacy & Security › Automation, then try again."),
                    items: [], confirmTitle: String(localized: "Open System Settings"), destructive: false
                ) { [weak self] _ in
                    self?.dismissConfirm(animated: true)
                    self?.controller?.hide()
                    Self.openAutomationSettings()
                }
            case .stillRunning:
                showErrorConfirm(icon: icon, title: title,
                                 message: String(localized: "The app didn’t quit. Quit it and try again."))
            case .other(let description):
                showErrorConfirm(icon: icon, title: title, message: description.isEmpty
                    ? String(localized: "Try again. Deleting it may require an administrator password.")
                    : description)
            }
        } else if !result.failed.isEmpty {
            // Usually protected containers (no Full Disk Access): offer to reveal them in Finder.
            var message = String(localized: "To remove them automatically, allow AppPad Full Disk Access in System Settings › Privacy & Security. You can also delete them in Finder.")
            if let cask = result.homebrewFailedCask { message += "\n\n" + Self.homebrewHelp(cask) }
            showConfirm(
                icon: icon,
                title: String(localized: "Some related files of “\(app.name)” couldn’t be moved to the Trash."),
                message: message,
                items: result.failed.map { ConfirmOverlayView.CheckItem(url: $0, checked: true) },
                confirmTitle: String(localized: "Show in Finder"), destructive: false
            ) { [weak self] urls in
                self?.dismissConfirm(animated: true)
                guard !urls.isEmpty else { return }
                self?.controller?.hide()
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        } else if let cask = result.homebrewFailedCask {
            // App is in the Trash, only the Homebrew record is left (e.g. its uninstall needs sudo).
            showConfirm(
                icon: icon,
                title: String(localized: "Homebrew couldn’t remove the cask of “\(app.name)”."),
                message: Self.homebrewHelp(cask),
                items: [], confirmTitle: String(localized: "Copy Command"), destructive: false
            ) { [weak self] _ in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(HomebrewCask.command(for: cask), forType: .string)
                self?.dismissConfirm(animated: true)
            }
        }
    }

    private func showErrorConfirm(icon: NSImage?, title: String, message: String) {
        showConfirm(icon: icon, title: title, message: message, items: [],
                    confirmTitle: String(localized: "OK"), destructive: false, showsCancel: false
        ) { [weak self] _ in self?.dismissConfirm(animated: true) }
    }

    private static func openAutomationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Uninstall progress cells

    // Every grid that can show the app: pages, search results, the open folder.
    private var uninstallGrids: [PageGridView] {
        (pager.pages + resultsPager.pages).compactMap { $0 as? PageGridView } + [folderOverlay?.grid].compactMap { $0 }
    }

    private func refreshUninstallCells(key: String) {
        for grid in uninstallGrids {
            for cell in grid.cells where cell.appKey == key { cell.refreshUninstallState() }
        }
    }

    // The trashed app's slot closes: the following icons slide back by one before the reload.
    private func closeUninstallGap(key: String) {
        for grid in uninstallGrids {
            guard let index = grid.cells.firstIndex(where: { $0.appKey == key }) else { continue }
            grid.cells[index].alphaValue = 0
            let slots = grid.cells.indices.map { $0 < index ? $0 : ($0 == index ? -1 : $0 - 1) }
            grid.applyArrangement(slots, animated: true)
        }
    }

    private static func homebrewHelp(_ cask: String) -> String {
        String(localized: "The app is already in the Trash. To remove it from Homebrew too, run this command in Terminal:")
            + "\n" + HomebrewCask.command(for: cask)
    }

    func showConfirm(icon: NSImage?, title: String, message: String, items: [ConfirmOverlayView.CheckItem],
                     confirmTitle: String, destructive: Bool, showsCancel: Bool = true,
                     onConfirm: @escaping ([URL]) -> Void) {
        // A dialog still fading out hands its blur level over (no flash back to clear).
        let fading = view.subviews.compactMap { $0 as? ConfirmOverlayView }.filter(\.isClosing)
        let start = fading.map(\.progress).max() ?? 0
        fading.forEach { $0.removeNow() }
        dismissConfirm()
        let overlay = ConfirmOverlayView(
            icon: icon, title: title, message: message, items: items,
            confirmTitle: confirmTitle, destructive: destructive, showsCancel: showsCancel,
            cornerRadius: LaunchpadController.cornerRadius
        )
        overlay.onConfirm = onConfirm
        overlay.onCancel = { [weak self] in self?.dismissConfirm(animated: true) }
        overlay.frame = view.bounds
        view.addSubview(overlay)
        confirmOverlay = overlay
        overlay.animateIn(from: start)
    }

    // animated: blur clears gradually (cancel / done); otherwise gone at once (panel hide / show).
    func dismissConfirm(animated: Bool = false) {
        if let overlay = confirmOverlay {
            confirmOverlay = nil
            if animated { overlay.animateOut() } else { overlay.removeNow() }
        }
        if !animated {
            // Panel hide / show: also drop any dialog still fading out.
            view.subviews.compactMap { $0 as? ConfirmOverlayView }.forEach { $0.removeNow() }
        }
        focusSearch()
    }
}
