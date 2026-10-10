import Foundation
import GRDB

extension Notification.Name {
    nonisolated static let clipboardStoreDidChange = Notification.Name("AppPad.clipboardStoreDidChange")
}

nonisolated struct ClipIngestOptions: Sendable {
    var imageQuality: Double
    var historyLimit: Int       // 0 = unlimited
    var retentionDays: Int      // 0 = forever
}

// GRDB store: rows in SQLite, images as files in blobs/<uuid>.<ext>.
// Thread-safe (DatabasePool); writes are expected on the monitor's serial queue or main.
nonisolated final class ClipboardStore: @unchecked Sendable {
    let directory: URL
    let blobDirectory: URL
    private let pool: DatabasePool
    private let ftsAvailable: Bool

    static let searchTextLimit = 10_000     // chars indexed per item
    static let maxImageBytes = 60_000_000

    init(directory: URL) throws {
        self.directory = directory
        blobDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        var config = Configuration()
        config.label = "Clipboard"
        pool = try DatabasePool(path: directory.appendingPathComponent("clipboard.sqlite").path, configuration: config)
        try Self.migrator.migrate(pool)
        ftsAvailable = (try? pool.read { try $0.tableExists("clip_fts") }) ?? false
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE clip (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT NOT NULL UNIQUE,
                    kind TEXT NOT NULL,
                    text TEXT,
                    searchText TEXT,
                    rtf BLOB,
                    imageExt TEXT,
                    imageWidth INTEGER,
                    imageHeight INTEGER,
                    byteSize INTEGER NOT NULL DEFAULT 0,
                    hash TEXT NOT NULL UNIQUE,
                    sourceBundleID TEXT,
                    sourceName TEXT,
                    createdAt DOUBLE NOT NULL,
                    lastUsedAt DOUBLE NOT NULL,
                    useCount INTEGER NOT NULL DEFAULT 0,
                    inHistory BOOLEAN NOT NULL DEFAULT 1,
                    saved BOOLEAN NOT NULL DEFAULT 0,
                    savedAt DOUBLE
                );
                CREATE INDEX clip_history ON clip(inHistory, lastUsedAt);
                CREATE INDEX clip_saved ON clip(saved, savedAt);
                CREATE INDEX clip_source ON clip(sourceBundleID);
                CREATE TABLE sourceApp (
                    bundleID TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    icon BLOB,
                    updatedAt DOUBLE NOT NULL
                );
                """)
        }
        // Trigram FTS (substring match, works for CJK). Skipped if SQLite lacks trigram → LIKE fallback.
        migrator.registerMigration("v1-fts") { db in
            do {
                try db.execute(sql: """
                    CREATE VIRTUAL TABLE clip_fts USING fts5(
                        searchText, content='clip', content_rowid='id', tokenize='trigram'
                    );
                    CREATE TRIGGER clip_fts_ai AFTER INSERT ON clip BEGIN
                        INSERT INTO clip_fts(rowid, searchText) VALUES (new.id, new.searchText);
                    END;
                    CREATE TRIGGER clip_fts_ad AFTER DELETE ON clip BEGIN
                        INSERT INTO clip_fts(clip_fts, rowid, searchText) VALUES ('delete', old.id, old.searchText);
                    END;
                    CREATE TRIGGER clip_fts_au AFTER UPDATE OF searchText ON clip BEGIN
                        INSERT INTO clip_fts(clip_fts, rowid, searchText) VALUES ('delete', old.id, old.searchText);
                        INSERT INTO clip_fts(rowid, searchText) VALUES (new.id, new.searchText);
                    END;
                    """)
            } catch {
                NSLog("Clipboard FTS unavailable: \(error)")
            }
        }
        migrator.registerMigration("v2-sourcePath") { db in
            try db.execute(sql: "ALTER TABLE clip ADD COLUMN sourcePath TEXT")
        }
        return migrator
    }

    // MARK: - Files

    func imageURL(uuid: String, ext: String) -> URL {
        blobDirectory.appendingPathComponent("\(uuid).\(ext)")
    }

    func imageURL(for item: ClipItem) -> URL? {
        item.imageExt.map { imageURL(uuid: item.uuid, ext: $0) }
    }

    func imageURL(for summary: ClipSummary) -> URL? {
        summary.imageExt.map { imageURL(uuid: summary.uuid, ext: $0) }
    }

    private func removeFiles(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Ingest

    func ingest(_ input: ClipCapture, options: ClipIngestOptions) throws {
        var capture = input
        if capture.kind == .image, capture.imageData == nil, let file = capture.imageFile {
            guard let data = try? Data(contentsOf: file), data.count <= Self.maxImageBytes else { return }
            capture.imageData = data
        }
        let now = Date().timeIntervalSince1970
        let hash = capture.contentHash

        if let app = capture.sourceBundleID, let icon = capture.sourceIcon {
            let record = SourceApp(bundleID: app, name: capture.sourceName ?? app, icon: icon, updatedAt: now)
            try pool.write { db in try record.save(db) }
        }

        let existingID = try pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM clip WHERE hash = ?", arguments: [hash])
        }
        if let existingID {
            // Same content copied again: move to top of history.
            try pool.write { db in
                try db.execute(sql: """
                    UPDATE clip SET inHistory = 1, lastUsedAt = ?, sourceBundleID = ?, sourceName = ?,
                        sourcePath = COALESCE(?, sourcePath)
                    WHERE id = ?
                    """, arguments: [now, capture.sourceBundleID, capture.sourceName, capture.sourcePath, existingID])
            }
        } else {
            var item = ClipItem(
                uuid: UUID().uuidString, kind: capture.kind, text: capture.text,
                searchText: capture.text.map { String($0.prefix(Self.searchTextLimit)) },
                rtf: capture.rtf, imageExt: nil, imageWidth: nil, imageHeight: nil,
                byteSize: capture.text?.utf8.count ?? 0, hash: hash,
                sourceBundleID: capture.sourceBundleID, sourceName: capture.sourceName,
                createdAt: now, lastUsedAt: now, useCount: 0, inHistory: true, saved: false, savedAt: nil,
                sourcePath: capture.sourcePath
            )
            if capture.kind == .image, let raw = capture.imageData {
                guard let encoded = ClipImageCodec.encode(raw, quality: options.imageQuality) else {
                    // Undecodable image file: keep it as a file reference instead of dropping it.
                    guard let file = capture.imageFile else { return }
                    var fallback = input
                    fallback.kind = .file
                    fallback.text = file.path
                    fallback.imageFile = nil
                    fallback.sourcePath = nil
                    try ingest(fallback, options: options)
                    return
                }
                let url = imageURL(uuid: item.uuid, ext: encoded.ext)
                try encoded.data.write(to: url, options: .atomic)
                item.imageExt = encoded.ext
                item.imageWidth = encoded.width
                item.imageHeight = encoded.height
                item.byteSize = encoded.data.count
            }
            do {
                let record = item
                try pool.write { db in
                    var copy = record
                    try copy.insert(db)
                }
            } catch {
                if let url = imageURL(for: item) { removeFiles([url]) }
                throw error
            }
        }
        try prune(options: options)
    }

    // Drops history beyond the count / age limits (0 = no limit). Saved items only leave the history.
    private func prune(options: ClipIngestOptions) throws {
        guard options.historyLimit > 0 || options.retentionDays > 0 else { return }
        let cutoff = options.retentionDays > 0
            ? Date().timeIntervalSince1970 - Double(options.retentionDays) * 86_400
            : -1
        let offset = options.historyLimit > 0 ? options.historyLimit : Int.max
        let files = try pool.write { db -> [URL] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, uuid, imageExt, saved FROM clip
                WHERE inHistory = 1 AND (lastUsedAt < ? OR id IN (
                    SELECT id FROM clip WHERE inHistory = 1 ORDER BY lastUsedAt DESC LIMIT -1 OFFSET ?
                ))
                """, arguments: [cutoff, offset])
            var urls: [URL] = []
            for row in rows {
                let id: Int64 = row["id"]
                let saved: Bool = row["saved"]
                if saved {
                    try db.execute(sql: "UPDATE clip SET inHistory = 0 WHERE id = ?", arguments: [id])
                } else {
                    try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [id])
                    if let ext: String = row["imageExt"] {
                        urls.append(self.imageURL(uuid: row["uuid"], ext: ext))
                    }
                }
            }
            return urls
        }
        removeFiles(files)
    }

    // MARK: - Queries

    func fetch(_ query: ClipQuery) -> [ClipSummary] {
        var conditions = [query.scope == .saved ? "saved = 1" : "inHistory = 1"]
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let bundleID = query.bundleID {
            conditions.append("sourceBundleID = ?")
            arguments.append(bundleID)
        }
        var ftsTerms: [String] = []
        for term in query.terms {
            if ftsAvailable && term.count >= 3 {
                ftsTerms.append("\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
            } else {
                conditions.append("searchText LIKE ? ESCAPE '\\'")
                arguments.append("%" + Self.escapeLike(term) + "%")
            }
        }
        if !ftsTerms.isEmpty {
            conditions.append("id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)")
            arguments.append(ftsTerms.joined(separator: " AND "))
        }
        // While searching / filtering history, saved-library items rank first.
        let searching = !query.terms.isEmpty || query.bundleID != nil
        let order: String
        switch query.scope {
        case .saved: order = "savedAt DESC"
        case .history: order = searching ? "saved DESC, lastUsedAt DESC" : "lastUsedAt DESC"
        }
        let sql = "SELECT \(ClipSummary.columns) FROM clip WHERE \(conditions.joined(separator: " AND ")) "
            + "ORDER BY \(order) LIMIT \(max(1, query.limit))"
        do {
            return try pool.read { db in
                try ClipSummary.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            }
        } catch {
            NSLog("Clipboard fetch failed: \(error)")
            return []
        }
    }

    func item(id: Int64) -> ClipItem? {
        try? pool.read { db in try ClipItem.fetchOne(db, key: id) }
    }

    func sourceApps() -> [(bundleID: String, name: String)] {
        let rows = (try? pool.read { db in try Row.fetchAll(db, sql: "SELECT bundleID, name FROM sourceApp") }) ?? []
        return rows.map { (bundleID: $0["bundleID"], name: $0["name"]) }
    }

    func sourceIcon(bundleID: String) -> Data? {
        try? pool.read { db in
            try Data.fetchOne(db, sql: "SELECT icon FROM sourceApp WHERE bundleID = ?", arguments: [bundleID])
        }
    }

    // MARK: - Mutations

    func markUsed(id: Int64) {
        let now = Date().timeIntervalSince1970
        write("UPDATE clip SET useCount = useCount + 1, lastUsedAt = ?, inHistory = 1 WHERE id = ?", [now, id])
    }

    func toggleSaved(id: Int64) {
        guard let item = item(id: id) else { return }
        if item.saved {
            if item.inHistory {
                write("UPDATE clip SET saved = 0, savedAt = NULL WHERE id = ?", [id])
            } else {
                deleteRow(item)
            }
        } else {
            write("UPDATE clip SET saved = 1, savedAt = ? WHERE id = ?", [Date().timeIntervalSince1970, id])
        }
    }

    // Removes the item from one scope; the row is deleted once it is in neither.
    func remove(id: Int64, from scope: ClipScope) {
        guard let item = item(id: id) else { return }
        switch scope {
        case .history:
            if item.saved { write("UPDATE clip SET inHistory = 0 WHERE id = ?", [id]) } else { deleteRow(item) }
        case .saved:
            if item.inHistory { write("UPDATE clip SET saved = 0, savedAt = NULL WHERE id = ?", [id]) } else { deleteRow(item) }
        }
    }

    // History rows in a time range (nil = all). Saved items are never included.
    private static func rangeCondition(_ range: ClipAgeRange?) -> (sql: String, arguments: [(any DatabaseValueConvertible)?]) {
        var sql = "inHistory = 1 AND saved = 0"
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let range {
            let bounds = range.bounds(now: Date().timeIntervalSince1970)
            if let from = bounds.from {
                sql += " AND lastUsedAt >= ?"
                arguments.append(from)
            }
            if let to = bounds.to {
                sql += " AND lastUsedAt < ?"
                arguments.append(to)
            }
        }
        return (sql, arguments)
    }

    func historyCount(in range: ClipAgeRange?) -> Int {
        let condition = Self.rangeCondition(range)
        let count = try? pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip WHERE \(condition.sql)",
                             arguments: StatementArguments(condition.arguments))
        }
        return (count ?? nil) ?? 0
    }

    func deleteHistory(in range: ClipAgeRange?) {
        let condition = Self.rangeCondition(range)
        do {
            let files = try pool.write { db -> [URL] in
                let arguments = StatementArguments(condition.arguments)
                let rows = try Row.fetchAll(db, sql: "SELECT uuid, imageExt FROM clip WHERE \(condition.sql)",
                                            arguments: arguments)
                try db.execute(sql: "DELETE FROM clip WHERE \(condition.sql)", arguments: arguments)
                return rows.compactMap { row in
                    (row["imageExt"] as String?).map { self.imageURL(uuid: row["uuid"], ext: $0) }
                }
            }
            removeFiles(files)
        } catch {
            NSLog("Clipboard delete failed: \(error)")
        }
    }

    private func deleteRow(_ item: ClipItem) {
        guard let id = item.id else { return }
        write("DELETE FROM clip WHERE id = ?", [id])
        if let url = imageURL(for: item) { removeFiles([url]) }
    }

    private func write(_ sql: String, _ arguments: [(any DatabaseValueConvertible)?]) {
        do {
            try pool.write { db in try db.execute(sql: sql, arguments: StatementArguments(arguments)) }
        } catch {
            NSLog("Clipboard write failed: \(error)")
        }
    }

    private static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
