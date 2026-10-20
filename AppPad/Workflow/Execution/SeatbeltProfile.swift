import Foundation

// What the sandboxed script may do: the granted subset of the declared permissions.
nonisolated struct SandboxGrant: Sendable {
    var readPaths: [String] = []
    var writePaths: [String] = []
    var network = false
    var systemServices = false
    var appleEvents: [String] = []

    init(items: [PermissionItem]) {
        for item in items {
            switch item.kind {
            case .fileRead: readPaths.append(item.value)
            case .fileWrite: writePaths.append(item.value)
            case .network: network = true
            case .systemServices: systemServices = true
            case .appleEvents: appleEvents.append(item.value)
            default: break
            }
        }
    }
}

// Builds an SBPL profile for /usr/bin/sandbox-exec (the kernel enforces it for the
// script and every child it spawns). Default deny; user files only where granted.
nonisolated enum SeatbeltProfile {
    static let sandboxExec = "/usr/bin/sandbox-exec"

    // Read-only system locations every script needs (binaries, libraries, dyld cache, config).
    private static let systemReadPaths = [
        "/usr", "/bin", "/sbin", "/System", "/Library", "/Applications",
        "/opt/homebrew", "/private/etc", "/private/var/db/timezone", "/private/var/select",
        "/dev",
    ]

    private static let networkServices = [
        "com.apple.dnssd.service", "com.apple.SystemConfiguration.configd",
        "com.apple.SystemConfiguration.DNSConfiguration", "com.apple.trustd", "com.apple.trustd.agent",
        "com.apple.networkd", "com.apple.nsurlsessiond", "com.apple.ocspd",
    ]

    private static let appleEventServices = [
        "com.apple.coreservices.appleevents", "com.apple.coreservices.launchservicesd",
        "com.apple.lsd.mapdb", "com.apple.CoreServices.coreservicesd",
    ]

    static func make(_ grant: SandboxGrant, tempDir: URL) -> String {
        var lines = [
            "(version 1)",
            "(deny default)",
            "(import \"system.sb\")",
            "(allow process-fork)",
            "(allow process-exec)",
            "(allow signal (target same-sandbox))",
            "(allow process-info* (target same-sandbox))",
            "(allow sysctl-read)",
            "(allow user-preference-read)",
            "(allow file-read-metadata)",
            "(allow file-read* (literal \"/\") " + systemReadPaths.map { "(subpath \(quote($0)))" }.joined(separator: " ") + ")",
            "(allow file-write* file-ioctl (literal \"/dev/null\") (literal \"/dev/zero\") (literal \"/dev/dtracehelper\") (regex #\"^/dev/tty\"))",
            "; per-run scratch directory (TMPDIR, working directory)",
            "(allow file-read* file-write* (subpath \(quote(resolve(tempDir.path)))))",
        ]

        let reads = grant.readPaths.map(resolve)
        if !reads.isEmpty {
            lines.append("(allow file-read* " + reads.map { "(subpath \(quote($0)))" }.joined(separator: " ") + ")")
        }
        let writes = grant.writePaths.map(resolve)
        if !writes.isEmpty {
            lines.append("(allow file-read* file-write* " + writes.map { "(subpath \(quote($0)))" }.joined(separator: " ") + ")")
        }

        if grant.network {
            lines.append("(allow network-outbound)")
            lines.append("(allow system-socket)")
            lines.append("(allow file-read* (subpath \"/private/var/run\"))")
            lines.append("(allow mach-lookup " + networkServices.map { "(global-name \(quote($0)))" }.joined(separator: " ") + ")")
        }

        if grant.systemServices {
            lines.append("(allow mach-lookup)")
            lines.append("(allow lsopen)")
            lines.append("(allow ipc-posix-shm-read-data ipc-posix-shm-write-data)")
            lines.append("(allow iokit-open)")
        }

        if !grant.appleEvents.isEmpty {
            if !grant.systemServices {
                lines.append("(allow mach-lookup " + appleEventServices.map { "(global-name \(quote($0)))" }.joined(separator: " ") + ")")
            }
            lines.append("(allow appleevent-send " + grant.appleEvents.map { "(appleevent-destination \(quote($0)))" }.joined(separator: " ") + ")")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // "~/x" → "/Users/me/x"; symlinks resolved (/tmp → /private/tmp) because rules match real paths.
    static func resolve(_ path: String) -> String {
        var expanded = path.trimmingCharacters(in: .whitespaces)
        if expanded.hasPrefix("$HOME") { expanded = "~" + expanded.dropFirst(5) }
        expanded = (expanded as NSString).expandingTildeInPath
        let resolved = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
        return resolved.count > 1 && resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
