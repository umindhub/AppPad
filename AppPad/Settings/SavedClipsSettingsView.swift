import SwiftUI
import AppKit

// Opens Settings › Saved Clips on one item (⌘↩ in the Clipboard panel).
// The id is kept until the tab consumes it: on appear, or at once if the tab is already showing.
@MainActor
enum SavedClipsNavigator {
    static let didRequest = Notification.Name("AppPad.savedClipsRevealRequest")
    static var pendingID: Int64?

    static func reveal(_ id: Int64) {
        pendingID = id
        UserDefaults.standard.set(SettingsTab.savedClips.rawValue, forKey: SettingsTab.storageKey)
        NotificationCenter.default.post(name: didRequest, object: nil)
    }
}

// Full text of one item, edited in a sheet.
private struct ClipContentDraft: Identifiable {
    let id: Int64
    let name: String?
    let text: String
}

// Settings → Saved Clips: browse, search, rename, edit, copy and remove saved clipboard items.
// Names are stored on the clip row and searched by the Clipboard panel too.
struct SavedClipsSettingsView: View {
    @ObservedObject var prefs: Preferences
    var store: ClipboardStore?
    @State private var query = ""
    @State private var items: [ClipSummary] = []
    @State private var total = 0
    @State private var pendingRemove: ClipSummary?
    @State private var highlightID: Int64?
    @State private var copiedID: Int64?
    @State private var editingContent: ClipContentDraft?
    @FocusState private var focusedID: Int64?

    private static let limit = 2000
    // Same insets as App Shortcuts: search bar lines up with the grouped cards.
    private static let formInset: CGFloat = 24
    private static let formCardMaxWidth: CGFloat = 704

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                searchBar
                form
                    .contentMargins(.horizontal, Self.formInset, for: .scrollContent)
            }
            .onAppear {
                reload()
                consumeReveal(proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: SavedClipsNavigator.didRequest)) { _ in
                consumeReveal(proxy)
            }
        }
        .onChange(of: query) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardStoreDidChange)) { _ in reload() }
        .sheet(item: $editingContent) { draft in
            ClipContentEditor(draft: draft) { saveContent(draft.id, text: $0) }
        }
        .alert("Remove from Saved?", isPresented: Binding(
            get: { pendingRemove != nil },
            set: { if !$0 { pendingRemove = nil } }
        ), presenting: pendingRemove) { item in
            Button("Remove", role: .destructive) { remove(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Items no longer in the clipboard history are deleted.")
        }
    }

    private var searchBar: some View {
        GlassSearchField(text: $query,
                         placeholder: String(localized: "Search saved items"),
                         isGlass: prefs.glassControls)
            .frame(maxWidth: Self.formCardMaxWidth)
            .frame(height: GlassSearchFieldView.height)
            .padding(.horizontal, Self.formInset)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private var form: some View {
        Form {
            Section {
                if store == nil {
                    Text("The clipboard store could not be opened.")
                        .foregroundStyle(.secondary)
                } else if items.isEmpty {
                    Text(query.isEmpty
                         ? String(localized: "Nothing saved yet — press ⌘S on an item to keep it here")
                         : String(localized: "No Items"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items, id: \.id) { item in
                        SavedClipRow(item: item, store: store, focus: $focusedID,
                                     highlighted: highlightID == item.id,
                                     copied: copiedID == item.id,
                                     onRename: { rename(item, to: $0) },
                                     onCopy: { copy(item) },
                                     onEditContent: { editContent(item) },
                                     onRemove: { pendingRemove = item })
                            .id(item.id)
                    }
                }
            } header: {
                Text("\(total) saved items")
            } footer: {
                Text("Names are searchable here and in the Clipboard panel. Return saves a name, Esc reverts it. Click the text of a text item to edit its content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private func reload() {
        guard let store else {
            items = []
            total = 0
            return
        }
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        items = store.fetch(ClipQuery(scope: .saved, terms: terms, bundleID: nil, limit: Self.limit))
        total = store.savedCount()
    }

    // Clears the search, scrolls to the requested item, flashes it and focuses its name field.
    // Delays: the window may still be activating when Settings was just opened.
    private func consumeReveal(_ proxy: ScrollViewProxy) {
        guard let id = SavedClipsNavigator.pendingID else { return }
        SavedClipsNavigator.pendingID = nil
        if !query.isEmpty { query = "" }
        reload()
        guard items.contains(where: { $0.id == id }) else { return }
        highlightID = id
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            proxy.scrollTo(id, anchor: .center)
            try? await Task.sleep(for: .milliseconds(250))
            focusedID = id
            try? await Task.sleep(for: .seconds(1.5))
            if highlightID == id {
                withAnimation(.easeOut(duration: 0.4)) { highlightID = nil }
            }
        }
    }

    private func rename(_ item: ClipSummary, to name: String) {
        store?.setName(id: item.id, name: name)
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
    }

    // Text items only: images and files have no editable content.
    private func editContent(_ summary: ClipSummary) {
        guard summary.kind == .text, let item = store?.item(id: summary.id) else { return }
        editingContent = ClipContentDraft(id: summary.id, name: item.name, text: item.text ?? "")
    }

    private func saveContent(_ id: Int64, text: String) -> ClipTextUpdate {
        guard let store else { return .failed }
        let result = store.updateText(id: id, text: text)
        if case .updated = result {
            NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        }
        return result
    }

    private func remove(_ item: ClipSummary) {
        store?.remove(id: item.id, from: .saved)
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
    }

    // Puts the item on the pasteboard (images are decoded off the main thread).
    private func copy(_ summary: ClipSummary) {
        guard let store, let item = store.item(id: summary.id) else {
            NSSound.beep()
            return
        }
        if item.kind == .image, let url = store.imageURL(for: item) {
            Task {
                let data = await Task.detached(priority: .medium) { PasteService.imageData(url: url) }.value
                guard let data else {
                    NSSound.beep()
                    return
                }
                finishCopy(item, image: data)
            }
        } else {
            finishCopy(item, image: nil)
        }
    }

    // Like a paste from the panel: the monitor skips our write (source app stays), the item counts as used.
    private func finishCopy(_ item: ClipItem, image: PasteImageData?) {
        let count = PasteService.write(item, image: image)
        NotificationCenter.default.post(name: .clipboardOwnWrite, object: nil, userInfo: ["changeCount": count])
        if let id = item.id { store?.markUsed(id: id) }
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        // Checkmark on the row's copy button for a moment.
        guard let id = item.id else { return }
        copiedID = id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == id { copiedID = nil }
        }
    }
}

// One saved item: source app icon | name + two lines of content | copy, delete, kind (stacked).
private struct SavedClipRow: View {
    let item: ClipSummary
    let store: ClipboardStore?
    var focus: FocusState<Int64?>.Binding
    var highlighted: Bool
    var copied: Bool
    var onRename: (String) -> Void
    var onCopy: () -> Void
    var onEditContent: () -> Void
    var onRemove: () -> Void

    @State private var draft = ""

    private static let iconSize: CGFloat = 40
    private static let actionSize = CGSize(width: 20, height: 16)
    private static let nameRatio: CGFloat = 2.0 / 3.0
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    private var isFocused: Bool { focus.wrappedValue == item.id }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .help(item.sourceName ?? "")
            VStack(alignment: .leading, spacing: 4) {
                // Name field 2/3, date in the rest.
                RatioSplit(ratio: Self.nameRatio) {
                    TextField(String(localized: "Name"), text: $draft, prompt: Text("Add a name"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused(focus, equals: item.id)
                        .onSubmit(commit)
                        .onExitCommand {
                            draft = item.name ?? ""
                            focus.wrappedValue = nil
                        }
                    Text(dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Text(content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .help(item.kind == .text ? String(localized: "Click to edit") : item.snippet)
                    .pointerStyle(item.kind == .text ? .link : nil)
                    .onTapGesture { if item.kind == .text { onEditContent() } }
            }
            // Fixed-size slots: the row height never changes.
            VStack(spacing: 6) {
                Button(action: onCopy) {
                    // Both symbols always laid out, only one visible: same size either way.
                    ZStack {
                        Image(systemName: "doc.on.doc")
                            .opacity(copied ? 0 : 1)
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                            .opacity(copied ? 1 : 0)
                    }
                    .frame(width: Self.actionSize.width, height: Self.actionSize.height)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Copy"))
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .frame(width: Self.actionSize.width, height: Self.actionSize.height)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Remove from Saved"))
                Image(systemName: Self.kindSymbol(item.kind))
                    .foregroundStyle(Self.kindColor(item.kind))
                    .frame(width: Self.actionSize.width, height: Self.actionSize.height)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(highlighted ? 0.18 : 0))
                .padding(-6)
        }
        .onAppear { draft = item.name ?? "" }
        .onChange(of: item.name) { _, newName in
            if !isFocused { draft = newName ?? "" }
        }
        .onChange(of: focus.wrappedValue) { oldID, newID in
            if oldID == item.id, newID != item.id { commit() }
        }
        .onDisappear(perform: commit)
    }

    // MARK: - Pieces

    private var appIcon: NSImage {
        SourceAppDirectory.shared.icon(for: item.sourceBundleID, store: store)
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
    }

    private var dateText: String {
        Self.dateFormatter.string(from: Date(timeIntervalSince1970: item.lastUsedAt))
    }

    private var content: String {
        switch item.kind {
        case .text:
            return item.snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        case .image:
            let name = item.snippet.isEmpty ? String(localized: "Image") : item.snippet
            guard let w = item.imageWidth, let h = item.imageHeight else { return name }
            return "\(name)  \(w) × \(h)"
        case .file:
            return item.snippet.split(separator: "\n")
                .map { (String($0) as NSString).lastPathComponent }
                .joined(separator: ", ")
        }
    }

    // Same symbols / colors as the Clipboard panel rows.
    private static func kindSymbol(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private static func kindColor(_ kind: ClipKind) -> Color {
        switch kind {
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        }
    }

    // MARK: - Actions

    // Saves only real changes; the store trims and clears empty names.
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (item.name ?? "") { onRename(trimmed) }
        if draft != trimmed { draft = trimmed }
    }
}

// Sheet editor for a text item's content. Plain text, no smart quotes / dashes (CodeTextView),
// so the pasted result is exactly what was typed. ⌘S / ⌘↩ save and close (↩ inserts a newline), Esc cancels.
private struct ClipContentEditor: View {
    let draft: ClipContentDraft
    var onSave: (String) -> ClipTextUpdate

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    private var canSave: Bool {
        text != draft.text && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Content")
                    .font(.headline)
                if let name = draft.name, !name.isEmpty {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            CodeTextView(text: $text, fontSize: 13)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            HStack(spacing: 10) {
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("\(text.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .help(Text(verbatim: "⌘S  ⌘↩"))
            }
        }
        // ⌘S: always enabled, so it also closes when nothing changed.
        .background {
            Button("", action: saveAndClose)
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(width: 620, height: 440)
        .onAppear { text = draft.text }
        .onChange(of: text) { error = nil }
    }

    // Unchanged → close; empty → beep; otherwise same path as the Save button.
    private func saveAndClose() {
        if text == draft.text {
            dismiss()
        } else if canSave {
            save()
        } else {
            NSSound.beep()
        }
    }

    private func save() {
        guard canSave else { return }
        switch onSave(text) {
        case .updated, .unchanged:
            dismiss()
        case .duplicate:
            error = String(localized: "Another clipboard item already has this content.")
        case .failed:
            error = String(localized: "The content could not be saved.")
        }
    }
}

// Two subviews side by side: the first gets `ratio` of the width, the second the rest.
// Both are vertically centered on the taller one.
private struct RatioSplit: SwiftUI.Layout {
    var ratio: CGFloat
    var spacing: CGFloat = 10

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let first = ((total - spacing) * ratio).rounded()
        return (first, max(0, total - spacing - first))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let total = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 360
        let (a, b) = widths(total)
        var height: CGFloat = 0
        for (view, width) in zip(subviews, [a, b]) {
            let size: CGSize = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            height = max(height, size.height)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        let (a, b) = widths(bounds.width)
        var x = bounds.minX
        for (view, width) in zip(subviews, [a, b]) {
            view.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                       proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}
