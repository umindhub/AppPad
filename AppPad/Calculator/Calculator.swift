import Foundation

// Expression evaluator for the search field.
// Supports + - * / ^ (or **), × ÷, % (postfix percent, or modulo between operands), mod, !,
// parentheses (auto-closed), implicit multiplication (2pi, 3(4+5)),
// scientific notation (1.5e-3, 2E10), constants pi/π/e/tau and common functions.
nonisolated enum Calculator {
    nonisolated struct Result: Equatable, Sendable {
        let value: Double
        let display: String    // localized, grouped
        let copyText: String   // plain, machine readable
    }

    static func evaluateIfExpression(_ input: String) -> Result? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeExpression(text),
              let value = evaluate(text),
              value.isFinite else { return nil }
        return Result(value: value, display: format(value, grouping: true), copyText: format(value, grouping: false))
    }

    static func evaluate(_ text: String) -> Double? {
        guard let tokens = tokenize(text), !tokens.isEmpty else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        return value
    }

    // Avoid treating plain app names (e.g. "Microsoft 365") as math.
    static func looksLikeExpression(_ s: String) -> Bool {
        let lower = s.lowercased()
        let hasNumber = s.contains(where: { $0.isASCII && $0.isNumber })
            || lower.contains("pi") || s.contains("π")
        guard hasNumber else { return false }
        let operators: Set<Character> = ["+", "-", "−", "*", "/", "^", "%", "(", ")", "×", "÷", "!"]
        if s.contains(where: { operators.contains($0) }) { return true }
        if lower.range(of: #"\bmod\b"#, options: .regularExpression) != nil { return true }
        // Pure scientific notation like 6.02e23
        return s.range(of: #"^\s*[0-9]*\.?[0-9]+[eE][+-]?[0-9]+\s*$"#, options: .regularExpression) != nil
    }

    // MARK: - Formatting

    static func format(_ value: Double, grouping: Bool) -> String {
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-6 {
            let parts = String(format: "%.9e", value).split(separator: "e")
            guard parts.count == 2 else { return "\(value)" }
            var mantissa = String(parts[0])
            if mantissa.contains(".") {
                while mantissa.hasSuffix("0") { mantissa.removeLast() }
                if mantissa.hasSuffix(".") { mantissa.removeLast() }
            }
            let exponent = Int(parts[1]) ?? 0
            return "\(mantissa)e\(exponent)"
        }
        // Trim binary noise like 0.1 + 0.2 = 0.30000000000000004
        let cleaned = Double(String(format: "%.12g", value)) ?? value
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = grouping
        formatter.locale = grouping ? Locale.current : Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: cleaned)) ?? "\(cleaned)"
    }

    // MARK: - Tokenizer

    nonisolated enum Token: Equatable, Sendable {
        case number(Double)
        case ident(String)
        case op(Character)
        case lparen
        case rparen
    }

    static func tokenize(_ s: String) -> [Token]? {
        let chars = Array(s)
        var tokens: [Token] = []
        var depth = 0
        var i = 0

        func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

        while i < chars.count {
            let c = chars[i]

            if c == " " || c == "," || c == "_" {
                i += 1
                continue
            }

            if isDigit(c) || c == "." {
                var j = i
                var literal = ""
                while j < chars.count, isDigit(chars[j]) || chars[j] == "." {
                    literal.append(chars[j])
                    j += 1
                }
                // Exponent part only when digits follow: 1e5, 2.5E-3
                if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                    var k = j + 1
                    var exponent = "e"
                    if k < chars.count, chars[k] == "+" || chars[k] == "-" {
                        exponent.append(chars[k])
                        k += 1
                    }
                    var digits = ""
                    while k < chars.count, isDigit(chars[k]) {
                        digits.append(chars[k])
                        k += 1
                    }
                    if !digits.isEmpty {
                        literal += exponent + digits
                        j = k
                    }
                }
                guard let value = Double(literal) else { return nil }
                tokens.append(.number(value))
                i = j
                continue
            }

            if c.isLetter || c == "π" {
                var j = i
                var name = ""
                while j < chars.count, chars[j].isLetter || chars[j] == "π" {
                    name.append(chars[j])
                    j += 1
                }
                name = name.lowercased()
                // log2 / log10
                if name == "log" {
                    if j + 1 < chars.count, chars[j] == "1", chars[j + 1] == "0" {
                        name = "log10"
                        j += 2
                    } else if j < chars.count, chars[j] == "2" {
                        name = "log2"
                        j += 1
                    }
                }
                tokens.append(.ident(name))
                i = j
                continue
            }

            switch c {
            case "+":
                tokens.append(.op("+"))
            case "-", "−", "–":
                tokens.append(.op("-"))
            case "*", "×", "·":
                if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                    tokens.append(.op("^"))
                    i += 1
                } else {
                    tokens.append(.op("*"))
                }
            case "/", "÷":
                tokens.append(.op("/"))
            case "^", "%", "!":
                tokens.append(.op(c))
            case "(":
                depth += 1
                tokens.append(.lparen)
            case ")":
                depth -= 1
                guard depth >= 0 else { return nil }
                tokens.append(.rparen)
            default:
                return nil
            }
            i += 1
        }

        // Auto-close trailing parentheses while typing.
        tokens += Array(repeating: .rparen, count: depth)
        return tokens
    }

    // MARK: - Parser (recursive descent)
    //   expr    := term (('+'|'-') term)*
    //   term    := unary (('*'|'/'|'%'|'mod') unary | implicit unary)*
    //   unary   := ('+'|'-') unary | power
    //   power   := postfix ('^' unary)?
    //   postfix := primary ('!' | '%')*
    //   primary := number | constant | func '(' expr ')' | '(' expr ')'

    static let constants: [String: Double] = [
        "pi": Double.pi, "π": Double.pi, "e": M_E, "tau": 2 * Double.pi,
    ]

    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { sqrt($0) }, "cbrt": { cbrt($0) }, "abs": { abs($0) },
        "ln": { log($0) }, "log": { log10($0) }, "log10": { log10($0) }, "log2": { log2($0) },
        "exp": { exp($0) },
        "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "sinh": { sinh($0) }, "cosh": { cosh($0) }, "tanh": { tanh($0) },
        "floor": { floor($0) }, "ceil": { ceil($0) }, "round": { $0.rounded() },
    ]

    nonisolated struct Parser {
        let tokens: [Token]
        var pos = 0

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        var isAtEnd: Bool { pos >= tokens.count }

        func peek(_ offset: Int = 0) -> Token? {
            let index = pos + offset
            return index < tokens.count ? tokens[index] : nil
        }

        mutating func advance() -> Token? {
            let token = peek()
            pos += 1
            return token
        }

        func startsOperand(_ token: Token?) -> Bool {
            switch token {
            case .number?, .lparen?: return true
            case .ident(let name)?: return name != "mod"
            default: return false
            }
        }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while case .op(let o)? = peek(), o == "+" || o == "-" {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = o == "+" ? lhs + rhs : lhs - rhs
            }
            return lhs
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parseUnary() else { return nil }
            while true {
                let token = peek()
                if case .op(let o)? = token, o == "*" || o == "/" || o == "%" {
                    pos += 1
                    guard let rhs = parseUnary() else { return nil }
                    switch o {
                    case "*": lhs *= rhs
                    case "/": lhs /= rhs
                    default: lhs = lhs.truncatingRemainder(dividingBy: rhs)
                    }
                } else if case .ident("mod")? = token {
                    pos += 1
                    guard let rhs = parseUnary() else { return nil }
                    lhs = lhs.truncatingRemainder(dividingBy: rhs)
                } else if startsOperand(token) {
                    // Implicit multiplication: 2pi, 3(4+5)
                    guard let rhs = parsePower() else { return nil }
                    lhs *= rhs
                } else {
                    break
                }
            }
            return lhs
        }

        mutating func parseUnary() -> Double? {
            if case .op(let o)? = peek(), o == "-" || o == "+" {
                pos += 1
                guard let value = parseUnary() else { return nil }
                return o == "-" ? -value : value
            }
            return parsePower()
        }

        mutating func parsePower() -> Double? {
            guard let base = parsePostfix() else { return nil }
            if case .op("^")? = peek() {
                pos += 1
                guard let exponent = parseUnary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while case .op(let o)? = peek(), o == "!" || o == "%" {
                // "a % b" is modulo (handled in parseTerm); trailing "%" is percent.
                if o == "%", startsOperand(peek(1)) { break }
                pos += 1
                if o == "%" {
                    value /= 100
                } else {
                    guard let f = Self.factorial(value) else { return nil }
                    value = f
                }
            }
            return value
        }

        mutating func parsePrimary() -> Double? {
            guard let token = advance() else { return nil }
            switch token {
            case .number(let value):
                return value
            case .lparen:
                guard let value = parseExpression(), case .rparen? = advance() else { return nil }
                return value
            case .ident(let name):
                if let constant = Calculator.constants[name] { return constant }
                guard let function = Calculator.functions[name],
                      case .lparen? = advance(),
                      let argument = parseExpression(),
                      case .rparen? = advance() else { return nil }
                return function(argument)
            default:
                return nil
            }
        }

        static func factorial(_ n: Double) -> Double? {
            guard n >= 0, n <= 170 else { return nil }
            guard n == n.rounded() else { return tgamma(n + 1) }
            var result = 1.0
            var i = 2.0
            while i <= n {
                result *= i
                i += 1
            }
            return result
        }
    }
}
