import AppKit

// `save_workflows` / `export_workflows`: AI-authored workflows go through the normal import path
// (format check, identifier / version rules) and are installed only after the user approves them
// in a dialog that shows every step. No permission is granted here: runs still ask.
enum MCPWorkflowWriter {

    // MARK: - Export

    // File-format JSON (no uid, panel key or enabled state); embedded icons are left out.
    static func export(_ refs: [String]) -> [String: Any] {
        var found: [Any] = []
        var notFound: [String] = []
        let encoder = JSONEncoder()
        encoder.userInfo[WorkflowFormat.includeLocalKey] = false
        for ref in refs {
            guard let workflow = lookup(ref),
                  let data = try? encoder.encode(workflow),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                notFound.append(ref)
                continue
            }
            if object.removeValue(forKey: "icon") != nil { object["icon"] = "(embedded image omitted)" }
            if workflow.group == BuiltinWorkflows.group {
                object["note"] = "Built-in workflow, read-only. To adapt it, save a copy with your own id and without group \"system\"."
            }
            found.append(object)
        }
        var payload: [String: Any] = ["workflows": found]
        if !notFound.isEmpty { payload["notFound"] = notFound }
        return payload
    }

    // Disabled workflows too (exporting is read-only).
    private static func lookup(_ ref: String) -> Workflow? {
        let key = ref.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = WorkflowStore.shared.workflows
        return all.first { $0.identifier == key }
            ?? all.first { $0.matchKeywords.contains(key) }
            ?? all.first { $0.searchNames.contains { $0.lowercased() == key } }
    }

    // MARK: - Save

    static func save(_ objects: [[String: Any]], client: String) throws -> [String: Any] {
        var rejected: [[String: Any]] = []
        var accepted: [(item: WorkflowImportItem, previous: String?)] = []
        let store = WorkflowStore.shared
        var seenIDs = Set<String>()

        for (index, object) in objects.enumerated() {
            let label = (object["id"] as? String) ?? "workflows[\(index)]"
            func reject(_ reason: String) { rejected.append(["id": label, "error": reason]) }

            let rawID = WorkflowIdentity.normalizeIdentifier(object["id"] as? String ?? "")
            guard WorkflowIdentity.isValidIdentifier(rawID) else {
                reject("id must be reverse-DNS, lowercase, e.g. com.yourname.tool")
                continue
            }
            guard seenIDs.insert(rawID).inserted else {
                reject("the same id appears twice in this call.")
                continue
            }
            guard !BuiltinWorkflows.identifiers.contains(rawID) else {
                reject("\(rawID) is a built-in workflow and cannot be changed. Use your own id.")
                continue
            }
            guard (object["group"] as? String)?.lowercased() != BuiltinWorkflows.group else {
                reject("group \"\(BuiltinWorkflows.group)\" is reserved for built-in workflows.")
                continue
            }
            let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty else {
                reject("name is required.")
                continue
            }
            let item: WorkflowImportItem
            do {
                let data = try JSONSerialization.data(withJSONObject: object)
                guard let first = try store.prepareImport(data: data).first else {
                    reject("could not read the workflow.")
                    continue
                }
                item = first
            } catch {
                reject("invalid workflow JSON: \(error.localizedDescription)")
                continue
            }
            let errors = item.workflow.validationErrors
            guard errors.isEmpty else {
                reject(errors.joined(separator: " "))
                continue
            }
            switch item.action {
            case .add:
                accepted.append((item, nil))
            case .upgrade(let existing):
                accepted.append((item, existing.version))
            case .sameVersion(let existing), .older(let existing):
                reject("version \(item.workflow.version) is not higher than the installed \(existing.version). Raise version to replace it.")
            case .reserved:
                reject("\(rawID) is a built-in workflow and cannot be changed. Use your own id.")
            }
        }

        var payload: [String: Any] = [:]
        if !rejected.isEmpty { payload["rejected"] = rejected }
        guard !accepted.isEmpty else {
            payload["saved"] = [Any]()
            return payload
        }
        guard ReviewPrompt.ask(client: client, items: accepted) else {
            payload["saved"] = [Any]()
            payload["declined"] = accepted.map { $0.item.workflow.identifier }
            payload["message"] = "The user cancelled the save in AppPad. Do not retry unless asked."
            return payload
        }
        // AI-written counts as the user's own ("Mine"); saving over an imported one keeps it third-party.
        for entry in accepted { store.install(entry.item.workflow, source: .local(client: client)) }
        payload["saved"] = accepted.map { entry -> [String: Any] in
            let workflow = entry.item.workflow
            var saved: [String: Any] = ["id": workflow.identifier, "name": workflow.name,
                                        "version": workflow.version,
                                        "action": entry.previous == nil ? "added" : "replaced"]
            if let previous = entry.previous { saved["previousVersion"] = previous }
            return saved
        }
        payload["message"] = "Saved. Permissions are asked the first time each workflow runs."
        return payload
    }

    // MARK: - Review dialog

    // Install / Cancel, with the full steps (scripts included) in a scrollable text view.
    private enum ReviewPrompt {
        static func ask(client: String, items: [(item: WorkflowImportItem, previous: String?)]) -> Bool {
            let alert = NSAlert()
            alert.messageText = String(localized: "“\(client)” wants to add or change workflows")
            alert.informativeText = String(localized: "Review the steps below. AppPad still asks for permissions the first time a workflow runs.")
            alert.icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            alert.accessoryView = textView(items.map { describe($0.item.workflow, previous: $0.previous) }
                .joined(separator: "\n\n────────\n\n"))
            alert.addButton(withTitle: String(localized: "Install"))
            let cancel = alert.addButton(withTitle: String(localized: "Cancel"))
            cancel.keyEquivalent = "\u{1b}"
            return FloatingAlert.runModal(alert) == .alertFirstButtonReturn
        }

        private static func describe(_ workflow: Workflow, previous: String?) -> String {
            let status = previous.map { String(localized: "Replaces version \($0)") } ?? String(localized: "New")
            var lines = ["\(workflow.name)  ·  \(workflow.identifier) \(workflow.version)  ·  \(status)"]
            if !workflow.summary.isEmpty { lines.append(workflow.summary) }
            let permissions = workflow.requiredPermissions.map { "  • " + $0.title }
            lines.append("")
            lines.append(String(localized: "Permissions") + ":")
            lines += permissions.isEmpty ? ["  " + String(localized: "None")] : permissions
            lines.append("")
            lines.append(String(localized: "Steps") + ":")
            for (index, step) in workflow.steps.enumerated() {
                lines.append("\(index + 1). \(step.kind.title)" + stepDetail(step))
                let body = stepBody(step)
                if !body.isEmpty {
                    lines += body.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + String($0) }
                }
            }
            return lines.joined(separator: "\n")
        }

        private static func stepDetail(_ step: WorkflowStep) -> String {
            switch step.kind {
            case .shortcut: return " “\(step.shortcutName)”"
            case .builtin: return " · " + (step.unsupportedBuiltin ?? step.builtin.title)
            case .http: return " · " + step.http.method.rawValue
            case .appleScript: return step.language == .javaScript ? " (JavaScript)" : ""
            case .shell: return ""
            }
        }

        private static func stepBody(_ step: WorkflowStep) -> String {
            switch step.kind {
            case .shell, .appleScript: return step.script
            case .shortcut: return step.shortcutInput
            case .http:
                return [step.http.url, step.http.headers, step.http.body]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            case .builtin:
                switch step.builtin {
                case .openURL: return step.url
                case .prefillTerminal:
                    return (step.directory.isEmpty ? "" : "cd " + step.directory + "\n") + step.command
                default: return ""
                }
            }
        }

        private static func textView(_ text: String) -> NSView {
            let scroll = NSTextView.scrollableTextView()
            scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 280)
            scroll.borderType = .bezelBorder
            scroll.hasVerticalScroller = true
            if let view = scroll.documentView as? NSTextView {
                view.isEditable = false
                view.isRichText = false
                view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                view.textContainerInset = NSSize(width: 6, height: 6)
                view.string = text
            }
            return scroll
        }
    }
}
