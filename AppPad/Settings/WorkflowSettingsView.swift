import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Settings → Workflows: list, run, shortcuts, import / export, Keychain secrets.
struct WorkflowSettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var store = WorkflowStore.shared
    @ObservedObject private var runner = WorkflowRunner.shared

    @State private var editing: Workflow?
    @State private var editingIsNew = false
    @State private var shownResult: WorkflowRunResult?
    @State private var pendingDelete: Workflow?
    @State private var secretNames: [String] = []
    @State private var editingSecret: SecretDraft?
    @State private var errorMessage: String?
    @State private var spotlightConflict = false

    var body: some View {
        Form {
            panelSection
            workflowsSection
            secretsSection
        }
        .formStyle(.grouped)
        .onAppear {
            secretNames = KeychainSecrets.names()
            spotlightConflict = SpotlightShortcut.conflicts(with: prefs.workflowPanelHotKey)
        }
        // ⌘↩ in the Workflow panel → open that workflow's editor (also fires on first appear).
        .onReceive(store.$pendingEditID) { id in
            guard let id else { return }
            store.pendingEditID = nil
            if let workflow = store.workflow(id: id) { edit(workflow, isNew: false) }
        }
        // The user may free ⌘Space in System Settings while this window stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            spotlightConflict = SpotlightShortcut.conflicts(with: prefs.workflowPanelHotKey)
        }
        .onChange(of: prefs.workflowPanelHotKey) { _, combo in
            spotlightConflict = SpotlightShortcut.conflicts(with: combo)
        }
        .sheet(item: $editing) { workflow in
            WorkflowEditorView(
                workflow: workflow, isNew: editingIsNew,
                onSave: { store.save($0); editing = nil },
                onCancel: { editing = nil }
            )
        }
        .sheet(item: $shownResult) { result in
            WorkflowResultView(result: result) { shownResult = nil }
        }
        .sheet(item: $editingSecret) { draft in
            SecretEditorView(draft: draft) { saved in
                editingSecret = nil
                if saved { secretNames = KeychainSecrets.names() }
            }
        }
        .confirmationDialog(
            Text("Delete “\(pendingDelete?.name ?? "")”?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { workflow in
            Button("Delete", role: .destructive) { store.delete(id: workflow.id) }
        } message: { _ in
            Text("Its permissions are removed too.")
        }
        .alert(Text(errorMessage ?? ""), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        }
    }

    // MARK: - Panel

    private var panelSection: some View {
        Section {
            LabeledContent("Open Workflows") {
                VStack(alignment: .trailing, spacing: 2) {
                    ShortcutRecorder(combo: $prefs.workflowPanelHotKey)
                        .frame(width: 170, height: 24)
                    if let conflict = prefs.conflictName(for: prefs.workflowPanelHotKey, excluding: .workflowPanel) {
                        Text("Same shortcut as \(conflict)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if spotlightConflict {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Spotlight still uses this shortcut, so it opens Spotlight instead of AppPad.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("System Settings › Keyboard › Keyboard Shortcuts › Spotlight: turn off “Show Spotlight search” or give it another shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Keyboard Settings…", action: SpotlightShortcut.openKeyboardShortcuts)
                }
            }
        } header: {
            Text("Workflow Panel")
        } footer: {
            Text("The panel lists your workflows and apps. ↩ runs or opens, ⌘1–⌘0 picks a row, ⌘↩ edits the workflow here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Workflows

    private var workflowsSection: some View {
        Section {
            if store.workflows.isEmpty {
                Text("No workflows yet. Add one to run shell scripts, AppleScript, Shortcuts or HTTP requests from the Workflow panel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.workflows) { workflow in
                    row(workflow)
                }
            }
        } header: {
            Text("Workflows")
        } footer: {
            HStack {
                Text("Scripts run in a sandbox with only the permissions you grant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("Import…", action: importWorkflows)
                Menu("Add") {
                    ForEach(WorkflowTemplate.allCases, id: \.self) { template in
                        Button(template.title) { edit(template.make(), isNew: true) }
                    }
                }
                .fixedSize()
            }
            .padding(.top, 4)
        }
    }

    private func row(_ workflow: Workflow) -> some View {
        let isRunning = runner.running.contains(workflow.id)
        let conflict = WorkflowPanelKeys.conflict(for: workflow.panelKey, excluding: workflow.id)
        let last = runner.lastResults[workflow.id]
        return HStack(spacing: 8) {
            Image(nsImage: WorkflowIcon.image(for: workflow))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: workflow.name)
                    .lineLimit(1)
                if !workflow.enabled {
                    Text("Disabled").font(.caption).foregroundStyle(.secondary)
                } else if let conflict {
                    Text(verbatim: conflict).font(.caption).foregroundStyle(.orange)
                } else if let last, !last.success, !last.cancelled {
                    Button {
                        shownResult = last
                    } label: {
                        Text("Last run failed").font(.caption).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(workflow.enabled ? 1 : 0.5)
            Spacer()
            ShortcutRecorder(combo: panelKeyBinding(workflow.id))
                .frame(width: 140, height: 22)
                .help(Text("Shortcut in the Workflow panel"))
            Button {
                if isRunning {
                    runner.cancel(id: workflow.id)
                } else {
                    run(workflow)
                }
            } label: {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderless)
            .help(isRunning ? Text("Stop") : Text("Run"))
            Menu {
                Button("Edit…") { edit(workflow, isNew: false) }
                Button("Duplicate") { store.duplicate(workflow) }
                Button("Export…") { export(workflow) }
                if let last {
                    Button("Show Last Result") { shownResult = last }
                }
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = workflow }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { edit(workflow, isNew: false) }
    }

    private func panelKeyBinding(_ id: UUID) -> Binding<KeyCombo?> {
        Binding(
            get: { store.workflow(id: id)?.panelKey },
            set: { newValue in
                guard var workflow = store.workflow(id: id) else { return }
                workflow.panelKey = newValue
                store.save(workflow)
            }
        )
    }

    private func edit(_ workflow: Workflow, isNew: Bool) {
        editingIsNew = isNew
        editing = workflow
    }

    private func run(_ workflow: Workflow) {
        Task {
            if let result = await runner.run(workflow, trigger: .settings) {
                shownResult = result
            }
        }
    }

    private func importWorkflows() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                try store.importFile(url)
            } catch {
                errorMessage = String(localized: "Could not import \(url.lastPathComponent).")
            }
        }
    }

    private func export(_ workflow: Workflow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = workflow.name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(workflow, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Secrets

    private var secretsSection: some View {
        Section {
            if secretNames.isEmpty {
                Text("No secrets yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(secretNames, id: \.self) { name in
                HStack {
                    Image(systemName: "key.fill").foregroundStyle(.secondary)
                    Text(verbatim: name).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Replace…") { editingSecret = SecretDraft(name: name, isNew: false) }
                    Button {
                        KeychainSecrets.delete(name)
                        secretNames = KeychainSecrets.names()
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Delete"))
                }
            }
        } header: {
            Text("Secrets")
        } footer: {
            HStack {
                Text("Stored in the Keychain. Use {{secret:NAME}} in HTTP steps; scripts never see them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("Add Secret…") { editingSecret = SecretDraft(name: "", isNew: true) }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Secret editor

struct SecretDraft: Identifiable {
    let id = UUID()
    var name: String
    var isNew: Bool
}

private struct SecretEditorView: View {
    let draft: SecretDraft
    let onDone: (Bool) -> Void
    @State private var name: String
    @State private var value = ""

    init(draft: SecretDraft, onDone: @escaping (Bool) -> Void) {
        self.draft = draft
        self.onDone = onDone
        _name = State(initialValue: draft.name)
    }

    private var nameIsValid: Bool { WorkflowPlaceholders.isValidSecretName(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.isNew ? LocalizedStringKey("Add Secret") : LocalizedStringKey("Replace Secret"))
                .font(.headline)
            Form {
                TextField("Name", text: $name, prompt: Text(verbatim: "github-token"))
                    .disabled(!draft.isNew)
                SecureField("Value", text: $value)
            }
            if !name.isEmpty, !nameIsValid {
                Text("Use letters, digits, “-”, “_” or “.” only.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onDone(KeychainSecrets.set(name, value: value))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!nameIsValid || value.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
