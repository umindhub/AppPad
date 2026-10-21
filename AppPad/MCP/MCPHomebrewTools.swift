import AppKit

// Apps for regular users via Homebrew casks. Policy (no exceptions, also not for own taps):
// casks only (never formulae), official homebrew/cask tap only, the cask installs nothing but
// apps (command-line tools only from inside those apps), and every app is notarized by Apple
// (checked after download, again after install).
// Installs and uninstalls are confirmed in AppPad (Settings › AI Assistants can turn that off);
// installing Homebrew itself always asks and pre-fills the official command in Terminal (runs on Return).
enum MCPHomebrewTools {
    static let names: Set<String> = ["homebrew_status", "install_homebrew", "search_apps", "get_app_info",
                                     "install_app", "app_install_status", "uninstall_app"]

    private static let searchLimit = 15

    static var definitions: [[String: Any]] {
        [
            tool("homebrew_status", "Whether Homebrew is installed (needed for search_apps, get_app_info and install_app).", [:]),
            tool("install_homebrew",
                 "Ask the user to install Homebrew. If they agree, AppPad opens Terminal with Homebrew's official install command filled in; nothing runs until the user presses Return, then Terminal asks for the Mac password. Call homebrew_status afterwards.",
                 [:]),
            tool("search_apps",
                 "Search Mac apps in Homebrew's official cask catalog. Returns token, name, description, homepage, whether it is installed, and whether AppPad can install it (with the reason if not).",
                 ["query": string("App name or keyword, e.g. \"firefox\" or \"rectangle\".")], required: ["query"]),
            tool("get_app_info",
                 "Details for one cask token: name, version, description, homepage, download host, and whether AppPad can install it. Nothing is downloaded.",
                 ["token": string("Cask token from search_apps, e.g. \"firefox\".")], required: ["token"]),
            tool("install_app",
                 """
                 Install one app by cask token. AppPad downloads it, checks that every app is notarized by \
                 Apple, shows the app, its developer and its sources to the user for confirmation, installs \
                 it with Homebrew and checks it again. Large downloads can take a while: if it is still \
                 running after wait_seconds, status is "running"; poll app_install_status. One install at a time.
                 """,
                 ["token": string("Cask token from search_apps."),
                  "wait_seconds": integer("How long to wait for the result, 1–600. Default 120.")],
                 required: ["token"]),
            tool("app_install_status", "Progress or result of the last install_app call for a token.",
                 ["token": string("Cask token.")], required: ["token"]),
            tool("uninstall_app",
                 """
                 Uninstall an app (after the user confirms in AppPad). Apps installed with Homebrew are removed \
                 with `brew uninstall --cask` (deleted, user data kept); other apps are moved to the Trash with \
                 their caches and preferences. System apps and AppPad itself cannot be removed.
                 """,
                 ["app": string("App id from get_launchpad_layout, bundle id, app name, or cask token.")],
                 required: ["app"]),
        ]
    }

    static func call(_ name: String, _ args: MCPArguments, client: String) async throws -> MCPTools.Outcome {
        switch name {
        case "homebrew_status": return ok(await status())
        case "install_homebrew": return ok(try await installHomebrew(client: client))
        case "search_apps": return ok(try await search(args.requireString("query")))
        case "get_app_info": return ok(try await appInfo(validToken(args)))
        case "install_app": return try await install(validToken(args), args: args, client: client)
        case "app_install_status": return jobOutcome(try validToken(args))
        case "uninstall_app": return try await uninstall(args.requireString("app"), client: client)
        default: throw MCPToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Homebrew

    private static func status() async -> [String: Any] {
        guard let path = Homebrew.executable else {
            return ["installed": false,
                    "message": "Homebrew is not installed. Call install_homebrew to ask the user to install it."]
        }
        var payload: [String: Any] = ["installed": true, "path": path]
        if let version = await Homebrew.version() { payload["version"] = version }
        return payload
    }

    private static func installHomebrew(client: String) async throws -> [String: Any] {
        guard !Homebrew.isInstalled else { return ["status": "already installed"] }
        guard await AppChangePrompt.installHomebrew(client: client) else {
            return ["status": "declined", "message": "The user chose Cancel. Do not retry unless asked."]
        }
        try HomebrewInstaller.openInTerminal()
        return ["status": "terminal opened",
                "message": "Terminal shows Homebrew's install command; the user presses Return to start it and finishes there. Call homebrew_status later."]
    }

    private static func requireHomebrew() throws {
        guard Homebrew.isInstalled else { throw HomebrewError.notInstalled }
    }

    // MARK: - Search / info

    private static func search(_ query: String) async throws -> [String: Any] {
        try requireHomebrew()
        guard Homebrew.isValidQuery(query) else {
            throw MCPToolError("Use letters, digits, spaces and . _ + @ - only (max 60 characters).")
        }
        let tokens = try await Homebrew.search(query, limit: searchLimit)
        let casks = try await Homebrew.info(tokens)
        let byToken = Dictionary(casks.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        let apps = tokens.compactMap { byToken[$0] }.map(summary)
        var payload: [String: Any] = ["apps": apps]
        if apps.isEmpty { payload["message"] = "No apps found in Homebrew's cask catalog." }
        return payload
    }

    private static func appInfo(_ token: String) async throws -> [String: Any] {
        try requireHomebrew()
        guard let cask = try await Homebrew.info(token) else { throw MCPToolError("No cask “\(token)” in Homebrew.") }
        var item = summary(cask)
        item["downloadHost"] = cask.downloadHost
        item["apps"] = cask.apps.map(\.target)
        if !cask.tools.isEmpty { item["commandLineTools"] = cask.tools.map(\.name) }
        item["updatesItself"] = cask.autoUpdates
        if cask.noChecksum { item["noFixedChecksum"] = true }
        if let caveats = cask.caveats { item["caveats"] = caveats }
        item["note"] = "Notarization is checked by install_app after the download."
        return item
    }

    private static func summary(_ cask: CaskInfo) -> [String: Any] {
        var item: [String: Any] = ["token": cask.token, "name": cask.name, "version": cask.version,
                                   "homepage": cask.homepage, "installable": cask.isAllowed]
        if !cask.summary.isEmpty { item["description"] = cask.summary }
        if let installed = cask.installedVersion { item["installedVersion"] = installed }
        if !cask.problems.isEmpty { item["notInstallableBecause"] = cask.problems }
        return item
    }

    private static func validToken(_ args: MCPArguments) throws -> String {
        let token = try args.requireString("token").lowercased()
        guard Homebrew.isValidToken(token) else {
            throw MCPToolError("“\(token)” is not a cask token. Use the token from search_apps (no tap prefix).")
        }
        return token
    }

    // MARK: - Install

    private final class InstallJob {
        let token: String
        var phase = "checking"
        var payload: [String: Any]?
        var isError = false
        init(token: String) { self.token = token }
    }

    private static var jobs: [String: InstallJob] = [:]
    private static var activeToken: String?

    private static func install(_ token: String, args: MCPArguments, client: String) async throws -> MCPTools.Outcome {
        try requireHomebrew()
        if let active = activeToken {
            throw MCPToolError("“\(active)” is still being installed. Poll app_install_status, then try again.")
        }
        let job = InstallJob(token: token)
        jobs[token] = job
        activeToken = token
        Task {
            do {
                job.payload = try await perform(job, client: client)
            } catch {
                job.payload = ["token": token, "status": "failed", "error": error.localizedDescription]
                job.isError = true
            }
            job.phase = "done"
            activeToken = nil
        }
        let wait = min(max(args.int("wait_seconds") ?? 120, 1), 600)
        let deadline = Date().addingTimeInterval(TimeInterval(wait))
        while job.payload == nil && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return jobOutcome(token)
    }

    private static func jobOutcome(_ token: String) -> MCPTools.Outcome {
        guard let job = jobs[token] else {
            return ok(["token": token, "status": "none", "message": "No install_app call for this token since AppPad started."])
        }
        guard let payload = job.payload else {
            return ok(["token": token, "status": "running", "phase": job.phase,
                       "message": "Still running. Call app_install_status again in a little while."])
        }
        return MCPTools.Outcome(text: MCPTools.json(payload), isError: job.isError)
    }

    private static func perform(_ job: InstallJob, client: String) async throws -> [String: Any] {
        let token = job.token
        guard let cask = try await Homebrew.info(token) else { throw MCPToolError("No cask “\(token)” in Homebrew.") }
        guard cask.isAllowed else {
            throw MCPToolError("AppPad does not install “\(cask.name)”: it " + cask.problems.joined(separator: "; ") + ".")
        }
        if let installed = cask.installedVersion {
            return ["token": token, "status": "already installed", "installedVersion": installed]
        }
        let taken = CaskVerifier.existingTargets(cask)
        guard taken.isEmpty else {
            throw MCPToolError("\(taken.joined(separator: ", ")) is already in the Applications folder (not installed with Homebrew).")
        }

        job.phase = "downloading"
        let download = try await CaskVerifier.fetch(cask)
        job.phase = "verifying"
        let staged = try await CaskVerifier.stage(download, cask: cask)
        let icon = staged.apps.first.map { renderedIcon($0.path) }
        await CaskVerifier.cleanup(staged)

        if MCPHost.shared.confirmAppChanges {
            job.phase = "waiting for the user's confirmation"
            guard await AppChangePrompt.install(client: client, cask: cask, signature: staged.signature, icon: icon) else {
                return ["token": token, "status": "declined",
                        "message": "The user chose Cancel in AppPad. Do not retry unless asked."]
            }
        }

        job.phase = "installing"
        let output = try await Homebrew.run(["install", "--cask", token], timeout: 1800)
        guard output.succeeded else { throw MCPToolError("Homebrew could not install it: " + Homebrew.errorText(output)) }

        // The installed copy must be the checked one; otherwise remove it again.
        let installed: [URL]
        do {
            installed = try await CaskVerifier.verifyInstalled(cask, expected: staged.signature)
        } catch {
            _ = try? await Homebrew.run(["uninstall", "--cask", token], timeout: 300)
            throw MCPToolError(error.localizedDescription + " It was removed again.")
        }
        var payload: [String: Any] = [
            "token": token, "status": "installed", "name": cask.name, "version": cask.version,
            "developer": staged.signature.developer, "teamID": staged.signature.teamID,
            "apps": installed.map(\.path),
        ]
        if !cask.tools.isEmpty { payload["commandLineTools"] = cask.tools.map(\.name) }
        if let caveats = cask.caveats { payload["caveats"] = caveats }
        return payload
    }

    // Drawn now: the source disk image is detached right after.
    private static func renderedIcon(_ path: String) -> NSImage {
        let source = NSWorkspace.shared.icon(forFile: path)
        let size = NSSize(width: 128, height: 128)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }.rasterized(size)
    }

    // MARK: - Uninstall

    private static func uninstall(_ ref: String, client: String) async throws -> MCPTools.Outcome {
        guard let launchpad = MCPLayoutTools.launchpad, !launchpad.catalogApps.isEmpty else {
            throw MCPToolError("AppPad is still scanning the installed apps. Try again in a moment.")
        }
        let app = try await resolveApp(ref, in: launchpad.catalogApps)
        guard !app.isSystem else { throw MCPToolError("“\(app.name)” is part of macOS and cannot be removed.") }
        guard app.bundleID != Bundle.main.bundleIdentifier else { throw MCPToolError("AppPad cannot uninstall itself.") }
        guard !app.isInstalling else { throw MCPToolError("“\(app.name)” is still being installed.") }
        guard !UninstallProgress.shared.isActive(app.key) else { throw MCPToolError("“\(app.name)” is already being removed.") }

        var token: String?
        if !app.isAppStore { token = await HomebrewCask.installedToken(appFileName: app.url.lastPathComponent) }
        if MCPHost.shared.confirmAppChanges {
            let confirmed = await AppChangePrompt.uninstall(client: client, app: app, caskToken: token)
            guard confirmed else {
                return ok(["app": app.key, "status": "declined",
                           "message": "The user chose Cancel in AppPad. Do not retry unless asked."])
            }
        }
        if let token {
            return try await removeWithHomebrew(app, token: token, launchpad: launchpad)
        }
        return try await moveToTrash(app, launchpad: launchpad)
    }

    private static func removeWithHomebrew(_ app: AppInfo, token: String,
                                           launchpad: LaunchpadController) async throws -> MCPTools.Outcome {
        guard await AppUninstaller.quitIfRunning(app) else {
            throw MCPToolError("“\(app.name)” did not quit. Ask the user to quit it, then try again.")
        }
        launchpad.beginUninstall()
        let output = try? await Homebrew.run(["uninstall", "--cask", token], timeout: 300)
        let removed = !FileManager.default.fileExists(atPath: app.url.path)
        launchpad.endUninstall(removing: removed ? app : nil)
        guard removed else {
            let detail = output.map(Homebrew.errorText) ?? HomebrewError.notInstalled.localizedDescription
            throw MCPToolError("Homebrew could not uninstall “\(app.name)”: " + detail)
        }
        return ok(["app": app.key, "name": app.name, "status": "uninstalled", "method": "homebrew", "token": token])
    }

    // Same path as deleting in the Launchpad's edit mode.
    private static func moveToTrash(_ app: AppInfo, launchpad: LaunchpadController) async throws -> MCPTools.Outcome {
        let installed = launchpad.installedBundleIDs
        let scan = await Task.detached(priority: .userInitiated) {
            AppUninstaller.scan(app, installedIDs: installed)
        }.value
        let appPath = app.url.standardizedFileURL.path
        let extra = scan.leftovers
            .filter { $0.matchedByBundleID && $0.url.standardizedFileURL.path != appPath }
            .map(\.url)
        launchpad.beginUninstall()
        let result = await AppUninstaller.uninstall(app, bundleIDs: scan.bundleIDs, extra: extra) { on in
            launchpad.setAuthorizing(on)
        }
        launchpad.endUninstall(removing: result.appRemoved ? app : nil)
        guard result.appRemoved else {
            switch result.failure ?? .other("") {
            case .cancelled: throw MCPToolError("The user cancelled the administrator password prompt.")
            case .automationDenied:
                throw MCPToolError("AppPad may not control Finder (System Settings › Privacy & Security › Automation), which is needed for this app.")
            case .stillRunning: throw MCPToolError("“\(app.name)” did not quit. Ask the user to quit it, then try again.")
            case .other(let text): throw MCPToolError("Could not move “\(app.name)” to the Trash" + (text.isEmpty ? "." : ": " + text))
            }
        }
        var payload: [String: Any] = ["app": app.key, "name": app.name, "status": "uninstalled", "method": "trash"]
        if !result.failed.isEmpty { payload["leftoversNotRemoved"] = result.failed.map(\.path) }
        return ok(payload)
    }

    // id → bundle id → name → cask token (its app name in the Applications folder).
    private static func resolveApp(_ ref: String, in apps: [AppInfo]) async throws -> AppInfo {
        let key = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = key.lowercased()
        if let hit = apps.first(where: { $0.key == key })
            ?? apps.first(where: { $0.bundleID?.lowercased() == lower })
            ?? apps.first(where: { $0.name.lowercased() == lower || $0.bundleName.lowercased() == lower })
            ?? apps.first(where: { $0.url.deletingPathExtension().lastPathComponent.lowercased() == lower }) {
            return hit
        }
        if Homebrew.isValidToken(lower), Homebrew.isInstalled, let cask = try? await Homebrew.info(lower) {
            let targets = Set(cask.apps.map(\.target))
            if let hit = apps.first(where: { targets.contains($0.url.lastPathComponent) }) { return hit }
        }
        throw MCPToolError("No installed app “\(ref)”. Use an id from get_launchpad_layout.")
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

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func integer(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }
}

// MARK: - Dialogs

// Intent confirmation: what will change and where it comes from. Plain Install / Cancel alert,
// shown with FloatingAlert so AppPad's other windows stay where they are.
enum AppChangePrompt {
    static func install(client: String, cask: CaskInfo, signature: CaskVerifier.Signature, icon: NSImage?) async -> Bool {
        var lines: [String] = []
        if !cask.summary.isEmpty { lines += [cask.summary, ""] }
        lines.append(String(localized: "Version: \(cask.version)", table: "MCP"))
        lines.append(String(localized: "Developer: \(signature.developer) (\(signature.teamID))", table: "MCP"))
        lines.append(String(localized: "Website: \(cask.homepageHost)", table: "MCP"))
        lines.append(String(localized: "Download: \(cask.downloadHost)", table: "MCP"))
        lines.append(String(localized: "Notarized by Apple", table: "MCP"))
        if !cask.tools.isEmpty {
            let tools = cask.tools.map(\.name).joined(separator: ", ")
            lines.append(String(localized: "Command-line tools: \(tools)", table: "MCP"))
        }
        if cask.noChecksum {
            lines += ["", String(localized: "This download has no fixed checksum: Homebrew installs the version the website currently offers.", table: "MCP")]
        }
        return await ask(title: String(localized: "“\(client)” wants to install “\(cask.name)”", table: "MCP"),
                   message: lines.joined(separator: "\n"), icon: icon,
                   confirm: String(localized: "Install", table: "MCP"), destructive: false)
    }

    static func uninstall(client: String, app: AppInfo, caskToken: String?) async -> Bool {
        let message = caskToken.map {
            String(localized: "Homebrew deletes the app (brew uninstall --cask \($0)). It is not moved to the Trash.", table: "MCP")
        } ?? String(localized: "The app will be moved to the Trash.")
        return await ask(title: String(localized: "“\(client)” wants to uninstall “\(app.name)”", table: "MCP"),
                   message: message, icon: IconCache.shared.icon(for: app),
                   confirm: String(localized: "Uninstall", table: "MCP"), destructive: true)
    }

    // Always asked (not covered by the confirmation setting).
    static func installHomebrew(client: String) async -> Bool {
        let message = String(localized: "AppPad opens Terminal with Homebrew’s official install command filled in. Press Return there to start it. Terminal asks for your Mac password; AppPad never sees it.", table: "MCP")
            + "\n\n" + Homebrew.installCommand
        return await ask(title: String(localized: "“\(client)” wants to install Homebrew", table: "MCP"),
                   message: message, icon: NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil),
                   confirm: String(localized: "Open Terminal", table: "MCP"), destructive: false)
    }

    private static func ask(title: String, message: String, icon: NSImage?, confirm: String,
                            destructive: Bool) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let icon { alert.icon = icon }
        let ok = alert.addButton(withTitle: confirm)
        ok.hasDestructiveAction = destructive
        let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
        cancel.keyEquivalent = "\u{1b}"
        return FloatingAlert.runModal(alert) == .alertFirstButtonReturn
    }
}

private extension NSImage {
    // Bitmap copy that no longer depends on the source file.
    func rasterized(_ size: NSSize) -> NSImage {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        return NSImage(cgImage: cg, size: size)
    }
}
