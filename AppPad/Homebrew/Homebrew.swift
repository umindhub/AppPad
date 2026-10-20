import AppKit

// Homebrew access shared by the uninstaller and the MCP app tools.
// Only the two official prefixes are used (no PATH lookup), and brew always runs with an explicit,
// minimal environment: user env vars such as HOMEBREW_CASK_OPTS are never inherited.
nonisolated enum Homebrew {
    static let officialCaskTap = "homebrew/cask"
    static let installCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    private static let prefixes = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    static var executable: String? {
        prefixes.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    static var isInstalled: Bool { executable != nil }

    // Non-interactive: no auto-update (the checked cask stays the installed one), no hints;
    // stdin is closed, so a sudo prompt fails instead of hanging.
    static func environment(brew: String) async -> [String: String] {
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

    static func run(_ arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        guard let brew = executable else { throw HomebrewError.notInstalled }
        let env = await environment(brew: brew)
        return await ProcessRunner.run(brew, arguments, environment: env, timeout: timeout)
    }

    static func version() async -> String? {
        guard let output = try? await run(["--version"], timeout: 20), output.succeeded else { return nil }
        return output.stdout.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    // Plain cask tokens only: no tap prefix ("user/tap/x"), never an option ("-…").
    static func isValidToken(_ token: String) -> Bool {
        token.range(of: #"^[a-z0-9][a-z0-9._+@-]{0,99}$"#, options: .regularExpression) != nil
    }

    // Letters, digits, spaces and . _ + @ -; no "/" (brew treats /…/ as a regex).
    static func isValidQuery(_ query: String) -> Bool {
        query.range(of: #"^[A-Za-z0-9][A-Za-z0-9 ._+@-]{0,59}$"#, options: .regularExpression) != nil
    }

    // MARK: - Metadata

    // `brew info --cask --json=v2`; unknown tokens are simply missing from the result.
    static func info(_ tokens: [String]) async throws -> [CaskInfo] {
        let valid = tokens.filter(isValidToken)
        guard !valid.isEmpty else { return [] }
        var result: [CaskInfo] = []
        for start in stride(from: 0, to: valid.count, by: 20) {
            let batch = Array(valid[start..<min(start + 20, valid.count)])
            let output = try await run(["info", "--cask", "--json=v2"] + batch, timeout: 90)
            // One unknown token fails the whole batch: retry the rest one by one.
            if !output.succeeded, batch.count > 1 {
                for token in batch {
                    if let one = try await info([token]).first { result.append(one) }
                }
                continue
            }
            guard output.succeeded, let data = output.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let casks = json["casks"] as? [[String: Any]] else { continue }
            result += casks.compactMap(CaskInfo.init)
        }
        return result
    }

    static func info(_ token: String) async throws -> CaskInfo? {
        try await info([token]).first { $0.token == token }
    }

    // `brew search --cask`: official tokens only (tap-qualified results are dropped).
    static func search(_ query: String, limit: Int) async throws -> [String] {
        let output = try await run(["search", "--cask", query], timeout: 60)
        guard output.succeeded else { return [] }   // non-zero exit = nothing found
        var tokens: [String] = []
        for line in output.stdout.split(whereSeparator: \.isNewline) {
            let token = line.trimmingCharacters(in: .whitespaces)
            guard isValidToken(token), !tokens.contains(token) else { continue }
            tokens.append(token)
            if tokens.count >= limit { break }
        }
        return tokens
    }

    // Short tail of brew's error output for messages.
    static func errorText(_ output: ProcessOutput) -> String {
        if let launch = output.launchError { return launch }
        if output.timedOut { return "Timed out." }
        let text = output.stderr.isEmpty ? output.stdout : output.stderr
        let lines = text.split(whereSeparator: \.isNewline).suffix(6).joined(separator: "\n")
        return lines.isEmpty ? "brew exited with code \(output.exitCode)." : lines
    }
}

nonisolated enum HomebrewError: LocalizedError, Sendable {
    case notInstalled

    var errorDescription: String? {
        "Homebrew is not installed. Call install_homebrew to let the user install it."
    }
}

// MARK: - Installer

// Official install command typed into Terminal; the user presses Return to start it,
// and Terminal itself asks for the password (AppPad never sees it).
enum HomebrewInstaller {
    static func openInTerminal() throws {
        try TerminalLauncher.prefill(command: Homebrew.installCommand)
    }
}

// MARK: - Terminal

nonisolated struct TerminalLaunchError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

// Opens Terminal with a command typed at the prompt but NOT run: the user reads it and presses
// Return. Only AppPad's fixed bootstrap runs on its own (cd + an interactive zsh with the user's
// rc files), so workflows cannot use this to leave the sandbox. No Apple Events: Terminal opens
// a one-shot .command file.
enum TerminalLauncher {
    private static let terminalID = "com.apple.Terminal"

    // Rejects text whose on-screen form may differ from what runs: control characters
    // (newlines, escape sequences) and bidirectional overrides.
    nonisolated static func isDisplaySafe(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return true
            default: return false
            }
        }
    }

    static func prefill(command: String, directory: String = "") throws {
        let line = command.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, isDisplaySafe(line), isDisplaySafe(directory) else {
            throw TerminalLaunchError(message: String(localized: "The command must be one line without control characters."))
        }
        var folder = ""
        if !directory.trimmingCharacters(in: .whitespaces).isEmpty {
            folder = SeatbeltProfile.resolve(directory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw TerminalLaunchError(message: String(localized: "The folder “\(directory)” does not exist."))
            }
        }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalID) else {
            throw TerminalLaunchError(message: String(localized: "Terminal is not available."))
        }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("AppPad-Terminal-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try write(zshenv, to: dir.appendingPathComponent(".zshenv"))
        try write(zshrc(folder: folder), to: dir.appendingPathComponent(".zshrc"))
        let script = dir.appendingPathComponent("AppPad.command")
        try write(bootstrap(command: line, zdotdir: dir.path), to: script, executable: true)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: configuration)
    }

    // Starts an interactive zsh whose ZDOTDIR is the temp folder, so the rc files below run
    // around the user's own ones. The command travels in an env var, never as code.
    private static func bootstrap(command: String, zdotdir: String) -> String {
        """
        #!/bin/zsh
        rm -f -- "$0"
        export APPPAD_ZDOTDIR="${ZDOTDIR:-$HOME}"
        export APPPAD_PREFILL=\(quote(command))
        ZDOTDIR=\(quote(zdotdir)) exec /bin/zsh -i

        """
    }

    // Sources the user's .zshenv; keeps ZDOTDIR on the temp folder so our .zshrc is read next.
    private static let zshenv = """
        _apppad_tmp="$ZDOTDIR"
        ZDOTDIR="$APPPAD_ZDOTDIR"
        [[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
        APPPAD_ZDOTDIR="$ZDOTDIR"
        ZDOTDIR="$_apppad_tmp"

        """

    // User's .zshrc, then cd, then the command pushed into the line editor (print -z: not run).
    private static func zshrc(folder: String) -> String {
        let cd = folder.isEmpty ? "" : "cd -- \(quote(folder))\n"
        return """
            ZDOTDIR="$APPPAD_ZDOTDIR"
            unset APPPAD_ZDOTDIR
            [[ -r "$ZDOTDIR/.zshrc" ]] && source "$ZDOTDIR/.zshrc"
            \(cd)print -rz -- "$APPPAD_PREFILL"
            unset APPPAD_PREFILL
            rm -rf -- "$_apppad_tmp"
            unset _apppad_tmp

            """
    }

    private static func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: url.path)
    }

    // POSIX single quotes: nothing inside is expanded.
    private static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Cask

// The fields of one `brew info --cask --json=v2` entry that the install policy looks at.
// Artifact entries look like {"app": ["Foo.app"], "target": "/Applications/Foo.app"}: brew adds the
// resolved "target" path next to every relocated artifact (app, binary), it is not an artifact itself.
nonisolated struct CaskInfo: Sendable {
    nonisolated struct App: Sendable {
        let source: String   // path inside the download ("Foo.app", "Foo 1.2/Foo.app")
        let target: String   // name in the Applications folder
        let path: String     // where brew puts it ("/Applications/Foo.app")
    }

    // A command-line tool that brew links into its bin folder. Allowed only when the file lives
    // inside one of the cask's own apps (covered by that app's notarized signature).
    nonisolated struct Tool: Sendable {
        let app: String      // App.target it belongs to
        let inner: String    // path inside the app bundle ("Contents/Resources/app/bin/code")
        let name: String     // link name in brew's bin folder
    }

    let token: String
    let name: String
    let summary: String
    let version: String
    let homepage: String
    let url: String
    let tap: String
    let noChecksum: Bool
    let autoUpdates: Bool
    let installedVersion: String?
    let caveats: String?
    let apps: [App]
    let tools: [Tool]
    let problems: [String]   // why it may not be installed (empty = allowed)

    // Artifacts an app cask may have. Everything else (pkg, installer, pre/postflight, fonts,
    // plug-ins, completions…) means more than "copy an app" and is refused.
    private static let allowedArtifacts: Set<String> = ["app", "binary", "uninstall", "zap"]
    private static let forbiddenUninstallKeys: Set<String> = ["script", "early_script"]
    private static let resolvedTargetKey = "target"
    // The Applications folder as a placeholder in a binary's source (API JSON / cask DSL).
    private static let appDirPlaceholders = ["$APPDIR/", "#{appdir}/"]
    private static let systemBinDirs = ["/bin", "/sbin", "/usr/bin", "/usr/sbin"]

    init?(_ json: [String: Any]) {
        guard let token = json["token"] as? String else { return nil }
        self.token = token
        name = (json["name"] as? [String])?.first ?? token
        summary = json["desc"] as? String ?? ""
        version = json["version"] as? String ?? ""
        homepage = json["homepage"] as? String ?? ""
        url = json["url"] as? String ?? ""
        let tap = json["tap"] as? String ?? ""
        self.tap = tap
        noChecksum = (json["sha256"] as? String) == "no_check"
        autoUpdates = json["auto_updates"] as? Bool ?? false
        installedVersion = json["installed"] as? String
        let caveatText = (json["caveats"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        caveats = caveatText?.isEmpty == false ? caveatText : nil

        var problems: [String] = []
        if tap != Homebrew.officialCaskTap {
            problems.append("comes from the third-party tap \(tap.isEmpty ? "(unknown)" : tap); only homebrew/cask is supported")
        }
        if json["deprecated"] as? Bool == true { problems.append("is deprecated in Homebrew") }
        if json["disabled"] as? Bool == true { problems.append("is disabled in Homebrew") }
        if let container = json["container"], !(container is NSNull) {
            problems.append("uses a nested container")
        }
        if let depends = json["depends_on"] as? [String: Any] {
            if depends["formula"] != nil { problems.append("depends on Homebrew formulae") }
            if depends["cask"] != nil { problems.append("depends on other casks") }
        }

        var apps: [App] = []
        var rawTools: [(value: Any, resolved: String?)] = []
        var refused = Set<String>()
        for artifact in json["artifacts"] as? [[String: Any]] ?? [] {
            let resolved = artifact[Self.resolvedTargetKey] as? String
            for (key, value) in artifact where key != Self.resolvedTargetKey {
                guard Self.allowedArtifacts.contains(key) else {
                    refused.insert(key)
                    continue
                }
                switch key {
                case "app": if let app = Self.app(from: value, resolved: resolved) { apps.append(app) }
                case "binary": rawTools.append((value, resolved))
                case "uninstall": if Self.hasScript(value) { refused.insert("uninstall script") }
                default: break
                }
            }
        }
        if !refused.isEmpty {
            problems.append("installs more than an app (\(refused.sorted().joined(separator: ", ")))")
        }
        if apps.isEmpty { problems.append("contains no app") }

        // After the loop: binary entries may come before the app they point into.
        var tools: [Tool] = []
        for raw in rawTools {
            switch Self.tool(from: raw.value, resolved: raw.resolved, apps: apps) {
            case .success(let tool): tools.append(tool)
            case .failure(let reason): problems.append(reason.message)
            }
        }
        self.apps = apps
        self.tools = tools
        self.problems = problems
    }

    var isAllowed: Bool { problems.isEmpty }

    var homepageHost: String { URL(string: homepage)?.host ?? homepage }
    var downloadHost: String { URL(string: url)?.host ?? url }

    // ["Foo.app"] or ["Foo/Foo.app", {"target": "Bar.app"}], plus brew's resolved target path.
    private static func app(from value: Any, resolved: String?) -> App? {
        guard let list = value as? [Any], let source = list.first as? String else { return nil }
        var target = (source as NSString).lastPathComponent
        if let options = list.dropFirst().first as? [String: Any], let custom = options["target"] as? String {
            target = (custom as NSString).lastPathComponent
        }
        var path = "/Applications/" + target
        if let resolved, resolved.hasPrefix("/") {
            path = resolved
            target = (resolved as NSString).lastPathComponent
        }
        guard target.hasSuffix(".app") else { return nil }
        return App(source: source, target: target, path: path)
    }

    private nonisolated struct Reason: Error {
        let message: String
    }

    // ["$APPDIR/Foo.app/Contents/MacOS/foo", {"target": "foo"}] → Tool, or why it is refused.
    private static func tool(from value: Any, resolved: String?, apps: [App]) -> Result<Tool, Reason> {
        guard let list = value as? [Any], let source = list.first as? String else {
            return .failure(Reason(message: "has an unreadable command-line tool entry"))
        }
        let option = (list.dropFirst().first as? [String: Any])?["target"] as? String
        var name = option ?? (source as NSString).lastPathComponent

        // Where the link goes: brew's resolved path, else an absolute target option.
        if let link = [resolved, option].compactMap({ $0 }).first(where: { $0.hasPrefix("/") }) {
            name = (link as NSString).lastPathComponent
            let dir = (link as NSString).deletingLastPathComponent
            let binDir = Homebrew.executable.map { ($0 as NSString).deletingLastPathComponent }
            guard dir == binDir else {
                return .failure(Reason(message: "links the command-line tool \(name) into \(dir), outside Homebrew's bin folder"))
            }
        }
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
            return .failure(Reason(message: "links the command-line tool \(name) to an unexpected place"))
        }

        // The file must be inside one of the apps: "$APPDIR/<App>/…", "<app path>/…" or "<app source>/…".
        let outside = Reason(message: "installs the command-line tool \(name) from outside its app")
        let placeholder = appDirPlaceholders.first(where: { source.hasPrefix($0) })
        let relative = placeholder.map { String(source.dropFirst($0.count)) } ?? source
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.contains(".."), !parts.contains(".") else { return .failure(outside) }
        var match: (app: App, inner: String)?
        for app in apps {
            let base: String
            if placeholder != nil { base = app.target }
            else if source.hasPrefix("/") { base = app.path }
            else { base = app.source }
            let baseParts = base.split(separator: "/").map(String.init)
            if parts.count > baseParts.count, Array(parts.prefix(baseParts.count)) == baseParts {
                match = (app, parts.dropFirst(baseParts.count).joined(separator: "/"))
                break
            }
        }
        guard let match else { return .failure(outside) }
        if let dir = systemBinDirs.first(where: { FileManager.default.fileExists(atPath: "\($0)/\(name)") }) {
            return .failure(Reason(message: "would hide the system command \(dir)/\(name)"))
        }
        return .success(Tool(app: match.app.target, inner: match.inner, name: name))
    }

    private static func hasScript(_ value: Any) -> Bool {
        let entries = value as? [[String: Any]] ?? []
        return entries.contains { !forbiddenUninstallKeys.isDisjoint(with: $0.keys) }
    }
}
