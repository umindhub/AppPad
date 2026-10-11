import AppKit
import Carbon.HIToolbox
import Combine

// Layout: title + hint, search field, list (2/3) | preview (1/3) — same as the clipboard panel.
// Rows: enabled workflows first, then apps (most used first; ranked by match while searching).
// Keys: ↩ run / open, ⌘↩ edit workflow in Settings, ⌘1–⌘0 row N, ⌘J/K or arrows move,
// in-panel workflow shortcuts (Settings › Workflows), Esc clears / closes.
final class WorkflowPanelViewController: NSViewController, NSSearchFieldDelegate,
    NSTableViewDataSource, NSTableViewDelegate {
    weak var controller: WorkflowPanelController?

    let root = FlippedView()
    private let searchChrome = GlassSearchFieldView()
    private var searchField: NSSearchField { searchChrome.field }
    private let titleLabel = NSTextField(labelWithString: String(localized: "Workflows"))
    private let hintLabel = NSTextField(labelWithString: String(localized: "⌘⇧J / ⌘⇧K  Switch"))
    private let scrollView = NSScrollView()
    private let tableView = ClipTableView()
    private let divider = NSBox()
    private let preview = WorkflowPreviewView()
    private let emptyLabel = NSTextField(labelWithString: String(localized: "No Results"))

    private var items: [WorkflowPanelItem] = []
    private var listFont = NSFont.systemFont(ofSize: 15)
    private var cancellables = Set<AnyCancellable>()

    private var prefs: Preferences { .shared }
    private var runner: WorkflowRunner { .shared }

    private static let pad: CGFloat = 24
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

        searchField.placeholderString = String(localized: "Search workflows and apps")
        searchField.delegate = self
        searchField.focusRingType = .none

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onHoverRow = { [weak self] row in self?.hoverSelect(row) }
        tableView.onClickRow = { [weak self] row in self?.activate(row: row) }

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
        preview.onEscape = { [weak self] in self?.focusSearch() }

        [scrollView, divider, preview, searchChrome, titleLabel, hintLabel, emptyLabel].forEach {
            root.addSubview($0)
        }

        // Live updates while visible: edits in Settings, running state, finished runs.
        NotificationCenter.default.addObserver(
            self, selector: #selector(workflowsDidChange(_:)), name: .workflowsDidChange, object: nil
        )
        runner.$running.combineLatest(runner.$lastResults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshVisibleRows() }
            .store(in: &cancellables)

        applyPreferences()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let b = view.bounds
        let pad = Self.pad
        let fieldHeight = searchChrome.preferredHeight
        let labelWidth = ceil(titleLabel.intrinsicContentSize.width)
        let hintWidth = ceil(hintLabel.intrinsicContentSize.width)
        let side = max(labelWidth, hintWidth) + 16
        let fieldWidth = max(160, min(560, b.width - 2 * pad - 2 * side))
        searchChrome.frame = NSRect(x: ((b.width - fieldWidth) / 2).rounded(), y: 18,
                                    width: fieldWidth, height: fieldHeight)
        let midY = searchChrome.frame.midY
        titleLabel.frame = NSRect(x: pad, y: (midY - 19).rounded(), width: labelWidth, height: 18)
        hintLabel.frame = NSRect(x: pad, y: (midY + 2).rounded(), width: hintWidth, height: 16)

        let top = searchChrome.frame.maxY + 16
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

    func prepareForShow() {
        _ = view
        searchField.stringValue = ""
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
        preview.show(nil)
    }

    func applyPreferences() {
        _ = view
        searchChrome.isGlass = prefs.glassControls
        // Same search font as the clipboard panel → same capsule height and title position.
        searchChrome.textFont = ClipboardFonts.make(family: prefs.clipboardSearchFontFamily,
                                                    size: prefs.clipboardSearchFontSize)
        tableView.rowHeight = max(48, ceil(listFont.ascender - listFont.descender) * 2 + 14)
        view.needsLayout = true
    }

    // MARK: - Data

    @objc private func workflowsDidChange(_ note: Notification) {
        if view.window?.isVisible == true { reload(selectFirst: false) }
    }

    private func reload(selectFirst: Bool) {
        let previousRow = tableView.selectedRow
        let query = SearchIndex.normalize(searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let workflows = WorkflowStore.shared.workflows.filter(\.enabled)
        let apps: [AppInfo]
        if query.isEmpty {
            items = workflows.map { .workflow($0) }
            apps = controller?.launchpad.appsByFrecency() ?? []
        } else {
            items = workflows
                .map { (workflow: $0, score: Self.score($0.name, query: query)) }
                .filter { $0.score > 0 }
                .sorted { $0.score > $1.score }
                .map { .workflow($0.workflow) }
            apps = controller?.launchpad.search(query) ?? []
        }
        items += apps.map { .app($0) }

        tableView.reloadData()
        let row = selectFirst || previousRow < 0 ? 0 : min(previousRow, items.count - 1)
        select(row: items.isEmpty ? -1 : row)
        emptyLabel.isHidden = !items.isEmpty
    }

    // Same tiers as app search: prefix > word prefix > acronym / pinyin > contains.
    private static func score(_ name: String, query: String) -> Int {
        let normalized = SearchIndex.normalize(name)
        let compact = query.replacingOccurrences(of: " ", with: "")
        if normalized.hasPrefix(query) { return 100 }
        let words = normalized.split(whereSeparator: { " -_.".contains($0) })
        if words.contains(where: { $0.hasPrefix(query) }) { return 85 }
        if compact.count >= 2, SearchIndex.acronyms(of: name).contains(where: { $0.hasPrefix(compact) }) { return 75 }
        if let pinyin = SearchIndex.pinyin(of: name) {
            if pinyin.initials.hasPrefix(compact) { return 70 }
            if pinyin.full.hasPrefix(compact) { return 65 }
            if pinyin.full.contains(compact) { return 30 }
        }
        if normalized.contains(query) { return 50 }
        return 0
    }

    // Running state / last result changed: redraw rows and preview in place.
    private func refreshVisibleRows() {
        guard view.window?.isVisible == true, !items.isEmpty else { return }
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                             columnIndexes: IndexSet(integer: 0))
        updatePreview()
    }

    // MARK: - Selection

    private var selectedItem: WorkflowPanelItem? {
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
        guard let item = selectedItem else {
            preview.show(nil)
            return
        }
        if case .workflow(let workflow) = item {
            preview.show(item, isRunning: runner.running.contains(workflow.id),
                         lastResult: runner.lastResults[workflow.id])
        } else {
            preview.show(item)
        }
    }

    // MARK: - Actions

    private func activate(row: Int) {
        guard items.indices.contains(row) else {
            NSSound.beep()
            return
        }
        switch items[row] {
        case .workflow(let workflow): controller?.run(workflow)
        case .app(let app): controller?.open(app)
        }
    }

    private func editSelected() {
        guard case .workflow(let workflow)? = selectedItem else {
            NSSound.beep()
            return
        }
        controller?.edit(workflow)
    }

    private func handleEscape() {
        if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            reload(selectFirst: true)
        } else {
            controller?.hide()
        }
    }

    // MARK: - Keyboard

    func controlTextDidChange(_ obj: Notification) {
        reload(selectFirst: true)
    }

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

    // In-panel workflow shortcuts (any modifier combination); reserved panel keys are left alone.
    func handlePanelShortcut(_ event: NSEvent) -> Bool {
        guard let combo = KeyCombo.from(event: event), !WorkflowPanelKeys.isReserved(combo) else { return false }
        guard let workflow = WorkflowStore.shared.workflows.first(where: {
            $0.enabled && $0.panelKey?.keyCode == combo.keyCode && $0.panelKey?.modifiers == combo.modifiers
        }) else { return false }
        controller?.run(workflow)
        return true
    }

    // ⌘ shortcuts, routed from the panel before the field editor sees them.
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command, .shift], key == "j" || key == "k" {
            controller?.switchPanel(key == "j" ? -1 : 1)
            return true
        }
        guard flags == .command else { return false }
        if let index = Self.digitKeys[event.keyCode] {
            activate(row: index)
            return true
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            editSelected()
            return true
        }
        switch key {
        case "j": moveSelection(1)
        case "k": moveSelection(-1)
        case "w": controller?.hide()
        case ",": controller?.openSettings()
        default: return false
        }
        return true
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: WorkflowRowView.identifier, owner: nil) as? WorkflowRowView
            ?? WorkflowRowView()
        let item = items[row]
        var running = false
        if case .workflow(let workflow) = item { running = runner.running.contains(workflow.id) }
        cell.configure(item, index: row, font: listFont, isRunning: running)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipTableRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }
}
