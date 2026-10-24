import Foundation

// Spot an app left when it vanished from disk (brew upgrade, pkg reinstall), so it returns there.
nonisolated struct Vacancy: Codable, Equatable, Sendable {
    var key: String
    var page: Int
    var index: Int                // top-level index on the page
    var folderID: String?
    var folderName: String?
    var folderApps: [String]?     // folder order when the app vanished
    var removedAt: Date
}

// Persists pages/folders as JSON and keeps them in sync with installed apps.
final class LayoutStore {
    private(set) var layout: Layout
    private let fileURL: URL
    private let vacancyURL: URL
    private var isFresh: Bool
    private var vacancies: [Vacancy]

    // Long enough for a slow pkg reinstall; an app returning later counts as new.
    private static let vacancyLifetime: TimeInterval = 60 * 60
    private static let vacancyLimit = 300

    init(fileURL: URL) {
        self.fileURL = fileURL
        vacancyURL = fileURL.deletingLastPathComponent().appendingPathComponent("layout-vacancies.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Layout.self, from: data) {
            layout = decoded
            isFresh = false
        } else {
            layout = Layout(capacity: nil, pages: [])
            isFresh = true
        }
        vacancies = (try? Data(contentsOf: vacancyURL))
            .flatMap { try? JSONDecoder().decode([Vacancy].self, from: $0) } ?? []
    }

    // Drop uninstalled apps (remembering their spot), put returning apps back, append new ones.
    func reconcile(apps: [AppInfo], capacity: Int) {
        guard !apps.isEmpty else { return }
        if isFresh {
            layout = DefaultLayout.build(apps: apps, capacity: capacity)
            isFresh = false
            setVacancies([])
            save()
            return
        }

        let now = Date()
        let installed = Set(apps.map(\.key))
        var placed = Set<String>()
        var vacated: [Vacancy] = []
        var pages: [[LayoutItem]] = layout.pages.enumerated().map { p, page in
            page.enumerated().compactMap { i, item -> LayoutItem? in
                switch item {
                case .app(let key):
                    guard installed.contains(key) else {
                        vacated.append(Vacancy(key: key, page: p, index: i, removedAt: now))
                        return nil
                    }
                    return placed.insert(key).inserted ? item : nil
                case .folder(var folder):
                    let order = folder.apps
                    for key in order where !installed.contains(key) {
                        vacated.append(Vacancy(key: key, page: p, index: i, folderID: folder.id,
                                               folderName: folder.name, folderApps: order, removedAt: now))
                    }
                    folder.apps = order.filter { installed.contains($0) && placed.insert($0).inserted }
                    return Self.normalized(folder)
                }
            }
        }

        // Refit before appending new apps so they don't count toward "was full".
        if layout.capacity != capacity {
            pages = Self.refit(pages, from: layout.capacity, to: capacity)
        }

        // Live vacancies by key; a fresh one replaces an older one for the same key.
        var open: [String: Vacancy] = [:]
        for v in vacancies + vacated where now.timeIntervalSince(v.removedAt) < Self.vacancyLifetime {
            open[v.key] = v
        }

        var returning: [(key: String, spot: Vacancy)] = []
        var newApps: [AppInfo] = []
        for app in apps where !placed.contains(app.key) {
            var spot = open.removeValue(forKey: app.key)
            if spot == nil, app.bundleID == nil {
                spot = Self.takeMovedPath(app.key, from: &open, installed: installed)
            }
            if let spot {
                returning.append((app.key, spot))
            } else {
                newApps.append(app)
            }
        }

        // Earlier spots first, so later indices on the same page stay right.
        returning.sort { a, b in
            if a.spot.page != b.spot.page { return a.spot.page < b.spot.page }
            if a.spot.index != b.spot.index { return a.spot.index < b.spot.index }
            let order = a.spot.folderApps ?? []
            return (order.firstIndex(of: a.key) ?? 0) < (order.firstIndex(of: b.key) ?? 0)
        }
        for item in returning { Self.putBack(item.key, at: item.spot, into: &pages) }
        if !returning.isEmpty { pages = pages.map { $0.compactMap(Self.normalizedItem) } }

        newApps.sort(by: DefaultLayout.byName)
        if !newApps.isEmpty {
            if pages.isEmpty { pages = [[]] }
            pages[pages.count - 1] += newApps.map { .app($0.key) }
        }

        // Keep only spots of apps that are still gone (newest last, capped).
        let remaining = open.values
            .filter { !installed.contains($0.key) }
            .sorted { $0.removedAt < $1.removedAt }
            .suffix(Self.vacancyLimit)
        setVacancies(Array(remaining))

        let updated = Layout(capacity: capacity, pages: Self.splitOverflow(pages, capacity: capacity))
        if updated != layout {
            layout = updated
            save()
        }
    }

    // Grid size changed: keep the arrangement, only move what the new size forces.
    func reflow(capacity: Int) {
        layout.pages = Self.refit(layout.pages, from: layout.capacity, to: capacity)
        layout.capacity = capacity
        save()
    }

    func reset(apps: [AppInfo], capacity: Int) {
        layout = DefaultLayout.build(apps: apps, capacity: capacity)
        setVacancies([])
        save()
    }

    // Backup restore: take the imported pages, then drop missing apps / append new ones.
    func restore(_ imported: Layout, apps: [AppInfo], capacity: Int) {
        layout = imported
        isFresh = false
        setVacancies([])   // old spots refer to the replaced arrangement
        reconcile(apps: apps, capacity: capacity)
        save()
    }

    // MARK: - Editing

    func items(onPage page: Int) -> [LayoutItem] {
        layout.pages.indices.contains(page) ? layout.pages[page] : []
    }

    func folder(id: String) -> FolderItem? {
        for page in layout.pages {
            for case .folder(let folder) in page where folder.id == id { return folder }
        }
        return nil
    }

    // folderName(targetKey, draggedKey) names a newly created folder.
    func move(from source: DragSource, to target: DropTarget, capacity: Int,
              folderName: (String, String) -> String) {
        var pages = layout.pages
        let item: LayoutItem

        switch source {
        case .page(let p, let i):
            guard pages.indices.contains(p), pages[p].indices.contains(i) else { return }
            item = pages[p].remove(at: i)

        case .folder(let id, let i):
            guard let location = Self.locate(folderID: id, in: pages),
                  case .folder(var folder) = pages[location.0][location.1],
                  folder.apps.indices.contains(i) else { return }
            let key = folder.apps.remove(at: i)
            if case .reorderInFolder(let index) = target {
                folder.apps.insert(key, at: min(max(0, index), folder.apps.count))
                pages[location.0][location.1] = .folder(folder)
                commit(pages, capacity: capacity)
                return
            }
            // Folder with one app left dissolves in place.
            pages[location.0][location.1] = Self.normalized(folder) ?? .app(key)
            item = .app(key)
        }

        switch target {
        case .insert(let page, let index):
            while pages.count <= page { pages.append([]) }
            pages[page].insert(item, at: min(max(0, index), pages[page].count))

        case .merge(let page, let index):
            guard pages.indices.contains(page), pages[page].indices.contains(index),
                  case .app(let draggedKey) = item else {
                // Folders cannot go into folders: fall back to an insert.
                while pages.count <= page { pages.append([]) }
                pages[page].insert(item, at: min(max(0, index), pages[page].count))
                break
            }
            switch pages[page][index] {
            case .app(let targetKey):
                let folder = FolderItem(id: UUID().uuidString, name: folderName(targetKey, draggedKey),
                                        apps: [targetKey, draggedKey])
                pages[page][index] = .folder(folder)
            case .folder(var folder):
                folder.apps.append(draggedKey)
                pages[page][index] = .folder(folder)
            }

        case .intoFolder(let page, let index, let position, let folderID):
            guard pages.indices.contains(page), pages[page].indices.contains(index),
                  case .app(let draggedKey) = item else {
                while pages.count <= page { pages.append([]) }
                pages[page].insert(item, at: min(max(0, index), pages[page].count))
                break
            }
            switch pages[page][index] {
            case .app(let targetKey):
                var apps = [targetKey]
                apps.insert(draggedKey, at: min(max(0, position), apps.count))
                pages[page][index] = .folder(FolderItem(id: folderID, name: folderName(targetKey, draggedKey), apps: apps))
            case .folder(var folder):
                folder.apps.insert(draggedKey, at: min(max(0, position), folder.apps.count))
                pages[page][index] = .folder(folder)
            }

        case .reorderInFolder:
            return   // only valid for folder sources (handled above)
        }

        commit(pages, capacity: capacity)
    }

    // Deliberate uninstall: no spot is kept for a later reinstall.
    func remove(appKey: String, capacity: Int) {
        if vacancies.contains(where: { $0.key == appKey }) {
            setVacancies(vacancies.filter { $0.key != appKey })
        }
        let pages = layout.pages.map { page in
            page.compactMap { item -> LayoutItem? in
                switch item {
                case .app(let key):
                    return key == appKey ? nil : item
                case .folder(var folder):
                    folder.apps.removeAll { $0 == appKey }
                    return Self.normalized(folder)
                }
            }
        }
        commit(pages, capacity: capacity)
    }

    func renameFolder(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let location = Self.locate(folderID: id, in: layout.pages),
              case .folder(var folder) = layout.pages[location.0][location.1] else { return }
        folder.name = trimmed
        layout.pages[location.0][location.1] = .folder(folder)
        save()
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(layout).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Layout save failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func setVacancies(_ list: [Vacancy]) {
        guard list != vacancies else { return }
        vacancies = list
        do {
            if list.isEmpty {
                try? FileManager.default.removeItem(at: vacancyURL)
            } else {
                try JSONEncoder().encode(list).write(to: vacancyURL, options: .atomic)
            }
        } catch {
            NSLog("Layout vacancies save failed: \(error)")
        }
    }

    // Path-keyed app (no bundle id) whose versioned folder was renamed,
    // e.g. /Applications/SEGGER/JLink_V988/X.app -> JLink_V992/X.app.
    private static func takeMovedPath(_ key: String, from open: inout [String: Vacancy],
                                      installed: Set<String>) -> Vacancy? {
        guard key.hasPrefix("/") else { return nil }
        let parts = key.split(separator: "/")
        let match = open.keys.sorted().first { old in
            guard old.hasPrefix("/"), !installed.contains(old) else { return false }
            let oldParts = old.split(separator: "/")
            guard oldParts.count == parts.count, oldParts.last == parts.last else { return false }
            return zip(oldParts, parts).filter { $0 != $1 }.count == 1
        }
        return match.flatMap { open.removeValue(forKey: $0) }
    }

    // Folder spot: rejoin the folder, rebuild it around its last app, or recreate it in place.
    private static func putBack(_ key: String, at spot: Vacancy, into pages: inout [[LayoutItem]]) {
        guard let id = spot.folderID else {
            insert(.app(key), at: spot, into: &pages)
            return
        }
        let order = spot.folderApps ?? [key]
        if let loc = locate(folderID: id, in: pages), case .folder(var folder) = pages[loc.0][loc.1] {
            folder.apps.insert(key, at: insertionIndex(of: key, into: folder.apps, order: order))
            pages[loc.0][loc.1] = .folder(folder)
            return
        }
        let siblings = Set(order).subtracting([key])
        for p in pages.indices {
            for i in pages[p].indices {
                guard case .app(let survivor) = pages[p][i], siblings.contains(survivor) else { continue }
                let apps = order.filter { $0 == survivor || $0 == key }
                pages[p][i] = .folder(FolderItem(id: id, name: spot.folderName ?? "", apps: apps))
                return
            }
        }
        insert(.folder(FolderItem(id: id, name: spot.folderName ?? "", apps: [key])), at: spot, into: &pages)
    }

    private static func insertionIndex(of key: String, into apps: [String], order: [String]) -> Int {
        let rank = order.firstIndex(of: key) ?? Int.max
        return apps.firstIndex { (order.firstIndex(of: $0) ?? Int.max) > rank } ?? apps.count
    }

    // A page that vanished with its apps comes back as a new page.
    private static func insert(_ item: LayoutItem, at spot: Vacancy, into pages: inout [[LayoutItem]]) {
        if pages.isEmpty { pages = [[]] }
        var p = max(0, spot.page)
        if p >= pages.count {
            pages.append([])
            p = pages.count - 1
        }
        pages[p].insert(item, at: min(max(0, spot.index), pages[p].count))
    }

    private static func normalizedItem(_ item: LayoutItem) -> LayoutItem? {
        if case .folder(let folder) = item { return normalized(folder) }
        return item
    }

    private func commit(_ pages: [[LayoutItem]], capacity: Int) {
        layout = Layout(capacity: capacity, pages: Self.splitOverflow(pages, capacity: capacity))
        save()
    }

    private static func locate(folderID: String, in pages: [[LayoutItem]]) -> (Int, Int)? {
        for (p, page) in pages.enumerated() {
            for (j, item) in page.enumerated() {
                if case .folder(let folder) = item, folder.id == folderID { return (p, j) }
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

    // Grow: only pages that were full pull items from the head of the following pages.
    // Shrink: a page's overflow moves to the head of the next page (cascading).
    private static func refit(_ pages: [[LayoutItem]], from oldCapacity: Int?, to newCapacity: Int) -> [[LayoutItem]] {
        let cap = max(1, newCapacity)
        guard let oldCapacity, cap > oldCapacity else { return splitOverflow(pages, capacity: cap) }
        var pages = pages
        let wasFull = pages.map { $0.count >= oldCapacity }
        for i in pages.indices where wasFull[i] {
            var j = i + 1
            while pages[i].count < cap, j < pages.count {
                let take = min(cap - pages[i].count, pages[j].count)
                pages[i] += pages[j].prefix(take)
                pages[j].removeFirst(take)
                j += 1   // only reached once page j is empty
            }
        }
        return splitOverflow(pages, capacity: cap)
    }

    // Carry overflow to the next page; drop empty pages.
    private static func splitOverflow(_ pages: [[LayoutItem]], capacity: Int) -> [[LayoutItem]] {
        var result: [[LayoutItem]] = []
        var carry: [LayoutItem] = []
        for page in pages {
            var current = carry + page
            carry = []
            if current.count > capacity {
                carry = Array(current[capacity...])
                current = Array(current[..<capacity])
            }
            if !current.isEmpty { result.append(current) }
        }
        result += DefaultLayout.chunk(carry, capacity: capacity)
        return result.isEmpty ? [[]] : result
    }
}
