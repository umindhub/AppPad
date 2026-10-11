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
            return String(localized: "Read files in \(Self.displayPath(value))")
        case .fileWrite:
            return String(localized: "Read and change files in \(Self.displayPath(value))")
        case .network:
            return String(localized: "Access the network from scripts")
        case .systemServices:
            return String(localized: "Use system services (open apps, clipboard, notifications)")
        case .appleEvents:
            return String(localized: "Control \(AppLookup.name(forBundleID: value))")
        case .httpHost:
            return String(localized: "Send HTTP requests to \(value)")
        case .secret:
            return String(localized: "Use the secret “\(value)” in HTTP requests")
        case .shortcut:
            return String(localized: "Run the shortcut “\(value)”")
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
        if steps.isEmpty { errors.append(String(localized: "Add at least one step.")) }
        let hosts = Set(permissions.httpHosts.map { $0.lowercased() })
        let secrets = Set(permissions.secrets)
        for (index, step) in steps.enumerated() {
            let n = index + 1
            switch step.kind {
            case .shell, .appleScript:
                if step.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(String(localized: "Step \(n): the script is empty."))
                }
            case .shortcut:
                if step.shortcutName.isEmpty {
                    errors.append(String(localized: "Step \(n): choose a shortcut."))
                }
            case .http:
                guard let host = step.http.host, step.http.url.lowercased().hasPrefix("http") else {
                    errors.append(String(localized: "Step \(n): enter a valid http(s) URL."))
                    continue
                }
                if !hosts.contains(host) {
                    errors.append(String(localized: "Step \(n): add \(host) to the declared HTTP hosts."))
                }
                for name in step.http.referencedSecrets where !secrets.contains(name) {
                    errors.append(String(localized: "Step \(n): declare the secret “\(name)”."))
                }
            case .builtin:
                if let raw = step.unsupportedBuiltin {
                    errors.append(String(localized: "Step \(n): “\(raw)” needs a newer version of AppPad."))
                } else if step.builtin == .openURL, step.url.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append(String(localized: "Step \(n): enter the URL to open."))
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
        case .shell: return String(localized: "Shell Script")
        case .appleScript: return String(localized: "AppleScript")
        case .shortcut: return String(localized: "Shortcut")
        case .http: return String(localized: "HTTP Request")
        case .builtin: return String(localized: "Built-in Action")
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
        case .emptyTrash: return String(localized: "Empty Trash")
        case .sleepDisplays: return String(localized: "Sleep Displays")
        case .sleepMac: return String(localized: "Sleep Mac")
        case .keepAwake: return String(localized: "Keep Awake")
        case .toggleDarkMode: return String(localized: "Toggle Light/Dark Mode")
        case .setVolume: return String(localized: "Set Volume")
        case .toggleMute: return String(localized: "Toggle Mute")
        case .ejectDisks: return String(localized: "Eject All Disks")
        case .toggleHiddenFiles: return String(localized: "Toggle Hidden Files")
        case .quitApp: return String(localized: "Quit App")
        case .openURL: return String(localized: "Open URL")
        case .copyIPAddress: return String(localized: "Copy IP Address")
        case .generateUUID: return String(localized: "Generate UUID")
        case .shutDown: return String(localized: "Shut Down…")
        case .restart: return String(localized: "Restart…")
        case .createReminder: return String(localized: "Add Reminder")
        }
    }

    var permissionTitle: String {
        switch self {
        case .emptyTrash: return String(localized: "Empty the Trash")
        case .sleepDisplays: return String(localized: "Put the displays to sleep")
        case .sleepMac: return String(localized: "Put the Mac to sleep")
        case .keepAwake: return String(localized: "Keep the Mac awake")
        case .toggleDarkMode: return String(localized: "Switch between light and dark appearance")
        case .setVolume: return String(localized: "Change the output volume")
        case .toggleMute: return String(localized: "Mute or unmute the sound")
        case .ejectDisks: return String(localized: "Eject disks")
        case .toggleHiddenFiles: return String(localized: "Change Finder’s hidden files setting and relaunch Finder")
        case .quitApp: return String(localized: "Quit running apps")
        case .openURL: return String(localized: "Open web pages and links")
        case .copyIPAddress: return String(localized: "Look up the public IP address (api.ipify.org)")
        case .generateUUID: return String(localized: "Generate UUIDs")
        case .shutDown: return String(localized: "Show the Shut Down dialog")
        case .restart: return String(localized: "Show the Restart dialog")
        case .createReminder: return String(localized: "Add reminders to the Reminders app")
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
