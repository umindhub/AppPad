import AppKit

// `AppPad --mcp`: thin stdio proxy for MCP clients (Claude Desktop, Claude Code, Cursor…).
//
//   client stdin  ──►  proxy  ──►  Unix socket  ──►  AppPad.app (MCPHost)
//   client stdout ◄──  proxy  ◄──  Unix socket  ◄──  AppPad.app
//
// Same binary as the app, so the environment (bundle id, socket path) always matches.
// Never starts NSApplication. stdout carries JSON-RPC frames only; diagnostics go to stderr.
//
// Clients spawn the proxy once per session, so it survives AppPad restarts: on socket EOF
// it fails in-flight requests and goes idle; the next request reconnects (launching AppPad
// if needed) and replays the cached initialize handshake.
nonisolated enum MCPProxy {
    static func run() -> Never {
        // write() to a dead socket must return EPIPE, not kill the proxy.
        signal(SIGPIPE, SIG_IGN)
        let relay = MCPRelay()
        // stdin on its own thread; the relay serializes everything else on its queue.
        let reader = Thread {
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            readLoop: while true {
                let n = read(0, &chunk, chunk.count)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break readLoop }
                buffer.append(chunk, count: n)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<nl])
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if !line.isEmpty { relay.stdinLine(line) }
                }
            }
            relay.stdinEOF()
        }
        reader.start()
        // exit() comes from the relay (stdin closed + socket drained, or stdout gone).
        dispatchMain()
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data(("[apppad-mcp] " + message + "\n").utf8))
    }
}

// MARK: - App probes

nonisolated private enum HostProbe {
    static func connect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        guard MCPPaths.makeAddress(path, into: &addr) else { close(fd); return nil }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) }
        }
        if result == 0 { return fd }
        close(fd)
        return nil
    }

    // Beacon lock held = app running. Kernel-accurate, no stale state.
    static func appIsRunning() -> Bool {
        let fd = open(MCPPaths.beaconPath, O_RDONLY)
        if fd >= 0 {
            defer { close(fd) }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                flock(fd, LOCK_UN)
                return false
            }
            if errno == EWOULDBLOCK { return true }
        }
        // No beacon yet (first launch): ask LaunchServices, ignoring this proxy process.
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: MCPPaths.bundleID)
            .contains { $0.processIdentifier != own && !$0.isTerminated }
    }

    // Launch the app this proxy lives in, in the background.
    static func launchApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.arguments = [MCPPaths.launchArgument]
        MCPProxy.log("launching \(Bundle.main.bundlePath)…")
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            if let error { MCPProxy.log("launch failed: \(error.localizedDescription)") }
        }
    }
}

// MARK: - JSON-RPC line inspection

// Only method, id and request/response kind are needed; unparsable lines pass through untracked.
nonisolated private struct RPCLine {
    let object: [String: Any]?

    init(_ raw: Data) {
        object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
    }

    var method: String? { object?["method"] as? String }
    var id: Any? {
        guard let value = object?["id"], !(value is NSNull) else { return nil }
        return value
    }
    var idKey: String? { RPCLine.key(for: id) }
    var isRequest: Bool { method != nil && idKey != nil }
    var isResponse: Bool { method == nil && idKey != nil }

    static func key(for id: Any?) -> String? {
        switch id {
        case let n as NSNumber: return "n:\(n)"
        case let s as String: return "s:\(s)"
        default: return nil
        }
    }
}

// MARK: - Relay

// Single-writer state machine: every mutation runs on `queue`. stdin lines arrive via
// queue.sync (backpressure on the client), socket lines via queue.async (FIFO).
nonisolated private final class MCPRelay: @unchecked Sendable {
    private enum State { case disconnected, handshaking, ready }

    private let queue = DispatchQueue(label: "com.youmindhub.apppad.mcp.relay")
    private var state: State = .disconnected
    private var socketFD: Int32 = -1
    private var connID = 0                    // bumped on (re)connect and teardown; stale events are ignored

    private var cachedInitialize: Data?
    private var cachedInitialized: Data?
    private var initializeIDKey: String?
    private var sessionEstablished = false    // client has its initialize response → replay on reconnect

    private var pending: [String: Any] = [:]  // idKey → original id, for synthesized errors
    private var outbox: [Data] = []           // parked while disconnected / handshaking
    private var stdinClosed = false

    private let connectTimeout: TimeInterval = 15
    private let handshakeTimeout: TimeInterval = 10
    private let mcpOffGrace: TimeInterval = 2      // running, no socket: maybe mid-restart of the listener
    private let launchGrace: TimeInterval = 6      // launched, running, still no socket → MCP is off

    private let reinitID = "__apppad_reinit__"
    private var reinitKey: String { "s:\(reinitID)" }

    private var offMessage: String {
        "\(MCPPaths.appName) is running, but AI assistant access is turned off. "
            + "Turn it on in AppPad Settings › AI Assistants (MCP), then retry."
    }

    // MARK: Entry points (stdin thread)

    func stdinLine(_ line: Data) {
        queue.sync { handleStdinLine(line) }
    }

    func stdinEOF() {
        queue.sync {
            stdinClosed = true
            if state == .disconnected { exit(0) }
            shutdown(socketFD, SHUT_WR)   // keep draining socket → stdout until the app closes
        }
    }

    // MARK: stdin → socket

    private func handleStdinLine(_ line: Data) {
        let msg = RPCLine(line)
        switch msg.method {
        case "initialize":
            cachedInitialize = line
            initializeIDKey = msg.idKey
        case "notifications/initialized":
            cachedInitialized = line
        default:
            break
        }
        if msg.isRequest, let key = msg.idKey { pending[key] = msg.id }

        switch state {
        case .ready:
            if !writeAll(socketFD, line) { socketBroken() }
        case .handshaking:
            outbox.append(line)
        case .disconnected:
            outbox.append(line)
            connectNow()
        }
    }

    // MARK: socket → stdout

    private func handleSocketLine(_ line: Data, connID id: Int) {
        guard id == connID else { return }
        let msg = RPCLine(line)
        if state == .handshaking, msg.idKey == reinitKey {
            // Answer to the replayed initialize: the client already has the real one.
            if let inited = cachedInitialized, !writeAll(socketFD, inited) {
                socketBroken()
                return
            }
            state = .ready
            flushOutbox()
            return
        }
        if msg.isResponse, let key = msg.idKey {
            pending.removeValue(forKey: key)
            if key == initializeIDKey { sessionEstablished = true }
        }
        writeStdout(line)
    }

    // MARK: Connect

    // Blocks the relay queue on purpose (backpressure); no reader thread exists while disconnected.
    private func connectNow() {
        guard state == .disconnected else { return }
        MCPPaths.ensureDirectory()
        let path = MCPPaths.socketPath
        guard MCPPaths.fitsSocketAddress(path) else {
            failEverything("socket path too long: \(path)")
            return
        }

        var fd = HostProbe.connect(path)
        if fd == nil, HostProbe.appIsRunning() {
            // Running without a socket: MCP is off (or the listener is restarting).
            let deadline = Date().addingTimeInterval(mcpOffGrace)
            while fd == nil && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
                fd = HostProbe.connect(path)
            }
            if fd == nil {
                failEverything(offMessage)
                return
            }
        } else if fd == nil {
            HostProbe.launchApp()
            let deadline = Date().addingTimeInterval(connectTimeout)
            var runningSince: Date?
            while fd == nil && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
                fd = HostProbe.connect(path)
                if fd != nil { break }
                if HostProbe.appIsRunning() {
                    if let since = runningSince {
                        if Date().timeIntervalSince(since) > launchGrace { break }
                    } else {
                        runningSince = Date()
                    }
                }
            }
            if fd == nil {
                failEverything(HostProbe.appIsRunning()
                    ? offMessage
                    : "Could not launch \(MCPPaths.appName). Check that it is installed, then retry.")
                return
            }
        }
        guard let connected = fd else { return }

        var one: Int32 = 1
        setsockopt(connected, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        socketFD = connected
        connID += 1
        startReader(fd: connected, connID: connID)
        MCPProxy.log("connected: \(path)")

        if sessionEstablished, let initLine = cachedInitialize, let replay = rewriteID(of: initLine, to: reinitID) {
            // Fresh app-side session: replay the client's initialize under a sentinel id.
            guard writeAll(socketFD, replay) else { socketBroken(); return }
            state = .handshaking
            scheduleHandshakeTimeout(connID: connID)
        } else {
            // First connection: the real initialize is in the outbox.
            state = .ready
            flushOutbox()
        }
    }

    private func scheduleHandshakeTimeout(connID id: Int) {
        queue.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
            guard let self, self.state == .handshaking, self.connID == id else { return }
            MCPProxy.log("handshake replay timed out")
            self.socketBroken()
        }
    }

    // Per-connection blocking reader; owns closing its fd, then reports EOF tagged with connID.
    private func startReader(fd: Int32, connID id: Int) {
        let thread = Thread { [weak self] in
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            readLoop: while true {
                let n = read(fd, &chunk, chunk.count)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break readLoop }
                buffer.append(chunk, count: n)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<nl])
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if !line.isEmpty, let self {
                        self.queue.async { self.handleSocketLine(line, connID: id) }
                    }
                }
            }
            close(fd)
            self?.queue.async { self?.handleSocketClosed(connID: id) }
        }
        thread.name = "com.youmindhub.apppad.mcp.reader.\(id)"
        thread.start()
    }

    // MARK: Teardown

    // App closed its side (quit, MCP turned off). The reader already closed the fd.
    private func handleSocketClosed(connID id: Int) {
        guard id == connID, state != .disconnected else { return }
        connID += 1
        socketFD = -1
        state = .disconnected
        MCPProxy.log("AppPad closed the connection")
        if stdinClosed { exit(0) }
        failEverything("\(MCPPaths.appName) quit or turned off AI assistant access. "
            + "The connection restores automatically on the next request.")
    }

    // Local write failure or handshake timeout.
    private func socketBroken() {
        guard state != .disconnected else { return }
        shutdown(socketFD, SHUT_RDWR)   // wakes the reader, which closes the fd
        connID += 1
        socketFD = -1
        state = .disconnected
        MCPProxy.log("connection to AppPad broke")
        if stdinClosed { exit(0) }
        failEverything("Connection to \(MCPPaths.appName) broke. Retry; it reconnects automatically.")
    }

    // Every unanswered request gets a JSON-RPC error so the client never hangs.
    private func failEverything(_ message: String) {
        MCPProxy.log(message)
        for (_, idValue) in pending {
            let response: [String: Any] = [
                "jsonrpc": "2.0",
                "id": idValue,
                "error": ["code": -32000, "message": message],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: response) { writeStdout(data) }
        }
        pending.removeAll()
        outbox.removeAll()
    }

    // MARK: Plumbing

    private func flushOutbox() {
        let lines = outbox
        outbox.removeAll()
        for line in lines {
            if !writeAll(socketFD, line) {
                socketBroken()
                return
            }
        }
    }

    private func rewriteID(of line: Data, to newID: String) -> Data? {
        guard var obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        obj["id"] = newID
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    private func writeStdout(_ line: Data) {
        if !writeAll(1, line) {
            MCPProxy.log("stdout closed, exiting")
            exit(1)
        }
    }

    // Blocking write of line + "\n" (blocking on purpose: backpressure to the client).
    private func writeAll(_ fd: Int32, _ line: Data) -> Bool {
        guard fd >= 0 else { return false }
        var framed = line
        framed.append(0x0A)
        return framed.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n > 0 { offset += n; continue }
                if errno == EINTR { continue }
                return false
            }
            return true
        }
    }
}
