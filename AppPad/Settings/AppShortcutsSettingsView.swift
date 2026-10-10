import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Settings → App Shortcuts tab: per-app global hotkeys (Raycast style).
struct AppShortcutsSettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                if prefs.appHotKeys.isEmpty {
                    Text("No app shortcuts yet. Add an app, or right-click an app in AppPad › Set Shortcut….")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($prefs.appHotKeys) { $item in
                        row(for: $item)
                    }
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Text("\(assignedCount) of \(prefs.appHotKeys.count) assigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                HStack {
                    Text("Press the shortcut to open or focus the app; press again while it is in front to hide it. Click a field to record, Delete clears, Esc cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Add App…", action: addApps)
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var assignedCount: Int {
        prefs.appHotKeys.filter { $0.combo != nil }.count
    }

    private func row(for item: Binding<AppHotKey>) -> some View {
        let value = item.wrappedValue
        let conflict = conflictName(for: value)
        let missing = AppActivator.resolveURL(value) == nil
        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: value.path))
                .resizable()
                .frame(width: 22, height: 22)
                .opacity(missing ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.name)
                    .lineLimit(1)
                if missing {
                    Text("App not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let conflict {
                    Text("Same shortcut as \(conflict)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if conflict != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text("Only one of them will work."))
            }
            ShortcutRecorder(combo: item.combo)
                .frame(width: 150, height: 22)
            Button {
                prefs.appHotKeys.removeAll { $0.key == value.key }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(Text("Remove"))
        }
    }

    // Name of the first other owner of the same key + modifiers, if any.
    private func conflictName(for item: AppHotKey) -> String? {
        prefs.conflictName(for: item.combo, excluding: .app(item.key))
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        var added = prefs.appHotKeys
        for url in panel.urls {
            let key = Bundle(url: url)?.bundleIdentifier ?? url.path
            guard !added.contains(where: { $0.key == key }) else { continue }
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            added.append(AppHotKey(key: key, path: url.path, name: name, combo: nil))
        }
        // Single assignment → one save / one hotkey re-registration.
        if added.count != prefs.appHotKeys.count { prefs.appHotKeys = added }
    }
}
