import Foundation

/// A symbol found in a document, for the Function List panel.
public struct Symbol: Equatable, Sendable {
    public let name: String
    public let kind: String
    public let line: Int
    public let offset: Int
    public init(name: String, kind: String, line: Int, offset: Int) {
        self.name = name
        self.kind = kind
        self.line = line
        self.offset = offset
    }
}

/// Per-language symbol extraction rules.
///
/// Notepad++ drives its Function List from per-language regular expressions in
/// functionList.xml, and we do the same: adding a language means adding a rule,
/// not writing a parser.
public struct FunctionListRule: Sendable {
    public let languageName: String
    /// Each pattern must expose a capture group named `name`.
    public let patterns: [(kind: String, pattern: String)]

    public init(languageName: String, patterns: [(kind: String, pattern: String)]) {
        self.languageName = languageName
        self.patterns = patterns
    }
}

public enum FunctionListExtractor {

    public static let rules: [FunctionListRule] = [
        FunctionListRule(languageName: "Swift", patterns: [
            ("func", #"^\s*(?:public|private|internal|fileprivate|open|static|class|final|override|\s)*func\s+(?<name>\w+)"#),
            ("type", #"^\s*(?:public|private|internal|fileprivate|open|final|\s)*(?:class|struct|enum|protocol|extension)\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "Python", patterns: [
            ("def", #"^\s*(?:async\s+)?def\s+(?<name>\w+)"#),
            ("class", #"^\s*class\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "JavaScript", patterns: [
            ("function", #"^\s*(?:export\s+)?(?:async\s+)?function\s+(?<name>\w+)"#),
            ("const", #"^\s*(?:export\s+)?(?:const|let|var)\s+(?<name>\w+)\s*=\s*(?:async\s*)?(?:\(|function)"#),
            ("class", #"^\s*(?:export\s+)?class\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "TypeScript", patterns: [
            ("function", #"^\s*(?:export\s+)?(?:async\s+)?function\s+(?<name>\w+)"#),
            ("class", #"^\s*(?:export\s+)?(?:abstract\s+)?class\s+(?<name>\w+)"#),
            ("interface", #"^\s*(?:export\s+)?interface\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "C", patterns: [
            ("function", #"^\s*(?:[\w\*]+\s+)+(?<name>\w+)\s*\([^;]*\)\s*\{"#),
            ("struct", #"^\s*(?:typedef\s+)?struct\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "C++", patterns: [
            ("function", #"^\s*(?:[\w\*&:<>]+\s+)+(?<name>\w+)\s*\([^;]*\)\s*(?:const\s*)?\{"#),
            ("class", #"^\s*(?:class|struct)\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "Java", patterns: [
            ("method", #"^\s*(?:public|private|protected|static|final|abstract|synchronized|\s)+[\w\<\>\[\]]+\s+(?<name>\w+)\s*\([^;]*\)\s*\{"#),
            ("class", #"^\s*(?:public|private|abstract|final|\s)*(?:class|interface|enum)\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "Ruby", patterns: [
            ("def", #"^\s*def\s+(?<name>[\w\.\?\!]+)"#),
            ("class", #"^\s*(?:class|module)\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "PHP", patterns: [
            ("function", #"^\s*(?:public|private|protected|static|abstract|final|\s)*function\s+(?<name>\w+)"#),
            ("class", #"^\s*(?:abstract\s+|final\s+)?(?:class|interface|trait)\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "Go", patterns: [
            ("func", #"^\s*func\s+(?:\([^)]*\)\s*)?(?<name>\w+)"#),
            ("type", #"^\s*type\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "Rust", patterns: [
            ("fn", #"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+(?<name>\w+)"#),
            ("type", #"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:struct|enum|trait|impl)\s+(?<name>\w+)"#),
        ]),
        FunctionListRule(languageName: "Shell", patterns: [
            ("function", #"^\s*(?:function\s+)?(?<name>[\w\-]+)\s*\(\s*\)\s*\{"#),
        ]),
        FunctionListRule(languageName: "SQL", patterns: [
            ("routine", #"(?i)^\s*create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+(?<name>[\w\.]+)"#),
            ("table", #"(?i)^\s*create\s+table\s+(?:if\s+not\s+exists\s+)?(?<name>[\w\.]+)"#),
        ]),
        FunctionListRule(languageName: "Lua", patterns: [
            ("function", #"^\s*(?:local\s+)?function\s+(?<name>[\w\.\:]+)"#),
        ]),
        FunctionListRule(languageName: "Markdown", patterns: [
            ("heading", #"^\s*#{1,6}\s+(?<name>.+?)\s*$"#),
        ]),
    ]

    public static func rule(for languageName: String?) -> FunctionListRule? {
        guard let languageName else { return nil }
        return rules.first { $0.languageName.caseInsensitiveCompare(languageName) == .orderedSame }
    }

    /// Extracts symbols line by line. Returns them in document order.
    public static func symbols(in text: String, languageName: String?) -> [Symbol] {
        guard let rule = rule(for: languageName) else { return [] }
        let compiled = rule.patterns.compactMap { entry -> (String, NSRegularExpression)? in
            guard let regex = try? NSRegularExpression(pattern: entry.pattern) else { return nil }
            return (entry.kind, regex)
        }
        guard !compiled.isEmpty else { return [] }

        let (lines, _) = LineOperations.split(text)
        var offset = 0
        var symbols: [Symbol] = []

        for (index, line) in lines.enumerated() {
            let range = NSRange(location: 0, length: (line as NSString).length)
            for (kind, regex) in compiled {
                guard let match = regex.firstMatch(in: line, options: [], range: range) else { continue }
                let nameRange = match.range(withName: "name")
                guard nameRange.location != NSNotFound else { continue }
                let name = (line as NSString).substring(with: nameRange)
                symbols.append(Symbol(name: name, kind: kind, line: index, offset: offset + nameRange.location))
                break   // first matching rule wins, so a line yields one symbol
            }
            offset += (line as NSString).length + 1   // + newline
        }
        return symbols
    }
}
