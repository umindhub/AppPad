import Foundation

nonisolated struct FolderItem: Codable, Equatable, Sendable {
    var id: String
    var name: String          // empty = built-in folder, shown with a localized default name
    var apps: [String]        // AppInfo keys

    var displayName: String {
        name.isEmpty ? String(localized: "Other") : name
    }
}

nonisolated enum LayoutItem: Codable, Equatable, Sendable {
    case app(String)          // AppInfo key
    case folder(FolderItem)
}

nonisolated struct Layout: Codable, Equatable, Sendable {
    var version: Int = 1
    var capacity: Int?        // items per page the pages were built for
    var pages: [[LayoutItem]]
}

// Where a drag started. Page indices are layout indices.
nonisolated enum DragSource: Equatable, Sendable {
    case page(Int, Int)           // page, item index
    case folder(String, Int)      // folder id, app index
}

// Where a drag ends. Page indices are in the page's item list *without* the dragged item.
nonisolated enum DropTarget: Equatable, Sendable {
    case insert(page: Int, index: Int)
    case merge(page: Int, index: Int)     // drop onto an app (new folder) or a folder (add)
    case reorderInFolder(index: Int)      // same folder the drag started in
    // Spring-loaded folder: into the app / folder at index, at position among its apps.
    // folderID names the folder when an app turns into one (the open sheet stays that folder).
    case intoFolder(page: Int, index: Int, position: Int, folderID: String)
}

// Resolved item for display.
enum GridEntry {
    case app(AppInfo)
    case folder(FolderItem, [AppInfo])
}
