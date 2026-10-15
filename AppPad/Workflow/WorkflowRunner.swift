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
    var declined = false           // the confirmation was answered with Cancel: nothing ran
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

    // Workflow panel entry point (Enter / ⌘N / in-panel shortcut). argument = text after the first space.
    // confirmed: the caller already asked (the panel's own dialog), so no second prompt.
    func start(id: UUID, trigger: RunTrigger, argument: String = "", confirmed: Bool = false) {
        guard let workflow = WorkflowStore.shared.workflow(id: id), workflow.enabled else {
            NSSound.beep()
            return
        }
        Task { await run(workflow, trigger: trigger, argument: argument, confirmed: confirmed) }
    }

    func cancel(id: UUID) {
        tasks[id]?.cancel()
    }

    // nil when it did not run (already running). Declined confirmation → cancelled result, not recorded.
    @discardableResult
    func run(_ workflow: Workflow, trigger: RunTrigger, argument: String = "",
             confirmed: Bool = false) async -> WorkflowRunResult? {
        guard !running.contains(workflow.id) else {
            NSSound.beep()
            return nil
        }
        // Every trigger (Settings, MCP…) asks unless the caller already did.
        if workflow.requiresConfirmation, !confirmed, !RunConfirmPrompt.ask(workflow: workflow) {
            var result = WorkflowRunResult(workflowID: workflow.id, workflowName: workflow.displayName,
                                           startedAt: Date(), finishedAt: Date())
            result.cancelled = true
            result.declined = true
            return result
        }
        running.insert(workflow.id)
        let task = Task { await self.execute(workflow, trigger: trigger, argument: argument) }
        tasks[workflow.id] = task
        let result = await task.value
        tasks[workflow.id] = nil
        running.remove(workflow.id)
        return result
    }

    // MARK: - Run

    private func execute(_ workflow: Workflow, trigger: RunTrigger, argument: String) async -> WorkflowRunResult? {
        var result = WorkflowRunResult(workflowID: workflow.id, workflowName: workflow.displayName,
                                       startedAt: Date(), finishedAt: Date())
        let errors = workflow.validationErrors
        guard errors.isEmpty else {
            result.message = errors.joined(separator: "\n")
            return finish(result, workflow, trigger)
        }
        // The parsed argument is the first step's input.
        var input = ""
        switch WorkflowArguments.parse(argument, type: workflow.argumentType, mode: workflow.argument) {
        case .success(let parsed):
            input = parsed.value
        case .failure(let error):
            result.message = error.message
            return finish(result, workflow, trigger)
        }
        let allowed = resolvePermissions(workflow, result: &result)
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

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
                stepResult = await runBuiltin(step, index: index, allowed: allowed, input: input)
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
        case .builtin: detail = " · " + (step.unsupportedBuiltin ?? step.builtin.title)
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
        // Template: "timer\n{{input}}" → two lines; empty template = the step input as is.
        let payload = step.shortcutInput.isEmpty ? input : step.shortcutInput
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: WorkflowPlaceholders.input, with: input)
        if !payload.isEmpty {
            let inputFile = tempDir.appendingPathComponent("shortcut-input-\(index + 1).txt")
            try? payload.write(to: inputFile, atomically: true, encoding: .utf8)
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
    private func runBuiltin(_ step: WorkflowStep, index: Int, allowed: [PermissionItem], input: String) async -> StepResult {
        if let raw = step.unsupportedBuiltin {
            return failure(step, index, String(localized: "“\(raw)” needs a newer version of AppPad."))
        }
        let item = PermissionItem(kind: .builtin, value: step.builtin.rawValue)
        guard allowed.contains(item) else { return denied(step, index, item) }
        switch step.builtin {
        case .emptyTrash:
            // Needs Automation permission for Finder (macOS asks once).
            // Finder answers an empty Trash with error -128, so check first.
            let out = await ProcessRunner.run("/usr/bin/osascript", ["-e", Self.emptyTrashScript], timeout: step.timeout)
            var r = makeResult(step, index, from: out)
            if r.success {
                r.output = r.output == "empty"
                    ? String(localized: "The Trash is already empty.")
                    : String(localized: "Trash emptied.")
            }
            return r
        case .sleepDisplays:
            return makeResult(step, index, from: await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 10))
        case .sleepMac:
            return makeResult(step, index, from: await ProcessRunner.run("/usr/bin/pmset", ["sleepnow"], timeout: 10))
        case .keepAwake:
            return await keepAwake(step, index, seconds: Int(input) ?? 0)
        case .toggleDarkMode:
            let out = await ProcessRunner.run("/usr/bin/osascript", ["-e", Self.darkModeScript], timeout: step.timeout)
            var r = makeResult(step, index, from: out)
            if r.success {
                r.output = r.output == "dark" ? String(localized: "Dark appearance") : String(localized: "Light appearance")
            }
            return r
        case .setVolume:
            // Out-of-range values are clamped (older copies may still pass "150" as a plain number).
            guard let raw = Double(input.trimmingCharacters(in: .whitespaces)), raw.isFinite else {
                return failure(step, index, String(localized: "Enter a volume from 0 to 100."))
            }
            let level = Int(min(max(raw, 0), 100).rounded())
            return await setVolume(step, index, level: level)
        case .toggleMute:
            return await toggleMute(step, index)
        case .ejectDisks:
            return await ejectDisks(step, index)
        case .toggleHiddenFiles:
            return await toggleHiddenFiles(step, index)
        case .quitApp:
            return quitApp(step, index, name: input)
        case .quitAllApps:
            return quitAllApps(step, index)
        case .openURL:
            return openURL(step, index, input: input)
        case .copyIPAddress:
            return await copyIPAddress(step, index)
        case .generateUUID:
            var r = StepResult(title: stepTitle(step, index))
            r.success = true
            r.output = UUID().uuidString
            return r
        case .shutDown, .restart:
            // The system's own dialog (Enter confirms, Esc cancels, auto after 60 s): a mistyped
            // panel search never powers off the Mac directly.
            let event = step.builtin == .shutDown ? "«event aevtrsdn»" : "«event aevtrrst»"
            let out = await ProcessRunner.run("/usr/bin/osascript", ["-e", "tell application \"loginwindow\" to \(event)"],
                                              timeout: 20)
            return makeResult(step, index, from: out)
        case .createReminder:
            return await createReminder(step, index, input: input)
        }
    }

    // Reminders via JXA (like Alfred): JSON from the reminder argument, or plain text parsed here.
    private func createReminder(_ step: WorkflowStep, _ index: Int, input: String) async -> StepResult {
        guard let request = ReminderRequest.decode(input) ?? ReminderParser.parse(input), let json = request.json else {
            return failure(step, index, String(localized: "Add the reminder text."))
        }
        let out = await ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.reminderScript, json],
                                          timeout: step.timeout)
        var r = makeResult(step, index, from: out)
        if r.success, r.output == "nolist" {
            r.success = false
            r.message = String(localized: "No Reminders list named “\(request.list)”.")
        } else if r.success {
            r.output = String(localized: "Reminder added: \(request.summary)")
        }
        return r
    }

    private func failure(_ step: WorkflowStep, _ index: Int, _ message: String) -> StepResult {
        var r = StepResult(title: stepTitle(step, index))
        r.message = message
        return r
    }

    private func success(_ step: WorkflowStep, _ index: Int, _ output: String) -> StepResult {
        var r = StepResult(title: stepTitle(step, index))
        r.success = true
        r.output = output
        return r
    }

    // caffeinate -di; seconds 0 = until cancelled (Stop in the panel or Settings).
    private func keepAwake(_ step: WorkflowStep, _ index: Int, seconds: Int) async -> StepResult {
        var arguments = ["-di"]
        if seconds > 0 { arguments += ["-t", String(seconds)] }
        let limit: TimeInterval = seconds > 0 ? TimeInterval(seconds) + 10 : 7 * 86_400
        let out = await ProcessRunner.run("/usr/bin/caffeinate", arguments, timeout: limit)
        var r = makeResult(step, index, from: out)
        if r.success { r.output = String(localized: "Keep Awake ended.") }
        return r
    }

    // External disks and disk images; network volumes are unmounted.
    private func ejectDisks(_ step: WorkflowStep, _ index: Int) async -> StepResult {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        let targets = volumes.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsRootFileSystem != true else { return false }
            return values.volumeIsEjectable == true || values.volumeIsInternal == false
        }
        guard !targets.isEmpty else { return success(step, index, String(localized: "No disks to eject.")) }
        var failed: [String] = []
        for url in targets {
            var out = await ProcessRunner.run("/usr/sbin/diskutil", ["eject", url.path], timeout: 60)
            if !out.succeeded {
                out = await ProcessRunner.run("/usr/sbin/diskutil", ["unmount", url.path], timeout: 60)
            }
            if !out.succeeded { failed.append(url.lastPathComponent) }
        }
        if failed.isEmpty {
            return success(step, index, String(localized: "Ejected \(targets.count) disk(s)."))
        }
        return failure(step, index, String(localized: "Could not eject: \(failed.joined(separator: ", "))"))
    }

    private func toggleHiddenFiles(_ step: WorkflowStep, _ index: Int) async -> StepResult {
        let read = await ProcessRunner.run("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"], timeout: 10)
        let current = ["1", "yes", "true"].contains(read.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let write = await ProcessRunner.run("/usr/bin/defaults",
                                            ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", current ? "false" : "true"],
                                            timeout: 10)
        guard write.succeeded else { return makeResult(step, index, from: write) }
        _ = await ProcessRunner.run("/usr/bin/killall", ["Finder"], timeout: 10)
        return success(step, index, current ? String(localized: "Hidden files are hidden.")
                                            : String(localized: "Hidden files are shown."))
    }

    // Exact name first, then prefix; never AppPad itself. Normal quit (apps may ask to save).
    private func quitApp(_ step: WorkflowStep, _ index: Int, name: String) -> StepResult {
        let query = SearchIndex.normalize(name.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return failure(step, index, String(localized: "Type the app name after a space.")) }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        func normalized(_ app: NSRunningApplication) -> String { SearchIndex.normalize(app.localizedName ?? "") }
        guard let app = apps.first(where: { normalized($0) == query })
                ?? apps.first(where: { normalized($0).hasPrefix(query) }) else {
            return failure(step, index, String(localized: "No running app named “\(name)”."))
        }
        let display = app.localizedName ?? name
        guard app.terminate() else { return failure(step, index, String(localized: "“\(display)” did not quit.")) }
        return success(step, index, String(localized: "Quit \(display)."))
    }

    // Every regular app except AppPad and Finder. Normal quit: apps with unsaved changes still ask.
    private func quitAllApps(_ step: WorkflowStep, _ index: Int) -> StepResult {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let targets = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
                && $0.bundleIdentifier != "com.apple.finder" && !$0.isTerminated
        }
        guard !targets.isEmpty else { return success(step, index, String(localized: "No apps to quit.")) }
        let failed = targets.filter { !$0.terminate() }.map { $0.localizedName ?? $0.bundleIdentifier ?? "?" }
        guard failed.isEmpty else {
            return failure(step, index, String(localized: "Could not quit: \(failed.joined(separator: ", "))"))
        }
        return success(step, index, String(localized: "Quit \(targets.count) app(s)."))
    }

    // {{input}} is percent-encoded (RFC 3986 unreserved characters stay as they are).
    private func openURL(_ step: WorkflowStep, _ index: Int, input: String) -> StepResult {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        let encoded = input.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        let text = step.url.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: WorkflowPlaceholders.input, with: encoded)
        guard let url = URL(string: text), url.scheme != nil else {
            return failure(step, index, String(localized: "Invalid URL"))
        }
        guard NSWorkspace.shared.open(url) else { return failure(step, index, String(localized: "Could not open \(text)")) }
        return success(step, index, text)
    }

    // Copies the LAN address (or the public one when offline from a LAN); output shows both.
    private func copyIPAddress(_ step: WorkflowStep, _ index: Int) async -> StepResult {
        let local = Self.localIPv4()
        var publicIP: String?
        if let url = URL(string: "https://api.ipify.org"),
           let reply = try? await session.data(for: URLRequest(url: url, timeoutInterval: 5)),
           (reply.1 as? HTTPURLResponse)?.statusCode == 200 {
            let text = String(decoding: reply.0.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { publicIP = text }
        }
        guard let copy = local ?? publicIP else { return failure(step, index, String(localized: "No network connection.")) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copy, forType: .string)
        var lines: [String] = []
        if let local { lines.append(String(localized: "Local: \(local)")) }
        if let publicIP { lines.append(String(localized: "Public: \(publicIP)")) }
        return success(step, index, lines.joined(separator: "\n"))
    }

    // First IPv4 address of an active en* interface (Wi-Fi / Ethernet).
    nonisolated private static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING), flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            found.append((String(cString: entry.ifa_name), text))
        }
        return (found.first { $0.name.hasPrefix("en") } ?? found.first)?.address
    }

    // Returns a token; the user-facing text is localized in Swift.
    private static let emptyTrashScript = """
    tell application "Finder"
        if (count of items of trash) is 0 then return "empty"
        empty trash
    end tell
    return "emptied"
    """

    private static let darkModeScript = """
    tell application "System Events"
        tell appearance preferences
            set dark mode to not dark mode
            if dark mode then return "dark"
        end tell
    end tell
    return "light"
    """

    // argv[0] = ReminderRequest JSON. Quits Reminders again if it was not running.
    private static let reminderScript = """
    function run(argv) {
        const data = JSON.parse(argv[0]);
        const app = Application('Reminders');
        const wasRunning = app.running();
        let list = app.defaultList();
        if (data.list) {
            const names = app.lists.name();
            const i = names.findIndex(n => n.toLowerCase() === data.list.toLowerCase());
            if (i < 0) return 'nolist';
            list = app.lists[i];
        }
        const props = { name: data.title };
        if (data.date) props.remindMeDate = new Date(data.date);
        if (data.priority) props.priority = data.priority;
        list.reminders.push(app.Reminder(props));
        if (!wasRunning) app.quit();
        return 'ok';
    }
    """

    // MARK: - Volume / mute

    // AppleScript `set volume` changes the level silently; only volume keys show the system HUD.
    // So we start one key step away from the target, press the key (HUD appears), then pin the exact level.
    private func setVolume(_ step: WorkflowStep, _ index: Int, level: Int) async -> StepResult {
        let exact = "set volume output volume \(level)"
        guard MediaKeys.canPost() else {
            var r = makeResult(step, index, from: await ProcessRunner.run("/usr/bin/osascript", ["-e", exact], timeout: 10))
            if r.success { r.output = String(localized: "Volume \(level)%") }
            return r
        }
        // One key = 1/16 (6.25). Below 7 there is no room under the target, so come down from above.
        let up = level >= 7
        let start = up ? level - 6 : level + 6
        let prep = await ProcessRunner.run("/usr/bin/osascript", ["-e", "set volume output volume \(start)"], timeout: 10)
        var r = makeResult(step, index, from: prep)
        guard r.success else { return r }
        MediaKeys.press(up ? .soundUp : .soundDown)      // also unmutes, like the hardware key
        try? await Task.sleep(for: .milliseconds(150))
        r = makeResult(step, index, from: await ProcessRunner.run("/usr/bin/osascript", ["-e", exact], timeout: 10))
        if r.success { r.output = String(localized: "Volume \(level)%") }
        return r
    }

    // Mute key when allowed (system HUD), otherwise the silent AppleScript toggle.
    private func toggleMute(_ step: WorkflowStep, _ index: Int) async -> StepResult {
        guard MediaKeys.canPost() else {
            var r = makeResult(step, index, from: await ProcessRunner.run("/usr/bin/osascript", ["-e", Self.muteScript], timeout: 10))
            if r.success { r.output = r.output == "muted" ? String(localized: "Sound muted") : String(localized: "Sound on") }
            return r
        }
        MediaKeys.press(.mute)
        try? await Task.sleep(for: .milliseconds(150))
        let out = await ProcessRunner.run("/usr/bin/osascript", ["-e", "output muted of (get volume settings)"], timeout: 10)
        var r = makeResult(step, index, from: out)
        if r.success { r.output = r.output == "true" ? String(localized: "Sound muted") : String(localized: "Sound on") }
        return r
    }

    private static let muteScript = """
    set wasMuted to output muted of (get volume settings)
    set volume output muted (not wasMuted)
    if wasMuted then return "unmuted"
    return "muted"
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
            notifier.post(title: String(localized: "“\(workflow.displayName)” failed"), body: body)
            return
        }
        let output = result.finalOutput
        if workflow.copyOutput, !output.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
        }
        switch workflow.successNotice {
        case .output:
            notifier.post(title: workflow.displayName, body: output.isEmpty ? String(localized: "Done") : output)
        case .custom:
            let body = Self.fill(workflow.successMessage, placeholder: "{{output}}", with: output,
                                 fallback: String(localized: "Done"))
            notifier.post(title: workflow.displayName, body: body)
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

// MARK: - Confirmation

// Asked before a workflow marked "Ask before running" starts (runs outside the Workflow panel).
// Cancel is the safe answer: Esc and closing the alert both decline.
enum RunConfirmPrompt {
    static func ask(workflow: Workflow) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Run “\(workflow.displayName)”?")
        alert.informativeText = workflow.confirmationMessage
        alert.icon = WorkflowIcon.image(for: workflow)
        let run = alert.addButton(withTitle: String(localized: "Run"))
        run.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
        cancel.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension Workflow {
    // Body of the confirmation dialog: the description, or a generic line.
    var confirmationMessage: String {
        let summary = displaySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? String(localized: "This workflow asks before it runs.") : summary
    }
}

// MARK: - Media keys

// Posts the same system-defined events as the keyboard's volume / mute keys, so macOS shows its own HUD.
// Needs the Accessibility (post events) permission AppPad already uses for pasting. Main actor (AppKit events).
private enum MediaKeys {
    enum Key: Int {
        case soundUp = 0      // NX_KEYTYPE_SOUND_UP
        case soundDown = 1    // NX_KEYTYPE_SOUND_DOWN
        case mute = 7         // NX_KEYTYPE_MUTE
    }

    // Asks once (system prompt) when not granted; callers fall back to AppleScript.
    static func canPost() -> Bool {
        if CGPreflightPostEventAccess() { return true }
        _ = CGRequestPostEventAccess()
        return false
    }

    static func press(_ key: Key) {
        post(key, down: true)
        post(key, down: false)
    }

    private static func post(_ key: Key, down: Bool) {
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                       modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       subtype: 8, data1: (key.rawValue << 16) | (state << 8), data2: -1)
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
