import Foundation
import Combine

// Static scan of the steps to pre-fill the manifest. Only a helper for the user:
// enforcement is the sandbox, never this scan.
enum PermissionSuggester {
    struct Suggestion {
        var permissions: WorkflowPermissions
        var added: [String]   // human-readable list of what changed
    }

    private static let networkPattern = #"\b(curl|wget|git|gh|ssh|scp|rsync|nc|ping|brew|npm|npx|pip3?|http)\b|https?://"#
    private static let servicesPattern = #"\b(open|pbcopy|pbpaste|osascript|say|defaults|killall|shortcuts|afplay|screencapture|launchctl|networksetup)\b"#
    private static let writePattern = #"\b(rm|mv|cp|touch|mkdir|tee|ln|rsync|unzip|tar|sed\s+-i)\b|>"#
    private static let pathPattern = #"(?:~|\$HOME|\$\{HOME\}|/Users/[^/\s"'`]+)(?:/[^\s"'`;|&<>()]*)?"#

    static func suggest(for workflow: Workflow) -> Suggestion {
        var p = workflow.permissions
        var added: [String] = []
        let home = NSHomeDirectory()

        func addPath(_ raw: String, write: Bool) {
            var path = raw.replacingOccurrences(of: "${HOME}", with: "~").replacingOccurrences(of: "$HOME", with: "~")
            if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            if write {
                guard !p.fileWrite.contains(path) else { return }
                p.fileWrite.append(path)
                p.fileRead.removeAll { $0 == path }
                added.append(String(localized: "Read and change \(path)"))
            } else {
                guard !p.fileRead.contains(path), !p.fileWrite.contains(path) else { return }
                p.fileRead.append(path)
                added.append(String(localized: "Read \(path)"))
            }
        }

        for step in workflow.steps {
            switch step.kind {
            case .shell, .appleScript:
                let script = step.script
                if !p.network, matches(script, networkPattern) {
                    p.network = true
                    added.append(String(localized: "Network access"))
                }
                if !p.systemServices, step.kind == .shell, matches(script, servicesPattern) {
                    p.systemServices = true
                    added.append(String(localized: "System services"))
                }
                for line in script.split(whereSeparator: \.isNewline).map(String.init) {
                    let write = matches(line, writePattern)
                    for path in captures(line, pathPattern, group: 0) { addPath(path, write: write) }
                }
                for id in controlledApps(in: script) where !p.appleEvents.contains(id) {
                    p.appleEvents.append(id)
                    added.append(String(localized: "Control \(AppLookup.name(forBundleID: id))"))
                }
            case .http:
                if let host = step.http.host, !p.httpHosts.map({ $0.lowercased() }).contains(host) {
                    p.httpHosts.append(host)
                    added.append(String(localized: "HTTP host \(host)"))
                }
                for name in step.http.referencedSecrets where !p.secrets.contains(name) {
                    p.secrets.append(name)
                    added.append(String(localized: "Secret \(name)"))
                }
            case .shortcut, .builtin:
                break   // implied by the step itself
            }
        }
        return Suggestion(permissions: p, added: added)
    }

    // tell application "Finder" / tell app "Music" / application id "com.x" / Application("Safari") (JXA).
    private static func controlledApps(in script: String) -> [String] {
        var ids: [String] = []
        ids += captures(script, #"(?i)application\s+id\s+"([^"]+)""#, group: 1)
        let names = captures(script, #"(?i)tell\s+app(?:lication)?\s+"([^"]+)""#, group: 1)
            + captures(script, #"Application\(\s*["']([^"']+)["']\s*\)"#, group: 1)
        for name in names {
            if let id = AppLookup.bundleID(forName: name) {
                ids.append(id)
            } else if name.contains(".") {
                ids.append(name)   // already a bundle id
            }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func captures(_ text: String, _ pattern: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: group), in: text).map { String(text[$0]) }
        }
    }
}

// Starting points offered by "Add" (Empty Trash is now a built-in workflow).
enum WorkflowTemplate: CaseIterable {
    case blankShell, blankAppleScript, githubAction, runShortcut

    var title: String {
        switch self {
        case .blankShell: return String(localized: "Shell Script")
        case .blankAppleScript: return String(localized: "AppleScript")
        case .githubAction: return String(localized: "Run GitHub Action")
        case .runShortcut: return String(localized: "Run Shortcut")
        }
    }

    // Names are the English base; translations go in the workflow's localizations.
    // Blank templates leave the identifier empty so it is the first thing to fill in.
    func make() -> Workflow {
        switch self {
        case .blankShell:
            var step = WorkflowStep(kind: .shell)
            step.script = "echo \"Hello from AppPad\"\n"
            return Self.named("New Shell Workflow", steps: [step])
        case .blankAppleScript:
            var step = WorkflowStep(kind: .appleScript)
            step.script = "on run argv\n\treturn \"Hello from AppPad\"\nend run\n"
            return Self.named("New AppleScript Workflow", steps: [step])
        case .githubAction:
            var step = WorkflowStep(kind: .http)
            step.http.method = .POST
            step.http.url = "https://api.github.com/repos/OWNER/REPO/actions/workflows/WORKFLOW.yml/dispatches"
            step.http.headers = """
            Accept: application/vnd.github+json
            Authorization: Bearer {{secret:github-token}}
            X-GitHub-Api-Version: 2022-11-28
            Content-Type: application/json
            """
            step.http.body = "{\"ref\": \"main\"}"
            var workflow = Self.named("Run GitHub Action", identifier: "com.youmindhub.github-action", steps: [step])
            workflow.permissions.httpHosts = ["api.github.com"]
            workflow.permissions.secrets = ["github-token"]
            return workflow
        case .runShortcut:
            return Self.named("Run Shortcut", identifier: "com.youmindhub.run-shortcut", steps: [WorkflowStep(kind: .shortcut)])
        }
    }

    // English base name plus the app's own translations of that key as localizations.
    private static func named(_ key: String, identifier: String = "", steps: [WorkflowStep]) -> Workflow {
        var workflow = Workflow(name: key, identifier: identifier, steps: steps)
        workflow.localizations = WorkflowLanguage.translations(of: key)
        return workflow
    }
}
