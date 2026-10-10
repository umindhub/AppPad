import Foundation
import Combine

extension Notification.Name {
    static let workflowsDidChange = Notification.Name("AppPad.workflowsDidChange")
}

// One JSON file per workflow in Application Support/<bundle id>/Workflows/<uuid>.json.
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
    }

    func workflow(id: UUID) -> Workflow? {
        workflows.first { $0.id == id }
    }

    func requestEdit(_ id: UUID) {
        pendingEditID = id
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        workflows = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                do {
                    return try decoder.decode(Workflow.self, from: data)
                } catch {
                    NSLog("Workflow file unreadable: \(url.lastPathComponent) \(error)")
                    return nil
                }
            }
            .sorted(by: Self.order)
    }

    func save(_ workflow: Workflow) {
        do {
            try write(workflow, to: fileURL(workflow.id))
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
        NotificationCenter.default.post(name: .workflowsDidChange, object: self)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(id))
        workflows.removeAll { $0.id == id }
        PermissionStore.shared.removeAll(for: id)
        NotificationCenter.default.post(name: .workflowsDidChange, object: self)
    }

    func duplicate(_ workflow: Workflow) {
        var copy = workflow
        copy.id = UUID()
        copy.name = String(localized: "\(workflow.name) Copy")
        copy.panelKey = nil
        save(copy)
    }

    // Accepts one workflow or an array. Imported workflows get fresh ids,
    // so they never inherit grants and always ask for every permission.
    @discardableResult
    func importFile(_ url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let items: [Workflow]
        if let many = try? decoder.decode([Workflow].self, from: data) {
            items = many
        } else {
            items = [try decoder.decode(Workflow.self, from: data)]
        }
        for var item in items {
            item.id = UUID()
            item.panelKey = nil
            item.steps = item.steps.map { var step = $0; step.id = UUID(); return step }
            save(item)
        }
        return items.count
    }

    func export(_ workflow: Workflow, to url: URL) throws {
        var copy = workflow
        copy.panelKey = nil   // shortcuts are personal
        try write(copy, to: url)
    }

    private func write(_ workflow: Workflow, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(workflow).write(to: url, options: .atomic)
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    private static func order(_ a: Workflow, _ b: Workflow) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
