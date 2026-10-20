import AppKit

// apppad://import-workflow?url=https://… (apppad-dev:// in Dev) from the Workflow Market:
// download the workflow file, show what it contains, install after the user confirms.
// Uses the same rules as Settings › Workflows › Import… (WorkflowStore.prepareImport).
final class WorkflowLinkImporter {
    static let shared = WorkflowLinkImporter()

    // Something was installed (AppDelegate shows Settings › Workflows).
    var onInstalled: (() -> Void)?

    private static let maxBytes = 1_000_000
    private var busy = false

    private init() {}

    // True when the link is ours (handled or rejected with a message).
    @discardableResult
    func handle(_ link: URL) -> Bool {
        guard link.host()?.lowercased() == "import-workflow" else { return false }
        guard !busy else { return true }   // one import at a time
        guard let source = Self.sourceURL(in: link) else {
            showError(String(localized: "This link does not point to a workflow file."))
            return true
        }
        busy = true
        Task {
            defer { busy = false }
            let data: Data
            do {
                data = try await download(source)
            } catch {
                showError(String(localized: "Could not download the workflow from \(Self.hostName(source))."))
                return
            }
            do {
                confirm(try WorkflowStore.shared.prepareImport(data: data), from: source)
            } catch let error as WorkflowImportError {
                showError(error.errorDescription ?? "")
            } catch {
                showError(String(localized: "The downloaded file is not a valid workflow."))
            }
        }
        return true
    }

    // MARK: - Link

    // "url" query item: https only; Dev also accepts http://localhost for the local website.
    private static func sourceURL(in link: URL) -> URL? {
        guard let raw = URLComponents(url: link, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              url.host() != nil
        else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", AppEnvironment.current == .dev, isLocalhost(url) { return url }
        return nil
    }

    private static func isLocalhost(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1"].contains(url.host()?.lowercased() ?? "")
    }

    // AppPad's own website (Dev: the dev site and localhost).
    private static func isTrusted(_ url: URL) -> Bool {
        if url.host()?.lowercased() == AppEnvironment.websiteURL.host()?.lowercased() { return true }
        return AppEnvironment.current == .dev && isLocalhost(url)
    }

    private static func hostName(_ url: URL) -> String {
        url.host() ?? url.absoluteString
    }

    // MARK: - Download

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= Self.maxBytes
        else { throw URLError(.badServerResponse) }
        return data
    }

    // MARK: - Confirm

    private func confirm(_ items: [WorkflowImportItem], from source: URL) {
        let installable = items.filter {
            switch $0.action {
            case .older, .reserved: return false
            default: return true
            }
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage

        guard !installable.isEmpty else {
            // Only older versions: nothing to do.
            alert.messageText = String(localized: "A newer version is already installed")
            alert.informativeText = items.map { describe($0, from: source) }.joined(separator: "\n\n")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            return
        }

        if items.count == 1 {
            alert.messageText = String(localized: "Add the workflow “\(items[0].workflow.displayName)”?")
        } else {
            alert.messageText = String(localized: "Add \(installable.count) workflows?")
        }
        var lines = items.map { describe($0, from: source) }
        lines.append(String(localized: "From \(Self.hostName(source))"))
        if !Self.isTrusted(source) {
            alert.alertStyle = .warning
            lines.append(String(localized: "This workflow does not come from AppPad’s website. Only add workflows you trust."))
        }
        lines.append(String(localized: "AppPad asks you before a workflow uses any of its permissions."))
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "Add"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        installable.forEach { WorkflowStore.shared.install($0.workflow, source: .link(source)) }
        onInstalled?()
    }

    // "Name  identifier 1.2", what happens, steps, permissions.
    private func describe(_ item: WorkflowImportItem, from source: URL) -> String {
        let workflow = item.workflow
        var lines = ["\(workflow.displayName)  (\(workflow.identifier) \(workflow.version))"]
        switch item.action {
        case .add:
            lines.append(String(localized: "New workflow"))
        case .upgrade(let installed):
            lines.append(String(localized: "Updates the installed version \(installed.version)"))
        case .sameVersion:
            lines.append(String(localized: "Replaces the installed copy of the same version"))
        case .older(let installed):
            lines.append(String(localized: "Skipped: the installed version \(installed.version) is newer"))
        case .reserved:
            lines.append(String(localized: "Skipped: built-in workflows can’t be replaced"))
        }
        // Replacing a copy from somewhere else: say where it was from, answers are asked again.
        switch item.action {
        case .upgrade(let installed), .sameVersion(let installed):
            if !WorkflowSource.link(source).sameOrigin(as: installed.source) {
                lines.append(String(localized: "Replaces a workflow marked “\(installed.source.longLabel)”. AppPad will ask for its permissions again."))
            }
        default:
            break
        }
        let steps = workflow.steps.map { Self.stepName($0) }
        if !steps.isEmpty {
            lines.append(String(localized: "Steps: \(steps.joined(separator: ", "))"))
        }
        let permissions = Self.permissionNames(workflow.permissions)
        lines.append(permissions.isEmpty
            ? String(localized: "Permissions: none")
            : String(localized: "Permissions: \(permissions.joined(separator: "; "))"))
        return lines.joined(separator: "\n")
    }

    private static func stepName(_ step: WorkflowStep) -> String {
        switch step.kind {
        case .shell:
            return String(localized: "Shell script")
        case .appleScript:
            return step.language == .javaScript ? "JavaScript" : "AppleScript"
        case .shortcut:
            return String(localized: "Shortcut “\(step.shortcutName)”")
        case .http:
            let host = URL(string: step.http.url)?.host() ?? step.http.url
            return "HTTP \(step.http.method.rawValue) \(host)"
        case .builtin:
            return String(localized: "Built-in action")
        }
    }

    private static func permissionNames(_ p: WorkflowPermissions) -> [String] {
        var names: [String] = []
        if !p.fileRead.isEmpty { names.append(String(localized: "read \(p.fileRead.joined(separator: ", "))")) }
        if !p.fileWrite.isEmpty { names.append(String(localized: "write \(p.fileWrite.joined(separator: ", "))")) }
        if p.network { names.append(String(localized: "network")) }
        if p.systemServices { names.append(String(localized: "system services")) }
        if !p.appleEvents.isEmpty { names.append(String(localized: "control \(p.appleEvents.joined(separator: ", "))")) }
        if !p.httpHosts.isEmpty { names.append(String(localized: "hosts \(p.httpHosts.joined(separator: ", "))")) }
        if !p.secrets.isEmpty { names.append(String(localized: "secrets \(p.secrets.joined(separator: ", "))")) }
        return names
    }

    // MARK: - Errors

    private func showError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Could not add the workflow")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
