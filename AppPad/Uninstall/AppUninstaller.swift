import AppKit

// Finds an app's leftover files in ~/Library and moves everything to the Trash via Finder
// (Finder asks for an admin password itself when a bundle is root-owned).
nonisolated enum AppUninstaller {
    nonisolated struct Leftover: Sendable {
        let url: URL
        let matchedByBundleID: Bool   // name-only matches are unchecked by default
    }

    static func findLeftovers(for app: AppInfo) -> [Leftover] {
        let fm = FileManager.default
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        var results: [Leftover] = []
        var seen = Set<String>()

        func add(_ relative: String, byID: Bool) {
            let url = library.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path), seen.insert(url.path).inserted else { return }
            results.append(Leftover(url: url, matchedByBundleID: byID))
        }

        if let id = app.bundleID {
            for relative in [
                "Application Support/\(id)",
                "Application Scripts/\(id)",
                "Caches/\(id)",
                "Containers/\(id)",
                "HTTPStorages/\(id)",
                "HTTPStorages/\(id).binarycookies",
                "Cookies/\(id).binarycookies",
                "WebKit/\(id)",
                "Logs/\(id)",
                "Preferences/\(id).plist",
                "Saved Application State/\(id).savedState",
            ] {
                add(relative, byID: true)
            }
            // Prefix / contains matches: ByHost prefs, launch agents, team-prefixed group containers.
            for folder in ["Preferences/ByHost", "LaunchAgents", "Group Containers"] {
                let dir = library.appendingPathComponent(folder, isDirectory: true)
                let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                for name in names where name.contains(id) {
                    add("\(folder)/\(name)", byID: true)
                }
            }
        }

        // Folders named after the app (third-party only, unchecked by default).
        if app.bundleID?.hasPrefix("com.apple.") != true {
            for name in Set([app.bundleName, app.name]) where !name.isEmpty {
                for folder in ["Application Support", "Caches", "Logs"] {
                    add("\(folder)/\(name)", byID: false)
                }
            }
        }
        return results
    }

    // Quit the app if running; true when it is no longer running.
    @MainActor
    static func quitIfRunning(_ app: AppInfo) async -> Bool {
        guard let id = app.bundleID else { return true }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(100))
            if running.allSatisfy(\.isTerminated) { return true }
        }
        return false
    }

    @MainActor
    static func moveToTrash(_ urls: [URL]) async -> Bool {
        do {
            let trashed = try await NSWorkspace.shared.recycle(urls)
            return !trashed.isEmpty
        } catch {
            NSLog("Move to Trash failed: \(error)")
            return false
        }
    }
}
