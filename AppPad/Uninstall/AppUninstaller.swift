import AppKit
import Security

// AppCleaner-style uninstall: finds an app's related files in ~/Library and /Library
// (by bundle id, embedded helper / extension ids and app-group ids), then moves them to the Trash.
// Root-owned items go through NSWorkspace.recycle, which asks for an admin password itself.
// Second pass: an app installed as a Homebrew cask is also removed from Homebrew (see HomebrewCask).
nonisolated enum AppUninstaller {
    nonisolated struct Leftover: Sendable {
        let url: URL
        let matchedByBundleID: Bool   // name-only / shared-group matches are unchecked by default
    }

    nonisolated struct Scan: Sendable {
        let leftovers: [Leftover]
        let bundleIDs: [String]       // main id first, then embedded helpers (quit before trashing)
    }

    nonisolated struct Result: Sendable {
        let appRemoved: Bool
        let failed: [URL]             // related files still on disk
        var homebrewFailedCask: String? = nil   // cask whose `brew uninstall` failed
    }

    // Children named "<id>" or "<id>.<suffix>" (plist, binarycookies, savedState, ShipIt…).
    private static let userPrefixFolders = [
        "Application Support", "Application Scripts", "Caches", "HTTPStorages", "Cookies",
        "WebKit", "Logs", "Preferences", "Preferences/ByHost", "Saved Application State",
    ]
    private static let systemPrefixFolders = ["Application Support", "Caches", "Preferences", "Logs"]
    // Launch jobs / helper tools are often named "<team-ish>.<id>.helper": contains-match.
    private static let userLaunchFolders = ["LaunchAgents"]
    private static let systemLaunchFolders = ["LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools"]

    // MARK: - Scan

    // installedIDs: other installed apps, so "com.foo.App" never claims "com.foo.App.Pro" files.
    static func scan(_ app: AppInfo, installedIDs: Set<String>) -> Scan {
        let fm = FileManager.default
        let userLibrary = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)
        var results: [Leftover] = []
        var seen = Set<String>()

        func add(_ url: URL, byID: Bool) {
            guard fm.fileExists(atPath: url.path), seen.insert(url.standardizedFileURL.path).inserted else { return }
            results.append(Leftover(url: url, matchedByBundleID: byID))
        }

        guard let mainID = app.bundleID, isSafeID(mainID) else {
            addNameMatches(app, library: userLibrary, add: add)
            return Scan(leftovers: results, bundleIDs: [])
        }

        let ids = [mainID] + embeddedBundleIDs(in: app.url, mainID: mainID)
        let ownIDs = Set(ids)
        let foreign = installedIDs.filter { $0 != mainID && $0.hasPrefix(mainID) && !ownIDs.contains($0) }

        func owns(_ name: String, id: String) -> Bool {
            guard name == id || name.hasPrefix(id + ".") else { return false }
            return !foreign.contains { name == $0 || name.hasPrefix($0 + ".") }
        }

        func scanFolders(_ library: URL, prefix: [String], launch: [String]) {
            for folder in prefix + launch {
                let dir = library.appendingPathComponent(folder, isDirectory: true)
                let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                let isLaunch = launch.contains(folder)
                for name in names {
                    // Contains-match only for specific ids (3+ parts), otherwise "<id>" / "<id>.*".
                    let hit = ids.contains { id in
                        isLaunch && id.split(separator: ".").count >= 3 ? name.contains(id) : owns(name, id: id)
                    }
                    if hit { add(dir.appendingPathComponent(name), byID: true) }
                }
            }
        }

        scanFolders(userLibrary, prefix: userPrefixFolders, launch: userLaunchFolders)

        // Sandbox containers: exact names only (listing other apps' containers can trigger a privacy prompt).
        for id in ids {
            add(userLibrary.appendingPathComponent("Containers/\(id)", isDirectory: true), byID: true)
        }

        // Group containers: declared app groups; groups not named after this app may be shared → unchecked.
        let groupsDir = userLibrary.appendingPathComponent("Group Containers", isDirectory: true)
        for group in appGroups(of: app.url) {
            add(groupsDir.appendingPathComponent(group, isDirectory: true), byID: group.contains(mainID))
        }
        let groupNames = (try? fm.contentsOfDirectory(atPath: groupsDir.path)) ?? []
        for name in groupNames where name.contains(mainID) {
            add(groupsDir.appendingPathComponent(name, isDirectory: true), byID: true)
        }

        scanFolders(systemLibrary, prefix: systemPrefixFolders, launch: systemLaunchFolders)
        addNameMatches(app, library: userLibrary, add: add)
        return Scan(leftovers: results, bundleIDs: ids)
    }

    // Folders named after the app (third-party only, unchecked by default).
    private static func addNameMatches(_ app: AppInfo, library: URL, add: (URL, Bool) -> Void) {
        guard app.bundleID?.hasPrefix("com.apple.") != true else { return }
        for name in Set([app.bundleName, app.name]) where name.count >= 3 {
            for folder in ["Application Support", "Caches", "Logs"] {
                add(library.appendingPathComponent("\(folder)/\(name)", isDirectory: true), false)
            }
        }
    }

    // Reverse-DNS, never Apple's.
    private static func isSafeID(_ id: String) -> Bool {
        id.split(separator: ".").count >= 2 && !id.hasPrefix("com.apple.")
    }

    // Helpers, login items, XPC services and extensions that share the main id as prefix.
    // (Shared frameworks such as Sparkle have foreign ids and are skipped.)
    private static func embeddedBundleIDs(in appURL: URL, mainID: String) -> [String] {
        let fm = FileManager.default
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let folders = [
            "Library/LoginItems", "Library/LaunchServices", "Library/SystemExtensions",
            "Library/QuickLook", "Library/Spotlight", "XPCServices", "PlugIns", "Extensions", "Helpers",
        ]
        var ids: [String] = []
        for folder in folders {
            let dir = contents.appendingPathComponent(folder, isDirectory: true)
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names {
                // Bundles carry an Info.plist; bare helper tools are named by their id.
                let id = bundleID(at: dir.appendingPathComponent(name)) ?? name
                if id != mainID, id.hasPrefix(mainID), isSafeID(id), !ids.contains(id) { ids.append(id) }
            }
        }
        return ids
    }

    private static func bundleID(at url: URL) -> String? {
        for plist in ["Contents/Info.plist", "Info.plist"] {
            let info = NSDictionary(contentsOf: url.appendingPathComponent(plist))
            if let id = info?["CFBundleIdentifier"] as? String { return id }
        }
        return nil
    }

    // com.apple.security.application-groups from the code signature.
    private static func appGroups(of appURL: URL) -> [String] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { return [] }
        let groups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        return groups.filter { !$0.isEmpty && !$0.contains("/") }
    }

    // MARK: - Uninstall

    @MainActor
    static func uninstall(_ app: AppInfo, bundleIDs: [String], extra: [URL]) async -> Result {
        guard await quitIfRunning(app, helperIDs: Array(bundleIDs.dropFirst())) else {
            return Result(appRemoved: false, failed: extra)
        }
        // App first: if that fails (or the password prompt is cancelled) nothing else is touched.
        await recycle([app.url])
        guard !exists(app.url) else { return Result(appRemoved: false, failed: extra) }

        await unloadLaunchAgents(extra)
        await recycle(extra)
        // recycle stops at the first failure: retry the rest one by one.
        for url in extra where exists(url) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        var result = Result(appRemoved: true, failed: extra.filter(exists))
        if !app.isAppStore, !app.isSystem,
           case .failed(let token) = await HomebrewCask.remove(appFileName: app.url.lastPathComponent) {
            result.homebrewFailedCask = token
        }
        return result
    }

    // Quit the app (and its running helpers); true when the app itself is no longer running.
    @MainActor
    static func quitIfRunning(_ app: AppInfo, helperIDs: [String] = []) async -> Bool {
        for id in helperIDs {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        }
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
    private static func recycle(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        do {
            _ = try await NSWorkspace.shared.recycle(urls)
        } catch {
            NSLog("Move to Trash failed: \(error)")
        }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // Stop the user's launch agents before trashing their plists (otherwise they run until logout).
    private static func unloadLaunchAgents(_ urls: [URL]) async {
        let agents = urls.filter {
            $0.pathExtension == "plist" && $0.deletingLastPathComponent().lastPathComponent == "LaunchAgents"
                && $0.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path)
        }
        guard !agents.isEmpty else { return }
        let domain = "gui/\(getuid())"
        await Task.detached {
            for agent in agents {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["bootout", domain, agent.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }.value
    }
}

// MARK: - Homebrew

// After the app is in the Trash: if it came from `brew install --cask`, `brew uninstall --cask` removes
// the cask record (Caskroom, linked binaries, its uninstall steps). No brew / no matching cask → skipped.
nonisolated enum HomebrewCask {
    nonisolated enum Outcome: Sendable {
        case skipped
        case removed(String)
        case failed(String)
    }

    private static let infoBatch = 20   // casks per `brew info` call (JSON size stays well below the cap)

    static func remove(appFileName: String) async -> Outcome {
        guard let brew = await brewPath() else { return .skipped }
        // Another copy still in an Applications folder: that one may be the cask's, leave it alone.
        let fm = FileManager.default
        let appDirs = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        guard !appDirs.contains(where: { fm.fileExists(atPath: ($0 as NSString).appendingPathComponent(appFileName)) })
        else { return .skipped }

        let env = await environment(brew: brew)
        guard let token = await caskToken(appFileName: appFileName, brew: brew, env: env) else { return .skipped }
        let output = await ProcessRunner.run(brew, ["uninstall", "--cask", token], environment: env, timeout: 180)
        if output.succeeded { return .removed(token) }
        NSLog("brew uninstall --cask \(token) failed (\(output.exitCode)): \(output.stderr)")
        return .failed(token)
    }

    static func command(for token: String) -> String {
        "brew uninstall --cask \(token)"
    }

    // Default prefixes first (Apple silicon / Intel), then the login shell's PATH.
    private static func brewPath() async -> String? {
        let fm = FileManager.default
        if let hit = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: fm.isExecutableFile(atPath:)) {
            return hit
        }
        let path = await ShellEnvironment.loginPath()
        for dir in path.split(separator: ":") {
            let candidate = (String(dir) as NSString).appendingPathComponent("brew")
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    // Non-interactive: no auto-update, no hints; stdin is closed, so a sudo prompt fails instead of hanging.
    private static func environment(brew: String) async -> [String: String] {
        let binDir = (brew as NSString).deletingLastPathComponent
        let path = await ShellEnvironment.loginPath()
        return [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "PATH": binDir + ":" + path,
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
            "NONINTERACTIVE": "1",
        ]
    }

    // `brew list --cask`, then `brew info` in batches (likely tokens first) until a cask installs this app.
    private static func caskToken(appFileName: String, brew: String, env: [String: String]) async -> String? {
        let list = await ProcessRunner.run(brew, ["list", "--cask", "-1"], environment: env, timeout: 30)
        guard list.succeeded else { return nil }
        let tokens = list.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains(" ") }
        guard !tokens.isEmpty else { return nil }

        let ordered = rank(tokens, appName: (appFileName as NSString).deletingPathExtension)
        var start = 0
        while start < ordered.count {
            let batch = Array(ordered[start..<min(start + infoBatch, ordered.count)])
            start += infoBatch
            let info = await ProcessRunner.run(brew, ["info", "--cask", "--json=v2"] + batch,
                                               environment: env, timeout: 60)
            guard info.succeeded, let data = info.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let casks = json["casks"] as? [[String: Any]] else { continue }
            for cask in casks {
                guard let token = cask["token"] as? String else { continue }
                let artifacts = cask["artifacts"] as? [[String: Any]] ?? []
                if artifacts.contains(where: { installedAppNames($0).contains(appFileName) }) { return token }
            }
        }
        return nil
    }

    // {"app": ["Foo.app"]} or {"app": ["Foo.app", {"target": "Bar.app"}]} → name in the Applications folder.
    private static func installedAppNames(_ artifact: [String: Any]) -> [String] {
        guard let app = artifact["app"] as? [Any], let source = app.first as? String else { return [] }
        if let options = app.dropFirst().first as? [String: Any], let target = options["target"] as? String {
            return [(target as NSString).lastPathComponent]
        }
        return [(source as NSString).lastPathComponent]
    }

    // "Visual Studio Code" → "visual-studio-code" first, then tokens containing / contained in it.
    private static func rank(_ tokens: [String], appName: String) -> [String] {
        let key = appName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        func score(_ token: String) -> Int {
            if token == key { return 0 }
            if !key.isEmpty, token.hasPrefix(key) || key.hasPrefix(token) { return 1 }
            if !key.isEmpty, token.contains(key) || key.contains(token) { return 2 }
            return 3
        }
        return tokens.enumerated()
            .sorted { (score($0.element), $0.offset) < (score($1.element), $1.offset) }
            .map(\.element)
    }
}
