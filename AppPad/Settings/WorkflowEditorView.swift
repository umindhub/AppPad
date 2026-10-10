import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Names from `shortcuts list` for the Shortcut step picker.
enum ShortcutsCatalog {
    static func names() async -> [String] {
        let out = await ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 10)
        return out.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

// Sheet: edit a draft; nothing is stored until Save (grants excepted, they apply to saved workflows).
struct WorkflowEditorView: View {
    let isNew: Bool
    let onSave: (Workflow) -> Void
    let onCancel: () -> Void

    @ObservedObject private var grants = PermissionStore.shared
    @State private var draft: Workflow
    @State private var shortcutNames: [String] = []
    @State private var secretNames: [String] = []
    @State private var detectNote: String?

    init(workflow: Workflow, isNew: Bool, onSave: @escaping (Workflow) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: workflow)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                generalSection
                noticeSection
                stepsSection
                permissionsSection
                authorizationSection
                if !draft.validationErrors.isEmpty {
                    Section {
                        ForEach(draft.validationErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(normalized(draft)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 580, height: 680)
        .task {
            secretNames = KeychainSecrets.names()
            shortcutNames = await ShortcutsCatalog.names()
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            LabeledContent("Icon") {
                HStack(spacing: 10) {
                    Image(nsImage: WorkflowIcon.image(for: draft))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                    Button("Choose Image…", action: chooseIcon)
                    if draft.icon != nil {
                        Button("Use Default") { draft.icon = nil }
                    }
                }
            }
            TextField("Name", text: $draft.name)
            Toggle("Enabled", isOn: $draft.enabled)
            LabeledContent("Shortcut in Workflow panel") {
                VStack(alignment: .trailing, spacing: 2) {
                    ShortcutRecorder(combo: $draft.panelKey)
                        .frame(width: 170, height: 24)
                    if let conflict = WorkflowPanelKeys.conflict(for: draft.panelKey, excluding: draft.id) {
                        Text(verbatim: conflict)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Text(isNew ? LocalizedStringKey("New Workflow") : LocalizedStringKey("Workflow"))
        } footer: {
            Text("The shortcut works only while the Workflow panel is open. ⌘1–⌘0 always run the row with that number.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Notifications

    private var noticeSection: some View {
        Section {
            Picker("When it succeeds", selection: $draft.successNotice) {
                Text("Show the result").tag(SuccessNotice.output)
                Text("Show a custom message").tag(SuccessNotice.custom)
                Text("No notification").tag(SuccessNotice.none)
            }
            if draft.successNotice == .custom {
                TextField("Message", text: $draft.successMessage, prompt: Text("Done: {{output}}"))
            }
            Toggle("Also copy the result to the clipboard", isOn: $draft.copyOutput)
            Picker("When it fails", selection: $draft.failureNotice) {
                Text("Show the error").tag(FailureNotice.error)
                Text("Show a custom message").tag(FailureNotice.custom)
            }
            if draft.failureNotice == .custom {
                TextField("Message", text: $draft.failureMessage, prompt: Text("Failed: {{error}}"))
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("{{output}} is replaced by the final output, {{error}} by the error. Runs started from Settings show the result window instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Section {
            // Element bindings + id-based actions (index bindings crash after a delete).
            ForEach($draft.steps) { $step in
                let index = draft.steps.firstIndex { $0.id == step.id } ?? 0
                StepEditor(
                    step: $step,
                    number: index + 1,
                    canMoveUp: index > 0,
                    canMoveDown: index < draft.steps.count - 1,
                    shortcutNames: shortcutNames,
                    onMoveUp: { moveStep(step.id, by: -1) },
                    onMoveDown: { moveStep(step.id, by: 1) },
                    onDelete: { draft.steps.removeAll { $0.id == step.id } }
                )
            }
            Menu("Add Step") {
                ForEach(WorkflowStepKind.allCases, id: \.self) { kind in
                    Button {
                        draft.steps.append(WorkflowStep(kind: kind))
                    } label: {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            }
            .fixedSize()
        } header: {
            Text("Steps")
        } footer: {
            Text("Steps run in order and stop at the first failure. Each step gets the previous output: stdin and $APPPAD_INPUT for shell, argv for AppleScript (on run argv), {{input}} in HTTP fields.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Declared permissions

    private var permissionsSection: some View {
        Section {
            ValueListEditor(title: "Read access", values: $draft.permissions.fileRead,
                            placeholder: "~/Projects", choose: chooseFiles)
            ValueListEditor(title: "Read and write access", values: $draft.permissions.fileWrite,
                            placeholder: "~/.Trash", choose: chooseFiles)
            Toggle(isOn: $draft.permissions.network) {
                Text("Network access")
                Text("Scripts may connect anywhere (curl, git, gh…).")
            }
            Toggle(isOn: $draft.permissions.systemServices) {
                Text("System services")
                Text("open, pbcopy, say, launching apps… Always on for AppleScript.")
            }
            ValueListEditor(title: "Control apps (Apple Events)", values: $draft.permissions.appleEvents,
                            placeholder: "com.apple.finder", display: AppLookup.name(forBundleID:), choose: chooseApps)
            ValueListEditor(title: "HTTP hosts", values: $draft.permissions.httpHosts, placeholder: "api.github.com")
            if draft.usesHTTP {
                if secretNames.isEmpty {
                    LabeledContent("Secrets") {
                        Text("None yet (add in Workflows › Secrets)").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(secretNames, id: \.self) { name in
                        Toggle(isOn: secretBinding(name)) {
                            Text("Use secret “\(name)”")
                        }
                    }
                }
            }
            HStack {
                Button("Detect from Steps", action: detect)
                if let detectNote {
                    Text(detectNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        } header: {
            Text("Declared Permissions")
        } footer: {
            Text("Shell and AppleScript steps run in a macOS sandbox that only allows what is declared and granted here. HTTP steps may only contact declared hosts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grants

    private var authorizationSection: some View {
        Section {
            if isNew {
                Text("Choose after saving, or answer the prompt on the first run.")
                    .foregroundStyle(.secondary)
            } else if draft.requiredPermissions.isEmpty {
                Text("This workflow needs no permissions.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.requiredPermissions) { item in
                    Picker(item.title, selection: decisionBinding(item)) {
                        Text("Ask Every Time").tag(PermissionDecision?.none)
                        Text("Always Allow").tag(PermissionDecision?.some(.allow))
                        Text("Don't Allow").tag(PermissionDecision?.some(.deny))
                    }
                }
            }
        } header: {
            Text("Authorization")
        }
    }

    // MARK: - Helpers

    private func decisionBinding(_ item: PermissionItem) -> Binding<PermissionDecision?> {
        let id = draft.id
        return Binding(
            get: { grants.decision(for: item, workflow: id) },
            set: { grants.set($0, for: [item], workflow: id) }
        )
    }

    private func moveStep(_ id: UUID, by offset: Int) {
        guard let from = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard draft.steps.indices.contains(to) else { return }
        draft.steps.swapAt(from, to)
    }

    private func secretBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { draft.permissions.secrets.contains(name) },
            set: { on in
                draft.permissions.secrets.removeAll { $0 == name }
                if on { draft.permissions.secrets.append(name) }
            }
        )
    }

    private func detect() {
        let suggestion = PermissionSuggester.suggest(for: draft)
        draft.permissions = suggestion.permissions
        detectNote = suggestion.added.isEmpty
            ? String(localized: "Nothing new found.")
            : String(localized: "Added: \(suggestion.added.joined(separator: ", "))")
    }

    private func normalized(_ workflow: Workflow) -> Workflow {
        var w = workflow
        w.name = w.name.trimmingCharacters(in: .whitespaces)
        func clean(_ list: [String]) -> [String] {
            var seen = Set<String>()
            return list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        w.permissions.fileRead = clean(w.permissions.fileRead)
        w.permissions.fileWrite = clean(w.permissions.fileWrite)
        w.permissions.appleEvents = clean(w.permissions.appleEvents)
        w.permissions.httpHosts = clean(w.permissions.httpHosts.map { $0.lowercased() })
        return w
    }

    // Any image → 512×512 PNG stored in the workflow (travels with export / import).
    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = WorkflowIcon.makePNG(from: url) {
            draft.icon = data
        } else {
            NSSound.beep()
        }
    }

    private func chooseFiles() -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { PermissionItem.displayPath($0.path) }
    }

    private func chooseApps() -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}

// MARK: - Step editor

private struct StepEditor: View {
    @Binding var step: WorkflowStep
    let number: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let shortcutNames: [String]
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: step.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(verbatim: "\(number). \(step.kind.title)")
                    .font(.headline)
                Spacer()
                Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .help(Text("Move Up"))
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .help(Text("Move Down"))
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .help(Text("Remove Step"))
            }
            .buttonStyle(.borderless)

            content

            if step.kind != .builtin || step.builtin == .emptyTrash {
                Stepper(value: $step.timeout, in: 5...3600, step: 5) {
                    Text("Timeout: \(Int(step.timeout)) s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch step.kind {
        case .shell:
            Text("zsh, runs sandboxed. Input on stdin and $APPPAD_INPUT.")
                .font(.caption)
                .foregroundStyle(.secondary)
            CodeEditorBox(text: $step.script)
        case .appleScript:
            Picker("Language", selection: $step.language) {
                Text("AppleScript").tag(ScriptLanguage.appleScript)
                Text("JavaScript").tag(ScriptLanguage.javaScript)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            CodeEditorBox(text: $step.script)
        case .shortcut:
            HStack {
                TextField("Shortcut name", text: $step.shortcutName)
                Menu {
                    if shortcutNames.isEmpty {
                        Text("No shortcuts found")
                    }
                    ForEach(shortcutNames, id: \.self) { name in
                        Button(name) { step.shortcutName = name }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        case .http:
            HStack {
                Picker("Method", selection: $step.http.method) {
                    ForEach(HTTPMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                // Grouped Form shows a TextField title as a leading label; the sample URL belongs in prompt.
                TextField("URL", text: $step.http.url,
                          prompt: Text(verbatim: "https://api.example.com/path"))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
            }
            Text("Headers, one per line (Name: Value). Use {{secret:NAME}} for tokens.")
                .font(.caption)
                .foregroundStyle(.secondary)
            CodeEditorBox(text: $step.http.headers, minHeight: 60)
            if step.http.method != .GET {
                Text("Body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CodeEditorBox(text: $step.http.body, minHeight: 60)
            }
        case .builtin:
            Picker("Action", selection: $step.builtin) {
                ForEach(BuiltinAction.allCases, id: \.self) { action in
                    Label(action.title, systemImage: action.symbolName).tag(action)
                }
            }
        }
    }
}

// MARK: - List editor

// Editable list of strings (paths, bundle ids, hosts) with an optional chooser.
private struct ValueListEditor: View {
    let title: LocalizedStringKey
    @Binding var values: [String]
    var placeholder: String
    var display: ((String) -> String)? = nil
    var choose: (() -> [String])? = nil
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            ForEach(values, id: \.self) { value in
                HStack {
                    Text(verbatim: display?(value) ?? value)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let display, display(value) != value {
                        Text(verbatim: value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        values.removeAll { $0 == value }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField(placeholder, text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                if let choose {
                    Button("Choose…") {
                        for value in choose() where !values.contains(value) { values.append(value) }
                    }
                }
            }
        }
    }

    private func add() {
        let value = newValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        if !values.contains(value) { values.append(value) }
        newValue = ""
    }
}
