import Foundation
import UniformTypeIdentifiers

// Parts of AppPad a backup can hold (raw values are stored in manifest.json).
nonisolated enum BackupSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case shortcuts, layout, workflows, clipboardHistory, clipboardSaved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: return String(localized: "App Shortcuts")
        case .layout: return String(localized: "AppPad Layout", table: "Settings")
        case .workflows: return String(localized: "Workflows")
        case .clipboardHistory: return String(localized: "Clipboard History", table: "Settings")
        case .clipboardSaved: return String(localized: "Saved items")
        }
    }

    var detail: String {
        switch self {
        case .shortcuts:
            return String(localized: "Per-app shortcuts, plus the Workflows, Clipboard and window shortcuts.", table: "Settings")
        case .layout:
            return String(localized: "Pages, folders, app positions and grid size.", table: "Settings")
        case .workflows:
            return String(localized: "Installed workflows with their icons, panel shortcuts and on/off state.", table: "Settings")
        case .clipboardHistory:
            return String(localized: "Copied text, images and files.", table: "Settings")
        case .clipboardSaved:
            return String(localized: "The saved clipboard library.", table: "Settings")
        }
    }

    var isClipboard: Bool { self == .clipboardHistory || self == .clipboardSaved }
}

nonisolated enum BackupImportMode: String, CaseIterable, Identifiable, Sendable {
    case merge, replace
    var id: String { rawValue }
}

// manifest.json at the archive root.
nonisolated struct BackupManifest: Codable, Sendable {
    static let currentFormat = 1
    static let fileName = "manifest.json"

    var format: Int
    var appVersion: String
    var bundleID: String
    var createdAt: Date
    var sections: [String]          // BackupSection raw values (unknown ones are ignored)
    var counts: [String: Int]       // section raw value → item count

    var knownSections: [BackupSection] {
        BackupSection.allCases.filter { sections.contains($0.rawValue) }
    }

    func count(_ section: BackupSection) -> Int? {
        counts[section.rawValue]
    }
}

// shortcuts.json. A missing combo means "cleared by the user".
nonisolated struct ShortcutsBackup: Codable, Sendable {
    var appHotKeys: [AppHotKey]
    var workflowPanel: KeyCombo?
    var clipboard: KeyCombo?
    var clipboardSaved: KeyCombo?
    var windowActions: [String: KeyCombo]   // WindowAction raw value → combo
}

// layout.json: grid size travels with the pages so positions match.
nonisolated struct LayoutBackup: Codable, Sendable {
    var gridColumns: Int
    var gridRows: Int
    var layout: Layout
}

// workflows.json: portable workflow (no local uid) + local state.
// source: missing in backups made before sources existed.
nonisolated struct WorkflowBackupEntry: Codable, Sendable {
    var workflow: Workflow
    var enabled: Bool
    var panelKey: KeyCombo?
    var source: WorkflowSource?
}

nonisolated enum BackupError: LocalizedError {
    case notABackup
    case unsupportedFormat(Int)
    case unsafeArchive
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notABackup:
            return String(localized: "This file is not an AppPad backup.", table: "Settings")
        case .unsupportedFormat(let version):
            return String(localized: "This backup was made by a newer version of AppPad (format \(version)). Update AppPad to restore it.", table: "Settings")
        case .unsafeArchive:
            return String(localized: "This backup contains invalid file paths and was not opened.", table: "Settings")
        case .archiveFailed(let message):
            return String(localized: "The backup file could not be processed: \(message)", table: "Settings")
        }
    }
}

// A backup unpacked into a temp folder, waiting for the user to pick what to restore.
struct OpenedBackup: Identifiable {
    let id = UUID()
    let fileName: String
    let manifest: BackupManifest
    let root: URL          // unpacked contents
    let workDirectory: URL // removed on discard
}

// What a restore did, for the summary alert.
struct BackupReport {
    var shortcuts: Int?
    var layoutRestored = false
    var workflowsAdded = 0
    var workflowsUpdated = 0
    var workflowsRemoved = 0
    var workflowsSkipped = 0
    var restoredWorkflows = false
    var clipboardAdded = 0
    var clipboardExisting = 0
    var restoredClipboard = false

    var lines: [String] {
        var result: [String] = []
        if let shortcuts {
            result.append(String(localized: "App Shortcuts: \(shortcuts) restored", table: "Settings"))
        }
        if layoutRestored {
            result.append(String(localized: "AppPad Layout: restored", table: "Settings"))
        }
        if restoredWorkflows {
            result.append(String(localized: "Workflows: \(workflowsAdded) added, \(workflowsUpdated) updated, \(workflowsRemoved) removed, \(workflowsSkipped) unchanged", table: "Settings"))
        }
        if restoredClipboard {
            result.append(String(localized: "Clipboard: \(clipboardAdded) added, \(clipboardExisting) already present", table: "Settings"))
        }
        return result
    }
}

extension UTType {
    // .apppadbackup = gzipped tar; dynamic type from the extension (no Info.plist declaration needed).
    nonisolated static var appPadBackup: UTType {
        UTType(filenameExtension: BackupArchive.fileExtension, conformingTo: .data) ?? .data
    }
}
