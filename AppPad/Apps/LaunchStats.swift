import AppKit

// Frecency with exponential half-life decay (default 72 days).
// score_now = score_saved * 0.5^(elapsedDays / halfLife); each launch adds 1.
// Apps seen for the first time get a seed score: common system app 3, other system app 1, installed app 2.
final class LaunchStats: NSObject {
    nonisolated struct Entry: Codable, Sendable {
        var score: Double
        var updatedAt: Date
    }

    nonisolated private struct StoreFile: Codable, Sendable {
        var entries: [String: Entry]
        var seeded: [String]
    }

    // Edit freely: system apps most people open often.
    static let commonSystemApps: Set<String> = [
        "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal",
        "com.apple.Notes", "com.apple.reminders", "com.apple.Photos", "com.apple.Music",
        "com.apple.FaceTime", "com.apple.Maps", "com.apple.AppStore", "com.apple.systempreferences",
        "com.apple.Preview", "com.apple.calculator", "com.apple.Terminal", "com.apple.Passwords",
    ]

    private var entries: [String: Entry] = [:]
    private var seeded = Set<String>()
    private var lastManual: [String: Date] = [:]
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
        if let data = try? Data(contentsOf: fileURL) {
            if let file = try? JSONDecoder().decode(StoreFile.self, from: data) {
                entries = file.entries
                seeded = Set(file.seeded)
            } else if let legacy = try? JSONDecoder().decode([String: Entry].self, from: data) {
                entries = legacy   // v1 format
            }
        }
        // Count launches from anywhere (Dock, Finder, Spotlight...), not only AppPad.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
    }

    private var halfLifeDays: Double {
        Double(max(1, Preferences.shared.frecencyHalfLifeDays))
    }

    static func seedScore(for app: AppInfo) -> Double {
        guard app.isSystem else { return 2 }
        return commonSystemApps.contains(app.bundleID ?? "") ? 3 : 1
    }

    // Give each app a starting score once; never re-seeds after decay or deletion.
    func seedIfNeeded(_ apps: [AppInfo]) {
        let now = Date()
        var changed = false
        for app in apps where !seeded.contains(app.key) {
            seeded.insert(app.key)
            changed = true
            if entries[app.key] == nil {
                entries[app.key] = Entry(score: Self.seedScore(for: app), updatedAt: now)
            }
        }
        if changed { scheduleSave() }
    }

    // Same once-only seeding for non-app keys (workflows: "workflow:<id>").
    func seedIfNeeded(keys: [String], score: Double) {
        let now = Date()
        var changed = false
        for key in keys where !seeded.contains(key) {
            seeded.insert(key)
            changed = true
            if entries[key] == nil { entries[key] = Entry(score: score, updatedAt: now) }
        }
        if changed { scheduleSave() }
    }

    // manual = launched from AppPad; suppresses the duplicate system notification.
    func record(_ key: String, manual: Bool = false) {
        let now = Date()
        if !manual, let last = lastManual[key], now.timeIntervalSince(last) < 10 { return }
        if manual { lastManual[key] = now }
        entries[key] = Entry(score: score(for: key, now: now) + 1, updatedAt: now)
        scheduleSave()
    }

    func score(for key: String, now: Date = Date()) -> Double {
        guard let entry = entries[key] else { return 0 }
        let days = max(0, now.timeIntervalSince(entry.updatedAt)) / 86_400
        return entry.score * pow(0.5, days / halfLifeDays)
    }

    @objc private func appDidLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let key = app.bundleIdentifier ?? app.bundleURL?.path else { return }
        record(key)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.pruneAndSave()
        }
    }

    private func pruneAndSave() {
        let now = Date()
        entries = entries.filter { score(for: $0.key, now: now) > 0.001 }
        let file = StoreFile(entries: entries, seeded: seeded.sorted())
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
