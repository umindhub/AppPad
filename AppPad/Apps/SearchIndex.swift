import Foundation

// Precomputed search terms per app (built off the main thread after each scan).
// Scope is intentionally narrow to keep results precise:
// - primary: localized display name in the current system language
// - bundleName: CFBundleName (usually the English name)
// - acronyms: word initials of those two names only — split on spaces/punctuation and on
//   camelCase / digit boundaries ("as" → App Store, "ws" → WebStorm)
// - pinyin / pinyin initials for a CJK display name ("jsq" → 计算器)
nonisolated struct SearchIndex: Sendable {
    nonisolated struct Entry: Sendable {
        let primary: String
        let primaryWords: [String]
        let bundleName: String
        let acronyms: [String]
        let pinyin: String
        let pinyinInitials: String
    }

    private var entries: [String: Entry] = [:]

    init(apps: [AppInfo]) {
        for app in apps {
            entries[app.key] = Self.makeEntry(app)
        }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    // MARK: - Matching

    // Higher is better; 0 = no match. `query` must be normalized.
    func matchScore(_ key: String, query: String) -> Int {
        guard let e = entries[key] else { return 0 }
        let compact = query.replacingOccurrences(of: " ", with: "")
        if e.primary.hasPrefix(query) { return 100 }
        if e.primaryWords.contains(where: { $0.hasPrefix(query) }) { return 85 }
        if compact.count >= 2, e.acronyms.contains(compact) { return 80 }
        if e.bundleName.hasPrefix(query) { return 75 }
        if compact.count >= 2, e.acronyms.contains(where: { $0.hasPrefix(compact) }) { return 72 }
        if !e.pinyinInitials.isEmpty, e.pinyinInitials.hasPrefix(compact) { return 70 }
        if !e.pinyin.isEmpty, e.pinyin.hasPrefix(compact) { return 65 }
        if e.primary.contains(query) { return 50 }
        if e.bundleName.contains(query) { return 40 }
        if !e.pinyin.isEmpty, e.pinyin.contains(compact) { return 30 }
        return 0
    }

    // MARK: - Building

    private static func makeEntry(_ app: AppInfo) -> Entry {
        let primary = normalize(app.name)
        let separators: Set<Character> = [" ", "-", "_", "."]
        let words = primary.split(whereSeparator: { separators.contains($0) }).map(String.init)

        var acronymSet = Set<String>()
        for name in [app.name, app.bundleName] {
            acronyms(of: name).forEach { acronymSet.insert($0) }
        }

        let py = pinyin(of: app.name)
        return Entry(
            primary: primary,
            primaryWords: words,
            bundleName: normalize(app.bundleName),
            acronyms: Array(acronymSet),
            pinyin: py?.full ?? "",
            pinyinInitials: py?.initials ?? ""
        )
    }

    // Word initials for Latin names: plain words ("App Store" → "as") and camelCase / digit
    // boundaries ("WebStorm" → "ws", "IntelliJ IDEA" → "iji"). Only 2+ letters.
    static func acronyms(of name: String) -> [String] {
        guard !name.unicodeScalars.contains(where: { $0.properties.isIdeographic }) else { return [] }
        let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        var result = Set<String>()

        let plain = normalize(String(parts.compactMap(\.first)))
        if plain.count >= 2 { result.insert(plain) }

        var camel = ""
        for part in parts {
            var previous: Character?
            for character in part {
                if let previous {
                    let lowerToUpper = character.isUppercase && previous.isLowercase
                    let digitBoundary = character.isNumber != previous.isNumber
                    if lowerToUpper || digitBoundary { camel.append(character) }
                } else {
                    camel.append(character)
                }
                previous = character
            }
        }
        camel = normalize(camel)
        if camel.count >= 2 { result.insert(camel) }
        return Array(result)
    }

    // Full pinyin and initials for names containing CJK ideographs.
    static func pinyin(of name: String) -> (full: String, initials: String)? {
        guard name.unicodeScalars.contains(where: { $0.properties.isIdeographic }),
              let latin = name.applyingTransform(.toLatin, reverse: false)?
                  .applyingTransform(.stripDiacritics, reverse: false) else { return nil }
        let parts = normalize(latin).split(separator: " ")
        guard !parts.isEmpty else { return nil }
        return (full: parts.joined(), initials: String(parts.compactMap(\.first)))
    }
}
