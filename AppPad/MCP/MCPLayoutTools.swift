import Foundation

// Launchpad arrangement for AI clients: read pages / folders with app details and usage,
// apply a new arrangement (validated; the previous one is kept for undo), undo.
// Applied right away: Claude's own tool approval plus the undo history are the safety net.
enum MCPLayoutTools {
    // Set by LaunchpadController.start().
    static weak var launchpad: LaunchpadController?

    static let names: Set<String> = ["get_launchpad_layout", "apply_launchpad_layout", "undo_launchpad_layout"]

    private static let historyLimit = 10
    private static let maxFolderName = 60

    static var definitions: [[String: Any]] {
        [
            tool("get_launchpad_layout",
                 """
                 Read the user's AppPad Launchpad: grid size (items per page), every page in order \
                 (app ids and folders), and all installed apps with name, App Store category, \
                 system / App Store flags and a usage score. Also returns guidelines for tidying it up. \
                 Call this before apply_launchpad_layout.
                 """,
                 [:]),
            tool("apply_launchpad_layout",
                 """
                 Replace the whole Launchpad arrangement. 'pages' is an array of pages; each page is an \
                 array of items in display order: an app id string, or a folder object \
                 {"folder": "Name", "apps": ["app id", …], "folderId": "optional existing id"}. \
                 A folder counts as one item; folders cannot contain folders. AppPad's own icon \
                 (pinned in get_launchpad_layout) always stays where it is. Unknown ids are skipped, \
                 duplicates keep their first place, apps left out are appended to the last page, and a \
                 page with more items than fit is split into consecutive pages. Applied immediately; \
                 the previous arrangement can be restored with undo_launchpad_layout. \
                 Use dry_run to validate without changing anything.
                 """,
                 ["pages": ["type": "array", "items": ["type": "array"],
                            "description": "Pages in order; each page is an array of app ids and folder objects."] as [String: Any],
                  "dry_run": ["type": "boolean",
                              "description": "Only validate and report; change nothing. Default false."] as [String: Any]],
                 required: ["pages"]),
            tool("undo_launchpad_layout",
                 "Restore the Launchpad arrangement from before the last apply_launchpad_layout (up to \(historyLimit) steps back).",
                 [:]),
        ]
    }

    static func call(_ name: String, _ args: MCPArguments) throws -> MCPTools.Outcome {
        guard let launchpad else { throw MCPToolError("AppPad's Launchpad is not ready yet. Try again in a moment.") }
        guard !launchpad.catalogApps.isEmpty else {
            throw MCPToolError("AppPad is still scanning the installed apps. Try again in a moment.")
        }
        switch name {
        case "get_launchpad_layout":
            return ok(describe(launchpad))
        case "apply_launchpad_layout":
            return ok(try apply(args, to: launchpad))
        case "undo_launchpad_layout":
            return ok(try undo(launchpad))
        default:
            throw MCPToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Read

    private static func describe(_ launchpad: LaunchpadController) -> [String: Any] {
        let prefs = Preferences.shared
        let apps = launchpad.catalogApps
        let pinned = pinnedKeys(apps)
        let pages: [[Any]] = launchpad.currentLayout.pages.map { page in
            page.map { item -> Any in
                switch item {
                case .app(let key):
                    return key
                case .folder(let folder):
                    return ["folder": folder.displayName, "folderId": folder.id, "apps": folder.apps] as [String: Any]
                }
            }
        }
        let rows: [[String: Any]] = apps
            .map { (app: $0, usage: launchpad.usageScore(for: $0.key)) }
            .sorted { $0.usage != $1.usage ? $0.usage > $1.usage : DefaultLayout.byName($0.app, $1.app) }
            .map { entry in
                let app = entry.app
                var row: [String: Any] = ["id": app.key, "name": app.name,
                                          "usage": (entry.usage * 10).rounded() / 10]
                if let category = category(app) { row["category"] = category }
                if app.isSystem { row["system"] = true }
                if app.isUtility { row["utility"] = true }
                if app.isAppStore { row["appStore"] = true }
                if app.isInstalling { row["installing"] = true }
                if pinned.contains(app.key) { row["pinned"] = true }
                return row
            }
        var payload: [String: Any] = [
            "grid": ["columns": prefs.gridColumns, "rows": prefs.gridRows, "itemsPerPage": launchpad.capacity],
            "pages": pages,
            "apps": rows,
            "usageNote": "usage = launch frecency: +1 per launch, halving every \(max(1, prefs.frecencyHalfLifeDays)) days. "
                + "Apps start at 1–3, so values near those mean rarely or never opened. Apps are listed most used first.",
            "guidelines": guidelines,
        ]
        if !history().isEmpty { payload["undoAvailable"] = true }
        return payload
    }

    // "public.app-category.developer-tools" → "developer-tools".
    private static func category(_ app: AppInfo) -> String? {
        guard let raw = app.category, !raw.isEmpty else { return nil }
        let prefix = "public.app-category."
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }

    private static let guidelines = """
        Defaults for tidying up (the user's own wishes always win):
        1. Page 1: the most used apps (highest usage) as single icons, most used first, up to itemsPerPage.
        2. Group the rest by purpose into folders (e.g. Developer, Design, Office, Media, Games, Utilities). \
        A folder needs at least 2 apps; 4–12 is a good size. Name folders briefly in the user's language.
        3. Keep frequently used apps out of folders; put rarely used ones (low usage) into folders.
        4. Keep the built-in "Other" folder (folderId builtin.other) for rarely used system utilities \
        unless the user wants otherwise. Pass folderId to keep an existing folder.
        5. Each page holds at most itemsPerPage items (a folder is one item). Fill pages in order; \
        avoid half-empty pages except the last one.
        6. Include every app exactly once. Apps marked installing are still downloading; place them like any other app.
        7. AppPad itself (pinned: true) is a special app: leave it on its current page at its current position \
        and arrange everything else around it. Wherever you put it, AppPad puts it back there.
        8. Before applying, describe the plan to the user unless they asked you to just do it. \
        Use dry_run to check it, then apply. Tell the user they can ask you to undo it.
        """

    // MARK: - Apply

    private struct Plan {
        var pages: [[LayoutItem]] = []
        var unknown: [String] = []
        var duplicates: [String] = []
        var invalid = 0
        var splitPages: [String] = []
    }

    private static func apply(_ args: MCPArguments, to launchpad: LaunchpadController) throws -> [String: Any] {
        let rawPages = try pagesArgument(args)
        let dryRun = args.bool("dry_run") ?? false
        let apps = launchpad.catalogApps
        var plan = try buildPlan(rawPages, apps: apps, current: launchpad.currentLayout)
        let pinned = pinnedKeys(apps)
        plan.pages = pin(plan.pages, keys: pinned, current: launchpad.currentLayout)
        plan.pages = splitLongPages(plan.pages, capacity: launchpad.capacity, notes: &plan.splitPages)

        let placed = Set(plan.pages.joined().flatMap { keys(of: $0) })
        guard !placed.subtracting(pinned).isEmpty else {
            throw MCPToolError("None of the given ids is an installed app. Nothing was changed. Use ids from get_launchpad_layout.")
        }
        let missing = apps.filter { !placed.contains($0.key) }.sorted(by: DefaultLayout.byName)

        var report: [String: Any] = ["placedApps": placed.count, "pages": plan.pages.count]
        let pinnedNames = apps.filter { pinned.contains($0.key) }.map { $0.name }
        if !pinnedNames.isEmpty { report["keptInPlace"] = pinnedNames }
        if !plan.unknown.isEmpty { report["skippedUnknownIds"] = plan.unknown }
        if !plan.duplicates.isEmpty { report["skippedDuplicates"] = plan.duplicates }
        if plan.invalid > 0 { report["skippedInvalidItems"] = plan.invalid }
        if !plan.splitPages.isEmpty { report["splitPages"] = plan.splitPages }
        if !missing.isEmpty { report["appendedToLastPage"] = missing.map { $0.name } }

        if dryRun {
            report["status"] = "preview"
            report["message"] = "Nothing was changed. Call again without dry_run to apply."
            return report
        }
        guard !launchpad.isDraggingItem else {
            throw MCPToolError("The user is dragging an icon in AppPad right now. Try again in a moment.")
        }
        pushHistory(launchpad.currentLayout)
        launchpad.restoreLayout(Layout(capacity: launchpad.capacity, pages: plan.pages))
        report["status"] = "applied"
        report["result"] = summary(launchpad)
        report["message"] = "Applied. undo_launchpad_layout restores the previous arrangement."
        return report
    }

    private static func pagesArgument(_ args: MCPArguments) throws -> [Any] {
        var value = args.raw("pages")
        // Some clients send the JSON as a string.
        if let text = value as? String, let data = text.data(using: .utf8) {
            value = try? JSONSerialization.jsonObject(with: data)
        }
        guard let pages = value as? [Any], !pages.isEmpty else {
            throw MCPToolError("Missing required argument: pages (non-empty array of pages)")
        }
        return pages
    }

    private static func buildPlan(_ rawPages: [Any], apps: [AppInfo], current: Layout) throws -> Plan {
        let resolver = AppResolver(apps)
        var existingFolders: [String: FolderItem] = [:]
        for page in current.pages {
            for case .folder(let folder) in page { existingFolders[folder.id] = folder }
        }
        var usedFolderIDs = Set<String>()
        var placed = Set<String>()
        var plan = Plan()

        func take(_ ref: String) -> String? {
            guard let key = resolver.key(for: ref) else {
                plan.unknown.append(ref)
                return nil
            }
            guard placed.insert(key).inserted else {
                plan.duplicates.append(ref)
                return nil
            }
            return key
        }

        for rawPage in rawPages {
            guard let list = rawPage as? [Any] else {
                throw MCPToolError("Each page must be an array of app ids and folder objects.")
            }
            var items: [LayoutItem] = []
            for raw in list {
                if let ref = appRef(raw) {
                    if let key = take(ref) { items.append(.app(key)) }
                    continue
                }
                guard let object = raw as? [String: Any], let refs = object["apps"] as? [Any] else {
                    plan.invalid += 1
                    continue
                }
                let members = refs.compactMap { appRef($0) }.compactMap { take($0) }
                plan.invalid += refs.count - refs.compactMap { appRef($0) }.count
                switch members.count {
                case 0: continue
                case 1: items.append(.app(members[0]))
                default:
                    let name = ((object["folder"] ?? object["name"]) as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let folder = makeFolder(name: name, members: members, requestedID: object["folderId"] as? String,
                                            existing: existingFolders, used: &usedFolderIDs, apps: resolver)
                    items.append(.folder(folder))
                }
            }
            if !items.isEmpty { plan.pages.append(items) }
        }
        return plan
    }

    // App item: a plain string, {"app": id} or {"type": "app", "id": id}.
    private static func appRef(_ raw: Any) -> String? {
        if let s = raw as? String { return s }
        guard let object = raw as? [String: Any], object["apps"] == nil else { return nil }
        if let s = object["app"] as? String { return s }
        if (object["type"] as? String) == "app", let s = object["id"] as? String { return s }
        return nil
    }

    // Keeps an existing folder's id (by folderId, else by name) so it stays the same folder.
    private static func makeFolder(name: String, members: [String], requestedID: String?,
                                   existing: [String: FolderItem], used: inout Set<String>,
                                   apps: AppResolver) -> FolderItem {
        var match: FolderItem?
        if let requestedID, let folder = existing[requestedID], !used.contains(requestedID) {
            match = folder
        } else if !name.isEmpty {
            match = existing.values.first { !used.contains($0.id) && $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
        }
        let id = match?.id ?? UUID().uuidString
        used.insert(id)

        var finalName = String(name.prefix(maxFolderName))
        if let match, match.name.isEmpty,
           finalName.isEmpty || finalName.caseInsensitiveCompare(match.displayName) == .orderedSame {
            finalName = ""   // built-in "Other" keeps its localized name
        } else if finalName.isEmpty {
            finalName = DefaultLayout.folderName(for: members.compactMap { apps.app(for: $0) })
        }
        return FolderItem(id: id, name: finalName, apps: members)
    }

    // MARK: - Pinned (AppPad itself)

    // Every installed AppPad copy (this build, Release / Beta, Dev): never moved by AI arrangements.
    private static func pinnedKeys(_ apps: [AppInfo]) -> Set<String> {
        let ids = Set([Bundle.main.bundleIdentifier].compactMap { $0 } + DefaultLayout.appPadBundleIDs)
        return Set(apps.filter { $0.bundleID.map(ids.contains) ?? false }.map { $0.key })
    }

    private enum Spot {
        case page(page: Int, index: Int)
        case folder(id: String, position: Int, page: Int, index: Int)

        var order: (Int, Int) {
            switch self {
            case .page(let page, let index): return (page, index)
            case .folder(_, _, let page, let index): return (page, index)
            }
        }
    }

    // Where the pinned apps are now (top level, or inside a folder).
    private static func spots(of keys: Set<String>, in layout: Layout) -> [(key: String, spot: Spot)] {
        var result: [(key: String, spot: Spot)] = []
        for (p, page) in layout.pages.enumerated() {
            for (i, item) in page.enumerated() {
                switch item {
                case .app(let key) where keys.contains(key):
                    result.append((key, .page(page: p, index: i)))
                case .folder(let folder):
                    for (j, key) in folder.apps.enumerated() where keys.contains(key) {
                        result.append((key, .folder(id: folder.id, position: j, page: p, index: i)))
                    }
                default:
                    break
                }
            }
        }
        return result.sorted { $0.spot.order < $1.spot.order }
    }

    // Removes pinned apps from wherever the plan put them, then puts them back at their old spot:
    // same page and index, or the same folder when the plan kept that folder.
    private static func pin(_ pages: [[LayoutItem]], keys: Set<String>, current: Layout) -> [[LayoutItem]] {
        let targets = spots(of: keys, in: current)
        guard !targets.isEmpty else { return pages }
        var pages: [[LayoutItem]] = pages.map { page in
            page.compactMap { item -> LayoutItem? in
                switch item {
                case .app(let key):
                    return keys.contains(key) ? nil : item
                case .folder(var folder):
                    folder.apps.removeAll { keys.contains($0) }
                    return normalized(folder)
                }
            }
        }
        for target in targets {
            if case .folder(let id, let position, _, _) = target.spot,
               let location = locate(folderID: id, in: pages),
               case .folder(var folder) = pages[location.0][location.1] {
                folder.apps.insert(target.key, at: min(position, folder.apps.count))
                pages[location.0][location.1] = .folder(folder)
                continue
            }
            let (page, index) = target.spot.order
            while pages.count <= page { pages.append([]) }
            pages[page].insert(.app(target.key), at: min(index, pages[page].count))
        }
        return pages.filter { !$0.isEmpty }
    }

    private static func locate(folderID: String, in pages: [[LayoutItem]]) -> (Int, Int)? {
        for (p, page) in pages.enumerated() {
            for (i, item) in page.enumerated() {
                if case .folder(let folder) = item, folder.id == folderID { return (p, i) }
            }
        }
        return nil
    }

    // 0 apps → removed, 1 app → plain app, otherwise folder.
    private static func normalized(_ folder: FolderItem) -> LayoutItem? {
        switch folder.apps.count {
        case 0: return nil
        case 1: return .app(folder.apps[0])
        default: return .folder(folder)
        }
    }

    // A page with too many items becomes several consecutive pages (later pages don't shift).
    private static func splitLongPages(_ pages: [[LayoutItem]], capacity: Int, notes: inout [String]) -> [[LayoutItem]] {
        var result: [[LayoutItem]] = []
        for (index, page) in pages.enumerated() {
            guard page.count > capacity else {
                result.append(page)
                continue
            }
            let chunks = DefaultLayout.chunk(page, capacity: capacity)
            notes.append("Page \(index + 1) had \(page.count) items (max \(capacity)); split into \(chunks.count) pages.")
            result += chunks
        }
        return result
    }

    private static func keys(of item: LayoutItem) -> [String] {
        switch item {
        case .app(let key): return [key]
        case .folder(let folder): return folder.apps
        }
    }

    // Compact view of the result: names per page, folders as "Name (n apps)".
    private static func summary(_ launchpad: LaunchpadController) -> [[String]] {
        launchpad.currentLayout.pages.map { page in
            page.map { item in
                switch item {
                case .app(let key): return launchpad.app(forKey: key)?.name ?? key
                case .folder(let folder): return "📁 \(folder.displayName) (\(folder.apps.count))"
                }
            }
        }
    }

    // MARK: - Undo

    private static func undo(_ launchpad: LaunchpadController) throws -> [String: Any] {
        var entries = history()
        guard let last = entries.popLast() else {
            throw MCPToolError("Nothing to undo: no AI arrangement has been applied.")
        }
        guard !launchpad.isDraggingItem else {
            throw MCPToolError("The user is dragging an icon in AppPad right now. Try again in a moment.")
        }
        saveHistory(entries)
        launchpad.restoreLayout(last.layout)
        return ["status": "restored", "savedAt": ISO8601DateFormatter().string(from: last.date),
                "remainingUndoSteps": entries.count, "result": summary(launchpad)]
    }

    private struct HistoryEntry: Codable {
        var date: Date
        var layout: Layout
    }

    private static var historyURL: URL {
        AppEnvironment.supportDirectory.appendingPathComponent("layout-ai-history.json")
    }

    private static func history() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private static func pushHistory(_ layout: Layout) {
        var entries = history()
        entries.append(HistoryEntry(date: Date(), layout: layout))
        saveHistory(Array(entries.suffix(historyLimit)))
    }

    private static func saveHistory(_ entries: [HistoryEntry]) {
        do {
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: historyURL)
                return
            }
            try JSONEncoder().encode(entries).write(to: historyURL, options: .atomic)
        } catch {
            NSLog("Layout history save failed: \(error)")
        }
    }

    // MARK: - Helpers

    private static func ok(_ payload: [String: Any]) -> MCPTools.Outcome {
        MCPTools.Outcome(text: MCPTools.json(payload), isError: false)
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any],
                             required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }
}

// id → case-insensitive id → unique name (localized or bundle name).
private struct AppResolver {
    private let byKey: [String: AppInfo]
    private let byLowerKey: [String: String]
    private let byName: [String: String]

    init(_ apps: [AppInfo]) {
        byKey = Dictionary(apps.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        byLowerKey = Dictionary(apps.map { ($0.key.lowercased(), $0.key) }, uniquingKeysWith: { first, _ in first })
        var names: [String: String?] = [:]
        for app in apps {
            for name in Set([app.name.lowercased(), app.bundleName.lowercased()]) where !name.isEmpty {
                if let existing = names[name], existing != app.key { names[name] = .some(nil) } else { names[name] = app.key }
            }
        }
        byName = names.compactMapValues { $0 }
    }

    func key(for ref: String) -> String? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if byKey[trimmed] != nil { return trimmed }
        let lower = trimmed.lowercased()
        return byLowerKey[lower] ?? byName[lower]
    }

    func app(for key: String) -> AppInfo? { byKey[key] }
}
