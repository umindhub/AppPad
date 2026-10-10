import Foundation

// One installed application. `key` is the stable identity used by layout and stats.
nonisolated struct AppInfo: Hashable, Sendable {
    let key: String          // bundle id, or path when the bundle has no id
    let bundleID: String?
    let url: URL
    let name: String         // localized display name
    let bundleName: String   // non-localized CFBundleName (for search)
    let category: String?    // LSApplicationCategoryType
    let isSystem: Bool       // ships with macOS (cannot be deleted)
    let isUtility: Bool      // lives in a "Utilities" folder
    let isAppStore: Bool     // has a Mac App Store receipt
}
