import Foundation
import Darwin

// Apps launched from Finder / login don't get the shell's PATH (brew, gh, node…).
// Read it once from the user's login shell (outside the sandbox: it is the user's own config).
nonisolated enum ShellEnvironment {
    private static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    private static let cache = PathCache()

    static var userShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    static func loginPath() async -> String {
        if let cached = cache.value { return cached }
        let marker = "__APPPAD_PATH__"
        let output = await ProcessRunner.run(
            userShell, ["-l", "-c", "printf '\(marker)%s' \"$PATH\""],
            environment: ["HOME": NSHomeDirectory(), "USER": NSUserName()],
            timeout: 5
        )
        var path = fallbackPath
        if output.succeeded, let range = output.stdout.range(of: marker, options: .backwards) {
            let value = output.stdout[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { path = value }
        }
        cache.value = path
        return path
    }

    // Minimal, explicit environment for workflow scripts (AppPad's own env is not inherited).
    static func scriptEnvironment(tempDir: URL, input: String, workflowName: String) async -> [String: String] {
        let path = await loginPath()
        var env: [String: String] = [
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "SHELL": userShell,
            "PATH": path,
            "TMPDIR": tempDir.path + "/",
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
            "APPPAD_WORKFLOW": workflowName,
        ]
        // Large inputs go through stdin / argv only.
        env["APPPAD_INPUT"] = input.utf8.count <= 64 * 1024 ? input : ""
        return env
    }
}

nonisolated private final class PathCache: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
