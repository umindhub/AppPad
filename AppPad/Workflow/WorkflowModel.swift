import Foundation

// MARK: - Enums

nonisolated enum WorkflowStepKind: String, Codable, CaseIterable, Sendable {
    case shell, appleScript, shortcut, http, builtin
}

nonisolated enum ScriptLanguage: String, Codable, CaseIterable, Sendable {
    case appleScript, javaScript
}

// Actions implemented by AppPad itself (trusted code, still permission-gated).
nonisolated enum BuiltinAction: String, Codable, CaseIterable, Sendable {
    case emptyTrash, sleepDisplays
}

nonisolated enum HTTPMethod: String, Codable, CaseIterable, Sendable {
    case GET, POST, PUT, PATCH, DELETE
}

// Notification after a successful run (panel runs only; Settings shows the result sheet).
nonisolated enum SuccessNotice: String, Codable, CaseIterable, Sendable {
    case output    // the final output (or "Done")
    case custom    // successMessage, {{output}} replaced
    case none      // silent
}

// Notification after a failed run.
nonisolated enum FailureNotice: String, Codable, CaseIterable, Sendable {
    case error     // failing step + its error
    case custom    // failureMessage, {{error}} replaced
}

// MARK: - HTTP

nonisolated struct HTTPRequestSpec: Codable, Equatable, Sendable {
    var method: HTTPMethod = .GET
    var url = ""
    var headers = ""   // one "Name: Value" per line
    var body = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        method = c.value(.method, .GET)
        url = c.value(.url, "")
        headers = c.value(.headers, "")
        body = c.value(.body, "")
    }

    // Parsed header lines; blank / malformed lines are skipped.
    var headerPairs: [(name: String, value: String)] {
        headers.split(whereSeparator: \.isNewline).compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : (name, value)
        }
    }
}

// MARK: - Step

// Flat struct (not an enum with payloads) so the editor can switch kinds without losing data.
nonisolated struct WorkflowStep: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: WorkflowStepKind
    var script = ""                       // shell / AppleScript / JXA source
    var language: ScriptLanguage = .appleScript
    var shortcutName = ""
    var http = HTTPRequestSpec()
    var builtin: BuiltinAction = .emptyTrash
    var timeout: Double = 60              // seconds

    init(kind: WorkflowStepKind) {
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        kind = try c.decode(WorkflowStepKind.self, forKey: .kind)
        script = c.value(.script, "")
        language = c.value(.language, .appleScript)
        shortcutName = c.value(.shortcutName, "")
        http = c.value(.http, HTTPRequestSpec())
        builtin = c.value(.builtin, .emptyTrash)
        timeout = c.value(.timeout, 60)
    }
}

// MARK: - Declared permissions (manifest)

nonisolated struct WorkflowPermissions: Codable, Equatable, Sendable {
    var fileRead: [String] = []        // paths, "~" allowed
    var fileWrite: [String] = []       // read + write
    var network = false                // sandboxed scripts only
    var systemServices = false         // open mach services (open, pbcopy, launching apps…)
    var appleEvents: [String] = []     // bundle ids scripts may control
    var httpHosts: [String] = []       // hosts HTTP steps may contact
    var secrets: [String] = []         // Keychain secrets HTTP steps may use

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileRead = c.value(.fileRead, [])
        fileWrite = c.value(.fileWrite, [])
        network = c.value(.network, false)
        systemServices = c.value(.systemServices, false)
        appleEvents = c.value(.appleEvents, [])
        httpHosts = c.value(.httpHosts, [])
        secrets = c.value(.secrets, [])
    }
}

// MARK: - Workflow

nonisolated struct Workflow: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var enabled = true
    var panelKey: KeyCombo?               // shortcut inside the Workflow panel only (not global)
    var icon: Data?                       // 512×512 PNG; nil = generated icon
    var successNotice: SuccessNotice = .none     // default: silent on success
    var successMessage = ""
    var failureNotice: FailureNotice = .error
    var failureMessage = ""
    var copyOutput = false                // also put the final output on the clipboard
    var steps: [WorkflowStep] = []
    var permissions = WorkflowPermissions()
    var formatVersion = 1

    private enum LegacyKeys: String, CodingKey {
        case outputMode
    }

    init(name: String, steps: [WorkflowStep] = []) {
        self.name = name
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "Workflow")
        enabled = c.value(.enabled, true)
        panelKey = try? c.decodeIfPresent(KeyCombo.self, forKey: .panelKey)
        icon = try? c.decodeIfPresent(Data.self, forKey: .icon)
        successNotice = c.value(.successNotice, .none)
        successMessage = c.value(.successMessage, "")
        failureNotice = c.value(.failureNotice, .error)
        failureMessage = c.value(.failureMessage, "")
        copyOutput = c.value(.copyOutput, false)
        // v1 files: "outputMode" notification / clipboard / none.
        if !c.contains(.successNotice),
           let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let mode = try? legacy.decodeIfPresent(String.self, forKey: .outputMode) {
            if mode == "clipboard" { copyOutput = true }
        }
        steps = c.value(.steps, [])
        permissions = c.value(.permissions, WorkflowPermissions())
        formatVersion = c.value(.formatVersion, 1)
    }
}

// Lenient decoding: missing or invalid keys fall back to defaults (forward compatible files).
extension KeyedDecodingContainer {
    nonisolated func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - Placeholders

nonisolated enum WorkflowPlaceholders {
    static let input = "{{input}}"

    // Names used as {{secret:NAME}} in a text.
    static func secretNames(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{secret:([A-Za-z0-9_.\-]+)\}\}"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func isValidSecretName(_ name: String) -> Bool {
        !name.isEmpty && name.range(of: #"^[A-Za-z0-9_.\-]+$"#, options: .regularExpression) != nil
    }
}

extension HTTPRequestSpec {
    nonisolated var referencedSecrets: [String] {
        WorkflowPlaceholders.secretNames(in: url + "\n" + headers + "\n" + body)
    }

    // Host of the URL as written (placeholders in the path are fine).
    nonisolated var host: String? {
        let raw = url.replacingOccurrences(of: WorkflowPlaceholders.input, with: "x")
        return URLComponents(string: raw)?.host?.lowercased()
    }
}
