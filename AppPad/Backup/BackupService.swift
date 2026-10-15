import AppKit

// Export / import of shortcuts, Launchpad layout, workflows and clipboard.
// Not included on purpose: Keychain secrets and "Always Allow" grants (re-asked on first run).
final class BackupService {
    static let shared = BackupService()

    // Wired by AppDelegate once the controllers have started.
    var clipboardStore: ClipboardStore?
    var layoutProvider: () -> Layout? = { nil }
    var layoutRestorer: (Layout) -> Void = { _ in }

    private enum File {
        static let shortcuts = "shortcuts.json"
        static let layout = "layout.json"
        static let workflows = "workflows.json"
        static let workflowIcons = "workflow-icons"
        static let clipboard = "clipboard"
    }

    private init() {}

    // Clipboard parts only when the store opened.
    var availableSections: [BackupSection] {
        BackupSection.allCases.filter { !$0.isClipboard || clipboardStore != nil }
    }

    static func suggestedFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "AppPad Backup \(formatter.string(from: Date())).\(BackupArchive.fileExtension)"
    }

    // MARK: - Export

    func export(_ sections: Set<BackupSection>, to destination: URL) async throws {
        let fm = FileManager.default
        let work = try Self.makeWorkDirectory()
        defer { try? fm.removeItem(at: work) }
        let root = work.appendingPathComponent("backup", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        var written: [BackupSection] = []
        var counts: [String: Int] = [:]
        let prefs = Preferences.shared

        if sections.contains(.shortcuts) {
            var windows: [String: KeyCombo] = [:]
            for (action, combo) in prefs.windowHotKeys { windows[action.rawValue] = combo }
            let backup = ShortcutsBackup(appHotKeys: prefs.appHotKeys,
                                         workflowPanel: prefs.workflowPanelHotKey,
                                         clipboard: prefs.clipboardHotKey,
                                         clipboardSaved: prefs.clipboardSavedHotKey,
                                         windowActions: windows)
            try Self.write(backup, to: root.appendingPathComponent(File.shortcuts))
            written.append(.shortcuts)
            counts[BackupSection.shortcuts.rawValue] = backup.appHotKeys.filter { $0.combo != nil }.count
        }

        if sections.contains(.layout), let layout = layoutProvider() {
            let backup = LayoutBackup(gridColumns: prefs.gridColumns, gridRows: prefs.gridRows, layout: layout)
            try Self.write(backup, to: root.appendingPathComponent(File.layout))
            written.append(.layout)
            counts[BackupSection.layout.rawValue] = layout.pages.flatMap { $0 }.reduce(0) { total, item in
                if case .folder(let folder) = item { return total + folder.apps.count }
                return total + 1
            }
        }

        if sections.contains(.workflows) {
            let workflows = WorkflowStore.shared.workflows
            let entries = workflows.map { WorkflowBackupEntry(workflow: $0, enabled: $0.enabled, panelKey: $0.panelKey) }
            try Self.write(entries, to: root.appendingPathComponent(File.workflows))
            // Downloaded URL icons, so a restore works offline.
            let icons = root.appendingPathComponent(File.workflowIcons, isDirectory: true)
            try fm.createDirectory(at: icons, withIntermediateDirectories: true)
            for workflow in workflows where !workflow.iconURL.isEmpty {
                let file = WorkflowIcon.fileURL(for: workflow.identifier)
                guard fm.fileExists(atPath: file.path) else { continue }
                try? fm.copyItem(at: file, to: icons.appendingPathComponent(workflow.identifier + ".png"))
            }
            written.append(.workflows)
            counts[BackupSection.workflows.rawValue] = workflows.count
        }

        let history = sections.contains(.clipboardHistory)
        let saved = sections.contains(.clipboardSaved)
        if (history || saved), let store = clipboardStore {
            let dir = root.appendingPathComponent(File.clipboard, isDirectory: true)
            let result = try await Task.detached(priority: .userInitiated) {
                try store.exportBackup(to: dir, history: history, saved: saved)
            }.value
            if history {
                written.append(.clipboardHistory)
                counts[BackupSection.clipboardHistory.rawValue] = result.history
            }
            if saved {
                written.append(.clipboardSaved)
                counts[BackupSection.clipboardSaved.rawValue] = result.saved
            }
        }

        let manifest = BackupManifest(
            format: BackupManifest.currentFormat,
            appVersion: AppEnvironment.versionNumber,
            bundleID: Bundle.main.bundleIdentifier ?? "",
            createdAt: Date(),
            sections: written.map(\.rawValue),
            counts: counts
        )
        try Self.write(manifest, to: root.appendingPathComponent(BackupManifest.fileName))

        // Pack next to the work folder, then move into place (save panel already confirmed overwrite).
        let packed = work.appendingPathComponent("packed.\(BackupArchive.fileExtension)")
        try await Task.detached(priority: .userInitiated) {
            try BackupArchive.pack(root, to: packed)
        }.value
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: packed, to: destination)
    }

    // MARK: - Import

    // Unpacks to a temp folder and reads the manifest; nothing is changed yet.
    func open(_ file: URL) async throws -> OpenedBackup {
        let work = try Self.makeWorkDirectory()
        let root = work.appendingPathComponent("backup", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try await Task.detached(priority: .userInitiated) {
                try BackupArchive.unpack(file, to: root)
            }.value
            guard let data = try? Data(contentsOf: root.appendingPathComponent(BackupManifest.fileName)),
                  let manifest = try? Self.decoder.decode(BackupManifest.self, from: data) else {
                throw BackupError.notABackup
            }
            guard manifest.format <= BackupManifest.currentFormat else {
                throw BackupError.unsupportedFormat(manifest.format)
            }
            return OpenedBackup(fileName: file.lastPathComponent, manifest: manifest, root: root, workDirectory: work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    func discard(_ backup: OpenedBackup) {
        try? FileManager.default.removeItem(at: backup.workDirectory)
    }

    // Restores the chosen sections. The layout is always replaced.
    func restore(_ backup: OpenedBackup, sections: Set<BackupSection>, mode: BackupImportMode) async throws -> BackupReport {
        let chosen = sections.intersection(backup.manifest.knownSections)
        let root = backup.root
        var report = BackupReport()

        if chosen.contains(.shortcuts) {
            let data = try Data(contentsOf: root.appendingPathComponent(File.shortcuts))
            let shortcuts = try Self.decoder.decode(ShortcutsBackup.self, from: data)
            report.shortcuts = restoreShortcuts(shortcuts, mode: mode)
        }
        if chosen.contains(.layout) {
            let data = try Data(contentsOf: root.appendingPathComponent(File.layout))
            let layout = try Self.decoder.decode(LayoutBackup.self, from: data)
            restoreLayoutSection(layout)
            report.layoutRestored = true
        }
        if chosen.contains(.workflows) {
            let data = try Data(contentsOf: root.appendingPathComponent(File.workflows))
            let entries = try Self.decoder.decode([WorkflowBackupEntry].self, from: data)
            restoreWorkflows(entries, icons: root.appendingPathComponent(File.workflowIcons), mode: mode, into: &report)
        }

        let history = chosen.contains(.clipboardHistory)
        let saved = chosen.contains(.clipboardSaved)
        if (history || saved), let store = clipboardStore {
            let dir = root.appendingPathComponent(File.clipboard, isDirectory: true)
            let replace = mode == .replace
            let result = try await Task.detached(priority: .userInitiated) {
                try store.importBackup(from: dir, history: history, saved: saved,
                                       replaceHistory: replace && history, replaceSaved: replace && saved)
            }.value
            SourceAppDirectory.shared.reload(from: store)
            NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
            report.restoredClipboard = true
            report.clipboardAdded = result.added
            report.clipboardExisting = result.existing
        }
        return report
    }

    // MARK: - Sections

    // Global shortcuts come from the backup in both modes; app rows merge by app key.
    private func restoreShortcuts(_ backup: ShortcutsBackup, mode: BackupImportMode) -> Int {
        let prefs = Preferences.shared
        prefs.workflowPanelHotKey = backup.workflowPanel
        prefs.clipboardHotKey = backup.clipboard
        prefs.clipboardSavedHotKey = backup.clipboardSaved
        var windows: [WindowAction: KeyCombo] = [:]
        for action in WindowAction.allCases {
            if let combo = backup.windowActions[action.rawValue] { windows[action] = combo }
        }
        prefs.windowHotKeys = windows

        switch mode {
        case .replace:
            prefs.appHotKeys = backup.appHotKeys
            return backup.appHotKeys.filter { $0.combo != nil }.count
        case .merge:
            var list = prefs.appHotKeys
            var restored = 0
            for var item in backup.appHotKeys {
                // A combo already used by another shortcut here is dropped (row kept).
                if let combo = item.combo, isTaken(combo, exceptApp: item.key, appRows: list, prefs: prefs) {
                    item.combo = nil
                }
                if let index = list.firstIndex(where: { $0.key == item.key }) {
                    guard item.combo != nil else { continue }   // keep the local combo
                    list[index] = item
                } else {
                    list.append(item)
                }
                if item.combo != nil { restored += 1 }
            }
            prefs.appHotKeys = list
            return restored
        }
    }

    private func isTaken(_ combo: KeyCombo, exceptApp key: String, appRows: [AppHotKey], prefs: Preferences) -> Bool {
        func same(_ other: KeyCombo?) -> Bool {
            other.map { $0.keyCode == combo.keyCode && $0.modifiers == combo.modifiers } ?? false
        }
        if same(prefs.workflowPanelHotKey) || same(prefs.clipboardHotKey) || same(prefs.clipboardSavedHotKey) {
            return true
        }
        if prefs.windowHotKeys.values.contains(where: { same($0) }) { return true }
        return appRows.contains { $0.key != key && same($0.combo) }
    }

    private func restoreLayoutSection(_ backup: LayoutBackup) {
        let prefs = Preferences.shared
        // Same ranges as the Settings steppers.
        prefs.gridColumns = min(max(backup.gridColumns, 3), 10)
        prefs.gridRows = min(max(backup.gridRows, 2), 8)
        layoutRestorer(backup.layout)
    }

    // merge: add missing, upgrade to higher versions, fill empty panel shortcuts.
    // replace: backup copies win regardless of version; workflows not in the backup are removed.
    private func restoreWorkflows(_ entries: [WorkflowBackupEntry], icons: URL, mode: BackupImportMode,
                                  into report: inout BackupReport) {
        let store = WorkflowStore.shared
        let fm = FileManager.default
        report.restoredWorkflows = true

        var valid: [WorkflowBackupEntry] = []
        var seen = Set<String>()
        for var entry in entries {
            entry.workflow.identifier = WorkflowIdentity.normalizeIdentifier(entry.workflow.identifier)
            guard WorkflowFormat.supported.contains(entry.workflow.formatVersion),
                  WorkflowIdentity.isValidIdentifier(entry.workflow.identifier),
                  seen.insert(entry.workflow.identifier).inserted else {
                report.workflowsSkipped += 1
                continue
            }
            if !WorkflowIdentity.isValidVersion(entry.workflow.version) { entry.workflow.version = "1.0" }
            valid.append(entry)
        }

        if mode == .replace {
            for local in store.workflows where !seen.contains(local.identifier) {
                store.delete(id: local.id)
                report.workflowsRemoved += 1
            }
        }

        var pendingKeys: [(identifier: String, combo: KeyCombo)] = []
        for entry in valid {
            let incoming = entry.workflow
            let existing = store.workflow(identifier: incoming.identifier)
            let shouldInstall: Bool
            if let existing, mode == .merge {
                shouldInstall = WorkflowIdentity.compareVersions(incoming.version, existing.version) == .orderedDescending
            } else {
                shouldInstall = true
            }
            if shouldInstall {
                copyIcon(for: incoming, from: icons, fm: fm)
                store.install(incoming)   // keeps local uid (grants), panel key and on/off of an existing copy
                if existing == nil { report.workflowsAdded += 1 } else { report.workflowsUpdated += 1 }
            } else {
                report.workflowsSkipped += 1
            }
            guard var installed = store.workflow(identifier: incoming.identifier) else { continue }
            switch mode {
            case .replace:
                installed.enabled = entry.enabled
                installed.panelKey = nil   // assigned below, after every workflow is in place
                store.save(installed)
                if let combo = entry.panelKey { pendingKeys.append((incoming.identifier, combo)) }
            case .merge:
                if existing == nil {
                    installed.enabled = entry.enabled
                    store.save(installed)
                }
                if installed.panelKey == nil, let combo = entry.panelKey {
                    pendingKeys.append((incoming.identifier, combo))
                }
            }
        }

        // Panel shortcuts last, skipping reserved keys and duplicates.
        for pending in pendingKeys {
            guard var workflow = store.workflow(identifier: pending.identifier),
                  WorkflowPanelKeys.conflict(for: pending.combo, excluding: workflow.id) == nil else { continue }
            workflow.panelKey = pending.combo
            store.save(workflow)
        }
    }

    private func copyIcon(for workflow: Workflow, from icons: URL, fm: FileManager) {
        guard !workflow.iconURL.isEmpty else { return }
        let source = icons.appendingPathComponent(workflow.identifier + ".png")
        let target = WorkflowIcon.fileURL(for: workflow.identifier)
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else { return }
        try? fm.copyItem(at: source, to: target)
    }

    // MARK: - Helpers

    private static func makeWorkDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppPad-Backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
