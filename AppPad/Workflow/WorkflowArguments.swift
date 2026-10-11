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
        case .reminder:
            guard let request = ReminderParser.parse(text), let json = request.json else {
                return .failure(ArgumentError(message: String(localized: "Add the reminder text.")))
            }
            return .success(ParsedArgument(value: json, summary: request.summary))
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
        case .reminder:
            return [String(localized: "tomorrow 3pm Call Mom"), String(localized: "in 2 hours Pay bills !!"),
                    String(localized: "Buy milk @Shopping")]
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

// MARK: - Reminders

// What "remind" creates in the Reminders app (passed as JSON to the builtin step).
nonisolated struct ReminderRequest: Codable, Sendable {
    var title: String
    var date: Double?          // alert time, ms since 1970 (JXA new Date(ms))
    var priority = 0           // Reminders: 0 none, 1 high, 5 medium, 9 low
    var list = ""              // empty = default list

    var json: String? {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }

    static func decode(_ text: String) -> ReminderRequest? {
        guard text.hasPrefix("{") else { return nil }
        return try? JSONDecoder().decode(ReminderRequest.self, from: Data(text.utf8))
    }

    // "Call Mom · Tomorrow at 3:00 PM · High · @Work"
    var summary: String {
        var parts = [title]
        if let date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            parts.append(formatter.string(from: Date(timeIntervalSince1970: date / 1000)))
        }
        switch priority {
        case 1: parts.append(String(localized: "High priority"))
        case 5: parts.append(String(localized: "Medium priority"))
        case 9: parts.append(String(localized: "Low priority"))
        default: break
        }
        if !list.isEmpty { parts.append("@" + list) }
        return parts.joined(separator: " · ")
    }
}

// Like Alfred's "r": text with an optional date, "!"/"!!"/"!!!" priority (start or end) and "@List" (end).
// Dates: Chinese rules first (明天下午3点, 10分钟后, 下周五), then NSDataDetector (tomorrow 3pm, in 2 hours…).
nonisolated enum ReminderParser {
    static func parse(_ input: String, now: Date = Date()) -> ReminderRequest? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = ReminderRequest(title: "")

        // Priority: leading or trailing run of 1–3 "!" (also full-width "！").
        let bangs = #"[!！]{1,3}"#
        if let range = text.range(of: "^" + bangs + #"(?=\s|$)"#, options: .regularExpression)
            ?? text.range(of: #"(?<=\s|^)"# + bangs + "$", options: .regularExpression) {
            request.priority = [1: 9, 2: 5, 3: 1][text[range].count] ?? 0
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        // List: trailing "@Name".
        if let range = text.range(of: #"(?<=\s|^)[@＠]\S+$"#, options: .regularExpression) {
            request.list = String(text[range].dropFirst())
            text.removeSubrange(range)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        // Date: remove the matched words from the title.
        if let found = chineseDate(in: text, now: now) ?? relativeEnglishDate(in: text, now: now)
            ?? detectedDate(in: text, now: now) {
            request.date = (found.date.timeIntervalSince1970 * 1000).rounded()
            text.removeSubrange(found.range)
        }
        request.title = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",，、")))
        return request.title.isEmpty ? nil : request
    }

    // MARK: Chinese

    private static let dayWords = #"今天|今晚|明天|明早|明晚|后天|後天|大后天|大後天|(?:下|这|這|本)?(?:周|週|星期|礼拜|禮拜)[一二三四五六日天]"#
    private static let periods = #"凌晨|早上|上午|中午|下午|傍晚|晚上"#

    private static func chineseDate(in text: String, now: Date) -> (date: Date, range: Range<String.Index>)? {
        let calendar = Calendar.current
        // 10分钟后 / 半小时后 / 2个小时后 / 3天后
        let relative = #"(\d+|半)\s*个?\s*(分钟|分鐘|小时|小時|钟头|鐘頭|天|周|週|星期)\s*(之)?后|(\d+|半)\s*个?\s*(分钟|分鐘|小时|小時|钟头|鐘頭|天|周|週|星期)\s*(之)?後"#
        if let range = text.range(of: relative, options: .regularExpression) {
            let match = String(text[range])
            let amount: Double = match.hasPrefix("半") ? 0.5
                : Double(match.prefix(while: \.isNumber)) ?? 0
            let seconds: Double
            if match.contains("分") { seconds = 60 }
            else if match.contains("小") || match.contains("钟头") || match.contains("鐘頭") { seconds = 3600 }
            else if match.contains("天") { seconds = 86_400 }
            else { seconds = 7 * 86_400 }
            return (now.addingTimeInterval(amount * seconds), range)
        }

        // [day] [period] H[:MM | 点[MM分|半]]   or   day alone
        let timed = "(" + dayWords + #")?\s*("# + periods + #")?\s*(\d{1,2})(?:[:：](\d{2})|[点點時](?:(\d{1,2})分?|(半))?)"#
        let regex = try? NSRegularExpression(pattern: timed)
        let ns = text as NSString
        if let m = regex?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
           let range = Range(m.range, in: text) {
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            // A bare "3:30" (no 明天 / 下午 …) is left to NSDataDetector ("tomorrow at 3:30pm").
            if group(1) == nil, group(2) == nil, group(4) != nil { return detectedOnlyChinese(text, now: now) }
            var hour = Int(group(3) ?? "") ?? 0
            let minute = group(6) != nil ? 30 : Int(group(4) ?? group(5) ?? "0") ?? 0
            let day = group(1)
            let period = group(2) ?? ""
            let evening = ["下午", "傍晚", "晚上"].contains(period) || day == "今晚" || day == "明晚"
            if evening && hour < 12 { hour += 12 }
            if period == "中午" && hour < 11 { hour += 12 }
            guard hour < 24, minute < 60 else { return nil }
            guard var date = dayStart(day, now: now) else { return nil }
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
            if day == nil, date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return (date, range)
        }
        return detectedOnlyChinese(text, now: now)
    }

    // A Chinese day word alone: 明天 → 9:00, 今晚 / 明晚 → 20:00.
    private static func detectedOnlyChinese(_ text: String, now: Date) -> (date: Date, range: Range<String.Index>)? {
        guard let range = text.range(of: dayWords, options: .regularExpression),
              let start = dayStart(String(text[range]), now: now) else { return nil }
        let word = String(text[range])
        let hour = word == "今晚" || word == "明晚" ? 20 : 9
        return (Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: start) ?? start, range)
    }

    // Start of the day a Chinese day word means (nil word = today).
    private static func dayStart(_ word: String?, now: Date) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let word else { return today }
        let offsets = ["今天": 0, "今晚": 0, "明天": 1, "明早": 1, "明晚": 1, "后天": 2, "後天": 2, "大后天": 3, "大後天": 3]
        if let offset = offsets[word] { return calendar.date(byAdding: .day, value: offset, to: today) }
        // 周X / 下周X: Monday = 0 … Sunday = 6
        let names: [Character: Int] = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6]
        guard let last = word.last, let target = names[last] else { return nil }
        let current = (calendar.component(.weekday, from: now) + 5) % 7
        var days = target - current
        if word.hasPrefix("下") {
            days += 7
        } else if days < 0 {
            days += 7
        }
        return calendar.date(byAdding: .day, value: days, to: today)
    }

    // MARK: English / other languages

    // "in 5 minutes", "in 2 hours", "in 3 days" (NSDataDetector misses some of these).
    private static func relativeEnglishDate(in text: String, now: Date) -> (date: Date, range: Range<String.Index>)? {
        let pattern = #"(?i)\bin\s+(\d+|an?|half an)\s*(min|mins|minutes?|hrs?|hours?|days?|weeks?)\b"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let words = text[range].lowercased().split(separator: " ").dropFirst()
        let first = words.first.map(String.init) ?? ""
        let amount: Double = first == "half" ? 0.5 : (first == "a" || first == "an") ? 1 : Double(first) ?? 1
        let unit = text[range].lowercased()
        let seconds: Double = unit.contains("min") ? 60 : (unit.contains("h") && !unit.contains("week")) ? 3600
            : unit.contains("day") ? 86_400 : 7 * 86_400
        return (now.addingTimeInterval(amount * seconds), range)
    }

    // Apple's natural-language date detection ("tomorrow at 3pm", "next Thursday 15:30", "on 24 Dec").
    private static func detectedDate(in text: String, now: Date) -> (date: Date, range: Range<String.Index>)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              var date = match.date, let range = Range(match.range, in: text) else { return nil }
        let words = text[range].lowercased()
        // A day without a time ("tomorrow") → 9:00.
        let hasTime = words.contains(where: \.isNumber)
            || ["noon", "midnight", "morning", "afternoon", "evening", "night"].contains { words.contains($0) }
        if !hasTime {
            date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        // "at 2pm" when it is already 5pm → tomorrow.
        if date < now, now.timeIntervalSince(date) < 86_400 {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return (date, range)
    }
}
