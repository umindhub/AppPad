import AppKit
import Combine

// Stored answers. "Allow Once" is never stored; no entry = ask next time.
nonisolated enum PermissionDecision: String, Codable, Sendable {
    case allow, deny
}

// Per-workflow, per-item decisions. Like iOS: "Always Allow" stays until the user changes it
// in Settings; editing the script does not reset it (the sandbox still enforces the manifest).
final class PermissionStore: ObservableObject {
    static let shared = PermissionStore()

    // [workflow id: [item key: decision]]
    @Published private(set) var grants: [String: [String: PermissionDecision]] = [:]

    private let url = AppEnvironment.supportDirectory.appendingPathComponent("workflow-permissions.json")

    private init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [String: PermissionDecision]].self, from: data) {
            grants = decoded
        }
    }

    func decision(for item: PermissionItem, workflow id: UUID) -> PermissionDecision? {
        grants[id.uuidString]?[item.key]
    }

    func set(_ decision: PermissionDecision?, for items: [PermissionItem], workflow id: UUID) {
        var entry = grants[id.uuidString] ?? [:]
        for item in items { entry[item.key] = decision }
        grants[id.uuidString] = entry.isEmpty ? nil : entry
        persist()
    }

    func removeAll(for id: UUID) {
        guard grants.removeValue(forKey: id.uuidString) != nil else { return }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(grants) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

nonisolated enum PermissionAnswer: Sendable {
    case allowOnce, alwaysAllow, deny
}

// iPhone-style prompt: Allow Once / Always Allow / Don't Allow for all undecided items at once.
enum PermissionPrompt {
    static func ask(workflow: Workflow, items: [PermissionItem]) -> PermissionAnswer {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "“\(workflow.name)” wants to:")
        alert.informativeText = items.map { "• " + $0.title }.joined(separator: "\n")
        alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        alert.addButton(withTitle: String(localized: "Allow Once"))
        alert.addButton(withTitle: String(localized: "Always Allow"))
        let deny = alert.addButton(withTitle: String(localized: "Don't Allow"))
        deny.keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .allowOnce
        case .alertSecondButtonReturn: return .alwaysAllow
        default: return .deny
        }
    }
}
