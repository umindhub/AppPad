import AppKit
import Combine

nonisolated enum RunTrigger: Sendable {
    case panel, settings, mcp
}

nonisolated struct StepResult: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var success = false
    var output = ""          // stdout / response body / shortcut output
    var stderr = ""
    var message: String?     // why it failed (denied, timeout, HTTP status…)
    var exitCode: Int32?
    var duration: TimeInterval = 0
}

nonisolated struct WorkflowRunResult: Identifiable, Sendable {
    let id = UUID()
    let workflowID: UUID
    let workflowName: String
    let startedAt: Date
    var finishedAt: Date
    var steps: [StepResult] = []
    var denied: [PermissionItem] = []
    var cancelled = false
    var message: String?           // run-level problem (invalid workflow)
    var sandboxProfile: String?    // last generated profile, for debugging

    var success: Bool { message == nil && !cancelled && !steps.isEmpty && steps.allSatisfy(\.success) }
    var finalOutput: String { steps.last?.output ?? "" }

    var failureSummary: String {
        if let message { return message }
        if cancelled { return String(localized: "Cancelled") }
        guard let failed = steps.first(where: { !$0.success }) else { return "" }
        let detail = failed.message ?? (failed.stderr.isEmpty ? failed.output : failed.stderr)
        return failed.title + (detail.isEmpty ? "" : ": " + detail)
    }
}

// Runs workflows: validation → confirmation → permission prompt → steps (sandboxed scripts) → delivery.
final class WorkflowRunner: ObservableObject {
    static let shared = WorkflowRunner()

    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var lastResults: [UUID: WorkflowRunResult] = [:]

    private var tasks: [UUID: Task<WorkflowRunResult?, Never>] = [:]
    private let session = URLSession(configuration: .ephemeral)

    // Workflow panel entry point (Enter / ⌘N / in-panel shortcut).
    func start(id: UUID, trigger: RunTrigger) {
        guard let workflow = WorkflowStore.shared.workflow(id: id), workflow.enabled else {
            NSSound.beep()
            return
        }
        Task { await run(workflow, trigger: trigger) }
    }

    func cancel(id: UUID) {
        tasks[id]?.cancel()
    }

    // nil when it did not run (already running).
    @discardableResult
    func run(_ workflow: Workflow, trigger: RunTrigger) async -> WorkflowRunResult? {
        guard !running.contains(workflow.id) else {
            NSSound.beep()
            return nil
        }
        running.insert(workflow.id)
        let task = Task { await self.execute(workflow, trigger: trigger) }
        tasks[workflow.id] = task
        let result = await task.value
        tasks[workflow.id] = nil
        running.remove(workflow.id)
        return result
    }

    // MARK: - Run

    private func execute(_ workflow: Workflow, trigger: RunTrigger) async -> WorkflowRunResult? {
        var result = WorkflowRunResult(workflowID: workflow.id, workflowName: workflow.name,
                                       startedAt: Date(), finishedAt: Date())
        let errors = workflow.validationErrors
        guard errors.isEmpty else {
            result.message = errors.joined(separator: "\n")
            return finish(result, workflow, trigger)
        }
        let allowed = resolvePermissions(workflow, result: &result)
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var input = ""
        for (index, step) in workflow.steps.enumerated() {
            if Task.isCancelled {
                result.cancelled = true
                break
            }
            let started = Date()
            var stepResult: StepResult
            switch step.kind {
            case .shell, .appleScript:
                let profile = SeatbeltProfile.make(SandboxGrant(items: allowed.filter(\.isSandboxRule)), tempDir: tempDir)
                result.sandboxProfile = profile
                stepResult = await runScript(step, index: index, profile: profile, input: input,
                                             tempDir: tempDir, workflowName: workflow.name)
            case .shortcut:
                stepResult = await runShortcut(step, index: index, allowed: allowed, input: input, tempDir: tempDir)
            case .http:
                stepResult = await runHTTP(step, index: index, allowed: allowed, input: input)
            case .builtin:
                stepResult = await runBuiltin(step, index: index, allowed: allowed)
            }
            stepResult.duration = Date().timeIntervalSince(started)
            result.steps.append(stepResult)
            if Task.isCancelled { result.cancelled = true }
            guard stepResult.success else { break }
            input = stepResult.output
        }
        result.finishedAt = Date()
        return finish(result, workflow, trigger)
    }

    private func finish(_ result: WorkflowRunResult, _ workflow: Workflow, _ trigger: RunTrigger) -> WorkflowRunResult {
        lastResults[workflow.id] = result
        deliver(result, workflow, trigger: trigger)
        return result
    }

    // Undecided items → one prompt. Returns the items allowed for this run.
    private func resolvePermissions(_ workflow: Workflow, result: inout WorkflowRunResult) -> [PermissionItem] {
        let store = PermissionStore.shared
        let needed = workflow.requiredPermissions
        let undecided = needed.filter { store.decision(for: $0, workflow: workflow.id) == nil }
        var once = Set<PermissionItem>()
        if !undecided.isEmpty {
            switch PermissionPrompt.ask(workflow: workflow, items: undecided) {
            case .allowOnce: once = Set(undecided)
            case .alwaysAllow: store.set(.allow, for: undecided, workflow: workflow.id)
            case .deny: store.set(.deny, for: undecided, workflow: workflow.id)
            }
        }
        let allowed = needed.filter { once.contains($0) || store.decision(for: $0, workflow: workflow.id) == .allow }
        result.denied = needed.filter { !allowed.contains($0) }
        return allowed
    }

    // MARK: - Steps

    private func stepTitle(_ step: WorkflowStep, _ index: Int) -> String {
        let detail: String
        switch step.kind {
        case .shortcut: detail = " “\(step.shortcutName)”"
        case .builtin: detail = " · " + step.builtin.title
        case .http: detail = " · " + step.http.method.rawValue + " " + (step.http.host ?? "")
        default: detail = ""
        }
        return "\(index + 1). " + step.kind.title + detail
    }

    private func denied(_ step: WorkflowStep, _ index: Int, _ item: PermissionItem) -> StepResult {
        var r = StepResult(title: stepTitle(step, index))
        r.message = String(localized: "Not allowed: \(item.title)")
        return r
    }

    private func makeResult(_ step: WorkflowStep, _ index: Int, from out: ProcessOutput) -> StepResult {
        var r = StepResult(title: stepTitle(step, index))
        r.success = out.succeeded
        r.output = Self.trimTrailingNewlines(out.stdout)
        r.stderr = Self.trimTrailingNewlines(out.stderr)
        if let launchError = out.launchError {
            r.message = launchError
        } else {
            r.exitCode = out.exitCode
            if out.timedOut {
                r.message = String(localized: "Timed out after \(Int(step.timeout)) s")
            } else if out.cancelled {
                r.message = String(localized: "Cancelled")
            } else if out.exitCode != 0 {
                r.message = String(localized: "Exit code \(out.exitCode)")
            }
        }
        return r
    }

    // Shell / AppleScript / JXA inside sandbox-exec with the generated profile.
    private func runScript(_ step: WorkflowStep, index: Int, profile: String, input: String,
                           tempDir: URL, workflowName: String) async -> StepResult {
        let env = await ShellEnvironment.scriptEnvironment(tempDir: tempDir, input: input, workflowName: workflowName)
        var arguments = ["-p", profile]
        if step.kind == .shell {
            // -f: no rc files (PATH is injected); input also arrives on stdin.
            arguments += ["/bin/zsh", "-f", "-c", step.script]
        } else {
            let isJS = step.language == .javaScript
            let file = tempDir.appendingPathComponent("step\(index + 1).\(isJS ? "js" : "applescript")")
            do {
                try step.script.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                var r = StepResult(title: stepTitle(step, index))
                r.message = error.localizedDescription
                return r
            }
            arguments.append("/usr/bin/osascript")
            if isJS { arguments += ["-l", "JavaScript"] }
            arguments.append(file.path)
            if !input.isEmpty { arguments.append(input) }   // on run argv / function run(argv)
        }
        let out = await ProcessRunner.run(SeatbeltProfile.sandboxExec, arguments, environment: env,
                                          currentDirectory: tempDir, stdin: Data(input.utf8), timeout: step.timeout)
        return makeResult(step, index, from: out)
    }

    // Shortcuts run in the Shortcuts service; AppPad only gates which one may run.
    private func runShortcut(_ step: WorkflowStep, index: Int, allowed: [PermissionItem],
                             input: String, tempDir: URL) async -> StepResult {
        let item = PermissionItem(kind: .shortcut, value: step.shortcutName)
        guard allowed.contains(item) else { return denied(step, index, item) }
        var arguments = ["run", step.shortcutName]
        if !input.isEmpty {
            let inputFile = tempDir.appendingPathComponent("shortcut-input-\(index + 1).txt")
            try? input.write(to: inputFile, atomically: true, encoding: .utf8)
            arguments += ["--input-path", inputFile.path]
        }
        let outputFile = tempDir.appendingPathComponent("shortcut-output-\(index + 1).txt")
        arguments += ["--output-path", outputFile.path, "--output-type", "public.plain-text"]
        let out = await ProcessRunner.run("/usr/bin/shortcuts", arguments, timeout: step.timeout)
        var r = makeResult(step, index, from: out)
        if let text = try? String(contentsOf: outputFile, encoding: .utf8) {
            r.output = Self.trimTrailingNewlines(text)
        }
        return r
    }

    // In-process HTTP: host and secrets must be granted; redirects may not leave the granted hosts.
    private func runHTTP(_ step: WorkflowStep, index: Int, allowed: [PermissionItem], input: String) async -> StepResult {
        let spec = step.http
        guard let host = spec.host else {
            var r = StepResult(title: stepTitle(step, index))
            r.message = String(localized: "Invalid URL")
            return r
        }
        let hostItem = PermissionItem(kind: .httpHost, value: host)
        guard allowed.contains(hostItem) else { return denied(step, index, hostItem) }
        var secrets: [String: String] = [:]
        for name in spec.referencedSecrets {
            let item = PermissionItem(kind: .secret, value: name)
            guard allowed.contains(item) else { return denied(step, index, item) }
            guard let value = KeychainSecrets.value(name) else {
                var r = StepResult(title: stepTitle(step, index))
                r.message = String(localized: "Secret “\(name)” is not set (Settings › Workflows › Secrets).")
                return r
            }
            secrets[name] = value
        }

        func render(_ text: String, encodeInput: Bool) -> String {
            var out = text
            let inputValue = encodeInput
                ? (input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
                : input
            out = out.replacingOccurrences(of: WorkflowPlaceholders.input, with: inputValue)
            for (name, value) in secrets {
                out = out.replacingOccurrences(of: "{{secret:\(name)}}", with: value)
            }
            return out
        }

        // Re-check the host after substitution ({{input}} must not move the request elsewhere).
        guard let url = URL(string: render(spec.url, encodeInput: true)), url.host?.lowercased() == host else {
            var r = StepResult(title: stepTitle(step, index))
            r.message = String(localized: "Invalid URL")
            return r
        }
        var request = URLRequest(url: url, timeoutInterval: step.timeout)
        request.httpMethod = spec.method.rawValue
        for header in spec.headerPairs {
            request.setValue(render(header.value, encodeInput: false), forHTTPHeaderField: header.name)
        }
        if spec.method != .GET, !spec.body.isEmpty {
            request.httpBody = Data(render(spec.body, encodeInput: false).utf8)
        }

        var r = StepResult(title: stepTitle(step, index))
        let allowedHosts = Set(allowed.filter { $0.kind == .httpHost }.map(\.value))
        do {
            let (data, response) = try await session.data(for: request, delegate: RedirectGuard(allowedHosts: allowedHosts))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(decoding: data.prefix(ProcessRunner.outputLimit), as: UTF8.self)
            r.exitCode = Int32(status)
            r.success = (200..<300).contains(status)
            r.output = body.isEmpty ? "HTTP \(status)" : Self.trimTrailingNewlines(body)
            if !r.success { r.message = "HTTP \(status)" }
        } catch is CancellationError {
            r.message = String(localized: "Cancelled")
        } catch let error as URLError where error.code == .cancelled {
            r.message = String(localized: "Cancelled")
        } catch {
            r.message = error.localizedDescription
        }
        return r
    }

    // AppPad's own trusted actions (not sandboxed, still permission-gated).
    private func runBuiltin(_ step: WorkflowStep, index: Int, allowed: [PermissionItem]) async -> StepResult {
        let item = PermissionItem(kind: .builtin, value: step.builtin.rawValue)
        guard allowed.contains(item) else { return denied(step, index, item) }
        let out: ProcessOutput
        switch step.builtin {
        case .emptyTrash:
            // Needs Automation permission for Finder (macOS asks once).
            // Finder answers an empty Trash with error -128, so check first.
            out = await ProcessRunner.run("/usr/bin/osascript", ["-e", Self.emptyTrashScript], timeout: step.timeout)
        case .sleepDisplays:
            out = await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 10)
        }
        var r = makeResult(step, index, from: out)
        if step.builtin == .emptyTrash, r.success {
            r.output = r.output == "empty"
                ? String(localized: "The Trash is already empty.")
                : String(localized: "Trash emptied.")
        }
        return r
    }

    // Returns a token; the user-facing text is localized in Swift.
    private static let emptyTrashScript = """
    tell application "Finder"
        if (count of items of trash) is 0 then return "empty"
        empty trash
    end tell
    return "emptied"
    """

    // MARK: - Delivery

    private func deliver(_ result: WorkflowRunResult, _ workflow: Workflow, trigger: RunTrigger) {
        // Settings shows the result sheet; MCP returns the result to the caller.
        guard trigger == .panel, !result.cancelled else { return }
        let notifier = WorkflowNotifier.shared
        guard result.success else {
            let error = result.failureSummary
            let body: String
            switch workflow.failureNotice {
            case .error: body = error
            case .custom: body = Self.fill(workflow.failureMessage, placeholder: "{{error}}", with: error, fallback: error)
            }
            notifier.post(title: String(localized: "“\(workflow.name)” failed"), body: body)
            return
        }
        let output = result.finalOutput
        if workflow.copyOutput, !output.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
        }
        switch workflow.successNotice {
        case .output:
            notifier.post(title: workflow.name, body: output.isEmpty ? String(localized: "Done") : output)
        case .custom:
            let body = Self.fill(workflow.successMessage, placeholder: "{{output}}", with: output,
                                 fallback: String(localized: "Done"))
            notifier.post(title: workflow.name, body: body)
        case .none:
            break
        }
    }

    // Custom message with its placeholder replaced; empty message → fallback.
    private static func fill(_ template: String, placeholder: String, with value: String, fallback: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return trimmed.replacingOccurrences(of: placeholder, with: value)
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppPad-Workflow-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private static func trimTrailingNewlines(_ text: String) -> String {
        var s = Substring(text)
        while let last = s.last, last.isNewline { s = s.dropLast() }
        return String(s)
    }
}

// Blocks redirects to hosts that were not granted (and with them any Authorization header).
// Completion-handler form on purpose: the async @objc variant crashes Swift 6.4 SILGen
// (emitNativeToForeignThunk) with NonisolatedNonsendingByDefault.
nonisolated private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    let allowedHosts: Set<String>

    init(allowedHosts: Set<String>) {
        self.allowedHosts = allowedHosts
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        if let host = request.url?.host?.lowercased(), allowedHosts.contains(host) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
