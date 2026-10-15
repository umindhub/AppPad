import Foundation
import CryptoKit
import GRDB

nonisolated enum ClipKind: String, Codable, DatabaseValueConvertible, Sendable {
    case text, image, file
}

// history: everything copied; saved: the kept library.
nonisolated enum ClipScope: Sendable {
    case history, saved
}

// Full row: used for preview and paste.
nonisolated struct ClipItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "clip"

    var id: Int64?
    var uuid: String
    var kind: ClipKind
    var text: String?          // plain text, or file paths joined by "\n"
    var searchText: String?    // indexed prefix of text
    var rtf: Data?
    var imageExt: String?      // heic / png, file lives in blobs/<uuid>.<ext>
    var imageWidth: Int?
    var imageHeight: Int?
    var byteSize: Int
    var hash: String
    var sourceBundleID: String?
    var sourceName: String?
    var createdAt: Double
    var lastUsedAt: Double
    var useCount: Int
    var inHistory: Bool
    var saved: Bool
    var savedAt: Double?
    var sourcePath: String?    // original file of an image copied as a file
    var name: String? = nil    // user label (edited in Settings › Saved Clips), searchable

    // File behind the item: the original image file, or the first copied file.
    var locationPath: String? {
        switch kind {
        case .image: return sourcePath
        case .file: return (text ?? "").split(separator: "\n").first.map(String.init)
        case .text: return nil
        }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// Lightweight row for the list (no full text / rtf).
nonisolated struct ClipSummary: FetchableRecord, Equatable, Sendable {
    var id: Int64
    var uuid: String
    var kind: ClipKind
    var snippet: String
    var imageExt: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var byteSize: Int
    var sourceBundleID: String?
    var sourceName: String?
    var lastUsedAt: Double
    var saved: Bool
    var name: String?

    static let columns = """
        id, uuid, kind, substr(searchText, 1, 300) AS snippet, imageExt, imageWidth, imageHeight, \
        byteSize, sourceBundleID, sourceName, lastUsedAt, saved, name
        """

    init(row: Row) {
        id = row["id"]
        uuid = row["uuid"]
        kind = row["kind"]
        snippet = row["snippet"] ?? ""
        imageExt = row["imageExt"]
        imageWidth = row["imageWidth"]
        imageHeight = row["imageHeight"]
        byteSize = row["byteSize"]
        sourceBundleID = row["sourceBundleID"]
        sourceName = row["sourceName"]
        lastUsedAt = row["lastUsedAt"]
        saved = row["saved"]
        name = row["name"]
    }

    // Non-empty user label.
    var displayName: String? {
        guard let name, !name.isEmpty else { return nil }
        return name
    }
}

// App the content was copied from; the icon is our own copy (survives app deletion).
nonisolated struct SourceApp: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sourceApp"

    var bundleID: String
    var name: String
    var icon: Data?            // 64 px PNG
    var updatedAt: Double
}

nonisolated struct ClipQuery: Sendable {
    var scope: ClipScope
    var terms: [String] = []
    var bundleID: String?
    var limit: Int
}

// History ranges for "Delete …" buttons, by lastUsedAt. Saved items are never touched.
nonisolated enum ClipAgeRange: CaseIterable, Hashable, Sendable {
    case lastHour, lastDay, lastWeek, threeToSixMonths, sixToTwelveMonths, olderThanYear

    private static let day: Double = 86_400

    // lastUsedAt >= from AND lastUsedAt < to (nil = open end).
    func bounds(now: Double) -> (from: Double?, to: Double?) {
        switch self {
        case .lastHour: return (now - 3_600, nil)
        case .lastDay: return (now - Self.day, nil)
        case .lastWeek: return (now - 7 * Self.day, nil)
        case .threeToSixMonths: return (now - 182 * Self.day, now - 91 * Self.day)
        case .sixToTwelveMonths: return (now - 365 * Self.day, now - 182 * Self.day)
        case .olderThanYear: return (nil, now - 365 * Self.day)
        }
    }
}

// Snapshot read from the pasteboard on the main thread, stored in the background.
nonisolated struct ClipCapture: Sendable {
    var kind: ClipKind
    var text: String?
    var rtf: Data?
    var imageData: Data?       // raw png / tiff
    var imageFile: URL?        // image copied as a file (Finder, chat apps): read in the background
    var sourcePath: String?    // kept so the folder can be shown / opened later
    var sourceBundleID: String?
    var sourceName: String?
    var sourceIcon: Data?      // only for apps not stored yet

    var contentHash: String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        if let text { hasher.update(data: Data(text.utf8)) }
        if let imageData { hasher.update(data: imageData) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
