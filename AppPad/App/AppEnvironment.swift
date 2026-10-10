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

    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let suffix: String
        switch current {
        case .dev: suffix = " Dev"
        case .beta: suffix = " Beta"
        case .release: suffix = ""
        }
        return "AppPad \(version) (\(build))\(suffix)"
    }

    // ~/Library/Application Support/<bundle id>/, created on demand.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.youmindhub.apppad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
