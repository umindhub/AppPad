import AppKit
import Carbon.HIToolbox
import Combine

// Layout: title + one line of shortcut hints (left, the block centered on the search line), search field, list (2/3) | preview (1/3).
// Rows: workflows and apps mixed, most used first (shared frecency); while searching, match quality first.
// Search: only the text before the first space is matched; the rest is the workflow argument.
// Typing after the first space only changes the argument: rows and selection stay.
// Picking a row (Tab, arrows, ⌘J/K, mouse) writes its name into the field with spaces as "-"
// ("Set-Timer 10:00"), so the first word always names the item and the rest is the argument.
// Calculator: when the whole field is a math expression, a calculator row is pinned first (↩ / click copies).
// While it shows, moving between rows does not rewrite the expression; Tab on another row still does.
// Keys: ↩ run / open / copy, Tab complete name (apps and workflows without an argument: run / open right away), ⌘↩ edit workflow in Settings,
// ⌘1–⌘0 row N (a workflow that takes an argument with none typed yet is only picked, like the mouse), ⌘J/K or arrows move,
// in-panel workflow shortcuts (Settings › Workflows), Esc closes (or clears first, see General settings).
// "Ask before running" workflows: an in-panel dialog first (↩ run, Esc cancel, every other key ignored).
final class WorkflowPanelViewController: NSViewController, NSSearchFieldDelegate,
    NSTableViewDataSource, NSTableViewDelegate {
    weak var controller: WorkflowPanelController?

    let root = FlippedView()
    private let searchChrome = GlassSearchFieldView()
    private var searchField: NSSearchField { searchChrome.field }
    private let header = PanelHeaderView(title: String(localized: "Workflows"), hints: [
        .init(keys: "Tab", action: String(localized: "Complete", table: "Workflow")),
        .init(keys: "⌘K/J", action: String(localized: "Up/Down")),
        .init(keys: "⌘⇧K/J", action: String(localized: "Switch")),
    ])
    private let scrollView = NSScrollView()
    private let tableView = ClipTableView()
    private let divider = NSBox()
    private let preview = WorkflowPreviewView()
    private let emptyLabel = NSTextField(labelWithString: String(localized: "No Results"))

    private var items: [WorkflowPanelItem] = []
    private var argument = ""                       // text after the first space
    private var lastTerm = ""                       // normalized search term the rows were built for
    private var installedShortcuts: Set<String>?    // nil = not known yet
    private var listFont = NSFont.systemFont(ofSize: 15)
    private var cancellables = Set<AnyCancellable>()
    private var confirmOverlay: ConfirmOverlayView?
    private var confirmShownAt: TimeInterval = 0

    private var prefs: Preferences { .shared }
    private var runner: WorkflowRunner { .shared }

    private static let pad: CGFloat = 24
    // ↩ pressed this soon after the dialog appeared (double tap) does not confirm.
    private static let confirmKeyDelay: TimeInterval = 0.3
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

        searchField.placeholderString = String(localized: "Search workflows and apps", table: "Workflow")
        searchField.delegate = self
        searchField.focusRingType = .none


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

        [scrollView, divider, preview, searchChrome, header, emptyLabel].forEach {
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
        let headerSize = header.preferredSize
        let side = headerSize.width + 16
        let fieldWidth = max(160, min(560, b.width - 2 * pad - 2 * side))
        searchChrome.frame = NSRect(x: ((b.width - fieldWidth) / 2).rounded(),
                                    y: 18,
                                    width: fieldWidth, height: fieldHeight)
        // Title + hints as one block, its center on the search field's center.
        header.frame = NSRect(x: pad, y: (searchChrome.frame.midY - headerSize.height / 2).rounded(),
                              width: headerSize.width, height: headerSize.height)

        let top = max(searchChrome.frame.maxY + 16, header.frame.maxY + 8)
        let bottom = b.height - 18
        let inner = b.width - 2 * pad
        let listWidth = (inner * 2 / 3).rounded()
        scrollView.frame = NSRect(x: pad, y: top, width: listWidth - 8, height: max(0, bottom - top))
        divider.frame = NSRect(x: pad + listWidth, y: top, width: 1, height: max(0, bottom - top))
        preview.frame = NSRect(x: pad + listWidth + 14, y: top + 2,
                               width: max(0, inner - listWidth - 14), height: max(0, bottom - top - 2))
        emptyLabel.frame = NSRect(x: pad, y: top + 40, width: listWidth - 8, height: 22)
        tableView.sizeLastColumnToFit()
        confirmOverlay?.frame = b
    }

    // MARK: - Show / hide

    func prepareForShow() {
        _ = view
        dismissConfirm()
        searchField.stringValue = ""
        reload(selectFirst: true)
        // Shortcuts may have been added since the last show.
        Task { [weak self] in
            let names = await ShortcutsCatalog.names()
            guard let self else { return }
            self.installedShortcuts = names.isEmpty ? nil : Set(names)   // empty = lookup failed, don't block
            self.updatePreview()
        }
    }

    func focusSearch() {
        guard let window = view.window else { return }
        if searchField.currentEditor() == nil { window.makeFirstResponder(searchField) }
        if let editor = searchField.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    func didHide() {
        dismissConfirm()
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
        let previousKey = selectedItem.map { Self.identity($0) }
        let parts = WorkflowArguments.split(searchField.stringValue)
        let term = SearchIndex.normalize(parts.term)
        argument = parts.argument
        lastTerm = term
        let workflows = WorkflowStore.shared.workflows.filter(\.enabled)
        let calculation = Self.calculation(searchField.stringValue)

        if let launchpad = controller?.launchpad {
            launchpad.seedWorkflows(workflows.map(\.statsKey))
            let now = Date()
            var ranked: [(item: WorkflowPanelItem, match: Int, frecency: Double, name: String)] = []
            for workflow in workflows {
                let match = term.isEmpty ? 1 : Self.score(workflow, query: term)
                guard match > 0 else { continue }
                ranked.append((item: WorkflowPanelItem.workflow(workflow), match: match,
                               frecency: launchpad.frecency(workflow.statsKey, now: now), name: workflow.displayName))
            }
            for (app, match) in launchpad.scoredApps(matching: term) {
                ranked.append((item: WorkflowPanelItem.app(app), match: match,
                               frecency: launchpad.frecency(app.key, now: now), name: app.name))
            }
            ranked.sort { a, b in
                if a.match != b.match { return a.match > b.match }
                if a.frecency != b.frecency { return a.frecency > b.frecency }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            items = ranked.map(\.item)
        } else {
            items = workflows.map { .workflow($0) }
        }
        if let calculation { items.insert(calculation, at: 0) }

        tableView.reloadData()
        var row = 0
        if !selectFirst {
            // Same item as before (rows may have moved), else the same row number.
            if let previousKey, let index = items.firstIndex(where: { Self.identity($0) == previousKey }) {
                row = index
            } else if previousRow >= 0 {
                row = min(previousRow, items.count - 1)
            }
        }
        select(row: items.isEmpty ? -1 : row)
        emptyLabel.isHidden = !items.isEmpty
    }

    private static func identity(_ item: WorkflowPanelItem) -> String {
        switch item {
        case .workflow(let workflow): return "w:" + workflow.id.uuidString
        case .app(let app): return "a:" + app.key
        case .calculator: return "c"
        }
    }

    // Whole field (spaces included) as math, e.g. "2 + 3", "sqrt(2)", "6.02e23".
    private static func calculation(_ text: String) -> WorkflowPanelItem? {
        let expression = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = Calculator.evaluateIfExpression(expression) else { return nil }
        return .calculator(expression: expression, result: result)
    }

    private var hasCalculatorRow: Bool {
        items.first?.isCalculator == true
    }

    // One-word form of a name for the search field: "Set Timer" → "Set-Timer".
    static func token(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    // Completed name ("set-timer") > whole name typed without spaces ("settimer") > any keyword exact
    // (current language + English) > keyword prefix > name tiers.
    // Names: localized, English and every translation ("关机" works in an English UI too).
    private static func score(_ workflow: Workflow, query: String) -> Int {
        let names = workflow.searchNames
        if names.contains(where: { SearchIndex.normalize(token($0)) == query }) { return 130 }
        let compact = SearchIndex.compact(query)
        if !compact.isEmpty, names.contains(where: { SearchIndex.compact(SearchIndex.normalize($0)) == compact }) { return 125 }
        let keywords = workflow.matchKeywords.map(SearchIndex.normalize)   // current language + English
        if keywords.contains(query) { return 120 }
        if keywords.contains(where: { $0.hasPrefix(query) }) { return 95 }
        if !compact.isEmpty, keywords.contains(where: { SearchIndex.compact($0).hasPrefix(compact) }) { return 92 }
        var best = names.map { score($0, query: query) }.max() ?? 0
        if query.contains("-") {
            let spaced = query.replacingOccurrences(of: "-", with: " ")
            best = max(best, names.map { score($0, query: spaced) }.max() ?? 0)
        }
        return best
    }

    // Same tiers as app search: prefix > word prefix > compact prefix > acronym / pinyin > contains.
    private static func score(_ name: String, query: String) -> Int {
        let normalized = SearchIndex.normalize(name)
        let compact = SearchIndex.compact(query)
        guard !compact.isEmpty else { return 0 }
        let compactName = SearchIndex.compact(normalized)
        if normalized.hasPrefix(query) { return 100 }
        let words = normalized.split(whereSeparator: { " -_.".contains($0) })
        if words.contains(where: { $0.hasPrefix(query) }) { return 85 }
        if compactName.hasPrefix(compact) { return 82 }   // "setvolume" → "Set Volume"
        if compact.count >= 2, SearchIndex.acronyms(of: name).contains(where: { $0.hasPrefix(compact) }) { return 75 }
        if let pinyin = SearchIndex.pinyin(of: name) {
            if pinyin.initials.hasPrefix(compact) { return 70 }
            if pinyin.full.hasPrefix(compact) { return 65 }
            if pinyin.full.contains(compact) { return 30 }
        }
        if normalized.contains(query) { return 50 }
        if compact.count >= 3, compactName.contains(compact) { return 45 }
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
        guard confirmOverlay == nil, items.indices.contains(row), row != tableView.selectedRow else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        fillSearchField(explicit: false)
    }

    // Arrows, ⌘J/K, page keys: a picked row also fills the field.
    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        select(row: min(max(current + delta, 0), items.count - 1))
        fillSearchField(explicit: false)
    }

    // Field = "<Name-With-Dashes> <argument>"; rows stay (lastTerm follows the new name),
    // so typing the argument next keeps the selection. The automatic first row is not filled.
    // explicit: Tab. With a calculator row only Tab rewrites the field (the expression is kept otherwise);
    // the rows are then rebuilt without the calculator, keeping the picked item selected.
    private func fillSearchField(explicit: Bool) {
        guard let item = selectedItem, !item.isCalculator else { return }
        let hadCalculator = hasCalculatorRow
        if hadCalculator && !explicit { return }
        let name = Self.token(item.title)
        var text = name
        if case .workflow = item { text += " " }
        if !argument.isEmpty { text = name + " " + argument }
        searchField.stringValue = text
        lastTerm = SearchIndex.normalize(name)
        if hadCalculator { reload(selectFirst: false) }
        focusSearch()   // caret to the end
        updatePreview()
    }

    private func updatePreview() {
        guard let item = selectedItem else {
            preview.show(nil)
            return
        }
        if case .workflow(let workflow) = item {
            preview.show(item, isRunning: runner.running.contains(workflow.id),
                         lastResult: runner.lastResults[workflow.id],
                         argument: argument, missingShortcut: missingShortcut(workflow))
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
        case .workflow(let workflow): run(workflow)
        case .app(let app): controller?.open(app)   // the argument is ignored for apps
        case .calculator(_, let result): copy(result)
        }
    }

    // ⌘N: a workflow that takes an argument and has none typed yet is picked (field filled, ready
    // for the argument) instead of run; everything else runs / opens like ↩ on that row.
    private func activateNumbered(row: Int) {
        guard items.indices.contains(row) else {
            NSSound.beep()
            return
        }
        if case .workflow(let workflow) = items[row], workflow.argument != .off,
           argument.trimmingCharacters(in: .whitespaces).isEmpty {
            select(row: row)
            fillSearchField(explicit: false)
            return
        }
        activate(row: row)
    }

    // Plain, machine-readable result to the pasteboard; the panel stays open.
    private func copy(_ result: Calculator.Result) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.copyText, forType: .string)
        preview.flashCopied()
    }

    // Missing shortcut → install / create it; bad argument → stay open (the preview says why).
    private func run(_ workflow: Workflow, argument: String? = nil) {
        let value = argument ?? self.argument
        if let name = missingShortcut(workflow) {
            controller?.installShortcut(name)
            return
        }
        if case .failure = WorkflowArguments.parse(value, type: workflow.argumentType, mode: workflow.argument) {
            NSSound.beep()
            updatePreview()
            return
        }
        if workflow.requiresConfirmation {
            askToRun(workflow, argument: value)
            return
        }
        controller?.run(workflow, argument: value)
    }

    // MARK: - Confirmation

    // Same in-panel dialog as the Launchpad's uninstall (the non-activating panel keeps focus).
    private func askToRun(_ workflow: Workflow, argument: String) {
        dismissConfirm()
        let overlay = ConfirmOverlayView(
            icon: WorkflowIcon.image(for: workflow),
            title: String(localized: "Run “\(workflow.displayName)”?", table: "Workflow"),
            message: workflow.confirmationMessage, items: [],
            confirmTitle: String(localized: "Run", table: "Workflow"), destructive: true,
            cornerRadius: root.layer?.cornerRadius ?? LaunchpadController.cornerRadius
        )
        overlay.onConfirm = { [weak self] _ in
            self?.dismissConfirm()
            self?.controller?.run(workflow, argument: argument, confirmed: true)
        }
        overlay.onCancel = { [weak self] in self?.dismissConfirm(animated: true) }
        overlay.frame = view.bounds
        view.addSubview(overlay)
        confirmOverlay = overlay
        confirmShownAt = ProcessInfo.processInfo.systemUptime
        overlay.animateIn()
    }

    // animated: cancel fades out; panel hide / show / run removes it at once.
    private func dismissConfirm(animated: Bool = false) {
        guard let overlay = confirmOverlay else { return }
        confirmOverlay = nil
        if animated { overlay.animateOut() } else { overlay.removeNow() }
        focusSearch()
    }

    // While the dialog shows it gets every key: ↩ run, Esc cancel, the rest is swallowed
    // (Tab / ↩ that opened it, typing, ⌘ shortcuts). A held or double-tapped ↩ never confirms.
    private func handleConfirmKey(_ event: NSEvent, _ overlay: ConfirmOverlayView) {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            let elapsed = ProcessInfo.processInfo.systemUptime - confirmShownAt
            guard !event.isARepeat, elapsed >= Self.confirmKeyDelay else { return }
            overlay.confirm()
        case kVK_Escape:
            overlay.cancel()
        default:
            break
        }
    }

    // In-panel shortcut for a workflow that takes an argument: select it and put its name in the
    // field, ready for the argument (the text typed for another row is not reused).
    private func selectForArgument(_ workflow: Workflow) {
        let name = Self.token(workflow.displayName)
        if !hasCalculatorRow, let index = items.firstIndex(where: { if case .workflow(let w) = $0 { return w.id == workflow.id }; return false }) {
            select(row: index)
            scrollRowToTop(index)
            argument = ""
            searchField.stringValue = name + " "
            lastTerm = SearchIndex.normalize(name)   // rows stay, typing the argument keeps the selection
            focusSearch()
            updatePreview()
        } else {
            // Not in the current rows: search for its exact name (ranked first).
            searchField.stringValue = name + " "
            reload(selectFirst: true)
            scrollRowToTop(0)
            focusSearch()
        }
    }

    // Put the row at the top of the list (rows near the end: scrolled to the bottom instead).
    private func scrollRowToTop(_ row: Int) {
        guard items.indices.contains(row) else { return }
        tableView.layoutSubtreeIfNeeded()
        let clip = scrollView.contentView
        let maxY = max(0, tableView.bounds.height - clip.bounds.height)
        let y = min(tableView.rect(ofRow: row).minY, maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    private func missingShortcut(_ workflow: Workflow) -> String? {
        guard let installedShortcuts else { return nil }
        return workflow.steps.first { $0.kind == .shortcut && !$0.shortcutName.isEmpty
            && !installedShortcuts.contains($0.shortcutName) }?.shortcutName
    }

    private func editSelected() {
        guard case .workflow(let workflow)? = selectedItem else {
            NSSound.beep()
            return
        }
        controller?.edit(workflow)
    }

    // Clears the search first only when that setting is on (General › Keyboard).
    private func handleEscape() {
        if prefs.escClearsSearchFirst, !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            reload(selectFirst: true)
        } else {
            controller?.hide()
        }
    }

    // MARK: - Keyboard

    // Only a changed search term (text before the first space) rebuilds the rows and selects the first.
    // Math is the exception: the whole field counts, so any change while it is (or was) math rebuilds.
    func controlTextDidChange(_ obj: Notification) {
        if hasCalculatorRow || Self.calculation(searchField.stringValue) != nil {
            reload(selectFirst: true)
            return
        }
        let parts = WorkflowArguments.split(searchField.stringValue)
        if SearchIndex.normalize(parts.term) == lastTerm {
            argument = parts.argument
            updatePreview()
            return
        }
        reload(selectFirst: true)
    }

    // Tab: nothing to complete for apps and workflows without an argument → run / open now;
    // otherwise the selected row's localized name ("Set-Timer ") goes in the field, ready for the argument.
    private func completeSelected() {
        guard let item = selectedItem, !item.isCalculator else {
            NSSound.beep()
            return
        }
        switch item {
        case .app:
            activate(row: tableView.selectedRow)
        case .workflow(let workflow) where workflow.argument == .off:
            run(workflow, argument: "")
        default:
            fillSearchField(explicit: true)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            handleEscape()
        case #selector(NSResponder.insertNewline(_:)):
            activate(row: tableView.selectedRow)
        case #selector(NSResponder.insertTab(_:)):
            completeSelected()
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
        if let confirmOverlay {
            handleConfirmKey(event, confirmOverlay)
            return true
        }
        guard let combo = KeyCombo.from(event: event), !WorkflowPanelKeys.isReserved(combo) else { return false }
        guard let workflow = WorkflowStore.shared.workflows.first(where: {
            $0.enabled && $0.panelKey?.keyCode == combo.keyCode && $0.panelKey?.modifiers == combo.modifiers
        }) else { return false }
        // No argument → run now; with an argument (optional or required) → select it first.
        if workflow.argument == .off {
            run(workflow, argument: "")
        } else {
            selectForArgument(workflow)
        }
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
            activateNumbered(row: index)
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
