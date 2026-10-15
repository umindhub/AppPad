import Foundation

// Scans application folders off the main thread.
nonisolated enum AppScanner {
    static var roots: [URL] {
        [
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    // Extra apps for the shortcuts list only (not the launcher grid).
    // Xcode / Xcode-beta share a bundle id, so scanAll() keeps only one of them.
    private static let extraAppPaths = [
        "/System/Library/CoreServices/Finder.app",
        "/Applications/Xcode.app",
        "/Applications/Xcode-beta.app",
    ]

    static func scanExtraLocations() -> [AppInfo] {
        extraAppPaths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .compactMap { makeInfo(URL(fileURLWithPath: $0)) }
    }

    private static let systemBundleIDsOutsideSystem: Set<String> = ["com.apple.Safari"]

    static func scanAll() -> [AppInfo] {
        var seen = Set<String>()
        var result: [AppInfo] = []
        for root in roots {
            for url in findApps(in: root, depth: 0) {
                guard let info = makeInfo(url), seen.insert(info.key).inserted else { continue }
                result.append(info)
            }
        }
        return removingLauncherDuplicates(result)
    }

    // Two entries with the same name where one is only a launcher (e.g. JetBrains Toolbox
    // shortcuts in ~/Applications, script stubs): keep the real app, drop the launcher.
    // Real duplicates (two genuine apps with the same name) are kept.
    private static func removingLauncherDuplicates(_ apps: [AppInfo]) -> [AppInfo] {
        let groups = Dictionary(grouping: apps, by: { $0.name.lowercased() })
        var drop = Set<String>()
        for group in groups.values where group.count > 1 {
            let launchers = group.filter(isLauncherStub)
            guard !launchers.isEmpty, launchers.count < group.count else { continue }   // never drop all
            launchers.forEach { drop.insert($0.key) }
        }
        return drop.isEmpty ? apps : apps.filter { !drop.contains($0.key) }
    }

    private static func isLauncherStub(_ app: AppInfo) -> Bool {
        let path = app.url.path
        if path.contains("/JetBrains Toolbox/") { return true }
        if let id = app.bundleID?.lowercased(), id.contains("toolbox.linkapp") { return true }
        return !hasMachOExecutable(app.url)
    }

    // Native apps have a Mach-O executable; launchers are often shell scripts.
    private static func hasMachOExecutable(_ url: URL) -> Bool {
        guard let executable = Bundle(url: url)?.executableURL,
              let handle = try? FileHandle(forReadingFrom: executable) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let machO: Set<UInt32> = [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA]
        return machO.contains(magic)
    }

    // Recurse into plain folders (e.g. Utilities, vendor folders), never into bundles.
    // Not using .skipsHiddenFiles: the OS marks the /Applications/Safari.app symlink
    // (-> cryptex) as hidden, which would drop Safari.
    private static func findApps(in dir: URL, depth: Int) -> [URL] {
        guard depth <= 2 else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: []
        ) else { return [] }

        var apps: [URL] = []
        for url in items where !url.lastPathComponent.hasPrefix(".") {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isHidden == true, !isSymlinkedApp(url, values) { continue }
            if url.pathExtension == "app" {
                apps.append(url)
                continue
            }
            if values?.isDirectory == true, values?.isPackage != true {
                apps += findApps(in: url, depth: depth + 1)
            }
        }
        return apps
    }

    // Hidden flag is ignored only for a symlink that points at an existing .app bundle.
    private static func isSymlinkedApp(_ url: URL, _ values: URLResourceValues?) -> Bool {
        guard values?.isSymbolicLink == true, url.pathExtension == "app" else { return false }
        let target = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        return target.pathExtension == "app"
            && FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func makeInfo(_ url: URL) -> AppInfo? {
        // Read the bundle through symlinks (Safari: /Applications/Safari.app -> cryptex),
        // but keep the original url for display, launch and layout.
        let resolved = url.resolvingSymlinksInPath()
        let bundle = Bundle(url: resolved) ?? Bundle(url: url)
        let plist = bundle?.infoDictionary ?? [:]
        if isTrue(plist["LSBackgroundOnly"]) { return nil }

        let fm = FileManager.default
        let path = url.path
        var name = fm.displayName(atPath: path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        let bundleID = bundle?.bundleIdentifier
        let bundleName = plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        let receipt = resolved.appendingPathComponent("Contents/_MASReceipt/receipt").path
        // Safari lives in /Applications but is part of the OS (cryptex).
        let isSystem = path.hasPrefix("/System/") || resolved.path.hasPrefix("/System/")
            || systemBundleIDsOutsideSystem.contains(bundleID ?? "")

        return AppInfo(
            key: bundleID ?? path,
            bundleID: bundleID,
            url: url,
            name: name,
            bundleName: bundleName,
            category: plist["LSApplicationCategoryType"] as? String,
            isSystem: isSystem,
            isUtility: url.deletingLastPathComponent().lastPathComponent == "Utilities",
            isAppStore: fm.fileExists(atPath: receipt)
        )
    }

    private static func isTrue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let s = value as? String { return s == "1" || s.lowercased() == "yes" || s.lowercased() == "true" }
        return false
    }
}
