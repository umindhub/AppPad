import AppKit

nonisolated enum PermissionKind: String, Codable, CaseIterable, Sendable {
    case fileRead, fileWrite, network, systemServices, appleEvents, httpHost, secret, shortcut, builtin
}

// One grantable permission. key is what PermissionStore persists.
nonisolated struct PermissionItem: Hashable, Identifiable, Sendable {
    let kind: PermissionKind
    let value: String   // path / bundle id / host / name; empty for flags

    var id: String { key }
    var key: String { value.isEmpty ? kind.rawValue : kind.rawValue + ":" + value }

    // Enforced by the Seatbelt profile (vs. checked in-process).
    var isSandboxRule: Bool {
        switch kind {
        case .fileRead, .fileWrite, .network, .systemServices, .appleEvents: return true
        case .httpHost, .secret, .shortcut, .builtin: return false
        }
    }
}

extension PermissionItem {
    // Shown in the permission prompt and the Authorization section.
    var title: String {
        switch kind {
        case .fileRead:
            return String(localized: "Read files in \(Self.displayPath(value))", table: "WorkflowPermissions")
        case .fileWrite:
            return String(localized: "Read and change files in \(Self.displayPath(value))", table: "WorkflowPermissions")
        case .network:
            return String(localized: "Access the network from scripts", table: "WorkflowPermissions")
        case .systemServices:
            return String(localized: "Use system services (open apps, clipboard, notifications)", table: "WorkflowPermissions")
        case .appleEvents:
            return String(localized: "Control \(AppLookup.name(forBundleID: value))", table: "WorkflowPermissions")
        case .httpHost:
            return String(localized: "Send HTTP requests to \(value)", table: "WorkflowPermissions")
        case .secret:
            return String(localized: "Use the secret “\(value)” in HTTP requests", table: "WorkflowPermissions")
        case .shortcut:
            return String(localized: "Run the shortcut “\(value)”", table: "WorkflowPermissions")
        case .builtin:
            return (BuiltinAction(rawValue: value) ?? .emptyTrash).permissionTitle
        }
    }

    static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

extension Workflow {
    var usesSandbox: Bool { steps.contains { $0.kind == .shell || $0.kind == .appleScript } }
    var usesHTTP: Bool { steps.contains { $0.kind == .http } }

    // Everything this workflow needs, in a stable order (manifest + implied by steps).
    var requiredPermissions: [PermissionItem] {
        var items: [PermissionItem] = []
        let p = permissions
        if usesSandbox {
            items += p.fileRead.map { PermissionItem(kind: .fileRead, value: $0) }
            items += p.fileWrite.map { PermissionItem(kind: .fileWrite, value: $0) }
            if p.network { items.append(PermissionItem(kind: .network, value: "")) }
            // osascript cannot work without mach services, so AppleScript implies them.
            if p.systemServices || steps.contains(where: { $0.kind == .appleScript }) {
                items.append(PermissionItem(kind: .systemServices, value: ""))
            }
            items += p.appleEvents.map { PermissionItem(kind: .appleEvents, value: $0) }
        }
        if usesHTTP {
            items += p.httpHosts.map { PermissionItem(kind: .httpHost, value: $0.lowercased()) }
            items += p.secrets.map { PermissionItem(kind: .secret, value: $0) }
        }
        for step in steps {
            switch step.kind {
            case .shortcut where !step.shortcutName.isEmpty:
                items.append(PermissionItem(kind: .shortcut, value: step.shortcutName))
            case .builtin where step.unsupportedBuiltin == nil:
                items.append(PermissionItem(kind: .builtin, value: step.builtin.rawValue))
            default:
                break
            }
        }
        var seen = Set<String>()
        return items.filter { seen.insert($0.key).inserted }
    }

    // Problems that block running (shown in the editor too).
    var validationErrors: [String] {
        var errors: [String] = []
        if steps.isEmpty { errors.append(String(localized: "Add at least one step.", table: "WorkflowPermissions")) }
        let hosts = Set(permissions.httpHosts.map { $0.lowercased() })
        let secrets = Set(permissions.secrets)
        for (index, step) in steps.enumerated() {
            let n = index + 1
            switch step.kind {
            case .shell, .appleScript:
                if step.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(String(localized: "Step \(n): the script is empty.", table: "WorkflowPermissions"))
                }
            case .shortcut:
                if step.shortcutName.isEmpty {
                    errors.append(String(localized: "Step \(n): choose a shortcut.", table: "WorkflowPermissions"))
                }
            case .http:
                guard let host = step.http.host, step.http.url.lowercased().hasPrefix("http") else {
                    errors.append(String(localized: "Step \(n): enter a valid http(s) URL.", table: "WorkflowPermissions"))
                    continue
                }
                if !hosts.contains(host) {
                    errors.append(String(localized: "Step \(n): add \(host) to the declared HTTP hosts.", table: "WorkflowPermissions"))
                }
                for name in step.http.referencedSecrets where !secrets.contains(name) {
                    errors.append(String(localized: "Step \(n): declare the secret “\(name)”.", table: "WorkflowPermissions"))
                }
            case .builtin:
                if let raw = step.unsupportedBuiltin {
                    errors.append(String(localized: "Step \(n): “\(raw)” needs a newer version of AppPad.", table: "WorkflowPermissions"))
                } else if step.builtin == .openURL, step.url.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(String(localized: "Step \(n): enter the URL to open.", table: "WorkflowPermissions"))
                } else if step.builtin == .prefillTerminal {
                    if step.command.trimmingCharacters(in: .whitespaces).isEmpty {
                        errors.append(String(localized: "Step \(n): enter the command to fill in Terminal.", table: "WorkflowPermissions"))
                    } else if !TerminalLauncher.isDisplaySafe(step.command) || !TerminalLauncher.isDisplaySafe(step.directory) {
                        errors.append(String(localized: "Step \(n): the command and folder must be one line without control characters.", table: "WorkflowPermissions"))
                    }
                }
            }
        }
        return errors
    }

    var symbolName: String {
        if !symbol.isEmpty { return symbol }
        switch steps.first?.kind {
        case .shell: return "terminal"
        case .appleScript: return "applescript"
        case .shortcut: return "square.2.layers.3d"
        case .http: return "network"
        case .builtin: return steps.first?.builtin.symbolName ?? "bolt"
        case nil: return "bolt"
        }
    }
}

extension WorkflowStepKind {
    var title: String {
        switch self {
        case .shell: return String(localized: "Shell Script", table: "WorkflowPermissions")
        case .appleScript: return String(localized: "AppleScript", table: "Workflow")
        case .shortcut: return String(localized: "Shortcut", table: "WorkflowPermissions")
        case .http: return String(localized: "HTTP Request", table: "WorkflowPermissions")
        case .builtin: return String(localized: "Built-in Action", table: "WorkflowPermissions")
        }
    }

    var symbolName: String {
        switch self {
        case .shell: return "terminal"
        case .appleScript: return "applescript"
        case .shortcut: return "square.2.layers.3d"
        case .http: return "network"
        case .builtin: return "bolt"
        }
    }
}

extension BuiltinAction {
    var title: String {
        switch self {
        case .emptyTrash: return String(localized: "Empty Trash", table: "WorkflowPermissions")
        case .sleepDisplays: return String(localized: "Sleep Displays", table: "WorkflowPermissions")
        case .sleepMac: return String(localized: "Sleep Mac", table: "WorkflowPermissions")
        case .keepAwake: return String(localized: "Keep Awake", table: "WorkflowPermissions")
        case .toggleDarkMode: return String(localized: "Toggle Light/Dark Mode", table: "WorkflowPermissions")
        case .setVolume: return String(localized: "Set Volume", table: "WorkflowPermissions")
        case .toggleMute: return String(localized: "Toggle Mute", table: "WorkflowPermissions")
        case .ejectDisks: return String(localized: "Eject All Disks", table: "WorkflowPermissions")
        case .toggleHiddenFiles: return String(localized: "Toggle Hidden Files", table: "WorkflowPermissions")
        case .quitApp: return String(localized: "Quit App", table: "WorkflowPermissions")
        case .openURL: return String(localized: "Open URL", table: "WorkflowPermissions")
        case .copyIPAddress: return String(localized: "Copy IP Address", table: "WorkflowPermissions")
        case .generateUUID: return String(localized: "Generate UUID", table: "WorkflowPermissions")
        case .shutDown: return String(localized: "Shut Down…", table: "WorkflowPermissions")
        case .restart: return String(localized: "Restart…", table: "WorkflowPermissions")
        case .createReminder: return String(localized: "Add Reminder", table: "WorkflowPermissions")
        case .quitAllApps: return String(localized: "Quit All Apps", table: "WorkflowPermissions")
        case .addToClaudeDesktop: return String(localized: "Add to Claude Desktop")
        case .removeFromClaudeDesktop: return String(localized: "Remove from Claude Desktop")
        case .addYouMindHubToClaudeDesktop: return String(localized: "Add YouMindHub to Claude Desktop", table: "WorkflowPermissions")
        case .removeYouMindHubFromClaudeDesktop: return String(localized: "Remove YouMindHub from Claude Desktop", table: "WorkflowPermissions")
        case .installHomebrew: return String(localized: "Install Homebrew", table: "WorkflowPermissions")
        case .prefillTerminal: return String(localized: "Pre-fill Terminal Command", table: "WorkflowPermissions")
        }
    }

    var permissionTitle: String {
        switch self {
        case .emptyTrash: return String(localized: "Empty the Trash", table: "WorkflowPermissions")
        case .sleepDisplays: return String(localized: "Put the displays to sleep", table: "WorkflowPermissions")
        case .sleepMac: return String(localized: "Put the Mac to sleep", table: "WorkflowPermissions")
        case .keepAwake: return String(localized: "Keep the Mac awake", table: "WorkflowPermissions")
        case .toggleDarkMode: return String(localized: "Switch between light and dark appearance", table: "WorkflowPermissions")
        case .setVolume: return String(localized: "Change the output volume", table: "WorkflowPermissions")
        case .toggleMute: return String(localized: "Mute or unmute the sound", table: "WorkflowPermissions")
        case .ejectDisks: return String(localized: "Eject disks", table: "WorkflowPermissions")
        case .toggleHiddenFiles: return String(localized: "Change Finder’s hidden files setting and relaunch Finder", table: "WorkflowPermissions")
        case .quitApp: return String(localized: "Quit running apps", table: "WorkflowPermissions")
        case .openURL: return String(localized: "Open web pages and links", table: "WorkflowPermissions")
        case .copyIPAddress: return String(localized: "Look up the public IP address (api.ipify.org)", table: "WorkflowPermissions")
        case .generateUUID: return String(localized: "Generate UUIDs", table: "WorkflowPermissions")
        case .shutDown: return String(localized: "Show the Shut Down dialog", table: "WorkflowPermissions")
        case .restart: return String(localized: "Show the Restart dialog", table: "WorkflowPermissions")
        case .createReminder: return String(localized: "Add reminders to the Reminders app", table: "WorkflowPermissions")
        case .quitAllApps: return String(localized: "Quit all running apps", table: "WorkflowPermissions")
        case .addToClaudeDesktop: return String(localized: "Add AppPad to Claude Desktop's MCP servers", table: "WorkflowPermissions")
        case .removeFromClaudeDesktop: return String(localized: "Remove AppPad from Claude Desktop's MCP servers", table: "WorkflowPermissions")
        case .addYouMindHubToClaudeDesktop: return String(localized: "Add YouMindHub to Claude Desktop's MCP servers", table: "WorkflowPermissions")
        case .removeYouMindHubFromClaudeDesktop: return String(localized: "Remove YouMindHub from Claude Desktop's MCP servers", table: "WorkflowPermissions")
        case .installHomebrew: return String(localized: "Open Terminal with Homebrew’s official install command", table: "WorkflowPermissions")
        case .prefillTerminal: return String(localized: "Open Terminal with a command filled in (it runs only after you press Return)", table: "WorkflowPermissions")
        }
    }

    var symbolName: String {
        switch self {
        case .emptyTrash: return "trash"
        case .sleepDisplays: return "display"
        case .sleepMac: return "moon.zzz"
        case .keepAwake: return "cup.and.saucer"
        case .toggleDarkMode: return "circle.lefthalf.filled"
        case .setVolume: return "speaker.wave.2"
        case .toggleMute: return "speaker.slash"
        case .ejectDisks: return "eject"
        case .toggleHiddenFiles: return "eye"
        case .quitApp: return "xmark.app"
        case .openURL: return "safari"
        case .copyIPAddress: return "network"
        case .generateUUID: return "number"
        case .shutDown: return "power"
        case .restart: return "restart"
        case .createReminder: return "checklist"
        case .quitAllApps: return "xmark.app"
        case .addToClaudeDesktop: return "plus.circle"
        case .removeFromClaudeDesktop: return "minus.circle"
        case .addYouMindHubToClaudeDesktop: return "plus.circle"
        case .removeYouMindHubFromClaudeDesktop: return "minus.circle"
        case .installHomebrew: return "shippingbox"
        case .prefillTerminal: return "terminal"
        }
    }

    // Actions that read the step input (the panel argument for the first step).
    var usesInput: Bool {
        switch self {
        case .keepAwake, .setVolume, .quitApp, .openURL, .createReminder: return true
        default: return false
        }
    }
}

// Bundle id ⇄ app name for permission titles and script detection.
enum AppLookup {
    private static let searchDirectories = [
        "/Applications", "/Applications/Utilities", "/System/Applications",
        "/System/Applications/Utilities", "/System/Library/CoreServices",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
    ]

    static func name(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return name
    }

    // "Finder" → com.apple.finder (nil when no such app is installed).
    static func bundleID(forName name: String) -> String? {
        let file = name.hasSuffix(".app") ? name : name + ".app"
        for dir in searchDirectories {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
            if let id = Bundle(url: url)?.bundleIdentifier { return id }
        }
        return nil
    }
}

// Automation consent (Privacy & Security › Automation), asked by AppPad itself before a sandboxed
// script sends Apple Events: the entry is registered under AppPad, and a refusal is reported clearly
// instead of a bare -1743 from osascript inside sandbox-exec.
enum AutomationConsent {
    enum Status { case granted, denied, unknown }

    // Granted in this session: no relaunch / recheck of the target app.
    private static var granted: Set<String> = []
    private static let notPermitted = OSStatus(errAEEventNotPermitted)
    private static let notRunning = OSStatus(procNotFound)

    static func request(_ bundleID: String) async -> Status {
        if granted.contains(bundleID) { return .granted }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return .unknown }
        // AEDeterminePermissionToAutomateTarget needs the target running (else procNotFound, no prompt).
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                    continuation.resume()
                }
            }
        }
        // A just-launched app may need a moment before it accepts events.
        for _ in 0..<20 {
            let status = await Task.detached { Self.determine(bundleID) }.value
            switch status {
            case 0:
                granted.insert(bundleID)
                return .granted
            case notPermitted:
                return .denied
            case notRunning:
                try? await Task.sleep(for: .milliseconds(250))
            default:
                return .unknown
            }
        }
        return .unknown
    }

    // Blocks until the user answers the system prompt: never call on the main thread.
    private nonisolated static func determine(_ bundleID: String) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        return withExtendedLifetime(target) {
            AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard),
                                                  AEEventID(typeWildCard), true)
        }
    }
}
