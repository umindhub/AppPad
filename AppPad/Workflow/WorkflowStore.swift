import Foundation
import Combine

extension Notification.Name {
    static let workflowsDidChange = Notification.Name("AppPad.workflowsDidChange")
}

// What an import would do with one incoming workflow.
enum WorkflowImportAction {
    case add                        // identifier not installed yet
    case upgrade(Workflow)          // incoming version is higher → replace
    case sameVersion(Workflow)      // same version → ask before replacing
    case older(Workflow)            // incoming version is lower → skip
    case reserved                   // built-in identifier: only AppPad itself installs these
}

struct WorkflowImportItem: Identifiable {
    let id = UUID()
    let workflow: Workflow
    let action: WorkflowImportAction
}

// One JSON file per workflow in Application Support/<bundle id>/Workflows/<uid>.json.
// The reverse-DNS identifier is unique; downloaded icons live in Workflows/Icons/<identifier>.png.
final class WorkflowStore: ObservableObject {
    static let shared = WorkflowStore()

    @Published private(set) var workflows: [Workflow] = []
    // Set by ⌘↩ in the Workflow panel; Settings › Workflows opens this one's editor.
    @Published var pendingEditID: UUID?

    let directory: URL

    private init() {
        directory = AppEnvironment.supportDirectory.appendingPathComponent("Workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        // Next turn of the run loop: install() saves and posts change notifications,
        // which must not reach observers while `shared` is still being created.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            BuiltinWorkflows.install(into: self)
        }
    }

    func workflow(id: UUID) -> Workflow? {
        workflows.first { $0.id == id }
    }

    func workflow(identifier: String) -> Workflow? {
        let key = WorkflowIdentity.normalizeIdentifier(identifier)
        return workflows.first { $0.identifier == key }
    }

    func isIdentifierTaken(_ identifier: String, excluding id: UUID?) -> Bool {
        let key = WorkflowIdentity.normalizeIdentifier(identifier)
        return workflows.contains { $0.identifier == key && $0.id != id }
    }

    func requestEdit(_ id: UUID) {
        pendingEditID = id
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.userInfo[WorkflowFormat.includeLocalKey] = true   // uid, panel key, enabled, source
        var loaded: [Workflow] = []
        var needsRewrite: [(workflow: Workflow, source: URL)] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                var workflow = try decoder.decode(Workflow.self, from: data)
                guard WorkflowFormat.supported.contains(workflow.formatVersion) else {
                    NSLog("Workflow file skipped, unsupported format \(workflow.formatVersion): \(url.lastPathComponent)")
                    continue
                }
                // Migrate: files from before sources were recorded.
                let hasSource = Self.hasSource(data)
                if !hasSource { workflow.source = BuiltinWorkflows.legacySource(for: workflow) }
                // Migrate: files without an identifier (or a duplicate) get a generated one.
                let taken = Set(loaded.map(\.identifier))
                workflow.identifier = WorkflowIdentity.normalizeIdentifier(workflow.identifier)
                if !WorkflowIdentity.isValidIdentifier(workflow.identifier) || taken.contains(workflow.identifier) {
                    workflow.identifier = WorkflowIdentity.suggestedIdentifier(for: workflow.name, taken: taken)
                    needsRewrite.append((workflow, url))
                } else if url.deletingPathExtension().lastPathComponent != workflow.id.uuidString {
                    needsRewrite.append((workflow, url))   // file copied in by hand: store under its uid
                } else if !hasSource {
                    needsRewrite.append((workflow, url))
                }
                loaded.append(workflow)
            } catch {
                NSLog("Workflow file unreadable: \(url.lastPathComponent) \(error)")
            }
        }
        workflows = loaded.sorted { Self.order($0, $1) }
        for (workflow, source) in needsRewrite {
            let target = fileURL(workflow.id)
            guard (try? write(workflow, to: target, local: true)) != nil else { continue }
            if source.standardizedFileURL != target.standardizedFileURL {
                try? FileManager.default.removeItem(at: source)
            }
        }
        // Retry icons whose download failed earlier.
        for workflow in workflows where !workflow.iconURL.isEmpty && workflow.icon == nil
            && !FileManager.default.fileExists(atPath: WorkflowIcon.fileURL(for: workflow.identifier).path) {
            downloadIcon(for: workflow)
        }
    }

    // Edits from Settings (and local state changes). The source can't be changed here:
    // an existing workflow keeps its own, built-in / third-party ones get "modified" when
    // their behavior changes, and a new workflow is the user's own.
    func save(_ workflow: Workflow) {
        var workflow = workflow
        if let previous = self.workflow(id: workflow.id) {
            workflow.source = previous.source
            if workflow.source.category != .mine, !workflow.sameBehavior(as: previous) {
                workflow.source.modified = true
            }
        } else if workflow.source.category != .mine {
            workflow.source = .local()
        }
        commit(workflow)
    }

    private func commit(_ workflow: Workflow) {
        var workflow = workflow
        workflow.identifier = WorkflowIdentity.normalizeIdentifier(workflow.identifier)
        workflow.iconURL = workflow.iconURL.trimmingCharacters(in: .whitespaces)
        if !workflow.iconURL.isEmpty { workflow.icon = nil }   // URL wins over an embedded image
        let previous = self.workflow(id: workflow.id)
        do {
            try write(workflow, to: fileURL(workflow.id), local: true)
        } catch {
            NSLog("Saving workflow failed: \(error)")
            return
        }
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[index] = workflow
        } else {
            workflows.append(workflow)
        }
        workflows.sort { Self.order($0, $1) }
        syncIcon(new: workflow, old: previous)
        NotificationCenter.default.post(name: .workflowsDidChange, object: self)
    }

    func delete(id: UUID) {
        if let workflow = workflow(id: id) {
            guard !workflow.isBuiltin else { return }   // built-ins can only be disabled
            WorkflowIcon.removeFile(for: workflow.identifier)
        }
        try? FileManager.default.removeItem(at: fileURL(id))
        workflows.removeAll { $0.id == id }
        PermissionStore.shared.removeAll(for: id)
        NotificationCenter.default.post(name: .workflowsDidChange, object: self)
    }

    func duplicate(_ workflow: Workflow) {
        var copy = workflow
        copy.id = UUID()
        copy.identifier = uniqueIdentifier(from: workflow.identifier + ".copy")
        copy.name = String(localized: "\(workflow.displayName) Copy")
        copy.localizations = [:]
        copy.panelKey = nil
        // A copy of a built-in is the user's own; a copy of a third-party one stays third-party.
        if workflow.source.isThirdParty {
            copy.source.date = Date()
        } else {
            copy.source = .local()
        }
        commit(copy)   // a URL icon is fetched again for the new identifier
    }

    // MARK: - Import

    // Reads a file (one workflow or an array) and decides per item; nothing is stored yet.
    // Throws WorkflowImportError.unsupportedFormat for format versions without a parser.
    func prepareImport(_ url: URL) throws -> [WorkflowImportItem] {
        try prepareImport(data: Data(contentsOf: url))
    }

    // Same as above for downloaded data (Workflow Market links).
    func prepareImport(data: Data) throws -> [WorkflowImportItem] {
        var items: [WorkflowImportItem] = []
        var batchIdentifiers = Set<String>()
        for var incoming in try WorkflowFormat.decode(data) {
            incoming.identifier = WorkflowIdentity.normalizeIdentifier(incoming.identifier)
            if !WorkflowIdentity.isValidVersion(incoming.version) { incoming.version = "1.0" }
            // Old exports had no identifier: generate one, it never collides.
            if !WorkflowIdentity.isValidIdentifier(incoming.identifier) {
                let taken = Set(workflows.map(\.identifier)).union(batchIdentifiers)
                incoming.identifier = WorkflowIdentity.suggestedIdentifier(for: incoming.name, taken: taken)
            }
            batchIdentifiers.insert(incoming.identifier)
            // "system" is AppPad's own group; an import can't put itself there.
            if incoming.group.lowercased() == BuiltinWorkflows.group { incoming.group = "" }
            let action: WorkflowImportAction
            if BuiltinWorkflows.identifiers.contains(incoming.identifier) {
                action = .reserved
            } else if let existing = workflow(identifier: incoming.identifier) {
                switch WorkflowIdentity.compareVersions(incoming.version, existing.version) {
                case .orderedDescending: action = .upgrade(existing)
                case .orderedSame: action = .sameVersion(existing)
                case .orderedAscending: action = .older(existing)
                }
            } else {
                action = .add
            }
            items.append(WorkflowImportItem(workflow: incoming, action: action))
        }
        return items
    }

    // Adds a new workflow or replaces the installed one with the same identifier; the caller
    // says where it comes from. A replacement keeps the local uid, panel shortcut and enabled
    // state; its permission answers only carry over when the origin stays the same.
    func install(_ incoming: Workflow, source: WorkflowSource) {
        var item = incoming
        var source = source
        item.steps = item.steps.map { var step = $0; step.id = UUID(); return step }
        if let existing = workflow(identifier: item.identifier) {
            item.id = existing.id
            item.panelKey = existing.panelKey
            item.enabled = existing.enabled
            if source.category == .mine, existing.source.isThirdParty {
                // Saving over an imported workflow (Settings, AI) doesn't make it the user's own.
                var kept = existing.source
                if !item.sameBehavior(as: existing) { kept.modified = true }
                source = kept
            }
            if !source.sameOrigin(as: existing.source) {
                PermissionStore.shared.removeAll(for: existing.id)   // new origin: ask again
            }
        } else {
            item.id = UUID()
            item.panelKey = nil
            item.enabled = true
        }
        item.source = source
        commit(item)
    }

    func export(_ workflow: Workflow, to url: URL) throws {
        try write(workflow, to: url, local: false)   // no uid, shortcut or enabled state
    }

    // MARK: - Private

    private func syncIcon(new: Workflow, old: Workflow?) {
        if let old, old.identifier != new.identifier {
            WorkflowIcon.moveFile(from: old.identifier, to: new.identifier)
        }
        if new.iconURL.isEmpty {
            WorkflowIcon.removeFile(for: new.identifier)
            return
        }
        let hasFile = FileManager.default.fileExists(atPath: WorkflowIcon.fileURL(for: new.identifier).path)
        if old?.iconURL != new.iconURL || !hasFile {
            downloadIcon(for: new)
        }
    }

    private func downloadIcon(for workflow: Workflow) {
        let identifier = workflow.identifier
        let urlString = workflow.iconURL
        Task {
            guard await WorkflowIcon.download(urlString, for: identifier) else { return }
            // Same list, new icon: republish so SwiftUI and the panel redraw.
            workflows = workflows
            NotificationCenter.default.post(name: .workflowsDidChange, object: self)
        }
    }

    private func uniqueIdentifier(from base: String) -> String {
        var candidate = base
        var n = 2
        while isIdentifierTaken(candidate, excluding: nil) {
            candidate = "\(base)\(n)"
            n += 1
        }
        return candidate
    }

    // Store files written before sources existed have no "source" key.
    private static func hasSource(_ data: Data) -> Bool {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["source"] != nil
    }

    private func write(_ workflow: Workflow, to url: URL, local: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.userInfo[WorkflowFormat.includeLocalKey] = local
        try encoder.encode(workflow).write(to: url, options: .atomic)
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    private static func order(_ a: Workflow, _ b: Workflow) -> Bool {
        a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
    }
}
