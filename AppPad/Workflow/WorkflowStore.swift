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
                // Migrate: files without an identifier (or a duplicate) get a generated one.
                let taken = Set(loaded.map(\.identifier))
                workflow.identifier = WorkflowIdentity.normalizeIdentifier(workflow.identifier)
                if !WorkflowIdentity.isValidIdentifier(workflow.identifier) || taken.contains(workflow.identifier) {
                    workflow.identifier = WorkflowIdentity.suggestedIdentifier(for: workflow.name, taken: taken)
                    needsRewrite.append((workflow, url))
                } else if url.deletingPathExtension().lastPathComponent != workflow.id.uuidString {
                    needsRewrite.append((workflow, url))   // file copied in by hand: store under its uid
                }
                loaded.append(workflow)
            } catch {
                NSLog("Workflow file unreadable: \(url.lastPathComponent) \(error)")
            }
        }
        workflows = loaded.sorted(by: Self.order)
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

    func save(_ workflow: Workflow) {
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
        workflows.sort(by: Self.order)
        syncIcon(new: workflow, old: previous)
        NotificationCenter.default.post(name: .workflowsDidChange, object: self)
    }

    func delete(id: UUID) {
        if let workflow = workflow(id: id) {
            WorkflowIcon.removeFile(for: workflow.identifier)
            BuiltinWorkflows.noteDeleted(workflow.identifier)   // don't reinstall it on next launch
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
        save(copy)   // a URL icon is fetched again for the new identifier
    }

    // MARK: - Import

    // Reads a file (one workflow or an array) and decides per item; nothing is stored yet.
    // Throws WorkflowImportError.unsupportedFormat for format versions without a parser.
    func prepareImport(_ url: URL) throws -> [WorkflowImportItem] {
        let data = try Data(contentsOf: url)
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
            let action: WorkflowImportAction
            if let existing = workflow(identifier: incoming.identifier) {
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

    // Adds a new workflow or replaces the installed one with the same identifier.
    // A replacement keeps the local uid (so grants stay), panel shortcut and enabled state.
    func install(_ incoming: Workflow) {
        var item = incoming
        item.steps = item.steps.map { var step = $0; step.id = UUID(); return step }
        if let existing = workflow(identifier: item.identifier) {
            item.id = existing.id
            item.panelKey = existing.panelKey
            item.enabled = existing.enabled
        } else {
            item.id = UUID()
            item.panelKey = nil
            item.enabled = true
        }
        save(item)
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
