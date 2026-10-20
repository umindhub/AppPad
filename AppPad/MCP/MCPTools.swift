import Foundation

// Tools exposed to AI clients. Workflows are addressed by their reverse-DNS id
// (com.youmindhub.emptytrash); names and keywords are accepted as a fallback.
// Runs go through WorkflowRunner with trigger .mcp: same confirmation and permission prompts
// as the panel, no notifications (the result goes back to the caller).
enum MCPTools {
    static let instructions = """
        AppPad runs the user's own workflows on their Mac: shell scripts, AppleScript, Shortcuts, \
        HTTP requests and built-in actions (empty Trash, set a timer, volume, reminders…).
        Call list_workflows first and use the returned id. A workflow takes at most ONE argument \
        string, exactly what the user would type after the workflow's keyword in AppPad's panel \
        (e.g. "10" or "1h30m" for a timer); see each workflow's argument hint and examples.
        AppPad may show a confirmation or permission dialog on the Mac; if the user declines or \
        denies, report it and do not retry unless asked. Disabled workflows are not available.
        You can also WRITE workflows for the user: call workflow_guide first (it is the only \
        reference for the JSON format), then save_workflows. To change one, export_workflows, \
        edit it, raise its version and save it again. The user approves every save in AppPad.
        AppPad is also the user's Launchpad (app grid with pages and folders). To tidy it up, call \
        get_launchpad_layout (it includes usage scores and guidelines), then apply_launchpad_layout \
        with the complete new arrangement; undo_launchpad_layout restores the previous one.
        AppPad can also install and uninstall regular Mac apps with Homebrew. Call homebrew_status \
        first; if Homebrew is missing, install_homebrew asks the user and opens Terminal. Find apps \
        with search_apps, then install_app with the cask token. Only apps from Homebrew's official \
        cask catalog that install nothing but the app (command-line tools only from inside the app; \
        no installers or scripts) and are notarized by Apple can be installed; formulae and third-party taps are not supported, \
        so do not suggest Terminal commands to get around this. uninstall_app removes an app. \
        The user confirms installs and uninstalls in AppPad.
        """

    static let names: Set<String> = Set(["list_workflows", "get_workflows", "run_workflow",
                                     "get_workflow_result", "stop_workflow",
                                     "workflow_guide", "export_workflows", "save_workflows"])
        .union(MCPLayoutTools.names)
        .union(MCPHomebrewTools.names)

    static var definitions: [[String: Any]] {
        [
            tool("list_workflows",
                 "List the user's enabled AppPad workflows with id, name, description, keywords and argument usage.",
                 ["query": string("Optional filter: matched against id, names, keywords and description.")]),
            tool("get_workflows",
                 "Details for one or more workflows: steps, declared permissions and whether each is already allowed, denied or will be asked.",
                 ["ids": stringArray("Workflow ids (or names / keywords).")], required: ["ids"]),
            tool("run_workflow",
                 """
                 Run one workflow and wait for its result. Returns status success / failed / declined / \
                 cancelled, the output, and per-step details. If it is still running after wait_seconds, \
                 returns status running; use get_workflow_result or stop_workflow afterwards.
                 """,
                 ["id": string("Workflow id (or name / keyword)."),
                  "argument": string("The single argument string, as typed after the keyword in the panel. Omit for workflows without an argument."),
                  "wait_seconds": integer("How long to wait for the result, 1–600. Default 60.")],
                 required: ["id"]),
            tool("get_workflow_result",
                 "Status of a workflow: running, or the result of its last run since AppPad started.",
                 ["id": string("Workflow id (or name / keyword).")], required: ["id"]),
            tool("stop_workflow",
                 "Stop a running workflow (e.g. Keep Awake without a time limit).",
                 ["id": string("Workflow id (or name / keyword).")], required: ["id"]),

            // --- Authoring ---
            tool("workflow_guide",
                 "Return the complete guide for WRITING AppPad workflows: JSON fields, step kinds (shell, AppleScript, Shortcuts, HTTP, built-in actions), argument types, sandbox permissions, validation rules and examples. Call this BEFORE save_workflows.",
                 [:]),
            tool("export_workflows",
                 "Return installed workflows as workflow JSON (the save_workflows format), including scripts. Use it to edit an existing workflow or to learn from one.",
                 ["ids": stringArray("Workflow ids (or names / keywords).")], required: ["ids"]),
            tool("save_workflows",
                 """
                 Add or replace workflows. Each entry is one workflow JSON object as described by \
                 workflow_guide (call it first). The same id replaces the installed workflow only with \
                 a HIGHER version; built-in workflows cannot be changed. The user reviews all entries \
                 in one AppPad dialog (Install / Cancel). Invalid entries come back in 'rejected' with \
                 the reason and are not shown to the user.
                 """,
                 ["workflows": objectArray("Workflow JSON objects.")], required: ["workflows"]),
        ] + MCPLayoutTools.definitions + MCPHomebrewTools.definitions
    }

    // MARK: - Calls

    struct Outcome {
        var text: String
        var isError: Bool
    }

    static func call(_ name: String, _ args: MCPArguments, client: String) async -> Outcome {
        do {
            switch name {
            case "list_workflows": return ok(listWorkflows(query: args.string("query")))
            case "get_workflows": return ok(try getWorkflows(args.requireStrings("ids")))
            case "run_workflow": return try await runWorkflow(args)
            case "get_workflow_result": return ok(try result(of: resolve(args.requireString("id"))))
            case "stop_workflow": return ok(try stop(resolve(args.requireString("id"))))
            case "workflow_guide": return Outcome(text: MCPWorkflowGuide.text, isError: false)
            case "export_workflows": return ok(MCPWorkflowWriter.export(try args.requireStrings("ids")))
            case "save_workflows":
                let payload = try MCPWorkflowWriter.save(try args.requireObjects("workflows"), client: client)
                let savedNothing = (payload["saved"] as? [Any])?.isEmpty ?? true
                return Outcome(text: json(payload), isError: savedNothing && payload["declined"] == nil)
            case _ where MCPLayoutTools.names.contains(name): return try MCPLayoutTools.call(name, args)
            case _ where MCPHomebrewTools.names.contains(name):
                return try await MCPHomebrewTools.call(name, args, client: client)
            default: return Outcome(text: "Unknown tool: \(name)", isError: true)
            }
        } catch {
            return Outcome(text: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    private static func listWorkflows(query: String?) -> [String: Any] {
        var items = WorkflowStore.shared.workflows.filter(\.enabled)
        if let query = query?.lowercased() {
            items = items.filter { workflow in
                let haystack = [workflow.identifier, workflow.displaySummary, workflow.summary]
                    + workflow.searchNames + workflow.matchKeywords
                return haystack.contains { $0.lowercased().contains(query) }
            }
        }
        return ["workflows": items.map { describe($0) }]
    }

    private static func getWorkflows(_ refs: [String]) throws -> [String: Any] {
        var found: [[String: Any]] = []
        var notFound: [String] = []
        for ref in refs {
            if let workflow = try? resolve(ref) {
                found.append(detail(workflow))
            } else {
                notFound.append(ref)
            }
        }
        var payload: [String: Any] = ["workflows": found]
        if !notFound.isEmpty { payload["notFound"] = notFound }
        return payload
    }

    private static func runWorkflow(_ args: MCPArguments) async throws -> Outcome {
        let workflow = try resolve(args.requireString("id"))
        let runner = WorkflowRunner.shared
        guard !runner.running.contains(workflow.id) else {
            throw MCPToolError("“\(workflow.displayName)” is already running. Use get_workflow_result or stop_workflow.")
        }
        let argument = args.rawString("argument") ?? ""
        // Same parse as the runner, so a bad argument comes back with its usage instead of a failed run.
        if case .failure(let error) = WorkflowArguments.parse(argument, type: workflow.argumentType,
                                                               mode: workflow.argument) {
            throw MCPToolError(error.message + " " + usage(workflow))
        }
        let wait = min(max(args.int("wait_seconds") ?? 60, 1), 600)
        MCPHost.shared.recordUse?(workflow.statsKey)

        let box = RunBox()
        Task {
            box.result = await runner.run(workflow, trigger: .mcp, argument: argument)
            box.done = true
        }
        let deadline = Date().addingTimeInterval(TimeInterval(wait))
        while !box.done && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard box.done else {
            return ok(["id": workflow.identifier, "name": workflow.displayName, "status": "running",
                       "message": "Still running after \(wait) s. Call get_workflow_result later, or stop_workflow."])
        }
        guard let result = box.result else {
            throw MCPToolError("“\(workflow.displayName)” is already running.")
        }
        let payload = encode(result, workflow)
        return Outcome(text: json(payload), isError: !result.success && !result.declined)
    }

    private static func result(of workflow: Workflow) -> [String: Any] {
        if WorkflowRunner.shared.running.contains(workflow.id) {
            return ["id": workflow.identifier, "name": workflow.displayName, "status": "running"]
        }
        guard let last = WorkflowRunner.shared.lastResults[workflow.id] else {
            return ["id": workflow.identifier, "name": workflow.displayName, "status": "none",
                    "message": "No run since AppPad started."]
        }
        return encode(last, workflow)
    }

    private static func stop(_ workflow: Workflow) -> [String: Any] {
        guard WorkflowRunner.shared.running.contains(workflow.id) else {
            return ["id": workflow.identifier, "status": "not running"]
        }
        WorkflowRunner.shared.cancel(id: workflow.id)
        return ["id": workflow.identifier, "status": "stopping"]
    }

    // MARK: - Lookup

    // id → keyword → name (any language); enabled workflows only.
    static func resolve(_ ref: String) throws -> Workflow {
        let key = ref.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = WorkflowStore.shared.workflows
        let match = all.first { $0.identifier == key }
            ?? all.first { $0.matchKeywords.contains(key) }
            ?? all.first { $0.searchNames.contains { $0.lowercased() == key } }
        guard let match else {
            throw MCPToolError("No workflow “\(ref)”. Call list_workflows for the available ids.")
        }
        guard match.enabled else {
            throw MCPToolError("“\(match.displayName)” is disabled in AppPad.")
        }
        return match
    }

    // MARK: - Encoding

    private static func describe(_ workflow: Workflow) -> [String: Any] {
        var item: [String: Any] = ["id": workflow.identifier, "name": workflow.displayName]
        if workflow.name != workflow.displayName { item["englishName"] = workflow.name }
        let summary = workflow.displaySummary
        if !summary.isEmpty { item["description"] = summary }
        if !workflow.group.isEmpty { item["group"] = BuiltinWorkflows.groupTitle(workflow.group) }
        if !workflow.matchKeywords.isEmpty { item["keywords"] = workflow.matchKeywords }
        if workflow.argument != .off {
            var argument: [String: Any] = [
                "required": workflow.argument == .required,
                "type": workflow.argumentType.rawValue,
                "format": formatHint(workflow.argumentType),
            ]
            let hint = workflow.displayArgumentHint
            if !hint.isEmpty { argument["hint"] = hint }
            let examples = WorkflowArguments.examples(for: workflow.argumentType)
            if !examples.isEmpty { argument["examples"] = examples }
            item["argument"] = argument
        }
        if workflow.requiresConfirmation { item["asksBeforeRunning"] = true }
        if WorkflowRunner.shared.running.contains(workflow.id) { item["running"] = true }
        return item
    }

    private static func detail(_ workflow: Workflow) -> [String: Any] {
        var item = describe(workflow)
        item["version"] = workflow.version
        item["steps"] = workflow.steps.enumerated().map { index, step -> [String: Any] in
            var entry: [String: Any] = ["step": index + 1, "kind": step.kind.rawValue]
            switch step.kind {
            case .builtin: entry["action"] = step.unsupportedBuiltin ?? step.builtin.rawValue
            case .shortcut: entry["shortcut"] = step.shortcutName
            case .http: entry["request"] = step.http.method.rawValue + " " + (step.http.host ?? "")
            case .appleScript: entry["language"] = step.language.rawValue
            case .shell: break
            }
            return entry
        }
        let store = PermissionStore.shared
        item["permissions"] = workflow.requiredPermissions.map { permission -> [String: Any] in
            let state: String
            switch store.decision(for: permission, workflow: workflow.id) {
            case .allow: state = "allowed"
            case .deny: state = "denied"
            case nil: state = "ask"
            }
            return ["permission": permission.title, "state": state]
        }
        return item
    }

    private static func encode(_ result: WorkflowRunResult, _ workflow: Workflow) -> [String: Any] {
        var payload: [String: Any] = ["id": workflow.identifier, "name": result.workflowName]
        if result.declined {
            payload["status"] = "declined"
            payload["message"] = "The user chose Cancel in AppPad's confirmation dialog. Do not retry unless asked."
            return payload
        }
        payload["status"] = result.success ? "success" : (result.cancelled ? "cancelled" : "failed")
        payload["output"] = clip(result.finalOutput)
        payload["durationSeconds"] = (result.finishedAt.timeIntervalSince(result.startedAt) * 10).rounded() / 10
        if !result.success { payload["error"] = clip(result.failureSummary) }
        if !result.denied.isEmpty { payload["deniedPermissions"] = result.denied.map(\.title) }
        if !result.steps.isEmpty {
            payload["steps"] = result.steps.map { step -> [String: Any] in
                var entry: [String: Any] = ["title": step.title, "success": step.success]
                if !step.output.isEmpty { entry["output"] = clip(step.output) }
                if !step.stderr.isEmpty { entry["stderr"] = clip(step.stderr) }
                if let message = step.message { entry["message"] = message }
                if let code = step.exitCode { entry["exitCode"] = Int(code) }
                return entry
            }
        }
        return payload
    }

    private static func usage(_ workflow: Workflow) -> String {
        var text = "Argument: " + formatHint(workflow.argumentType)
        let examples = WorkflowArguments.examples(for: workflow.argumentType)
        if !examples.isEmpty { text += " Examples: " + examples.joined(separator: ", ") + "." }
        return text
    }

    private static func formatHint(_ type: ArgumentType) -> String {
        switch type {
        case .text: return "Free text."
        case .duration: return "A duration: minutes as a plain number (10), or 90s, 1h30m, 1:30. Under 24 hours."
        case .time: return "A clock time: 7:30, 19:30 or 7pm, optionally followed by a label."
        case .number: return "An integer."
        case .percent: return "A number from 0 to 100 (out-of-range values are clamped)."
        case .reminder:
            return "Reminder text with an optional date/time (\"tomorrow 3pm\", \"in 2 hours\"), "
                + "\"!\" / \"!!\" / \"!!!\" for low / medium / high priority and a trailing \"@List\"."
        }
    }

    // Keeps replies small; full output stays visible in AppPad.
    private static func clip(_ text: String, limit: Int = 20_000) -> String {
        text.count > limit ? String(text.prefix(limit)) + "\n… (truncated)" : text
    }

    // MARK: - Helpers

    private static func ok(_ payload: [String: Any]) -> Outcome {
        Outcome(text: json(payload), isError: false)
    }

    static func json(_ payload: [String: Any]) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: options) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any],
                             required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func integer(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private static func stringArray(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "description": description]
    }

    private static func objectArray(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "object"], "description": description]
    }
}

// Result holder for the wait loop in run_workflow (main actor only).
private final class RunBox {
    var result: WorkflowRunResult?
    var done = false
}

nonisolated struct MCPToolError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Arguments

// Lenient readers: models send numbers as strings, arrays as comma lists, and so on.
struct MCPArguments {
    private let values: [String: Any]

    init(_ values: [String: Any]) {
        self.values = values
    }

    // Trimmed, nil when empty.
    func string(_ key: String) -> String? {
        guard let raw = rawString(key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // As sent; numbers become their text ("10").
    func rawString(_ key: String) -> String? {
        switch values[key] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    func requireString(_ key: String) throws -> String {
        guard let value = string(key) else { throw MCPToolError("Missing required argument: \(key)") }
        return value
    }

    // Value as sent (arrays / objects for structured arguments).
    func raw(_ key: String) -> Any? {
        values[key]
    }

    func bool(_ key: String) -> Bool? {
        switch values[key] {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    func int(_ key: String) -> Int? {
        if let n = values[key] as? NSNumber { return n.intValue }
        if let s = values[key] as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    // Array of objects; a single object counts as one entry.
    func requireObjects(_ key: String) throws -> [[String: Any]] {
        switch values[key] {
        case let array as [Any]:
            let objects = array.compactMap { $0 as? [String: Any] }
            guard !objects.isEmpty, objects.count == array.count else {
                throw MCPToolError("\(key) must be a non-empty array of objects")
            }
            return objects
        case let object as [String: Any]:
            return [object]
        case let text as String:
            // Some clients send the JSON as a string.
            guard let data = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) else {
                throw MCPToolError("\(key) must be an array of workflow objects")
            }
            return try MCPArguments([key: parsed]).requireObjects(key)
        default:
            throw MCPToolError("Missing required argument: \(key) (array of objects)")
        }
    }

    func requireStrings(_ key: String) throws -> [String] {
        let list: [String]
        switch values[key] {
        case let array as [Any]: list = array.compactMap { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue }
        case let s as String: list = s.split(separator: ",").map(String.init)
        default: list = []
        }
        let cleaned = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { throw MCPToolError("Missing required argument: \(key) (non-empty array)") }
        return cleaned
    }
}
