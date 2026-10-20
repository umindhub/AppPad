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
    @State private var pendingReplace: [(item: WorkflowImportItem, source: WorkflowSource)] = []   // same version: ask first
    @State private var importNotes: [String] = []                  // shown after the import
    @State private var importReport: String?
    @State private var highlightedID: UUID?                        // built-in revealed from the panel

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                panelSection
                windowSection
                BackgroundSection(settings: $prefs.workflowBackground, allowsFollow: true)
                workflowsSection
                ForEach(groupKeys, id: \.self) { group in
                    groupSection(group)
                }
                secretsSection
            }
            .formStyle(.grouped)
            // ⌘↩ in the Workflow panel (also fires on first appear): open the editor,
            // or for a built-in (not editable) scroll to its row and highlight it.
            .onReceive(store.$pendingEditID) { id in
                guard let id else { return }
                store.pendingEditID = nil
                guard let workflow = store.workflow(id: id) else { return }
                if workflow.isBuiltin {
                    reveal(id, with: proxy)
                } else {
                    edit(workflow, isNew: false)
                }
            }
        }
        .onAppear {
            secretNames = KeychainSecrets.names()
            spotlightConflict = SpotlightShortcut.conflicts(with: prefs.workflowPanelHotKey)
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
            .pillButtons()
        }
        .sheet(item: $shownResult) { result in
            WorkflowResultView(result: result) { shownResult = nil }
                .pillButtons()
        }
        .sheet(item: $editingSecret) { draft in
            SecretEditorView(draft: draft) { saved in
                editingSecret = nil
                if saved { secretNames = KeychainSecrets.names() }
            }
            .pillButtons()
        }
        .confirmationDialog(
            Text("Delete “\(pendingDelete?.displayName ?? "")”?"),
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
        .alert(Text("Replace workflows with the same version?"),
               isPresented: Binding(get: { !pendingReplace.isEmpty }, set: { if !$0 { finishReplace(false) } })) {
            Button("Replace") { finishReplace(true) }
            Button("Skip", role: .cancel) { finishReplace(false) }
        } message: {
            Text(verbatim: pendingReplace.map { "\($0.item.workflow.displayName)  (\($0.item.workflow.identifier) \($0.item.workflow.version))" }
                .joined(separator: "\n"))
        }
        .alert(Text("Some workflows were not imported"),
               isPresented: Binding(get: { importReport != nil }, set: { if !$0 { importReport = nil } })) {
            Button("OK") { importReport = nil }
        } message: {
            Text(verbatim: importReport ?? "")
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
                    Button("Open Keyboard Settings…") { SpotlightShortcut.openKeyboardShortcuts() }
                }
            }
            Toggle("Switch to English input when opened", isOn: $prefs.workflowSwitchToEnglishInput)
        } header: {
            Text("Workflow Panel")
        } footer: {
            Text("The panel lists your workflows and apps. ↩ runs or opens, ⌘1–⌘0 picks a row, ⌘↩ edits the workflow here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Window

    // Follows the Clipboard window by default; off = own width / height.
    private var windowSection: some View {
        Section("Window") {
            Toggle(isOn: $prefs.workflowFollowsClipboardSize) {
                Text("Same as Clipboard")
                Text("Uses the Clipboard window's width, height and position.")
            }
            if !prefs.workflowFollowsClipboardSize {
                PanelPercentSlider(title: "Width", value: $prefs.workflowWidthPercent)
                PanelPercentSlider(title: "Height", value: $prefs.workflowHeightPercent)
            }
        }
    }

    // MARK: - Workflows

    // Named groups after "Workflows" (ungrouped); AppPad's built-in group last.
    private var groupKeys: [String] {
        let groups = Set(store.workflows.map(\.group)).subtracting([""])
        return groups.sorted { a, b in
            if (a == BuiltinWorkflows.group) != (b == BuiltinWorkflows.group) { return b == BuiltinWorkflows.group }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    private func groupSection(_ group: String) -> some View {
        Section {
            ForEach(store.workflows.filter { $0.group == group }) { workflow in
                row(workflow)
            }
        } header: {
            Text(verbatim: BuiltinWorkflows.groupTitle(group))
        } footer: {
            if group == BuiltinWorkflows.group {
                Text("Built-in workflows are updated with AppPad and can’t be edited or deleted. Duplicate one to make your own version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var workflowsSection: some View {
        Section {
            let own = store.workflows.filter { $0.group.isEmpty }
            if own.isEmpty {
                Text("No workflows yet. Add one to run shell scripts, AppleScript, Shortcuts or HTTP requests from the Workflow panel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(own) { workflow in
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
                .menuStyle(.button)   // pill like the buttons next to it
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
                HStack(spacing: 6) {
                    Text(verbatim: workflow.displayName)
                        .lineLimit(1)
                    WorkflowSourcePill(source: workflow.source)
                }
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
                } else {
                    Text(verbatim: (workflow.matchKeywords.isEmpty ? "" : workflow.matchKeywords.joined(separator: ", ") + " · ")
                         + "\(workflow.identifier) · \(workflow.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                rowActions(workflow, last: last)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !workflow.isBuiltin { edit(workflow, isNew: false) }
        }
        .contextMenu { rowActions(workflow, last: last) }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(highlightedID == workflow.id ? 0.18 : 0))
                .padding(-4)
        )
        .id(workflow.id)
    }

    // "…" button and right click. Built-ins can't be edited or deleted: Disable / Enable instead.
    @ViewBuilder
    private func rowActions(_ workflow: Workflow, last: WorkflowRunResult?) -> some View {
        if !workflow.isBuiltin {
            Button("Edit…") { edit(workflow, isNew: false) }
        }
        Button("Duplicate") { store.duplicate(workflow) }
        Button("Export…") { export(workflow) }
        if let last {
            Button("Show Last Result") { shownResult = last }
        }
        Divider()
        if workflow.isBuiltin {
            Button(workflow.enabled ? LocalizedStringKey("Disable") : LocalizedStringKey("Enable")) { setEnabled(!workflow.enabled, for: workflow.id) }
        } else {
            Button("Delete…", role: .destructive) { pendingDelete = workflow }
        }
    }

    private func setEnabled(_ enabled: Bool, for id: UUID) {
        guard var workflow = store.workflow(id: id) else { return }
        workflow.enabled = enabled
        store.save(workflow)
    }

    // Scroll to a row and flash it for a moment (after the window has laid out).
    private func reveal(_ id: UUID, with proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { proxy.scrollTo(id, anchor: .center) }
            highlightedID = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.4)) {
                    if highlightedID == id { highlightedID = nil }
                }
            }
        }
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
        var argument = ""
        if workflow.argument != .off {
            guard let value = askArgument(workflow) else { return }
            argument = value
        }
        Task {
            // Declined confirmation: nothing ran, no result sheet.
            if let result = await runner.run(workflow, trigger: .settings, argument: argument), !result.declined {
                shownResult = result
            }
        }
    }

    // Settings has no search field: ask for the argument (an invalid one shows in the result sheet).
    private func askArgument(_ workflow: Workflow) -> String? {
        let word = workflow.keyword.isEmpty ? workflow.displayName : workflow.keyword
        let hint = workflow.displayArgumentHint.isEmpty ? String(localized: "argument") : workflow.displayArgumentHint
        let examples = WorkflowArguments.examples(for: workflow.argumentType)
        let alert = NSAlert()
        alert.messageText = workflow.displayName
        alert.informativeText = "\(word) ‹\(hint)›" + (examples.isEmpty ? "" : "\n" + examples.map { "\(word) \($0)" }.joined(separator: "   "))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = examples.first ?? hint
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Run"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func importWorkflows() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var notes: [String] = []
        var replace: [(item: WorkflowImportItem, source: WorkflowSource)] = []
        for url in panel.urls {
            let source = WorkflowSource.file(url.lastPathComponent)
            do {
                for item in try store.prepareImport(url) {
                    switch item.action {
                    case .add, .upgrade:
                        store.install(item.workflow, source: source)
                    case .sameVersion:
                        replace.append((item, source))
                    case .older(let installed):
                        notes.append(String(localized: "“\(item.workflow.displayName)” \(item.workflow.version) is older than the installed \(installed.version) and was skipped."))
                    case .reserved:
                        notes.append(String(localized: "“\(item.workflow.displayName)” uses the id of a built-in workflow and was skipped."))
                    }
                }
            } catch let error as WorkflowImportError {
                notes.append(url.lastPathComponent + ": " + (error.errorDescription ?? ""))
            } catch {
                notes.append(String(localized: "Could not import \(url.lastPathComponent)."))
            }
        }
        importNotes = notes
        if replace.isEmpty {
            showImportNotes()
        } else {
            pendingReplace = replace
        }
    }

    private func finishReplace(_ replace: Bool) {
        guard !pendingReplace.isEmpty else { return }
        if replace { pendingReplace.forEach { store.install($0.item.workflow, source: $0.source) } }
        pendingReplace = []
        showImportNotes()
    }

    private func showImportNotes() {
        guard !importNotes.isEmpty else { return }
        let report = importNotes.joined(separator: "\n")
        importNotes = []
        // Let the previous alert finish dismissing first.
        DispatchQueue.main.async { importReport = report }
    }

    private func export(_ workflow: Workflow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = workflow.identifier + ".json"
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

// MARK: - Source pill

// Built-in (green) / Mine (blue) / third-party host or file (orange); "· Edited" once changed.
// Same colors as the panel pill (WorkflowSourceBadgeView); no EDR here.
struct WorkflowSourcePill: View {
    let source: WorkflowSource

    var body: some View {
        let tint = Color(nsColor: source.tint)
        HStack(spacing: 3) {
            Image(systemName: source.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(verbatim: source.label)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color(nsColor: source.ink))   // darker / brighter shade, readable on the fill
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(tint.opacity(0.16)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
        .fixedSize()
        .help(Text(verbatim: source.longLabel))
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
                .pillProminentButton()
                .disabled(!nameIsValid || value.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
