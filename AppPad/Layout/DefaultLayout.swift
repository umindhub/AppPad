import Foundation

// First-launch arrangement in the classic Launchpad order.
// Entries match by bundle id, or by bundle file name with a "file:" prefix (for apps whose id varies).
// Missing entries are skipped, so new macOS releases need no code change:
// 1. primaryOrder apps (page 1)
// 2. other system apps not listed (e.g. new apps in macOS 27), by name
// 3. "Other" folder: */Utilities + otherFolderExtras
// 4. remaining Apple apps (Xcode, Pages…) by name, then third-party apps by name
nonisolated enum DefaultLayout {
    static let otherFolderID = "builtin.other"

    static let primaryOrder: [String] = [
        "com.apple.AppStore",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.AddressBook",
        "com.apple.iCal",
        "com.apple.reminders",
        "com.apple.Notes",
        "com.apple.FaceTime",
        "file:Phone",                 // macOS 26 Phone app
        "com.apple.MobileSMS",
        "com.apple.Maps",
        "com.apple.findmy",
        "com.apple.PhotoBooth",
        "com.apple.Photos",
        "com.apple.Preview",
        "com.apple.Music",
        "com.apple.podcasts",
        "com.apple.TV",
        "com.apple.VoiceMemos",
        "com.apple.iBooksX",
        "com.apple.news",
        "com.apple.stocks",
        "com.apple.Home",
        "com.apple.weather",
        "com.apple.clock",
        "com.apple.calculator",
        "com.apple.freeform",
        "com.apple.Passwords",
        "com.apple.ScreenContinuity",
        "com.apple.shortcuts",
        "com.apple.Siri",
        "com.apple.exposelauncher",
        "com.apple.backup.launcher",
        "com.apple.systempreferences",
        "com.apple.Terminal",         // kept out of "Other": important for developers
    ]

    // Go into the "Other" folder together with the Utilities apps (matched by bundle file name).
    static let otherFolderExtras: Set<String> = [
        "TextEdit", "Stickies", "Chess", "Dictionary", "Font Book",
        "Image Capture", "QuickTime Player", "Automator", "Image Playground", "Tips",
    ]

    static func fileName(_ app: AppInfo) -> String {
        app.url.deletingPathExtension().lastPathComponent
    }

    static func build(apps: [AppInfo], capacity: Int) -> Layout {
        var remaining = Dictionary(apps.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [LayoutItem] = []

        // Folder contents first, so listed extras never appear on page 1.
        // Apps named in primaryOrder (e.g. Terminal) stay out of the folder.
        let primaryIDs = Set(primaryOrder)
        let folderApps: [AppInfo] = remaining.values
            .filter { app in
                guard app.isSystem, !primaryIDs.contains(app.bundleID ?? "") else { return false }
                return app.isUtility || otherFolderExtras.contains(fileName(app))
            }
            .sorted(by: byName)
        folderApps.forEach { remaining[$0.key] = nil }

        // 1. Primary order
        for entry in primaryOrder {
            let match: AppInfo?
            if entry.hasPrefix("file:") {
                let name = String(entry.dropFirst(5))
                match = remaining.values.first { $0.isSystem && fileName($0) == name }
            } else {
                match = remaining[entry]
            }
            guard let app = match else { continue }
            items.append(.app(app.key))
            remaining[app.key] = nil
        }

        // 2. Other system apps
        let otherSystem = remaining.values.filter(\.isSystem).sorted(by: byName)
        otherSystem.forEach { remaining[$0.key] = nil }
        items += otherSystem.map { LayoutItem.app($0.key) }

        // 3. "Other" folder
        if folderApps.count > 1 {
            items.append(.folder(FolderItem(id: otherFolderID, name: "", apps: folderApps.map(\.key))))
        } else {
            items += folderApps.map { LayoutItem.app($0.key) }
        }

        // 4. Remaining Apple apps, then third-party
        let rest = remaining.values.sorted(by: byName)
        let isApple: (AppInfo) -> Bool = { $0.bundleID?.hasPrefix("com.apple.") == true }
        items += rest.filter(isApple).map { LayoutItem.app($0.key) }
        items += rest.filter { !isApple($0) }.map { LayoutItem.app($0.key) }

        return Layout(capacity: capacity, pages: chunk(items, capacity: capacity))
    }

    // New folder name from the App Store category (e.g. "public.app-category.developer-tools" → "Developer Tools").
    static func folderName(for apps: [AppInfo]) -> String {
        for app in apps {
            guard let category = app.category, let last = category.split(separator: ".").last else { continue }
            if let name = categoryName(String(last)) { return name }
            // Unknown category: title-case the id as before
            let words = last.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            if !words.isEmpty { return words.joined(separator: " ") }
        }
        return String(localized: "Folder")
    }

    // Localized App Store category names (all *-games subcategories → Games).
    private static func categoryName(_ id: String) -> String? {
        if id == "games" || id.hasSuffix("-games") { return String(localized: "Games") }
        switch id {
        case "business": return String(localized: "Business")
        case "developer-tools": return String(localized: "Developer Tools")
        case "education": return String(localized: "Education")
        case "entertainment": return String(localized: "Entertainment")
        case "finance": return String(localized: "Finance")
        case "graphics-design": return String(localized: "Graphics & Design")
        case "healthcare-fitness": return String(localized: "Health & Fitness")
        case "lifestyle": return String(localized: "Lifestyle")
        case "medical": return String(localized: "Medical")
        case "music": return String(localized: "Music")
        case "news": return String(localized: "News")
        case "photography": return String(localized: "Photography")
        case "productivity": return String(localized: "Productivity")
        case "reference": return String(localized: "Reference")
        case "social-networking": return String(localized: "Social Networking")
        case "sports": return String(localized: "Sports")
        case "travel": return String(localized: "Travel")
        case "utilities": return String(localized: "Utilities")
        case "video": return String(localized: "Video")
        case "weather": return String(localized: "Weather")
        default: return nil
        }
    }

    static func byName(_ a: AppInfo, _ b: AppInfo) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    static func chunk(_ items: [LayoutItem], capacity: Int) -> [[LayoutItem]] {
        let size = max(1, capacity)
        return stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }
}
