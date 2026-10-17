import AppKit
import Darwin
import Security

// AppCleaner-style uninstall: finds an app's related files in ~/Library and /Library
// (by bundle id, embedded helper / extension ids and app-group ids), then moves them to the Trash.
// Everything goes through NSWorkspace.recycle first (no prompt). That never asks for a password, so
// root-owned items (App Store / pkg-installed apps, /Library files) fail with EACCES, and App
// Management can refuse others: those are deleted by Finder via Apple Events, which shows the admin
// password prompt itself and keeps "Put Back" working. Finder is brought to the front for the
// prompt (a background requester gets an inactive dialog, Touch ID disabled).
// Processes still running from inside the bundle (widgets, extensions, XPC) are stopped first:
// they never show up as NSRunningApplication, but keep the bundle "in use".
// Second pass: an app installed as a Homebrew cask is also removed from Homebrew (see HomebrewCask).
nonisolated enum AppUninstaller {
    nonisolated struct Leftover: Sendable {
        let url: URL
        let matchedByBundleID: Bool   // checked by default (name-only matches are not)
    }

    nonisolated struct Scan: Sendable {
        let leftovers: [Leftover]
        let bundleIDs: [String]       // main id first, then embedded helpers (quit before trashing)
    }

    // Why the app bundle itself stayed on disk.
    nonisolated enum Failure: Sendable, Equatable {
        case stillRunning             // the app did not quit
        case cancelled                // admin password prompt cancelled
        case automationDenied         // AppPad may not control Finder (Privacy › Automation)
        case other(String)            // system error description (may be empty)
    }

    nonisolated struct Result: Sendable {
        let appRemoved: Bool
        let failed: [URL]             // related files still on disk
        var failure: Failure? = nil   // set when appRemoved is false
        var homebrewFailedCask: String? = nil   // cask whose `brew uninstall` failed
    }

    // Children named "<id>" or "<id>.<suffix>" (plist, binarycookies, savedState, ShipIt…).
    // "Application Scripts" is user data of the sandbox container (see scan): kept for now.
    private static let userPrefixFolders = [
        "Application Support", /* "Application Scripts", */ "Caches", "HTTPStorages", "Cookies",
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

        // User data is kept for now: ~/Library/Containers and ~/Library/Group Containers hold the app's
        // settings and often its documents. Deleting an App Store app in Finder / Launchpad keeps them
        // too, so a reinstall gets everything back. (macOS also protects them: removing them shows a
        // privacy prompt and still fails, and even listing Group Containers can prompt.)
        /*
        for id in ids {
            add(userLibrary.appendingPathComponent("Containers/\(id)", isDirectory: true), byID: false)
        }
        let groupsDir = userLibrary.appendingPathComponent("Group Containers", isDirectory: true)
        for group in appGroups(of: app.url) {
            add(groupsDir.appendingPathComponent(group, isDirectory: true), byID: false)
        }
        let groupNames = (try? fm.contentsOfDirectory(atPath: groupsDir.path)) ?? []
        for name in groupNames where name.contains(mainID) {
            add(groupsDir.appendingPathComponent(name, isDirectory: true), byID: false)
        }
        */

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

    // authorizing(true/false) brackets a Finder password prompt (the caller keeps its panel open).
    @MainActor
    static func uninstall(_ app: AppInfo, bundleIDs: [String], extra: [URL],
                          authorizing: (Bool) -> Void = { _ in }) async -> Result {
        guard await quitIfRunning(app, helperIDs: Array(bundleIDs.dropFirst())) else {
            return Result(appRemoved: false, failed: extra, failure: .stillRunning)
        }
        // App first: if that fails (or the password prompt is cancelled) nothing else is touched.
        await stopProcesses(inside: app.url)
        var error = await recycle([app.url])
        if exists(app.url), !isPermissionError(error) {
            // A widget may have been relaunched in between: stop it again and retry once.
            await stopProcesses(inside: app.url)
            error = await recycle([app.url])
        }
        if exists(app.url), isPermissionError(error) {
            // Root-owned bundle: Finder asks for the admin password.
            if let finderFailure = await trashWithFinder([app.url], authorizing: authorizing), exists(app.url) {
                return Result(appRemoved: false, failed: extra, failure: finderFailure)
            }
        }
        guard !exists(app.url) else {
            return Result(appRemoved: false, failed: extra, failure: failure(for: error))
        }

        await unloadLaunchAgents(extra)
        await recycle(extra)
        // recycle stops at the first failure: retry the rest one by one.
        for url in extra where exists(url) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        // Root-owned leftovers in /Library: one Finder call, one password prompt.
        let system = extra.filter { exists($0) && $0.standardizedFileURL.path.hasPrefix("/Library/") }
        if !system.isEmpty {
            _ = await trashWithFinder(system, authorizing: authorizing)
        }
        var result = Result(appRemoved: true, failed: extra.filter(exists))
        if !app.isAppStore, !app.isSystem,
           case .failed(let token) = await HomebrewCask.remove(appFileName: app.url.lastPathComponent) {
            result.homebrewFailedCask = token
        }
        return result
    }

    private static func failure(for error: Error?) -> Failure {
        guard let error else { return .other("") }
        let ns = error as NSError
        for e in errorChain(ns) {
            if e.domain == NSCocoaErrorDomain, e.code == NSUserCancelledError { return .cancelled }
            if e.domain == NSOSStatusErrorDomain, e.code == Int(errAuthorizationCanceled) || e.code == -128 {
                return .cancelled   // -128 = userCanceledErr
            }
        }
        return .other(ns.localizedDescription)
    }

    // Write permission missing (EACCES / NSFileWriteNoPermissionError / afpAccessDenied).
    private static func isPermissionError(_ error: Error?) -> Bool {
        guard let error else { return false }
        return errorChain(error as NSError).contains { e in
            (e.domain == NSCocoaErrorDomain && e.code == NSFileWriteNoPermissionError)
                || (e.domain == NSPOSIXErrorDomain && (e.code == Int(EACCES) || e.code == Int(EPERM)))
                || (e.domain == NSOSStatusErrorDomain && e.code == -5000)   // afpAccessDenied
        }
    }

    // The error plus its nested underlying errors (single and multiple).
    private static func errorChain(_ error: NSError) -> [NSError] {
        var result: [NSError] = []
        var queue = [error]
        while let next = queue.first, result.count < 16 {
            queue.removeFirst()
            result.append(next)
            if let single = next.userInfo[NSUnderlyingErrorKey] as? NSError { queue.append(single) }
            if let many = next.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] { queue.append(contentsOf: many) }
        }
        return result
    }

    // MARK: - Finder fallback

    // osascript runs out of process, so the password prompt never blocks AppPad's main thread.
    // nil = Finder reported success.
    @MainActor
    private static func trashWithFinder(_ urls: [URL], authorizing: (Bool) -> Void) async -> Failure? {
        func quoted(_ url: URL) -> String {
            let path = url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "POSIX file \"\(path)\" as alias"
        }
        let items = urls.map(quoted).joined(separator: ", ")
        let lines = [
            "tell application \"Finder\"",
            "activate",   // frontmost requester → active password dialog with Touch ID
            "delete {\(items)}",
            "end tell",
        ]
        authorizing(true)
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.apple.finder")
        let output = await Task.detached { runOsascript(lines) }.value
        authorizing(false)
        guard output.status != 0 else { return nil }
        NSLog("Finder delete failed (\(output.status)): \(output.stderr)")
        if output.stderr.contains("(-128)") { return .cancelled }
        if output.stderr.contains("(-1743)") || output.stderr.contains("(-1744)") { return .automationDenied }
        return .other(cleanAppleScriptError(output.stderr))
    }

    nonisolated private static func runOsascript(_ lines: [String]) -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] }
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // "0:58: execution error: Finder got an error: … (-10006)" → "Finder got an error: …"
    nonisolated private static func cleanAppleScriptError(_ text: String) -> String {
        var message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = message.range(of: "execution error: ") { message = String(message[range.upperBound...]) }
        if let range = message.range(of: #"\s*\(-?\d+\)$"#, options: .regularExpression) { message.removeSubrange(range) }
        return message
    }

    // MARK: - Bundle processes

    // SIGTERM everything running from inside the bundle, SIGKILL what is left after 1.5 s.
    @MainActor
    private static func stopProcesses(inside appURL: URL) async {
        let pids = await Task.detached { processes(inside: appURL) }.value
        guard !pids.isEmpty else { return }
        NSLog("Uninstall: stopping \(pids.count) process(es) inside \(appURL.path)")
        pids.forEach { _ = kill($0, SIGTERM) }
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(100))
            if !pids.contains(where: isAlive) { return }
        }
        pids.filter(isAlive).forEach { _ = kill($0, SIGKILL) }
        try? await Task.sleep(for: .milliseconds(200))
    }

    // Own-user processes whose executable lives in the bundle (other users' are not killable anyway).
    nonisolated private static func processes(inside appURL: URL) -> [pid_t] {
        let base = appURL.standardizedFileURL.path
        let resolved = appURL.resolvingSymlinksInPath().path
        let prefixes = Set([base, resolved, "/System/Volumes/Data" + resolved]).map { $0 + "/" }

        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        let me = getpid()
        let uid = getuid()
        var buffer = [UInt8](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE
        var result: [pid_t] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 && pid != me {
            let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
            guard length > 0 else { continue }
            let path = String(decoding: buffer.prefix(length), as: UTF8.self)
            guard prefixes.contains(where: { path.hasPrefix($0) }) else { continue }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid != uid { continue }
            result.append(pid)
        }
        return result
    }

    nonisolated private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
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

    @MainActor @discardableResult
    private static func recycle(_ urls: [URL]) async -> Error? {
        guard !urls.isEmpty else { return nil }
        do {
            _ = try await NSWorkspace.shared.recycle(urls)
            return nil
        } catch {
            NSLog("Move to Trash failed: \(error)")
            return error
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
