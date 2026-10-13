import SwiftUI
import AppKit

// App-wide settings shared by every feature (not tied to one panel).
struct GeneralSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        guard newValue != LoginItem.isEnabled else { return }
                        LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }

            // Shared by AppPad, Clipboard, Workflows and the Settings sidebar.
            Section("Appearance") {
                Toggle(isOn: $prefs.glassControls) {
                    Text("Liquid Glass controls")
                    Text("Applies to search fields and controls in AppPad, Clipboard and Workflows.")
                }
            }

            Section("Keyboard") {
                Toggle(isOn: $prefs.escClearsSearchFirst) {
                    Text("Esc clears the search first")
                    Text("When on, Esc clears the search text first and closes on the next press. When off, Esc closes right away. Applies to AppPad, Clipboard and Workflows.")
                }
            }

            Section("Displays") {
                Toggle(isOn: $prefs.panelsFollowMouseScreen) {
                    Text("Open on the display with the pointer")
                    Text("Applies to AppPad, Clipboard and Workflows. When off, they open on the main display.")
                }
            }
        }
        .formStyle(.grouped)
        // Login item may be toggled from the menu bar while Settings stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
