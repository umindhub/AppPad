import Foundation
import GRDB

// One frecency record (apps: bundle id / path, workflows: "workflow:<id>").
nonisolated struct FrecencyEntry: Codable, Sendable {
    var score: Double
    var updatedAt: Date
}

// SQLite persistence for LaunchStats: stats.sqlite in the support directory.
// Loaded once at launch; writes run in order on a background serial queue.
nonisolated final class FrecencyStore: @unchecked Sendable {
    nonisolated struct Snapshot: Sendable {
        var entries: [String: FrecencyEntry]
        var seeded: Set<String>
    }

    private let dbQueue: DatabaseQueue
    private let writeQueue = DispatchQueue(label: "AppPad.FrecencyStore", qos: .utility)

    // legacyJSON: old launch-stats.json, imported once and then renamed to *.migrated.
    init(directory: URL, legacyJSON: URL) throws {
        var config = Configuration()
        config.label = "Frecency"
        dbQueue = try DatabaseQueue(path: directory.appendingPathComponent("stats.sqlite").path, configuration: config)
        try Self.migrator(legacyJSON: legacyJSON).migrate(dbQueue)
        Self.retireLegacyFile(legacyJSON)
    }

    // MARK: - Schema

    private static func migrator(legacyJSON: URL) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE frecency (
                    key TEXT PRIMARY KEY NOT NULL,
                    score DOUBLE NOT NULL,
                    updatedAt DOUBLE NOT NULL
                );
                CREATE TABLE frecencySeed (
                    key TEXT PRIMARY KEY NOT NULL,
                    seededAt DOUBLE NOT NULL
                );
                """)
        }
        // One-time import of the JSON store; missing or unreadable file → start empty.
        migrator.registerMigration("v1-import-json") { db in
            guard let legacy = LegacyFile.read(legacyJSON) else { return }
            try insertSeeds(db, keys: legacy.seeded, at: Date().timeIntervalSince1970)
            try upsert(db, entries: legacy.entries)
            NSLog("FrecencyStore: imported \(legacy.entries.count) entries, \(legacy.seeded.count) seeds from JSON")
        }
        return migrator
    }

    // Old JSON formats: {entries, seeded} or v1 plain [key: entry].
    nonisolated private struct LegacyFile: Decodable {
        var entries: [String: FrecencyEntry]
        var seeded: [String]

        static func read(_ url: URL) -> LegacyFile? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            if let file = try? decoder.decode(LegacyFile.self, from: data) { return file }
            if let v1 = try? decoder.decode([String: FrecencyEntry].self, from: data) {
                return LegacyFile(entries: v1, seeded: [])
            }
            return nil
        }
    }

    // Keep the old file as a backup instead of deleting it.
    private static func retireLegacyFile(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let backup = url.appendingPathExtension("migrated")
        try? fm.removeItem(at: backup)
        do {
            try fm.moveItem(at: url, to: backup)
        } catch {
            NSLog("FrecencyStore: could not rename legacy JSON: \(error)")
        }
    }

    // MARK: - Read

    func load() throws -> Snapshot {
        try dbQueue.read { db in
            var entries: [String: FrecencyEntry] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, score, updatedAt FROM frecency") {
                let key: String = row["key"]
                let updatedAt: Double = row["updatedAt"]
                entries[key] = FrecencyEntry(score: row["score"], updatedAt: Date(timeIntervalSince1970: updatedAt))
            }
            let seeded = try String.fetchSet(db, sql: "SELECT key FROM frecencySeed")
            return Snapshot(entries: entries, seeded: seeded)
        }
    }

    // MARK: - Write (async, ordered)

    func upsert(key: String, entry: FrecencyEntry) {
        write { db in try Self.upsert(db, entries: [key: entry]) }
    }

    // New seed keys plus the starting entries created for them, in one transaction.
    func seed(keys: [String], entries: [String: FrecencyEntry]) {
        let now = Date().timeIntervalSince1970
        write { db in
            try Self.insertSeeds(db, keys: keys, at: now)
            try Self.upsert(db, entries: entries)
        }
    }

    // Drop decayed entries; seeds stay so apps are never re-seeded.
    func delete(keys: [String]) {
        write { db in
            let statement = try db.makeStatement(sql: "DELETE FROM frecency WHERE key = ?")
            for key in keys { try statement.execute(arguments: [key]) }
        }
    }

    private func write(_ updates: @escaping @Sendable (Database) throws -> Void) {
        writeQueue.async { [dbQueue] in
            do {
                try dbQueue.write(updates)
            } catch {
                NSLog("FrecencyStore: write failed: \(error)")
            }
        }
    }

    private static func upsert(_ db: Database, entries: [String: FrecencyEntry]) throws {
        guard !entries.isEmpty else { return }
        let statement = try db.makeStatement(sql: """
            INSERT INTO frecency (key, score, updatedAt) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET score = excluded.score, updatedAt = excluded.updatedAt
            """)
        for (key, entry) in entries {
            try statement.execute(arguments: [key, entry.score, entry.updatedAt.timeIntervalSince1970])
        }
    }

    private static func insertSeeds(_ db: Database, keys: [String], at time: Double) throws {
        guard !keys.isEmpty else { return }
        let statement = try db.makeStatement(sql: "INSERT OR IGNORE INTO frecencySeed (key, seededAt) VALUES (?, ?)")
        for key in keys { try statement.execute(arguments: [key, time]) }
    }
}
