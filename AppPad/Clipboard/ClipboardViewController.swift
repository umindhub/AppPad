import AppKit
import Carbon.HIToolbox

// Layout: title + one line of shortcut hints (left, the block centered on the search line), search field, app filter chips,
// list (2/3) | preview (1/3).
// The search field always keeps focus; arrows, ⌘J/K, Enter and ⌘1–⌘0 drive the list.
// Mouse: hovering a row selects it, a single click pastes it.
final class ClipboardViewController: NSViewController, NSSearchFieldDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    weak var controller: ClipboardController?

    let root = FlippedView()
    private let searchChrome = GlassSearchFieldView()
    private var searchField: NSSearchField { searchChrome.field }
    private let header = PanelHeaderView(title: String(localized: "Clipboard"), hints: [
        .init(keys: "⌘K/J", action: String(localized: "Up/Down")),
        .init(keys: "⌘⇧K/J", action: String(localized: "Switch")),
    ])
    private let savedToggle = SavedToggleView()
    private let filterBar = AppFilterBarView()
    private let scrollView = NSScrollView()
    private let tableView = ClipTableView()
    private let divider = NSBox()
    private let preview = ClipPreviewView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private(set) var scope: ClipScope = .history
    private var items: [ClipSummary] = []
    private var listFont = NSFont.systemFont(ofSize: 15)

    private var prefs: Preferences { .shared }
    private var store: ClipboardStore? { controller?.store }

    private static let listLimit = 300
    private static let chipSample = 100
    private static let chipCount = 5
    private static let pad: CGFloat = 24
    // Carbon key codes → ⌘1…⌘0 (layout independent).
    private static let digitKeys: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 0, UInt16(kVK_ANSI_2): 1, UInt16(kVK_ANSI_3): 2, UInt16(kVK_ANSI_4): 3,
        UInt16(kVK_ANSI_5): 4, UInt16(kVK_ANSI_6): 5, UInt16(kVK_ANSI_7): 6, UInt16(kVK_ANSI_8): 7,
        UInt16(kVK_ANSI_9): 8, UInt16(kVK_ANSI_0): 9,
    ]

    // MARK: - View

    override func loadView() {
        root.wantsLayer = true
        root.layer?.cornerRadius = LaunchpadController.cornerRadius
        root.layer?.masksToBounds = true
        view = root

        searchField.placeholderString = String(localized: "Search clipboard")
        searchField.delegate = self
        searchField.focusRingType = .none

        savedToggle.toolTip = String(localized: "Show saved items only")
        savedToggle.onToggle = { [weak self] in
            guard let self else { return }
            self.setScope(self.scope == .saved ? .history : .saved)
            self.focusSearch()
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)   // gap drawn by ClipTableRowView inset
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onHoverRow = { [weak self] row in self?.hoverSelect(row) }
        tableView.onClickRow = { [weak self] row in self?.activate(row: row) }
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        divider.boxType = .separator
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.isHidden = true

        filterBar.onToggle = { [weak self] bundleID in self?.toggleAppFilter(bundleID) }
        preview.onEscape = { [weak self] in self?.focusSearch() }

        [scrollView, divider, preview, filterBar, searchChrome, header, savedToggle, emptyLabel].forEach {
            root.addSubview($0)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(storeDidChange(_:)), name: .clipboardStoreDidChange, object: nil
        )
        applyPreferences()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let b = view.bounds
        let pad = Self.pad

        let fieldHeight = searchChrome.preferredHeight
        // Left: title + hints block, its center on the search field's center. Center: search field.
        // Right of it: [★ Saved], same height and line.
        let headerSize = header.preferredSize
        if savedToggle.height != fieldHeight { savedToggle.setHeight(fieldHeight) }
        let toggleWidth = savedToggle.intrinsicContentSize.width
        let gap: CGFloat = 10
        let side = max(headerSize.width + 16, toggleWidth + gap + 16)
        let fieldWidth = max(160, min(560, b.width - 2 * pad - 2 * side))
        searchChrome.frame = NSRect(x: ((b.width - fieldWidth) / 2).rounded(),
                                    y: 18,
                                    width: fieldWidth, height: fieldHeight)
        savedToggle.frame = NSRect(x: searchChrome.frame.maxX + gap, y: searchChrome.frame.minY,
                                   width: toggleWidth, height: fieldHeight)
        header.frame = NSRect(x: pad, y: (searchChrome.frame.midY - headerSize.height / 2).rounded(),
                              width: headerSize.width, height: headerSize.height)

        filterBar.frame = NSRect(x: pad, y: searchChrome.frame.maxY + 8, width: b.width - 2 * pad,
                                 height: AppFilterBarView.chipSize + 4)
        let top = max(filterBar.frame.maxY + 8, header.frame.maxY + 8)
        let bottom = b.height - 18
        let inner = b.width - 2 * pad
        let listWidth = (inner * 2 / 3).rounded()
        scrollView.frame = NSRect(x: pad, y: top, width: listWidth - 8, height: max(0, bottom - top))
        divider.frame = NSRect(x: pad + listWidth, y: top, width: 1, height: max(0, bottom - top))
        preview.frame = NSRect(x: pad + listWidth + 14, y: top + 2,
                               width: max(0, inner - listWidth - 14), height: max(0, bottom - top - 2))
        emptyLabel.frame = NSRect(x: pad, y: top + 40, width: listWidth - 8, height: 22)
        tableView.sizeLastColumnToFit()
    }

    // MARK: - Show / hide

    func prepareForShow(scope: ClipScope) {
        _ = view
        self.scope = scope
        searchField.stringValue = ""
        updateScopeLabel()
        reload(selectFirst: true)
    }

    // ⌘⇧J / ⌘⇧K / hotkey while visible: keep the typed search.
    func setScope(_ newScope: ClipScope) {
        _ = view
        scope = newScope
        updateScopeLabel()
        reload(selectFirst: true)
    }

    func focusSearch() {
        guard let window = view.window else { return }
        if searchField.currentEditor() == nil { window.makeFirstResponder(searchField) }
        if let editor = searchField.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    func didHide() {
        preview.show(nil, font: listFont, store: nil)
    }

    func applyPreferences() {
        _ = view
        searchChrome.isGlass = prefs.glassControls
        savedToggle.isGlass = prefs.glassControls
        searchChrome.textFont = ClipboardFonts.make(family: prefs.clipboardSearchFontFamily,
                                                    size: prefs.clipboardSearchFontSize)
        listFont = ClipboardFonts.make(family: prefs.clipboardListFontFamily, size: prefs.clipboardListFontSize)
        tableView.rowHeight = max(36, ceil(ClipboardFonts.lineHeight(listFont)) + 20)
        if view.window?.isVisible == true { reload(selectFirst: false) }
        view.needsLayout = true
    }

    private func updateScopeLabel() {
        savedToggle.isOn = scope == .saved
    }

    // MARK: - Data

    @objc private func storeDidChange(_ note: Notification) {
        if let store { SourceAppDirectory.shared.reload(from: store) }
        // Hidden panel reloads in prepareForShow.
        if view.window?.isVisible == true { reload(selectFirst: false) }
    }

    // selectFirst false: keep the selected item (or its row position if it is gone).
    private func reload(selectFirst: Bool) {
        guard let store else { return }
        let previousID = selectFirst ? nil : selectedItem?.id
        let previousRow = tableView.selectedRow

        let parsed = parseQuery(searchField.stringValue)
        items = store.fetch(ClipQuery(scope: scope, terms: parsed.terms, bundleID: parsed.bundleID,
                                      limit: Self.listLimit))

        // Chips: most frequent source apps among the first 100 matches (ignoring the app filter).
        let sample = parsed.bundleID == nil
            ? Array(items.prefix(Self.chipSample))
            : store.fetch(ClipQuery(scope: scope, terms: parsed.terms, bundleID: nil, limit: Self.chipSample))
        filterBar.set(chips: topApps(in: sample, selected: parsed.bundleID), selected: parsed.bundleID)

        tableView.reloadData()
        var row = 0
        if let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
            row = index
        } else if !selectFirst, previousRow >= 0 {
            row = min(previousRow, items.count - 1)
        }
        select(row: items.isEmpty ? -1 : row)

        emptyLabel.stringValue = scope == .saved && searchField.stringValue.isEmpty
            ? String(localized: "Nothing saved yet — press ⌘S on an item to keep it here")
            : String(localized: "No Items")
        emptyLabel.isHidden = !items.isEmpty
    }

    private func topApps(in sample: [ClipSummary], selected: String?) -> [AppFilterBarView.Chip] {
        var counts: [String: Int] = [:]
        for item in sample {
            if let id = item.sourceBundleID { counts[id, default: 0] += 1 }
        }
        var ids = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(Self.chipCount).map(\.key)
        if let selected, !ids.contains(selected) {
            ids.insert(selected, at: 0)
            if ids.count > Self.chipCount { ids.removeLast() }
        }
        let directory = SourceAppDirectory.shared
        return ids.map { id in
            AppFilterBarView.Chip(bundleID: id, name: directory.name(for: id) ?? id,
                                  icon: directory.icon(for: id, store: store), count: counts[id] ?? 0)
        }
    }

    // "AppName::content" → app filter + content terms. Unknown names stay plain text (e.g. "std::vector").
    private func parseQuery(_ raw: String) -> (terms: [String], bundleID: String?, content: String) {
        var content = raw
        var bundleID: String?
        if let range = raw.range(of: "::") {
            let name = raw[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, let id = SourceAppDirectory.shared.resolve(name: name) {
                bundleID = id
                content = String(raw[range.upperBound...])
            }
        }
        let terms = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return (terms, bundleID, content)
    }

    private func toggleAppFilter(_ bundleID: String) {
        let parsed = parseQuery(searchField.stringValue)
        let newText: String
        if parsed.bundleID == bundleID {
            newText = parsed.content            // unselect: drop "AppName::"
        } else {
            let name = SourceAppDirectory.shared.name(for: bundleID) ?? bundleID
            newText = "\(name)::" + parsed.content
        }
        replaceSearchText(newText)
    }

    // Through the field editor so undo and controlTextDidChange behave like typing.
    private func replaceSearchText(_ text: String) {
        focusSearch()
        if let editor = searchField.currentEditor() as? NSTextView {
            let length = (editor.string as NSString).length
            if text.isEmpty {
                editor.selectAll(nil)
                editor.delete(nil)
            } else {
                editor.insertText(text, replacementRange: NSRange(location: 0, length: length))
            }
        } else {
            searchField.stringValue = text
            reload(selectFirst: true)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        reload(selectFirst: true)
    }

    // MARK: - Selection

    private var selectedItem: ClipSummary? {
        let row = tableView.selectedRow
        return items.indices.contains(row) ? items[row] : nil
    }

    private func select(row: Int) {
        if items.indices.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        updatePreview()
    }

    // Hover: select without scrolling, the row is already under the pointer.
    private func hoverSelect(_ row: Int) {
        guard items.indices.contains(row), row != tableView.selectedRow else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        select(row: min(max(current + delta, 0), items.count - 1))
    }

    private func updatePreview() {
        let item = selectedItem.flatMap { store?.item(id: $0.id) }
        preview.show(item, font: listFont, store: store)
    }

    // MARK: - Actions

    private func activate(row: Int, autoPaste: Bool? = nil) {
        guard items.indices.contains(row), let store, let item = store.item(id: items[row].id) else {
            NSSound.beep()
            return
        }
        controller?.paste(item, autoPaste: autoPaste ?? prefs.clipboardAutoPaste)
    }

    // ⌘↩: edit the item in Settings › Saved Clips (an unsaved item is saved first).
    private func editInSavedClips(row: Int) {
        guard items.indices.contains(row), let store else {
            NSSound.beep()
            return
        }
        let item = items[row]
        if !item.saved {
            store.toggleSaved(id: item.id)
            NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        }
        SavedClipsNavigator.reveal(item.id)
        controller?.hide()
        controller?.onOpenSettings?()
    }

    // ⌘⇧↩: show the original file (image copied from a folder, or copied files) in Finder.
    private func revealInFinder(row: Int) {
        guard items.indices.contains(row), let item = store?.item(id: items[row].id),
              let path = item.locationPath else {
            NSSound.beep()
            return
        }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        if fm.fileExists(atPath: path) {
            controller?.hide()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if fm.fileExists(atPath: url.deletingLastPathComponent().path) {
            // File moved / deleted: open its folder instead.
            controller?.hide()
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        } else {
            NSSound.beep()
        }
    }

    private func toggleSaved(_ id: Int64) {
        store?.toggleSaved(id: id)
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
    }

    private func remove(_ id: Int64) {
        store?.remove(id: id, from: scope)
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
    }

    // Clears the search first only when that setting is on (General › Keyboard).
    private func handleEscape() {
        if prefs.escClearsSearchFirst, !searchField.stringValue.isEmpty {
            replaceSearchText("")
        } else {
            controller?.hide()
        }
    }

    // MARK: - Keyboard

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            handleEscape()
        case #selector(NSResponder.insertNewline(_:)):
            activate(row: tableView.selectedRow)
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
        case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)):
            moveSelection(-visibleRowCount())
        case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)):
            moveSelection(visibleRowCount())
        default:
            return false
        }
        return true
    }

    private func visibleRowCount() -> Int {
        max(1, Int(scrollView.contentView.bounds.height / max(1, tableView.rowHeight)) - 1)
    }

    // ⌘ shortcuts, routed from the panel before the field editor sees them.
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command, .shift] {
            // ⌘⇧⌫ deletes; plain ⌘⌫ stays with the search field (delete to line start).
            if event.keyCode == UInt16(kVK_Delete) {
                if let id = selectedItem?.id { remove(id) }
                return true
            }
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                revealInFinder(row: tableView.selectedRow)
                return true
            }
            switch key {
            case "j": controller?.switchPanel(-1); return true
            case "k": controller?.switchPanel(1); return true
            default: return false
            }
        }
        guard flags == .command else { return false }
        if let index = Self.digitKeys[event.keyCode] {
            activate(row: index)
            return true
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            editInSavedClips(row: tableView.selectedRow)
            return true
        }
        switch key {
        case "j": moveSelection(1)
        case "k": moveSelection(-1)
        case "s": if let id = selectedItem?.id { toggleSaved(id) }
        case "w": controller?.hide()
        case ",":
            controller?.hide()
            controller?.onOpenSettings?()
        default: return false
        }
        return true
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ClipRowView.identifier, owner: nil) as? ClipRowView ?? ClipRowView()
        cell.configure(items[row], index: row, font: listFont, showSavedMark: scope == .history, store: store)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipTableRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        let item = items[row]
        menu.addItem(ClosureMenuItem(String(localized: "Paste")) { [weak self] in
            self?.activate(row: row, autoPaste: true)
        })
        menu.addItem(ClosureMenuItem(String(localized: "Copy")) { [weak self] in
            self?.activate(row: row, autoPaste: false)
        })
        if item.kind != .text {
            menu.addItem(ClosureMenuItem(String(localized: "Show in Finder")) { [weak self] in
                self?.revealInFinder(row: row)
            })
        }
        let saveTitle = item.saved ? String(localized: "Remove from Saved") : String(localized: "Save")
        menu.addItem(ClosureMenuItem(saveTitle) { [weak self] in self?.toggleSaved(item.id) })
        menu.addItem(ClosureMenuItem(String(localized: "Edit in Saved Clips")) { [weak self] in
            self?.editInSavedClips(row: row)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(String(localized: "Delete")) { [weak self] in self?.remove(item.id) })
    }
}
