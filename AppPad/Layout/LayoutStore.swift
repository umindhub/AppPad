import Foundation

// Persists pages/folders as JSON and keeps them in sync with installed apps.
final class LayoutStore {
    private(set) var layout: Layout
    private let fileURL: URL
    private var isFresh: Bool

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Layout.self, from: data) {
            layout = decoded
            isFresh = false
        } else {
            layout = Layout(capacity: nil, pages: [])
            isFresh = true
        }
    }

    // Drop uninstalled apps, append new ones at the end, refill if the grid size changed.
    func reconcile(apps: [AppInfo], capacity: Int) {
        guard !apps.isEmpty else { return }
        if isFresh {
            layout = DefaultLayout.build(apps: apps, capacity: capacity)
            isFresh = false
            save()
            return
        }

        let installed = Set(apps.map(\.key))
        var placed = Set<String>()
        var pages: [[LayoutItem]] = layout.pages.map { page in
            page.compactMap { item -> LayoutItem? in
                switch item {
                case .app(let key):
                    guard installed.contains(key), placed.insert(key).inserted else { return nil }
                    return item
                case .folder(var folder):
                    folder.apps = folder.apps.filter { installed.contains($0) && placed.insert($0).inserted }
                    return Self.normalized(folder)
                }
            }
        }

        let newApps = apps.filter { !placed.contains($0.key) }.sorted(by: DefaultLayout.byName)
        if !newApps.isEmpty {
            if pages.isEmpty { pages = [[]] }
            pages[pages.count - 1] += newApps.map { .app($0.key) }
        }

        if layout.capacity != capacity {
            pages = DefaultLayout.chunk(pages.flatMap { $0 }, capacity: capacity)
        }
        let updated = Layout(capacity: capacity, pages: Self.splitOverflow(pages, capacity: capacity))
        if updated != layout {
            layout = updated
            save()
        }
    }

    // Grid size changed: refill pages in order.
    func reflow(capacity: Int) {
        layout.pages = DefaultLayout.chunk(layout.pages.flatMap { $0 }, capacity: capacity)
        layout.capacity = capacity
        save()
    }

    func reset(apps: [AppInfo], capacity: Int) {
        layout = DefaultLayout.build(apps: apps, capacity: capacity)
        save()
    }

    // Backup restore: take the imported pages, then drop missing apps / append new ones.
    func restore(_ imported: Layout, apps: [AppInfo], capacity: Int) {
        layout = imported
        isFresh = false
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

        case .reorderInFolder:
            return   // only valid for folder sources (handled above)
        }

        commit(pages, capacity: capacity)
    }

    func remove(appKey: String, capacity: Int) {
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
