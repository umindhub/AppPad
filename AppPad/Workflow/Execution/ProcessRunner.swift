import Foundation

nonisolated struct ProcessOutput: Sendable {
    var exitCode: Int32 = -1
    var stdout = ""
    var stderr = ""
    var timedOut = false
    var cancelled = false
    var launchError: String?

    var succeeded: Bool { launchError == nil && !timedOut && !cancelled && exitCode == 0 }
}

// Runs a child process off the main actor. Everything here is nonisolated:
// Process callbacks arrive on background threads.
nonisolated enum ProcessRunner {
    static let outputLimit = 512 * 1024

    static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        stdin: Data? = nil,
        timeout: TimeInterval
    ) async -> ProcessOutput {
        let state = RunState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProcessOutput, Never>) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment { process.environment = environment }
                if let currentDirectory { process.currentDirectoryURL = currentDirectory }

                let outPipe = Pipe()
                let errPipe = Pipe()
                let inPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = inPipe
                state.prepare(continuation: continuation, process: process,
                              readers: [outPipe.fileHandleForReading, errPipe.fileHandleForReading])

                let out = state.out
                let err = state.err
                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { state.streamClosed(handle) } else { out.append(data) }
                }
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { state.streamClosed(handle) } else { err.append(data) }
                }
                process.terminationHandler = { _ in
                    state.processTerminated()
                    // Background children may keep the pipes open: don't wait for EOF forever.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { state.finish() }
                }

                do {
                    try process.run()
                } catch {
                    state.fail(message: error.localizedDescription)
                    return
                }
                state.launched()

                // Feed stdin on a background queue (a child that never reads must not block us).
                DispatchQueue.global().async {
                    if let stdin, !stdin.isEmpty {
                        try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
                    }
                    try? inPipe.fileHandleForWriting.close()
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + max(1, timeout)) {
                    state.stop(.timeout)
                }
            }
        } onCancel: {
            state.stop(.cancel)
        }
    }

    // SIGTERM to the direct children and the process, SIGKILL if still alive after 2 s.
    fileprivate static func terminateTree(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-TERM", "-P", String(pid)]
        try? pkill.run()
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

// Thread-safe capped byte buffer.
nonisolated private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int
    private var truncated = false

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let room = limit - data.count
        guard room > 0 else { truncated = true; return }
        data.append(chunk.prefix(room))
        if chunk.count > room { truncated = true }
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        let text = String(decoding: data, as: UTF8.self)
        return truncated ? text + "\n" + String(localized: "… (output truncated)", table: "WorkflowPermissions") : text
    }
}

// Shared by the callbacks: resumes the continuation exactly once.
nonisolated private final class RunState: @unchecked Sendable {
    enum StopReason { case timeout, cancel }

    let out = OutputBuffer(limit: ProcessRunner.outputLimit)
    let err = OutputBuffer(limit: ProcessRunner.outputLimit)

    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessOutput, Never>?
    private var process: Process?
    private var readers: [FileHandle] = []
    private var openStreams = 2
    private var isLaunched = false
    private var terminated = false
    private var reason: StopReason?
    private var pendingStop: StopReason?
    private var resumed = false

    func prepare(continuation: CheckedContinuation<ProcessOutput, Never>, process: Process, readers: [FileHandle]) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
        self.process = process
        self.readers = readers
    }

    func launched() {
        lock.lock()
        isLaunched = true
        let pending = pendingStop
        lock.unlock()
        if let pending { stop(pending) }
    }

    func streamClosed(_ handle: FileHandle) {
        handle.readabilityHandler = nil
        lock.lock()
        openStreams -= 1
        let done = openStreams <= 0 && terminated
        lock.unlock()
        if done { finish() }
    }

    func processTerminated() {
        lock.lock()
        terminated = true
        let done = openStreams <= 0
        lock.unlock()
        if done { finish() }
    }

    func stop(_ newReason: StopReason) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        guard isLaunched, let process else {
            pendingStop = newReason   // cancelled before launch finished
            lock.unlock()
            return
        }
        if reason == nil { reason = newReason }
        lock.unlock()
        ProcessRunner.terminateTree(process)
    }

    func finish() {
        lock.lock()
        guard !resumed, let continuation, let process, terminated else { lock.unlock(); return }
        resumed = true
        self.continuation = nil
        let reason = self.reason
        let readers = self.readers
        lock.unlock()
        readers.forEach { $0.readabilityHandler = nil }
        var output = ProcessOutput()
        output.exitCode = process.terminationStatus
        output.stdout = out.string
        output.stderr = err.string
        output.timedOut = reason == .timeout
        output.cancelled = reason == .cancel
        continuation.resume(returning: output)
    }

    func fail(message: String) {
        lock.lock()
        guard !resumed, let continuation else { lock.unlock(); return }
        resumed = true
        self.continuation = nil
        let readers = self.readers
        lock.unlock()
        readers.forEach { $0.readabilityHandler = nil }
        var output = ProcessOutput()
        output.launchError = message
        continuation.resume(returning: output)
    }
}
