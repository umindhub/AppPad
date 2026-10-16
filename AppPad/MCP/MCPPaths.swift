import Foundation

// Locations shared by the GUI app (MCP host) and the `--mcp` proxy (same binary, same bundle).
// Everything lives in Application Support/<bundle id>/MCP, so Dev and Beta / Release never collide.
nonisolated enum MCPPaths {
    // `AppPad --mcp`: run as the stdio proxy instead of the app.
    static let proxyArgument = "--mcp"
    // Passed when the proxy launches AppPad: a launch for MCP never opens Launchpad.
    static let launchArgument = "--launched-by-mcp"

    static let bundleID = Bundle.main.bundleIdentifier ?? "com.youmindhub.apppad"

    static var isDev: Bool {
        #if DEV
        return true
        #else
        return false
        #endif
    }

    // Server key in client configs; Dev gets its own so both can be set up side by side.
    static var serverName: String { isDev ? "apppad-dev" : "apppad" }

    // For proxy error messages ("AppPad Dev").
    static var appName: String { isDev ? "AppPad Dev" : "AppPad" }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("MCP", isDirectory: true)
    }

    // Same-user only: directory 0700, socket 0600.
    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)
    }

    static var socketPath: String { directory.appendingPathComponent("mcp.sock").path }

    // The app flock()s this file for its whole lifetime (released on quit, crash and kill -9).
    static var beaconPath: String { directory.appendingPathComponent("running.lock").path }

    // What clients launch: this exact binary (Dev builds point into DerivedData).
    static var executablePath: String {
        Bundle.main.executableURL?.path ?? "/Applications/AppPad.app/Contents/MacOS/AppPad"
    }

    // sun_path is 104 bytes on macOS.
    static func fitsSocketAddress(_ path: String) -> Bool { path.utf8.count < 104 }

    // Fills a sockaddr_un; false when the path does not fit.
    static func makeAddress(_ path: String, into addr: inout sockaddr_un) -> Bool {
        addr.sun_family = sa_family_t(AF_UNIX)
        return withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8)
            guard bytes.count < raw.count else { return false }
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
            return true
        }
    }
}
