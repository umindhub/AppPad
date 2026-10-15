import SwiftUI
import AppKit

// Settings → Windows tab: snap / maximize / restore / move-to-display shortcuts.
struct WindowControlSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var trusted = PasteService.isTrusted

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable window control", isOn: $prefs.windowControlEnabled)
                if !trusted {
                    HStack {
                        Text("Needs Accessibility permission to move and resize windows.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access…") {
                            PasteService.requestAccess()
                            PasteService.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    row(for: action)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                HStack(alignment: .top) {
                    Text("Works on the focused window of the frontmost app. Click a field to record, Delete clears, Esc cancels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Restore Defaults") {
                        prefs.windowHotKeys = WindowAction.defaultCombos
                    }
                }
                .padding(.top, 4)
            }
            .disabled(!prefs.windowControlEnabled)
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = PasteService.isTrusted
        }
        .onAppear { trusted = PasteService.isTrusted }
    }

    private func row(for action: WindowAction) -> some View {
        let conflict = prefs.conflictName(for: prefs.windowHotKeys[action], excluding: .window(action))
        return HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .lineLimit(1)
                if let conflict {
                    Text("Same shortcut as \(conflict)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if conflict != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text("Only one of them will work."))
            }
            ShortcutRecorder(combo: binding(for: action))
                .frame(width: 150, height: 22)
        }
    }

    private func binding(for action: WindowAction) -> Binding<KeyCombo?> {
        Binding(
            get: { prefs.windowHotKeys[action] },
            set: { prefs.windowHotKeys[action] = $0 }
        )
    }
}
