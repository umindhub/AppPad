import Foundation

// Build environment resolved from compilation conditions set in Config/*.xcconfig.
enum AppEnvironment {
    case dev, beta, release

    static let current: AppEnvironment = {
        #if DEV
        return .dev
        #elseif BETA
        return .beta
        #else
        return .release
        #endif
    }()

    // "AppPad 1.0.0 (1) Dev" (menu bar).
    static var versionDescription: String {
        "AppPad \(versionNumber)"
    }

    // "1.0.0 (1) Dev" (Settings › About).
    static var versionNumber: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let suffix: String
        switch current {
        case .dev: suffix = " Dev"
        case .beta: suffix = " Beta"
        case .release: suffix = ""
        }
        return "\(version) (\(build))\(suffix)"
    }

    // Official site: Dev has its own; Beta and Release share one.
    static var websiteURL: URL {
        switch current {
        case .dev: return URL(string: "https://devapppad.youmindhub.com")!
        case .beta, .release: return URL(string: "https://apppad.youmindhub.com")!
        }
    }

    // ~/Library/Application Support/<bundle id>/, created on demand.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.youmindhub.apppad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
