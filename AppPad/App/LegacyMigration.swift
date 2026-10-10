import Foundation

// One-time import of settings and data from the old AppsPad bundle ids.
// Must run before anything touches UserDefaults or AppEnvironment.supportDirectory.
// Old data is copied, never moved or deleted.
enum LegacyMigration {
    private static let doneKey = "legacyMigration.appsPad.done"

    // new bundle id → old bundle id
    private static let legacyIDs: [String: String] = [
        "com.youmindhub.apppad": "com.youmindhub.appspad",
        "com.youmindhub.devapppad": "com.youmindhub.devappspad",
    ]

    static func runIfNeeded() {
        guard let newID = Bundle.main.bundleIdentifier,
              let oldID = legacyIDs[newID] else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        migrateDefaults(from: oldID, to: newID, defaults: defaults)
        migrateSupportDirectory(from: oldID, to: newID)
        defaults.set(true, forKey: doneKey)
    }

    // Copy old preference keys that don't exist yet in the new domain.
    private static func migrateDefaults(from oldID: String, to newID: String, defaults: UserDefaults) {
        guard let old = defaults.persistentDomain(forName: oldID), !old.isEmpty else { return }
        var copied = 0
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        NSLog("LegacyMigration: copied \(copied) defaults keys from \(oldID)")
    }

    // Copy ~/Library/Application Support/<old id>/ when the new folder is missing or empty.
    private static func migrateSupportDirectory(from oldID: String, to newID: String) {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDir = base.appendingPathComponent(oldID, isDirectory: true)
        let newDir = base.appendingPathComponent(newID, isDirectory: true)

        guard fm.fileExists(atPath: oldDir.path) else { return }
        if fm.fileExists(atPath: newDir.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: newDir.path)) ?? []
            guard contents.filter({ $0 != ".DS_Store" }).isEmpty else { return }
            try? fm.removeItem(at: newDir)
        }
        do {
            try fm.copyItem(at: oldDir, to: newDir)
            NSLog("LegacyMigration: copied support folder from \(oldID)")
        } catch {
            NSLog("LegacyMigration: support folder copy failed: \(error)")
        }
    }
}
