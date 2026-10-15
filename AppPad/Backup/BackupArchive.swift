import Foundation

// .apppadbackup files: gzipped tar written / read with the system bsdtar.
// bsdtar refuses ".." and absolute paths on extract; entries are also checked before extracting.
nonisolated enum BackupArchive {
    static let fileExtension = "apppadbackup"

    private static let tar = URL(fileURLWithPath: "/usr/bin/tar")

    // Packs the contents of `directory` (not the folder itself) into `file`.
    static func pack(_ directory: URL, to file: URL) throws {
        _ = try run(["-czf", file.path, "-C", directory.path, "."])
    }

    // Unpacks `file` into the existing `directory`.
    static func unpack(_ file: URL, to directory: URL) throws {
        let listing = try run(["-tzf", file.path])
        let entries = listing.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty else { throw BackupError.notABackup }
        for entry in entries where !isSafe(entry) {
            throw BackupError.unsafeArchive
        }
        _ = try run(["-xzf", file.path, "-C", directory.path])
    }

    private static func isSafe(_ entry: String) -> Bool {
        guard !entry.hasPrefix("/") else { return false }
        return !entry.split(separator: "/").contains("..")
    }

    // Runs tar; stdout is returned, a non-zero exit throws with stderr.
    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = tar
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["COPYFILE_DISABLE"] = "1"   // no ._ AppleDouble files in the archive
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            throw BackupError.archiveFailed(error.localizedDescription)
        }
        // Drain stderr on its own thread so a chatty tar can't block on a full pipe.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw message.isEmpty ? BackupError.notABackup : BackupError.archiveFailed(message)
        }
        return String(decoding: output, as: UTF8.self)
    }

    nonisolated private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}
