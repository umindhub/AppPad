import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Settings › Backup: export chosen parts to one .apppadbackup file, or restore from one.
struct BackupSettingsView: View {
    private let service = BackupService.shared

    @State private var exportSelection = Set(BackupService.shared.availableSections)
    @State private var isWorking = false
    @State private var lastExport: URL?
    @State private var opened: OpenedBackup?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        Form {
            Section("Back Up") {
                ForEach(service.availableSections) { section in
                    Toggle(isOn: binding(for: section)) {
                        Text(section.title)
                        Text(section.detail)
                    }
                }
                HStack {
                    if let lastExport {
                        Text(lastExport.lastPathComponent)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([lastExport])
                        }
                    }
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                    Button("Export Backup…", action: chooseExport)
                        .disabled(exportSelection.isEmpty || isWorking)
                }
            }

            Section("Restore Backup") {
                HStack {
                    Text("Choose a backup file. You can pick what to restore before anything changes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Import Backup…", action: chooseImport)
                        .disabled(isWorking)
                }
            }

            Section {
                Text("Not included: Keychain secrets used by workflows and “Always Allow” permissions. Restored workflows ask for permission again the first time they run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $opened) { backup in
            BackupImportSheet(backup: backup, isWorking: $isWorking) { sections, mode in
                restore(backup, sections: sections, mode: mode)
            } onCancel: {
                service.discard(backup)
                opened = nil
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func binding(for section: BackupSection) -> Binding<Bool> {
        Binding(
            get: { exportSelection.contains(section) },
            set: { on in
                if on { exportSelection.insert(section) } else { exportSelection.remove(section) }
            }
        )
    }

    // MARK: - Actions

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.appPadBackup]
        panel.nameFieldStringValue = BackupService.suggestedFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let sections = exportSelection
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await service.export(sections, to: url)
                lastExport = url
            } catch {
                present(String(localized: "Backup failed"), error.localizedDescription)
            }
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.appPadBackup]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                opened = try await service.open(url)
            } catch {
                present(String(localized: "Could not open the backup"), error.localizedDescription)
            }
        }
    }

    // Sheet closes first; the summary alert follows once the sheet is gone.
    private func restore(_ backup: OpenedBackup, sections: Set<BackupSection>, mode: BackupImportMode) {
        opened = nil
        isWorking = true
        Task {
            let title: String
            let message: String
            do {
                let report = try await service.restore(backup, sections: sections, mode: mode)
                title = String(localized: "Backup restored")
                message = report.lines.joined(separator: "\n")
            } catch {
                title = String(localized: "Restore failed")
                message = error.localizedDescription
            }
            service.discard(backup)
            isWorking = false
            try? await Task.sleep(for: .milliseconds(350))   // let the sheet finish closing
            present(title, message)
        }
    }

    private func present(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// Sheet shown after a backup file was opened: pick sections and merge / replace.
private struct BackupImportSheet: View {
    let backup: OpenedBackup
    @Binding var isWorking: Bool
    var onRestore: (Set<BackupSection>, BackupImportMode) -> Void
    var onCancel: () -> Void

    @State private var selection: Set<BackupSection> = []
    @State private var mode: BackupImportMode = .merge

    private var sections: [BackupSection] { backup.manifest.knownSections }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restore from Backup")
                    .font(.title3.weight(.semibold))
                Text(backup.fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Created \(backup.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)) with AppPad \(backup.manifest.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sections) { section in
                        Toggle(isOn: binding(for: section)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.title)
                                if let count = backup.manifest.count(section) {
                                    Text("\(count) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Picker("When an item already exists", selection: $mode) {
                    Text("Merge").tag(BackupImportMode.merge)
                    Text("Replace").tag(BackupImportMode.replace)
                }
                .pickerStyle(.segmented)
                Group {
                    switch mode {
                    case .merge:
                        Text("Adds what is missing. Newer workflow versions replace older ones; everything else here stays.")
                            .foregroundStyle(.secondary)
                    case .replace:
                        Text("Current items in the selected parts are removed first and replaced by the backup.")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                if selection.contains(.layout) {
                    Text("The AppPad layout is always replaced. Apps not installed on this Mac are skipped; apps missing from the backup are added at the end.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Restore Backup") { onRestore(selection, mode) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || isWorking)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { selection = Set(sections) }
    }

    private func binding(for section: BackupSection) -> Binding<Bool> {
        Binding(
            get: { selection.contains(section) },
            set: { on in
                if on { selection.insert(section) } else { selection.remove(section) }
            }
        )
    }
}
