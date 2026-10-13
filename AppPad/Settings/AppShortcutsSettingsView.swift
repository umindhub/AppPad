import SwiftUI
import AppKit
import UniformTypeIdentifiers

// One scanned app with its Contacts-style index letter (CJK → Latin, e.g. 访达 → F).
nonisolated struct AppShortcutEntry: Identifiable, Sendable {
    let app: AppInfo
    let letter: String      // "A"…"Z" or "#"
    let sortKey: String     // latinized, lowercased
    let searchKey: String   // name + bundle name + latinized (no spaces)

    var id: String { app.key }

    static let letters: [String] = (65...90).map { String(UnicodeScalar(UInt8($0))) } + ["#"]

    init(app: AppInfo) {
        self.app = app
        let latin = Self.latinize(app.name)
        sortKey = latin.lowercased()
        letter = Self.indexLetter(latin)
        searchKey = (app.name + " " + app.bundleName + " " + latin.replacingOccurrences(of: " ", with: "")).lowercased()
    }

    private static func latinize(_ s: String) -> String {
        let latin = s.applyingTransform(.toLatin, reverse: false) ?? s
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }

    private static func indexLetter(_ latin: String) -> String {
        guard let first = latin.trimmingCharacters(in: .whitespaces).first else { return "#" }
        let upper = String(first).uppercased()
        guard upper.unicodeScalars.count == 1, let v = upper.unicodeScalars.first?.value, (65...90).contains(v) else {
            return "#"
        }
        return upper
    }

    // Scan system + installed apps + extra locations, sorted by index letter then name ("#" last).
    static func loadAll() -> [AppShortcutEntry] {
        // One entry per path; a bundle id installed twice (Xcode + Xcode-beta) gets path keys
        // so each copy has its own shortcut.
        var seenPaths = Set<String>()
        let unique = (AppScanner.scanAll() + AppScanner.scanExtraLocations())
            .filter { seenPaths.insert($0.url.standardizedFileURL.path).inserted }
        let idCounts = Dictionary(grouping: unique, by: { $0.key }).mapValues(\.count)
        let apps = unique.map { app -> AppInfo in
            guard idCounts[app.key, default: 0] > 1 else { return app }
            return AppInfo(key: app.url.standardizedFileURL.path, bundleID: app.bundleID, url: app.url,
                           name: app.name, bundleName: app.bundleName, category: app.category,
                           isSystem: app.isSystem, isUtility: app.isUtility, isAppStore: app.isAppStore)
        }
        return apps
            .map(AppShortcutEntry.init)
            .sorted { a, b in
                if a.letter != b.letter {
                    if a.letter == "#" { return false }
                    if b.letter == "#" { return true }
                    return a.letter < b.letter
                }
                return a.sortKey.localizedStandardCompare(b.sortKey) == .orderedAscending
            }
    }
}

// Apps of one index letter.
private struct LetterGroup: Identifiable {
    let letter: String
    var items: [AppShortcutEntry]
    var id: String { letter }
}

// Scan result kept across tab switches (the tab view is rebuilt each time).
@MainActor
private enum ShortcutAppsCache {
    static var entries: [AppShortcutEntry]?
}

// Small icon cache for this tab (rows re-render often).
@MainActor
private final class ShortcutIconCache {
    static let shared = ShortcutIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(path: String) -> NSImage {
        if let image = cache[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 44, height: 44)
        cache[path] = image
        return image
    }
}

// Settings → App Shortcuts tab: per-app global hotkeys (Raycast style).
// Top: apps with a shortcut. Below: every scanned app (assigned ones included), grouped A–Z like Contacts.
// Both places edit the same prefs entry, so changes show up in both at once.
struct AppShortcutsSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var entries: [AppShortcutEntry] = ShortcutAppsCache.entries ?? []
    @State private var loaded = ShortcutAppsCache.entries != nil
    @State private var query = ""
    @State private var scrollAnchor = ScrollAnchor()

    // Extra scroll-content margin so the index bar fits between the cards and the scroller.
    private static let formInset: CGFloat = 24
    // Grouped Form caps its cards at this width and centers them (measured: 704 pt).
    private static let formCardMaxWidth: CGFloat = 704
    // Index bar sits left of the vertical scroller.
    private static let scrollerWidth: CGFloat =
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle)

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                searchBar
                form
                    .contentMargins(.horizontal, Self.formInset, for: .scrollContent)
                    .overlay(alignment: .trailing) {
                        LetterIndexBar(letters: AppShortcutEntry.letters,
                                       available: Set(groups.map(\.letter))) { letter in
                            guard let target = scrollTarget(for: letter) else { return }
                            proxy.scrollTo(target, anchor: .top)
                        }
                        .padding(.trailing, Self.scrollerWidth + 2)
                    }
            }
        }
        .task {
            // Show the cached list at once, then refresh (apps may have been installed / removed).
            let fresh = await Task.detached(priority: .userInitiated) { AppShortcutEntry.loadAll() }.value
            ShortcutAppsCache.entries = fresh
            entries = fresh
            loaded = true
        }
        .onDisappear {
            // Rows added via "Set Shortcut…" but never recorded.
            if prefs.appHotKeys.contains(where: { $0.combo == nil }) {
                prefs.appHotKeys.removeAll { $0.combo == nil }
            }
        }
    }

    // Same rule as the cards below: inset by contentMargins, capped width, centered.
    private var searchBar: some View {
        GlassSearchField(text: $query,
                         placeholder: String(localized: "Search apps"),
                         isGlass: prefs.glassControls)
            .frame(maxWidth: Self.formCardMaxWidth)
            .frame(height: GlassSearchFieldView.height)
            .padding(.horizontal, Self.formInset)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private static func headerID(_ letter: String) -> String { "letter-header-" + letter }

    private var form: some View {
        Form {
            Section {
                if assigned.isEmpty {
                    Group {
                        if query.isEmpty {
                            Text("No app shortcuts yet. Click a field below to record one.")
                        } else {
                            Text("No apps match.")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(assigned, id: \.key) { item in
                        assignedRow(item)
                    }
                }
            } header: {
                HStack {
                    Text("With Shortcuts")
                    Spacer()
                    Text("\(assignedCount) of \(prefs.appHotKeys.count) assigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Grab the Form's NSScrollView for scroll anchoring.
                .background(EnclosingScrollViewFinder { scrollAnchor.attach($0) })
            } footer: {
                HStack {
                    Text("Press the shortcut to open or focus the app; press again while it is in front to hide it. Click a field to record, Delete clears, Esc cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Add App…", action: addApps)
                }
                .padding(.top, 4)
            }

            if !loaded {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning apps…").foregroundStyle(.secondary)
                    }
                }
            } else if groups.isEmpty, !query.isEmpty, !assigned.isEmpty {
                Section {
                    Text("No apps match.").foregroundStyle(.secondary)
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { entry in
                        unassignedRow(entry)
                    }
                } header: {
                    // Scroll target: the letter header, not the first row (which hid the header).
                    Text(verbatim: group.letter)
                        .id(Self.headerID(group.letter))
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // Assigned (and pending "Set Shortcut…") rows, sorted by name.
    private var assigned: [AppHotKey] {
        let q = normalizedQuery
        return prefs.appHotKeys
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || searchKey(for: $0.key)?.contains(q) == true }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var assignedCount: Int {
        prefs.appHotKeys.filter { $0.combo != nil }.count
    }

    private func searchKey(for key: String) -> String? {
        entries.first { $0.app.key == key }?.searchKey
    }

    // All scanned apps (assigned ones stay in place), grouped by letter.
    private var groups: [LetterGroup] {
        let q = normalizedQuery.replacingOccurrences(of: " ", with: "")
        let visible = entries.filter { entry in
            q.isEmpty || entry.searchKey.replacingOccurrences(of: " ", with: "").contains(q)
        }
        var result: [LetterGroup] = []
        for entry in visible {
            if result.last?.letter == entry.letter {
                result[result.count - 1].items.append(entry)
            } else {
                result.append(LetterGroup(letter: entry.letter, items: [entry]))
            }
        }
        return result
    }

    // Letter tapped → its section header, or the next letter that has rows.
    private func scrollTarget(for letter: String) -> String? {
        let present = Set(groups.map(\.letter))
        guard let start = AppShortcutEntry.letters.firstIndex(of: letter) else { return nil }
        for l in AppShortcutEntry.letters[start...] where present.contains(l) {
            return Self.headerID(l)
        }
        return groups.last.map { Self.headerID($0.letter) }
    }

    // MARK: - Rows

    private func assignedRow(_ value: AppHotKey) -> some View {
        let conflict = prefs.conflictName(for: value.combo, excluding: .app(value.key))
        let missing = AppActivator.resolveURL(value) == nil
        return HStack(spacing: 8) {
            Image(nsImage: ShortcutIconCache.shared.icon(path: value.path))
                .resizable()
                .frame(width: 22, height: 22)
                .opacity(missing ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.name)
                    .lineLimit(1)
                if missing {
                    Text("App not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let conflict {
                    Text("Same shortcut as \(conflict)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if conflict != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text("Only one of them will work."))
            }
            ShortcutRecorder(combo: comboBinding(key: value.key))
                .frame(width: 150, height: 22)
            Button {
                prefs.appHotKeys.removeAll { $0.key == value.key }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            }
            .buttonStyle(.borderless)
            .help(Text("Remove"))
        }
    }

    private func unassignedRow(_ entry: AppShortcutEntry) -> some View {
        let combo = prefs.appHotKeys.first { $0.key == entry.app.key }?.combo
        let conflict = prefs.conflictName(for: combo, excluding: .app(entry.app.key))
        return HStack(spacing: 8) {
            Image(nsImage: ShortcutIconCache.shared.icon(path: entry.app.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(entry.app.name)
                .lineLimit(1)
            Spacer()
            if let conflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text("Same shortcut as \(conflict)"))
            }
            ShortcutRecorder(combo: comboBinding(key: entry.app.key, app: entry.app))
                .frame(width: 150, height: 22)
        }
    }

    // Shared by both lists. Recording adds/updates the prefs entry (shows in "With Shortcuts");
    // clearing removes it from the top list, the A–Z row stays.
    private func comboBinding(key: String, app: AppInfo? = nil) -> Binding<KeyCombo?> {
        Binding(
            get: { prefs.appHotKeys.first { $0.key == key }?.combo },
            set: { newValue in
                let index = prefs.appHotKeys.firstIndex { $0.key == key }
                // A–Z edit that adds/removes a top row → keep the edited row where it is on screen.
                if app != nil, (newValue != nil) != (index != nil) {
                    scrollAnchor.hold()
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    switch (newValue, index) {
                    case let (combo?, index?):
                        prefs.appHotKeys[index].combo = combo
                    case let (combo?, nil):
                        guard let app else { return }
                        prefs.appHotKeys.append(AppHotKey(key: app.key, path: app.url.path, name: app.name, combo: combo))
                    case let (nil, index?):
                        prefs.appHotKeys.remove(at: index)
                    case (nil, nil):
                        break
                    }
                }
            }
        )
    }

    // For apps outside the scanned folders.
    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        var added = prefs.appHotKeys
        for url in panel.urls {
            let key = Bundle(url: url)?.bundleIdentifier ?? url.path
            guard !added.contains(where: { $0.key == key }) else { continue }
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            added.append(AppHotKey(key: key, path: url.path, name: name, combo: nil))
        }
        // Single assignment → one save / one hotkey re-registration.
        if added.count != prefs.appHotKeys.count { prefs.appHotKeys = added }
    }
}

// Contacts-style A–Z index: click or drag along it to jump.
private struct LetterIndexBar: View {
    let letters: [String]
    let available: Set<String>
    let onSelect: (String) -> Void
    @State private var last: String?

    private let rowHeight: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(verbatim: letter)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(available.contains(letter) ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 16, height: rowHeight)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let index = Int(value.location.y / rowHeight)
                    guard letters.indices.contains(index) else { return }
                    let letter = letters[index]
                    guard letter != last else { return }
                    last = letter
                    onSelect(letter)
                }
                .onEnded { _ in last = nil }
        )
    }
}

// Keeps the viewport still while rows above it are inserted/removed:
// shifts the scroll offset by however much the document height changed.
@MainActor
private final class ScrollAnchor: NSObject {
    private weak var scrollView: NSScrollView?
    private var baseHeight: CGFloat?
    private var token = 0

    func attach(_ view: NSScrollView) {
        guard view !== scrollView, let doc = view.documentView else { return }
        if let old = scrollView?.documentView {
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: old)
        }
        scrollView = view
        doc.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(documentFrameChanged(_:)),
            name: NSView.frameDidChangeNotification, object: doc
        )
    }

    // Call right before the change; compensation stays armed briefly (update may take a few layout passes).
    func hold() {
        guard let doc = scrollView?.documentView, doc.isFlipped else { return }
        baseHeight = doc.frame.height
        token += 1
        let current = token
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.token == current else { return }
            self.baseHeight = nil
        }
    }

    @objc private func documentFrameChanged(_ note: Notification) {
        guard let base = baseHeight, let sv = scrollView, let doc = sv.documentView else { return }
        let delta = doc.frame.height - base
        baseHeight = doc.frame.height
        guard delta != 0 else { return }
        let clip = sv.contentView
        var origin = clip.bounds.origin
        origin.y += delta
        let rect = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size))
        clip.scroll(to: rect.origin)
        sv.reflectScrolledClipView(clip)
    }
}

// Reports the NSScrollView this view ends up inside (the Form's scroller).
private struct EnclosingScrollViewFinder: NSViewRepresentable {
    let onFind: (NSScrollView) -> Void

    func makeNSView(context: Context) -> FinderView {
        let view = FinderView()
        view.onFind = onFind
        return view
    }

    func updateNSView(_ view: FinderView, context: Context) {
        view.onFind = onFind
    }

    final class FinderView: NSView {
        var onFind: ((NSScrollView) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // Hierarchy may still be attaching; look it up on the next turn.
            Task { @MainActor [weak self] in
                guard let self, let sv = self.enclosingScrollView else { return }
                self.onFind?(sv)
            }
        }
    }
}
