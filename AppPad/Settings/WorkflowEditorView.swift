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
    @State private var iconPreview: NSImage?      // downloaded from draft.iconURL, not saved yet
    @State private var iconStatus: String?
    @State private var loadingIcon = false
    private let savedIconURL: String
    @State private var keywordText: String
    @State private var localizedKeywordText: [String: String]   // per language, edited as text

    init(workflow: Workflow, isNew: Bool, onSave: @escaping (Workflow) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: workflow)
        savedIconURL = workflow.iconURL
        _keywordText = State(initialValue: workflow.keywords.joined(separator: ", "))
        _localizedKeywordText = State(initialValue: workflow.localizations.mapValues { $0.keywords.joined(separator: ", ") })
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                generalSection
                argumentSection
                languagesSection
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
                    .disabled(!canSave)
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
            VStack(alignment: .leading, spacing: 2) {
                TextField("ID", text: $draft.identifier, prompt: Text(verbatim: "com.example.my-workflow"))
                    .font(.system(.body, design: .monospaced))
                if let identifierError {
                    Text(verbatim: identifierError).font(.caption).foregroundStyle(.orange)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                TextField("Version", text: $draft.version, prompt: Text(verbatim: "1.0"))
                    .font(.system(.body, design: .monospaced))
                if let versionError {
                    Text(verbatim: versionError).font(.caption).foregroundStyle(.orange)
                }
            }
            TextField("Name", text: $draft.name)
            TextField("Description", text: $draft.summary, axis: .vertical)
                .lineLimit(1...4)
            VStack(alignment: .leading, spacing: 2) {
                // Own text state: rebuilding the list on each keystroke would eat the comma being typed.
                TextField("Keywords", text: $keywordText, prompt: Text(verbatim: "shutdown, poweroff"))
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: keywordText) { _, text in draft.keywords = Workflow.cleanKeywords([text]) }
                Text("Separate keywords with commas or spaces. An exact keyword ranks the workflow first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Group", text: $draft.group, prompt: Text("None"))
            LabeledContent("Icon") {
                HStack(spacing: 10) {
                    Image(nsImage: iconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                    Button("Choose Image…", action: chooseIcon)
                    if draft.icon != nil || !draft.iconURL.isEmpty {
                        Button("Use Default") {
                            draft.icon = nil
                            draft.iconURL = ""
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    TextField("Icon URL", text: $draft.iconURL, prompt: Text(verbatim: "https://example.com/icon.png"))
                        .onSubmit(loadIcon)
                    if loadingIcon {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Load", action: loadIcon)
                            .disabled(!WorkflowIdentity.isValidIconURL(draft.iconURL))
                    }
                }
                if let iconURLError {
                    Text(verbatim: iconURLError).font(.caption).foregroundStyle(.orange)
                } else if let iconStatus {
                    Text(verbatim: iconStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: draft.iconURL) { _, _ in
                iconPreview = nil
                iconStatus = nil
            }
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
            VStack(alignment: .leading, spacing: 4) {
                Text("The ID is unique. Importing a workflow with the same ID and a higher version replaces this one; the icon URL is downloaded and stored with the ID.")
                Text("The shortcut works only while the Workflow panel is open. ⌘1–⌘0 always run the row with that number.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Argument

    private var argumentSection: some View {
        Section {
            Picker("Argument", selection: $draft.argument) {
                Text("None").tag(ArgumentMode.off)
                Text("Optional").tag(ArgumentMode.optional)
                Text("Required").tag(ArgumentMode.required)
            }
            if draft.argument != .off {
                Picker("Type", selection: $draft.argumentType) {
                    Text("Text").tag(ArgumentType.text)
                    Text("Duration (→ seconds)").tag(ArgumentType.duration)
                    Text("Time of day (→ HH:mm)").tag(ArgumentType.time)
                    Text("Number").tag(ArgumentType.number)
                    Text("Reminder (date, !priority, @list)").tag(ArgumentType.reminder)
                }
                TextField("Hint", text: $draft.argumentHint, prompt: Text(verbatim: "minutes"))
                let examples = WorkflowArguments.examples(for: draft.argumentType)
                if !examples.isEmpty {
                    let word = draft.keyword.isEmpty ? draft.name : draft.keyword
                    LabeledContent("Examples") {
                        Text(verbatim: examples.map { "\(word) \($0)" }.joined(separator: "   "))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Argument")
        } footer: {
            Text("In the Workflow panel only the text before the first space is searched; the rest is the argument. It is parsed by its type and becomes the first step’s input ({{input}}, $APPPAD_INPUT, stdin, argv). Apps ignore it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Languages

    private var languagesSection: some View {
        Section {
            ForEach(draft.localizations.keys.sorted(), id: \.self) { code in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(verbatim: WorkflowLanguage.displayName(code))
                            .font(.headline)
                        Text(verbatim: code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            draft.localizations[code] = nil
                            localizedKeywordText[code] = nil
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Remove Language"))
                    }
                    TextField("Name", text: localizedBinding(code, \.name), prompt: Text(verbatim: draft.name))
                    TextField("Description", text: localizedBinding(code, \.summary),
                              prompt: Text(verbatim: draft.summary), axis: .vertical)
                        .lineLimit(1...4)
                    if draft.argument != .off {
                        TextField("Hint", text: localizedBinding(code, \.argumentHint),
                                  prompt: Text(verbatim: draft.argumentHint))
                    }
                    TextField("Keywords", text: localizedKeywordBinding(code),
                              prompt: Text(verbatim: draft.keywords.joined(separator: ", ")))
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.vertical, 2)
            }
            let missing = WorkflowLanguage.editable.filter { draft.localizations[$0] == nil }
            Menu("Add Language") {
                ForEach(missing, id: \.self) { code in
                    Button(WorkflowLanguage.displayName(code)) {
                        draft.localizations[code] = WorkflowLocalization()
                    }
                }
            }
            .fixedSize()
            .disabled(missing.isEmpty)
        } header: {
            Text("Languages")
        } footer: {
            Text("Name and Description above are English, the default language. Empty translated fields fall back to English. Keywords of the current language and the English ones both work.")
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

    // MARK: - Validation

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && identifierError == nil && versionError == nil && iconURLError == nil
    }

    private var identifierError: String? {
        let id = WorkflowIdentity.normalizeIdentifier(draft.identifier)
        if id.isEmpty { return String(localized: "Enter an ID first, e.g. com.example.my-workflow.") }
        if !WorkflowIdentity.isValidIdentifier(id) {
            return String(localized: "Use a reverse-DNS ID: lowercase letters, digits and “-”, separated by dots.")
        }
        if WorkflowStore.shared.isIdentifierTaken(id, excluding: draft.id) {
            return String(localized: "Another workflow already uses this ID.")
        }
        return nil
    }

    private var versionError: String? {
        WorkflowIdentity.isValidVersion(draft.version.trimmingCharacters(in: .whitespaces))
            ? nil : String(localized: "Use a version like 1.0 or 1.2.3.")
    }

    private var iconURLError: String? {
        let url = draft.iconURL.trimmingCharacters(in: .whitespaces)
        if url.isEmpty || WorkflowIdentity.isValidIconURL(url) { return nil }
        return String(localized: "The icon URL must start with https://.")
    }

    // Preview: freshly loaded URL image, else what is stored (the downloaded file only matches the saved URL).
    private var iconImage: NSImage {
        if let iconPreview { return iconPreview }
        var shown = draft
        if draft.iconURL != savedIconURL { shown.iconURL = "" }
        return WorkflowIcon.image(for: shown)
    }

    // MARK: - Helpers

    private func localizedBinding(_ code: String, _ field: WritableKeyPath<WorkflowLocalization, String>) -> Binding<String> {
        Binding(
            get: { draft.localizations[code]?[keyPath: field] ?? "" },
            set: { value in
                var entry = draft.localizations[code] ?? WorkflowLocalization()
                entry[keyPath: field] = value
                draft.localizations[code] = entry
            }
        )
    }

    private func localizedKeywordBinding(_ code: String) -> Binding<String> {
        Binding(
            get: { localizedKeywordText[code] ?? "" },
            set: { text in
                localizedKeywordText[code] = text
                var entry = draft.localizations[code] ?? WorkflowLocalization()
                entry.keywords = Workflow.cleanKeywords([text])
                draft.localizations[code] = entry
            }
        )
    }

    private func loadIcon() {
        let url = draft.iconURL.trimmingCharacters(in: .whitespaces)
        guard WorkflowIdentity.isValidIconURL(url), !loadingIcon else { return }
        loadingIcon = true
        iconStatus = nil
        Task {
            let png = await WorkflowIcon.fetchPNG(from: url)
            loadingIcon = false
            guard draft.iconURL.trimmingCharacters(in: .whitespaces) == url else { return }
            if let png, let image = NSImage(data: png) {
                iconPreview = image
                draft.icon = nil
                iconStatus = String(localized: "Loaded. It is stored when you save.")
            } else {
                iconStatus = String(localized: "Could not load an image from this URL.")
            }
        }
    }

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
        w.identifier = WorkflowIdentity.normalizeIdentifier(w.identifier)
        w.version = w.version.trimmingCharacters(in: .whitespaces)
        w.keywords = Workflow.cleanKeywords(w.keywords)
        w.group = w.group.trimmingCharacters(in: .whitespaces)
        w.argumentHint = w.argumentHint.trimmingCharacters(in: .whitespaces)
        w.summary = w.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        w.iconURL = w.iconURL.trimmingCharacters(in: .whitespaces)
        w.localizations = w.localizations.compactMapValues { entry in
            let cleaned = WorkflowLocalization(name: entry.name.trimmingCharacters(in: .whitespaces),
                                               summary: entry.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                                               argumentHint: entry.argumentHint.trimmingCharacters(in: .whitespaces),
                                               keywords: Workflow.cleanKeywords(entry.keywords))
            return cleaned.isEmpty ? nil : cleaned
        }
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
    // The last one set wins: choosing a file clears the icon URL.
    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = WorkflowIcon.makePNG(from: url) {
            draft.iconURL = ""
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
            TextField("Input", text: $step.shortcutInput, prompt: Text(verbatim: "{{input}}"))
                .font(.system(.body, design: .monospaced))
            Text("Sent to the shortcut. Empty = the step input; {{input}} inserts it, \\n starts a new line.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if step.builtin == .openURL {
                TextField("URL", text: $step.url,
                          prompt: Text(verbatim: "https://www.google.com/search?q={{input}}"))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
                Text("{{input}} is replaced by the argument (URL-encoded).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if step.builtin.usesInput {
                Text("Uses the step input (the panel argument for the first step).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
