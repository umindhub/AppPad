import Foundation
import Combine

// AppPad is the MCP server; `AppPad --mcp` (MCPProxy) relays a client's stdio to the socket.
// On by default; toggle in Settings › AI Assistants (MCP). Same-user only (0700 dir, 0600 socket).
final class MCPHost: ObservableObject {
    static let shared = MCPHost()

    private static let enabledKey = "mcpEnabled"
    private static let confirmAppChangesKey = "mcpConfirmAppChanges"

    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { start() } else { stop() }
        }
    }
    // AI app installs / uninstalls (Homebrew) ask first; on by default.
    @Published var confirmAppChanges: Bool {
        didSet { UserDefaults.standard.set(confirmAppChanges, forKey: Self.confirmAppChangesKey) }
    }
    @Published private(set) var isListening = false
    @Published private(set) var clientCount = 0

    // Frecency hook (set by AppDelegate): an AI run counts like a panel run.
    var recordUse: ((String) -> Void)?

    private let listener = MCPListener()
    private var sessions: [UUID: MCPSession] = [:]
    private var beaconFD: Int32 = -1

    private init() {
        // Never toggled (no stored value) = on.
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        confirmAppChanges = UserDefaults.standard.object(forKey: Self.confirmAppChangesKey) as? Bool ?? true
    }

    // App launch: hold the beacon for the whole process, listen when enabled.
    func launch() {
        MCPPaths.ensureDirectory()
        acquireBeacon()
        if enabled { start() }
    }

    // App termination: unlink the socket so proxies fail fast instead of hanging.
    func shutdown() {
        stop()
    }

    private func start() {
        guard !isListening else { return }
        MCPPaths.ensureDirectory()
        isListening = listener.start(path: MCPPaths.socketPath) { fd in
            MCPHost.shared.accept(fd)
        }
    }

    private func stop() {
        listener.stop()
        for session in sessions.values { session.close() }
        sessions.removeAll()
        clientCount = 0
        isListening = false
    }

    private func accept(_ fd: Int32) {
        guard isListening else {
            Darwin.close(fd)   // turned off between accept and here
            return
        }
        let id = UUID()
        let session = MCPSession(fd: fd) { [weak self] in
            self?.sessions.removeValue(forKey: id)
            self?.clientCount = self?.sessions.count ?? 0
        }
        sessions[id] = session
        clientCount = sessions.count
        session.begin()
    }

    // flock held until exit; the proxy uses it to tell "not running" from "MCP off".
    private func acquireBeacon() {
        guard beaconFD < 0 else { return }
        let fd = open(MCPPaths.beaconPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            beaconFD = fd
        } else {
            Darwin.close(fd)
        }
    }
}

// MARK: - Session

// One proxy connection = one MCP session with its own handshake.
final class MCPSession {
    private let connection: MCPConnection
    private let onClosed: () -> Void
    private var clientName = "AI"   // from initialize, shown in the save review dialog

    init(fd: Int32, onClosed: @escaping () -> Void) {
        connection = MCPConnection(fd: fd)
        self.onClosed = onClosed
    }

    func begin() {
        connection.start(
            onLine: { [weak self] line in self?.receive(line) },
            onClose: { [weak self] in self?.onClosed() }
        )
    }

    func close() {
        connection.close()
    }

    // Requests run concurrently (a long workflow must not block tools/list); replies keep their ids.
    private func receive(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) else {
            reply(MCPRPC.error(id: NSNull(), code: -32700, message: "Parse error"))
            return
        }
        guard let message = object as? [String: Any] else {
            reply(MCPRPC.error(id: NSNull(), code: -32600, message: "Batch requests are not supported"))
            return
        }
        guard let method = message["method"] as? String else { return }   // a response from the client
        let id = message["id"].flatMap { $0 is NSNull ? nil : $0 }
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else { return }   // notifications (initialized, cancelled…) need no answer
        if method == "initialize" { clientName = Self.displayName(params["clientInfo"] as? [String: Any]) }
        let client = clientName
        Task { [weak self] in
            let response = await MCPRPC.handle(method: method, id: id, params: params, client: client)
            self?.reply(response)
        }
    }

    // "claude-ai" → "Claude"; unknown clients keep their own title or name.
    private static func displayName(_ info: [String: Any]?) -> String {
        let name = info?["name"] as? String ?? ""
        switch name.lowercased() {
        case "claude-ai", "claude desktop": return "Claude"
        case "claude-code": return "Claude Code"
        case let n where n.hasPrefix("cursor"): return "Cursor"
        default:
            let title = (info?["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            if !title.isEmpty { return title }
            return name.isEmpty ? "AI" : name
        }
    }

    private func reply(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        connection.send(data)
    }
}

// MARK: - JSON-RPC

enum MCPRPC {
    static let supportedVersions: Set<String> = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
    static let latestVersion = "2025-06-18"

    static func handle(method: String, id: Any, params: [String: Any], client: String) async -> [String: Any] {
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? latestVersion
            let version = supportedVersions.contains(requested) ? requested : latestVersion
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            return result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": MCPPaths.serverName, "title": MCPPaths.appName, "version": appVersion],
                "instructions": MCPTools.instructions,
            ])
        case "ping":
            return result(id: id, [:])
        case "tools/list":
            return result(id: id, ["tools": MCPTools.definitions])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return error(id: id, code: -32602, message: "Missing tool name")
            }
            guard MCPTools.names.contains(name) else {
                return error(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let outcome = await MCPTools.call(name, MCPArguments(arguments), client: client)
            return result(id: id, [
                "content": [["type": "text", "text": outcome.text]],
                "isError": outcome.isError,
            ])
        default:
            return error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
}
