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
    case emptyTrash, sleepDisplays, sleepMac, keepAwake, toggleDarkMode, setVolume, toggleMute
    case ejectDisks, toggleHiddenFiles, quitApp, quitAllApps, openURL, copyIPAddress, generateUUID
    case shutDown, restart, createReminder
}

// Whether a workflow takes the text after the first space in the panel search.
nonisolated enum ArgumentMode: String, Codable, CaseIterable, Sendable {
    case off = "none"   // not ".none": comparisons with .none would mean Optional.none
    case optional, required
}

// How the argument is parsed before it becomes the first step's input.
nonisolated enum ArgumentType: String, Codable, CaseIterable, Sendable {
    case text       // as typed
    case duration   // 10, 90s, 1h30m, 1:30 → seconds
    case time       // 7:30, 730, 7pm → HH:mm
    case number     // integer
    case percent    // 0–100, out-of-range values are clamped (volume)
    case reminder   // "tomorrow 3pm Call Mom !! @Work" → JSON ReminderRequest
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
    var shortcutInput = ""                // template sent to the shortcut; empty = step input, {{input}} / \n allowed
    var http = HTTPRequestSpec()
    var builtin: BuiltinAction = .emptyTrash
    var url = ""                          // openURL template, {{input}} is percent-encoded
    var timeout: Double = 60              // seconds
    var unsupportedBuiltin: String?       // builtin from a newer AppPad (not encoded)

    private enum CodingKeys: String, CodingKey {
        case id, kind, script, language, shortcutName, shortcutInput, http, builtin, url, timeout
    }

    init(kind: WorkflowStepKind) {
        self.kind = kind
    }

    init(builtin action: BuiltinAction, timeout: Double = 60) {
        kind = .builtin
        builtin = action
        self.timeout = timeout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        kind = try c.decode(WorkflowStepKind.self, forKey: .kind)
        script = c.value(.script, "")
        language = c.value(.language, .appleScript)
        shortcutName = c.value(.shortcutName, "")
        shortcutInput = c.value(.shortcutInput, "")
        http = c.value(.http, HTTPRequestSpec())
        // Unknown actions must never fall back to a real one (e.g. emptyTrash).
        let rawBuiltin: String = c.value(.builtin, BuiltinAction.emptyTrash.rawValue)
        if let action = BuiltinAction(rawValue: rawBuiltin) {
            builtin = action
        } else {
            unsupportedBuiltin = rawBuiltin
        }
        url = c.value(.url, "")
        timeout = c.value(.timeout, 60)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(script, forKey: .script)
        try c.encode(language, forKey: .language)
        try c.encode(shortcutName, forKey: .shortcutName)
        if !shortcutInput.isEmpty { try c.encode(shortcutInput, forKey: .shortcutInput) }
        try c.encode(http, forKey: .http)
        try c.encode(unsupportedBuiltin ?? builtin.rawValue, forKey: .builtin)   // keep unknown actions intact
        if !url.isEmpty { try c.encode(url, forKey: .url) }
        try c.encode(timeout, forKey: .timeout)
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

// MARK: - Localization

// Per-language overrides; empty / missing fields fall back to the English base.
nonisolated struct WorkflowLocalization: Codable, Equatable, Sendable {
    var name = ""
    var summary = ""
    var argumentHint = ""
    var keywords: [String] = []           // matched together with the English keywords

    private enum CodingKeys: String, CodingKey {
        case name, argumentHint, keywords
        case summary = "description"
    }

    init(name: String = "", summary: String = "", argumentHint: String = "", keywords: [String] = []) {
        self.name = name
        self.summary = summary
        self.argumentHint = argumentHint
        self.keywords = keywords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "")
        summary = c.value(.summary, "")
        argumentHint = c.value(.argumentHint, "")
        keywords = Workflow.cleanKeywords(c.value(.keywords, [String]()))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !name.isEmpty { try c.encode(name, forKey: .name) }
        if !summary.isEmpty { try c.encode(summary, forKey: .summary) }
        if !argumentHint.isEmpty { try c.encode(argumentHint, forKey: .argumentHint) }
        if !keywords.isEmpty { try c.encode(keywords, forKey: .keywords) }
    }

    var isEmpty: Bool {
        keywords.isEmpty && [name, summary, argumentHint].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - Workflow

// JSON keys:
//   "id"  = reverse-DNS identifier (com.youmindhub.emptytrash), unique, shared across machines
//   "uid" = local instance UUID (file name, grants, runner); only in the local store, never exported
nonisolated struct Workflow: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()                       // local uid
    var identifier = ""                   // reverse-DNS id
    var version = "1.0"                   // workflow revision, higher replaces lower on import
    var name: String                      // English (default language)
    var summary = ""                      // English description
    var localizations: [String: WorkflowLocalization] = [:]   // "zh-Hans" → overrides
    var group = ""                        // "system" = AppPad's built-in group, else free text
    var keywords: [String] = []           // exact match ranks first in the panel ("shutdown", "poweroff")
    var argument: ArgumentMode = .off
    var argumentType: ArgumentType = .text
    var argumentHint = ""                 // English, shown as "time ‹minutes›"
    var symbol = ""                       // SF Symbol for the generated icon (optional)
    var enabled = true
    var panelKey: KeyCombo?               // shortcut inside the Workflow panel only (not global)
    var icon: Data?                       // 512×512 PNG; nil = iconURL or generated icon
    var iconURL = ""                      // https image, downloaded to Icons/<identifier>.png
    var successNotice: SuccessNotice = .none     // default: silent on success
    var successMessage = ""
    var failureNotice: FailureNotice = .error
    var failureMessage = ""
    var copyOutput = false                // also put the final output on the clipboard
    var requiresConfirmation = false      // ask before every run (risky actions like Quit All Apps)
    var steps: [WorkflowStep] = []
    var permissions = WorkflowPermissions()
    var formatVersion = WorkflowFormat.current

    private enum CodingKeys: String, CodingKey {
        case uid, id, version, name, localizations, enabled, panelKey, icon, iconURL
        case group, keywords, keyword, argument, argumentType, argumentHint, symbol
        case summary = "description"
        case successNotice, successMessage, failureNotice, failureMessage, copyOutput
        case requiresConfirmation = "confirm"
        case steps, permissions, formatVersion
    }

    private enum LegacyKeys: String, CodingKey {
        case outputMode
    }

    init(name: String, identifier: String = "", steps: [WorkflowStep] = []) {
        self.name = name
        self.identifier = identifier
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawID: String = c.value(.id, "")
        if let uid = try? c.decodeIfPresent(UUID.self, forKey: .uid) {
            id = uid
            identifier = rawID
        } else if let legacy = UUID(uuidString: rawID) {
            // Old files: "id" was the local UUID; the store assigns an identifier.
            id = legacy
            identifier = ""
        } else {
            id = UUID()
            identifier = rawID
        }
        version = c.value(.version, "1.0")
        name = c.value(.name, String(localized: "Workflow"))
        summary = c.value(.summary, "")
        localizations = c.value(.localizations, [:])
        group = c.value(.group, "")
        // "keywords": [...]; early files had one "keyword" string.
        keywords = Workflow.cleanKeywords(c.value(.keywords, [String]()) + [c.value(.keyword, "")])
        argument = c.value(.argument, ArgumentMode.off)
        argumentType = c.value(.argumentType, .text)
        argumentHint = c.value(.argumentHint, "")
        symbol = c.value(.symbol, "")
        enabled = c.value(.enabled, true)
        panelKey = try? c.decodeIfPresent(KeyCombo.self, forKey: .panelKey)
        icon = try? c.decodeIfPresent(Data.self, forKey: .icon)
        iconURL = c.value(.iconURL, "")
        successNotice = c.value(.successNotice, .none)
        successMessage = c.value(.successMessage, "")
        failureNotice = c.value(.failureNotice, .error)
        failureMessage = c.value(.failureMessage, "")
        copyOutput = c.value(.copyOutput, false)
        requiresConfirmation = c.value(.requiresConfirmation, false)   // missing in older files = no prompt
        // Early files: "outputMode" notification / clipboard / none.
        if !c.contains(.successNotice),
           let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let mode = try? legacy.decodeIfPresent(String.self, forKey: .outputMode) {
            if mode == "clipboard" { copyOutput = true }
        }
        steps = c.value(.steps, [])
        permissions = c.value(.permissions, WorkflowPermissions())
        formatVersion = WorkflowFormat.version(in: c, key: .formatVersion) ?? WorkflowFormat.current
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(WorkflowFormat.current, forKey: .formatVersion)
        if encoder.userInfo[WorkflowFormat.includeLocalKey] as? Bool == true {
            try c.encode(id, forKey: .uid)
            try c.encodeIfPresent(panelKey, forKey: .panelKey)
            try c.encode(enabled, forKey: .enabled)
        }
        try c.encode(identifier, forKey: .id)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        if !summary.isEmpty { try c.encode(summary, forKey: .summary) }
        if !localizations.isEmpty { try c.encode(localizations, forKey: .localizations) }
        if !group.isEmpty { try c.encode(group, forKey: .group) }
        if !keywords.isEmpty { try c.encode(keywords, forKey: .keywords) }
        if argument != .off {
            try c.encode(argument, forKey: .argument)
            try c.encode(argumentType, forKey: .argumentType)
            if !argumentHint.isEmpty { try c.encode(argumentHint, forKey: .argumentHint) }
        }
        if !symbol.isEmpty { try c.encode(symbol, forKey: .symbol) }
        if !iconURL.isEmpty {
            try c.encode(iconURL, forKey: .iconURL)
        } else {
            try c.encodeIfPresent(icon, forKey: .icon)
        }
        try c.encode(successNotice, forKey: .successNotice)
        try c.encode(successMessage, forKey: .successMessage)
        try c.encode(failureNotice, forKey: .failureNotice)
        try c.encode(failureMessage, forKey: .failureMessage)
        try c.encode(copyOutput, forKey: .copyOutput)
        if requiresConfirmation { try c.encode(true, forKey: .requiresConfirmation) }
        try c.encode(steps, forKey: .steps)
        try c.encode(permissions, forKey: .permissions)
    }

    // MARK: Localized text

    var displayName: String {
        let localized = WorkflowLanguage.pick(localizations)?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return localized.isEmpty ? name : localized
    }

    var displaySummary: String {
        let localized = WorkflowLanguage.pick(localizations)?.summary.trimmingCharacters(in: .whitespaces) ?? ""
        return localized.isEmpty ? summary : localized
    }

    var displayArgumentHint: String {
        let localized = WorkflowLanguage.pick(localizations)?.argumentHint.trimmingCharacters(in: .whitespaces) ?? ""
        return localized.isEmpty ? argumentHint : localized
    }

    // Keywords that trigger it: current language first, then English ("关机", "shutdown", "poweroff").
    var matchKeywords: [String] {
        Workflow.cleanKeywords((WorkflowLanguage.pick(localizations)?.keywords ?? []) + keywords)
    }

    // First matching keyword: shown in usage hints ("倒计时 ‹时长›").
    var keyword: String { matchKeywords.first ?? "" }

    // Every name the panel matches: localized, English, and all translations.
    var searchNames: [String] {
        var names = [displayName, name]
        for entry in localizations.values where !entry.name.isEmpty && !names.contains(entry.name) {
            names.append(entry.name)
        }
        return names
    }

    // Lowercased, no spaces, no duplicates; commas / spaces separate ("shutdown, poweroff").
    static func cleanKeywords(_ list: [String]) -> [String] {
        var result: [String] = []
        for item in list {
            for word in item.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" }) {
                let w = String(word)
                if !result.contains(w) { result.append(w) }
            }
        }
        return result
    }

    // Frecency key shared with apps (LaunchStats).
    var statsKey: String { "workflow:" + identifier }
}

// MARK: - File format

nonisolated enum WorkflowFormat {
    static let current = "1.0"
    // One parser per format version; files with any other version can't be imported.
    static let supported: Set<String> = ["1.0"]

    // Encoder userInfo flag: write local-only fields (uid, panel key, enabled).
    static let includeLocalKey = CodingUserInfoKey(rawValue: "AppPad.workflow.includeLocal")!

    // Accepts "1.0" or the early integer 1.
    static func version<K: CodingKey>(in c: KeyedDecodingContainer<K>, key: K) -> String? {
        if let text = try? c.decodeIfPresent(String.self, forKey: key) {
            return text.trimmingCharacters(in: .whitespaces)
        }
        if let number = try? c.decodeIfPresent(Int.self, forKey: key) { return "\(number).0" }
        if let number = try? c.decodeIfPresent(Double.self, forKey: key) { return String(number) }
        return nil
    }

    // Decodes one workflow or an array, checking each item's format version first.
    static func decode(_ data: Data) throws -> [Workflow] {
        let decoder = JSONDecoder()
        let probes: [FormatProbe]
        let isArray: Bool
        if let many = try? decoder.decode([FormatProbe].self, from: data) {
            probes = many
            isArray = true
        } else {
            probes = [try decoder.decode(FormatProbe.self, from: data)]
            isArray = false
        }
        if let bad = probes.first(where: { !supported.contains($0.formatVersion) }) {
            throw WorkflowImportError.unsupportedFormat(bad.formatVersion)
        }
        // All supported versions are 1.0 today; dispatch here when a new format is added.
        return isArray ? try decoder.decode([Workflow].self, from: data)
                       : [try decoder.decode(Workflow.self, from: data)]
    }

    nonisolated private struct FormatProbe: Decodable {
        let formatVersion: String

        private enum CodingKeys: String, CodingKey { case formatVersion }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            formatVersion = WorkflowFormat.version(in: c, key: .formatVersion) ?? WorkflowFormat.current
        }
    }
}

nonisolated enum WorkflowImportError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let version):
            return String(localized: "Workflow format \(version) is not supported by this version of AppPad.")
        }
    }
}

// MARK: - Identifier / version rules

nonisolated enum WorkflowIdentity {
    // Reverse-DNS, at least two segments: com.youmindhub, com.youmindhub.emptytrash
    static func isValidIdentifier(_ text: String) -> Bool {
        text.range(of: #"^[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)+$"#, options: .regularExpression) != nil
    }

    static func normalizeIdentifier(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // 1, 1.0, 1.2.3, 2.10
    static func isValidVersion(_ text: String) -> Bool {
        text.range(of: #"^[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil
    }

    // Numeric per component: 1.10 > 1.9, 1.0 == 1
    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    // https only (ATS); empty = no URL.
    static func isValidIconURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return false }
        return true
    }

    // Identifier for workflows that don't have one yet: com.youmindhub.user.<slug>
    static func suggestedIdentifier(for name: String, taken: Set<String>) -> String {
        var slug = ""
        for scalar in name.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug += "-"
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = String(UUID().uuidString.prefix(8)).lowercased() }
        let base = "com.youmindhub.user." + slug
        var candidate = base
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }
}

// MARK: - Language matching

nonisolated enum WorkflowLanguage {
    // Languages offered in the editor (the app's own localizations, English is the base).
    static let editable = ["de", "es", "fr", "it", "ja", "ko", "nl", "zh-Hans", "zh-Hant"]

    // The language AppPad's UI is running in.
    static let current: String = Bundle.main.preferredLocalizations.first ?? "en"

    // Exact key, then same language + script (zh-CN ↔ zh-Hans, but never zh-Hant → zh-Hans).
    static func pick(_ table: [String: WorkflowLocalization]) -> WorkflowLocalization? {
        guard !table.isEmpty else { return nil }
        if let exact = table[current] { return exact }
        let want = maximal(current)
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            let have = maximal(key)
            if have.languageCode == want.languageCode && have.script == want.script { return value }
        }
        return nil
    }

    // Translations of an app string key (Localizable) for every editable language.
    // keywords = the English list joined by ", " (its translation is split the same way).
    static func translations(of key: String, summary: String = "", hint: String = "",
                             keywords: String = "") -> [String: WorkflowLocalization] {
        var table: [String: WorkflowLocalization] = [:]
        for code in editable {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            func look(_ k: String) -> String {
                guard !k.isEmpty else { return "" }
                let value = bundle.localizedString(forKey: k, value: nil, table: nil)
                return value == k ? "" : value
            }
            let entry = WorkflowLocalization(name: look(key), summary: look(summary), argumentHint: look(hint),
                                             keywords: Workflow.cleanKeywords([look(keywords)]))
            if !entry.isEmpty { table[code] = entry }
        }
        return table
    }

    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private static func maximal(_ code: String) -> Locale.Language {
        Locale.Language(identifier: Locale.Language(identifier: code).maximalIdentifier)
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
