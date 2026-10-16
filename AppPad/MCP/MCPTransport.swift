import Foundation

// Plain POSIX sockets (NWListener never delivers AF_UNIX connections; see YouMindHub's MCPHost).
// Both classes are nonisolated: their handlers run on background queues and hop to the main
// actor through DispatchQueue.main (FIFO, so message order is kept).

// MARK: - Listener

nonisolated final class MCPListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.youmindhub.apppad.mcp.accept")
    private var source: DispatchSourceRead?
    private var path = ""

    // Binds and listens; false when the socket could not be set up.
    func start(path: String, onAccept: @escaping @Sendable @MainActor (Int32) -> Void) -> Bool {
        guard source == nil else { return true }
        guard MCPPaths.fitsSocketAddress(path) else {
            NSLog("[MCP] socket path too long: \(path)")
            return false
        }
        unlink(path)   // stale file from a crash makes bind() fail with EADDRINUSE
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var addr = sockaddr_un()
        guard MCPPaths.makeAddress(path, into: &addr) else { Darwin.close(fd); return false }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else {
            NSLog("[MCP] bind() failed: \(String(cString: strerror(errno)))")
            Darwin.close(fd)
            return false
        }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else {
            Darwin.close(fd)
            unlink(path)
            return false
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    break   // EWOULDBLOCK: drained
                }
                var one: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                DispatchQueue.main.async { MainActor.assumeIsolated { onAccept(client) } }
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.source = source
        self.path = path
        NSLog("[MCP] listening on \(path)")
        return true
    }

    func stop() {
        source?.cancel()   // cancel handler closes the fd
        source = nil
        if !path.isEmpty { unlink(path) }
        path = ""
    }
}

// MARK: - Connection

// One accepted proxy connection: newline-delimited JSON-RPC in both directions.
nonisolated final class MCPConnection: @unchecked Sendable {
    private let fd: Int32
    private let queue = DispatchQueue(label: "com.youmindhub.apppad.mcp.io")
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var closed = false   // queue only
    private var onClose: (@Sendable @MainActor () -> Void)?

    init(fd: Int32) {
        self.fd = fd
    }

    func start(onLine: @escaping @Sendable @MainActor (Data) -> Void,
               onClose: @escaping @Sendable @MainActor () -> Void) {
        let fd = self.fd
        self.onClose = onClose
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, !self.closed else { return }
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            var eof = false
            drain: while true {
                let n = read(fd, &chunk, chunk.count)
                if n > 0 {
                    self.buffer.append(chunk, count: n)
                    continue
                }
                if n == 0 { eof = true; break }
                switch errno {
                case EINTR: continue
                case EAGAIN, EWOULDBLOCK: break drain
                default: eof = true; break drain
                }
            }
            while let nl = self.buffer.firstIndex(of: 0x0A) {
                let line = Data(self.buffer[self.buffer.startIndex..<nl])
                self.buffer.removeSubrange(self.buffer.startIndex...nl)
                if !line.isEmpty {
                    DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
                }
            }
            if eof { self.closeOnQueue() }
        }
        source.setCancelHandler { Darwin.close(fd) }   // only place the fd is closed
        self.source = source
        source.resume()
    }

    // Writes one frame; waits for room when the socket buffer is full (large results).
    func send(_ data: Data) {
        queue.async { [self] in
            guard !closed else { return }
            var framed = data
            framed.append(0x0A)
            let ok: Bool = framed.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return true }
                var offset = 0
                while offset < raw.count {
                    let n = write(fd, base + offset, raw.count - offset)
                    if n > 0 { offset += n; continue }
                    switch errno {
                    case EINTR:
                        continue
                    case EAGAIN, EWOULDBLOCK:
                        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        _ = poll(&pfd, 1, 1_000)
                    default:
                        return false
                    }
                }
                return true
            }
            if !ok { closeOnQueue() }
        }
    }

    func close() {
        queue.async { [self] in closeOnQueue() }
    }

    // Peer EOF, write failure or close(): reported to the main actor once.
    private func closeOnQueue() {
        guard !closed else { return }
        closed = true
        shutdown(fd, SHUT_RDWR)
        source?.cancel()
        source = nil
        if let onClose {
            self.onClose = nil
            DispatchQueue.main.async { MainActor.assumeIsolated { onClose() } }
        }
    }
}
