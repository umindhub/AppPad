import Foundation

// Reads kernel sandbox violations ("deny(1) file-read-data /path") from the unified log
// for a time window, so missing permissions can be spotted after a failed run.
nonisolated enum SandboxLog {
    static func denials(from start: Date, to end: Date) async -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let output = await ProcessRunner.run(
            "/usr/bin/log",
            ["show", "--style", "compact",
             "--start", formatter.string(from: start.addingTimeInterval(-1)),
             "--end", formatter.string(from: end.addingTimeInterval(2)),
             "--predicate", "eventMessage CONTAINS \"deny(\""],
            timeout: 20
        )
        var seen = Set<String>()
        return output.stdout
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard let range = line.range(of: "deny(") else { return nil }
                // Drop the timestamp columns; keep "process(pid) deny(1) operation target".
                let text = String(line[(line.range(of: "Sandbox: ")?.upperBound ?? range.lowerBound)...])
                let key = text.replacingOccurrences(of: #"\(\d+\)"#, with: "", options: .regularExpression)
                return seen.insert(key).inserted ? text : nil
            }
            .prefix(200)
            .map { $0 }
    }
}
