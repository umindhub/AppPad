import Foundation

// Panel query "time 1h30m": search term "time", argument "1h30m".
// The argument is parsed by the workflow's ArgumentType and becomes the first step's input.
nonisolated struct ParsedArgument: Sendable {
    let value: String     // passed to the first step ("5400", "07:30", …)
    let summary: String   // shown in the preview ("1 hour, 30 minutes")
}

nonisolated struct ArgumentError: Error, Sendable {
    let message: String
}

nonisolated enum WorkflowArguments {
    // Splits at the first space; leading spaces are ignored.
    static func split(_ query: String) -> (term: String, argument: String) {
        let text = query.drop(while: { $0.isWhitespace })
        guard let space = text.firstIndex(where: { $0.isWhitespace }) else {
            return (String(text), "")
        }
        let argument = text[space...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(text[..<space]), argument)
    }

    static func parse(_ raw: String, type: ArgumentType, mode: ArgumentMode) -> Result<ParsedArgument, ArgumentError> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .off:
            return .success(ParsedArgument(value: "", summary: ""))
        case .optional where text.isEmpty:
            return .success(ParsedArgument(value: "", summary: ""))
        case .required where text.isEmpty:
            return .failure(ArgumentError(message: String(localized: "Type the argument after a space.")))
        default:
            break
        }
        switch type {
        case .text:
            return .success(ParsedArgument(value: text, summary: text))
        case .number:
            guard let number = Int(text) else {
                return .failure(ArgumentError(message: String(localized: "Not a number.")))
            }
            return .success(ParsedArgument(value: String(number), summary: String(number)))
        case .duration:
            guard let seconds = durationSeconds(text), seconds > 0, seconds < 86_400 else {
                return .failure(ArgumentError(message: String(localized: "Not a duration. Try 10, 90s or 1h30m.")))
            }
            return .success(ParsedArgument(value: String(seconds), summary: formatDuration(seconds)))
        case .time:
            guard let time = timeAndLabel(text) else {
                return .failure(ArgumentError(message: String(localized: "Not a time. Try 7:30, 19:30 or 7pm.")))
            }
            // "07:30" or "07:30\nWake up" (the label is everything after the time).
            let clock = String(format: "%02d:%02d", time.hour, time.minute)
            let shown = formatTime(time.hour, time.minute)
            if time.label.isEmpty { return .success(ParsedArgument(value: clock, summary: shown)) }
            return .success(ParsedArgument(value: clock + "\n" + time.label, summary: shown + " · " + time.label))
        }
    }

    // Sample arguments for the preview.
    static func examples(for type: ArgumentType) -> [String] {
        switch type {
        case .duration: return ["10", "90s", "1h30m"]
        case .time: return ["7:30", "19:30", "7pm"]
        case .number: return ["30"]
        case .text: return []
        }
    }

    // MARK: - Duration

    // "10" = minutes; units h/m/s (also 小时/分钟/秒); "1h30" = 1 h 30 min; "1:30" = 1 min 30 s; "1:02:03" = h:m:s.
    static func durationSeconds(_ input: String) -> Int? {
        let text = input.lowercased().replacingOccurrences(of: " ", with: "")
        if let minutes = Double(text) { return Int((minutes * 60).rounded()) }

        let colon = text.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        if colon.count >= 2, colon.count <= 3, colon.allSatisfy({ $0 != nil }) {
            let parts = colon.map { $0! }
            if parts.dropFirst().contains(where: { $0 >= 60 }) { return nil }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2]
        }

        let units: [(names: [String], seconds: Double)] = [
            (["hours", "hour", "hrs", "hr", "h", "小时", "小時", "时", "時"], 3600),
            (["minutes", "minute", "mins", "min", "m", "分钟", "分鐘", "分"], 60),
            (["seconds", "second", "secs", "sec", "s", "秒"], 1),
        ]
        var rest = Substring(text)
        var total = 0.0
        var lastUnit: Double?
        while !rest.isEmpty {
            let digits = rest.prefix(while: { $0.isNumber || $0 == "." })
            guard !digits.isEmpty, let value = Double(digits) else { return nil }
            rest = rest.dropFirst(digits.count)
            if rest.isEmpty {
                // Bare trailing number: one unit below the previous one (1h30 → 30 min).
                guard let lastUnit, lastUnit > 1 else { return nil }
                total += value * lastUnit / 60
                break
            }
            guard let unit = units.first(where: { unit in unit.names.contains { rest.hasPrefix($0) } }),
                  let name = unit.names.first(where: { rest.hasPrefix($0) }) else { return nil }
            total += value * unit.seconds
            lastUnit = unit.seconds
            rest = rest.dropFirst(name.count)
        }
        return total > 0 ? Int(total.rounded()) : nil
    }

    static func formatDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds) s"
    }

    // MARK: - Clock time

    // "7:30 Wake up", "7:30 pm Wake up", "下午 3点 开会" → time + optional label.
    static func timeAndLabel(_ input: String) -> (hour: Int, minute: Int, label: String)? {
        let tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first else { return nil }
        let meridiems: Set<String> = ["am", "pm", "a.m.", "p.m."]
        let prefixes: Set<String> = ["上午", "早上", "凌晨", "中午", "下午", "晚上"]
        if tokens.count >= 2, meridiems.contains(tokens[1].lowercased()) || prefixes.contains(first),
           let time = clockTime(first + tokens[1]) {
            return (time.hour, time.minute, tokens.dropFirst(2).joined(separator: " "))
        }
        guard let time = clockTime(first) else { return nil }
        return (time.hour, time.minute, tokens.dropFirst().joined(separator: " "))
    }

    // 7:30, 07.30, 730, 1930, 7, 7pm, 7:30am, 下午3点, 7点半
    static func clockTime(_ input: String) -> (hour: Int, minute: Int)? {
        var text = input.lowercased().replacingOccurrences(of: " ", with: "")
        var meridiem: Character?   // "a" / "p"
        for (prefix, mark) in [("上午", "a"), ("早上", "a"), ("凌晨", "a"), ("中午", "p"), ("下午", "p"), ("晚上", "p")]
        where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            meridiem = Character(mark)
        }
        for suffix in ["am", "a.m.", "a", "pm", "p.m.", "p"] where text.hasSuffix(suffix) {
            meridiem = suffix.first
            text.removeLast(suffix.count)
            break
        }
        text = text.replacingOccurrences(of: "点半", with: ":30")
            .replacingOccurrences(of: "點半", with: ":30")
            .replacingOccurrences(of: "点", with: ":")
            .replacingOccurrences(of: "點", with: ":")
            .replacingOccurrences(of: "分", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: ".", with: ":")
        if text.hasSuffix(":") { text.removeLast() }

        var hour: Int
        var minute = 0
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), parts[1].count == 2 {
            hour = h
            minute = m
        } else if parts.count == 1, let number = Int(text), text.allSatisfy(\.isNumber) {
            switch text.count {
            case 1, 2: hour = number
            case 3, 4: hour = number / 100; minute = number % 100
            default: return nil
            }
        } else {
            return nil
        }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "p", hour < 12 { hour += 12 }
            if meridiem == "a", hour == 12 { hour = 0 }
        }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour: hour, minute: minute)
    }

    static func formatTime(_ hour: Int, _ minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else { return String(format: "%02d:%02d", hour, minute) }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
