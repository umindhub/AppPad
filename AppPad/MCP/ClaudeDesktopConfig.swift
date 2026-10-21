import AppKit
import Combine
import SwiftUI

nonisolated enum ClaudeDesktopError: Error, Sendable {
    case notInstalled, unreadable, writeFailed(String)
    case youMindHubNotInstalled

    var message: String {
        switch self {
        case .notInstalled:
            return String(localized: "Claude Desktop is not installed.", table: "MCP")
        case .unreadable:
            return String(localized: "claude_desktop_config.json is not valid JSON. Fix or delete it, then try again.", table: "MCP")
        case .writeFailed(let detail):
            return String(localized: "Could not save claude_desktop_config.json: \(detail)", table: "MCP")
        case .youMindHubNotInstalled:
            return String(localized: "YouMindHub is not installed in the Applications folder.", table: "MCP")
        }
    }
}

// Adds / removes AppPad's MCP server in Claude Desktop's claude_desktop_config.json.
// Only our own key (apppad / apppad-dev) is touched; other servers and settings are kept.
// Shared by the built-in workflows, Settings › AI Assistants and the onboarding guide.
@MainActor
final class ClaudeDesktopMCP: ObservableObject {
    static let shared = ClaudeDesktopMCP()
    static let bundleID = "com.anthropic.claudefordesktop"

    enum Status: Equatable {
        case notInstalled   // no Claude Desktop app (a leftover config folder does not count)
        case notAdded
        case added
        case outdated       // our key points at another AppPad binary (moved / other build)
        case unreadable     // config exists but is not a JSON object
    }

    @Published private(set) var status: Status = .notAdded

    private init() {
        refresh()
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    // Follow a symlinked config so the link itself is never replaced.
    static var targetURL: URL { configURL.resolvingSymlinksInPath() }

    // A real Claude.app on disk: LaunchServices also remembers apps in the Trash or already deleted.
    static var isClaudeInstalled: Bool {
        let fm = FileManager.default
        var candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        candidates.append(URL(fileURLWithPath: "/Applications/Claude.app"))
        candidates.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Claude.app"))
        return candidates.contains { url in
            let path = url.resolvingSymlinksInPath().path
            guard fm.fileExists(atPath: path), !path.contains("/.Trash/") else { return false }
            return Bundle(url: url)?.bundleIdentifier?.hasPrefix("com.anthropic.claude") == true
        }
    }

    private static var entry: [String: Any] {
        ["command": MCPPaths.executablePath, "args": [MCPPaths.proxyArgument]]
    }

    func refresh() {
        let next = Self.readStatus()
        if next != status { status = next }
    }

    // MARK: - Actions

    func add() -> Result<String, ClaudeDesktopError> {
        defer { refresh() }
        guard Self.isClaudeInstalled else { return .failure(.notInstalled) }
        let url = Self.targetURL
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: url.path) {
            guard let loaded = Self.load(url) else { return .failure(.unreadable) }
            root = loaded
        }
        if let existing = root["mcpServers"], !(existing is [String: Any]) { return .failure(.unreadable) }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        if Self.matches(servers[MCPPaths.serverName]) {
            Self.enableHost()
            return .success(String(localized: "AppPad is already in Claude Desktop.", table: "MCP"))
        }
        servers[MCPPaths.serverName] = Self.entry
        root["mcpServers"] = servers
        do {
            try Self.write(root, to: url)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
        Self.enableHost()
        return .success(String(localized: "AppPad was added to Claude Desktop. Restart Claude Desktop to use it.", table: "MCP"))
    }

    func remove() -> Result<String, ClaudeDesktopError> {
        defer { refresh() }
        let url = Self.targetURL
        let notPresent = String(localized: "AppPad is not in Claude Desktop.", table: "MCP")
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(notPresent) }
        guard var root = Self.load(url) else { return .failure(.unreadable) }
        guard var servers = root["mcpServers"] as? [String: Any], servers[MCPPaths.serverName] != nil else {
            return .success(notPresent)
        }
        servers.removeValue(forKey: MCPPaths.serverName)
        root["mcpServers"] = servers
        do {
            try Self.write(root, to: url)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
        return .success(String(localized: "AppPad was removed from Claude Desktop. Restart Claude Desktop to apply.", table: "MCP"))
    }

    // A client entry without a running server is useless: turn the MCP host on as well.
    private static func enableHost() {
        if !MCPHost.shared.enabled { MCPHost.shared.enabled = true }
    }

    // MARK: - File

    private static func readStatus() -> Status {
        guard isClaudeInstalled else { return .notInstalled }
        let url = targetURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .notAdded }
        guard let root = load(url) else { return .unreadable }
        guard let server = (root["mcpServers"] as? [String: Any])?[MCPPaths.serverName] else { return .notAdded }
        return matches(server) ? .added : .outdated
    }

    private static func matches(_ server: Any?) -> Bool {
        guard let server = server as? [String: Any] else { return false }
        return server["command"] as? String == MCPPaths.executablePath
            && (server["args"] as? [String] ?? []) == [MCPPaths.proxyArgument]
    }

    // Empty / whitespace-only file = empty object; anything else must be a JSON object.
    static func load(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // Keeps one backup of the previous file next to it, then writes atomically.
    static func write(_ root: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("apppad-backup")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
        }
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try JSONSerialization.data(withJSONObject: root, options: options)
        data.append(contentsOf: Array("\n".utf8))
        try data.write(to: url, options: .atomic)
    }
}

// YouMindHub's own MCP server (its bundled helper) in the same config file.
// Used by the two built-in YouMindHub workflows; only the "youmindhub" key is touched.
@MainActor
enum YouMindHubClaudeDesktop {
    static let serverName = "youmindhub"
    static let helperPath = "/Applications/YouMindHub.app/Contents/Helpers/youmindhub-mcp"

    static var isYouMindHubInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: helperPath)
    }

    static func add() -> Result<String, ClaudeDesktopError> {
        guard ClaudeDesktopMCP.isClaudeInstalled else { return .failure(.notInstalled) }
        guard isYouMindHubInstalled else { return .failure(.youMindHubNotInstalled) }
        let url = ClaudeDesktopMCP.targetURL
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let loaded = ClaudeDesktopMCP.load(url) else { return .failure(.unreadable) }
            root = loaded
        }
        if let existing = root["mcpServers"], !(existing is [String: Any]) { return .failure(.unreadable) }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        if matches(servers[serverName]) {
            return .success(String(localized: "YouMindHub is already in Claude Desktop.", table: "MCP"))
        }
        servers[serverName] = ["command": helperPath]   // replaces an entry pointing elsewhere
        root["mcpServers"] = servers
        do {
            try ClaudeDesktopMCP.write(root, to: url)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
        return .success(String(localized: "YouMindHub was added to Claude Desktop. Restart Claude Desktop to use it.", table: "MCP"))
    }

    static func remove() -> Result<String, ClaudeDesktopError> {
        let url = ClaudeDesktopMCP.targetURL
        let notPresent = String(localized: "YouMindHub is not in Claude Desktop.", table: "MCP")
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(notPresent) }
        guard var root = ClaudeDesktopMCP.load(url) else { return .failure(.unreadable) }
        guard var servers = root["mcpServers"] as? [String: Any], servers[serverName] != nil else {
            return .success(notPresent)
        }
        servers.removeValue(forKey: serverName)
        root["mcpServers"] = servers
        do {
            try ClaudeDesktopMCP.write(root, to: url)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
        return .success(String(localized: "YouMindHub was removed from Claude Desktop. Restart Claude Desktop to apply.", table: "MCP"))
    }

    // Same helper, no arguments (extra keys such as "env" are allowed).
    private static func matches(_ server: Any?) -> Bool {
        guard let server = server as? [String: Any] else { return false }
        return server["command"] as? String == helperPath && (server["args"] as? [String] ?? []).isEmpty
    }
}

// Short status line used by Settings and the onboarding guide.
struct ClaudeDesktopStatusText: View {
    var status: ClaudeDesktopMCP.Status

    var body: some View {
        switch status {
        case .notInstalled: Text("Not installed", tableName: "MCP").foregroundStyle(.secondary)
        case .notAdded: Text("Not added", tableName: "MCP").foregroundStyle(.secondary)
        case .added: Text("Added", tableName: "MCP").foregroundStyle(.green)
        case .outdated: Text("Set up for another copy of AppPad", tableName: "MCP").foregroundStyle(.orange)
        case .unreadable: Text("Invalid configuration file", tableName: "MCP").foregroundStyle(.red)
        }
    }
}

// Button state shared by Settings and the onboarding guide.
extension ClaudeDesktopMCP.Status {
    // Not installed stays clickable: the click explains why nothing was added.
    var canAdd: Bool { self != .added }
    var canRemove: Bool { self == .added || self == .outdated || self == .unreadable }
}
