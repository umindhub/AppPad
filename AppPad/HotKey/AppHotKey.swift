import AppKit

// Per-app global shortcut (Raycast style).
nonisolated struct AppHotKey: Codable, Equatable, Identifiable, Sendable {
    var key: String        // bundle id, or path for bundles without one
    var path: String       // last known bundle path
    var name: String
    var combo: KeyCombo?

    var id: String { key }
}

// Opens / focuses / hides apps.
enum AppActivator {
    // Raycast-like toggle: frontmost → hide, otherwise open or bring to front.
    static func toggle(_ hotKey: AppHotKey) {
        if !hotKey.key.hasPrefix("/"),
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: hotKey.key).first,
           running.isActive {
            running.hide()
            return
        }
        guard let url = resolveURL(hotKey) else {
            NSSound.beep()
            return
        }
        open(url)
    }

    static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    // Prefer Launch Services lookup so moved apps still resolve.
    static func resolveURL(_ hotKey: AppHotKey) -> URL? {
        if !hotKey.key.hasPrefix("/"),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hotKey.key) {
            return url
        }
        return FileManager.default.fileExists(atPath: hotKey.path) ? URL(fileURLWithPath: hotKey.path) : nil
    }
}
