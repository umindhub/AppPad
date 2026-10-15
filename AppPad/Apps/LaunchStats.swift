import AppKit

// Frecency with exponential half-life decay (default 72 days).
// score_now = score_saved * 0.5^(elapsedDays / halfLife); each launch adds 1.
// Apps seen for the first time get a seed score: common system app 3, other system app 1, installed app 2.
// Ranking reads an in-memory cache; every change is written through to SQLite (FrecencyStore).
final class LaunchStats: NSObject {
    typealias Entry = FrecencyEntry

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
    private let store: FrecencyStore?   // nil → DB failed to open, stats live in memory only

    init(directory: URL) {
        do {
            store = try FrecencyStore(directory: directory,
                                      legacyJSON: directory.appendingPathComponent("launch-stats.json"))
        } catch {
            NSLog("LaunchStats: database unavailable, keeping stats in memory: \(error)")
            store = nil
        }
        super.init()
        do {
            if let snapshot = try store?.load() {
                entries = snapshot.entries
                seeded = snapshot.seeded
            }
        } catch {
            NSLog("LaunchStats: load failed: \(error)")
        }
        pruneStale()
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
        seed(apps.map { (key: $0.key, score: Self.seedScore(for: $0)) })
    }

    // Same once-only seeding for non-app keys (workflows: "workflow:<id>").
    func seedIfNeeded(keys: [String], score: Double) {
        seed(keys.map { (key: $0, score: score) })
    }

    private func seed(_ items: [(key: String, score: Double)]) {
        let now = Date()
        var newSeeds: [String] = []
        var newEntries: [String: Entry] = [:]
        for item in items where !seeded.contains(item.key) {
            seeded.insert(item.key)
            newSeeds.append(item.key)
            if entries[item.key] == nil {
                let entry = Entry(score: item.score, updatedAt: now)
                entries[item.key] = entry
                newEntries[item.key] = entry
            }
        }
        guard !newSeeds.isEmpty else { return }
        store?.seed(keys: newSeeds, entries: newEntries)
    }

    // manual = launched from AppPad; suppresses the duplicate system notification.
    func record(_ key: String, manual: Bool = false) {
        let now = Date()
        if !manual, let last = lastManual[key], now.timeIntervalSince(last) < 10 { return }
        if manual { lastManual[key] = now }
        let entry = Entry(score: score(for: key, now: now) + 1, updatedAt: now)
        entries[key] = entry
        store?.upsert(key: key, entry: entry)
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

    // Entries decayed to ~0 are dropped at launch (seeds are kept).
    private func pruneStale() {
        let now = Date()
        let stale = entries.keys.filter { score(for: $0, now: now) <= 0.001 }
        guard !stale.isEmpty else { return }
        for key in stale { entries[key] = nil }
        store?.delete(keys: stale)
    }
}
