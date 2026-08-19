import Foundation

/// The three search modes in Notepad++'s Find dialog.
public enum SearchMode: String, CaseIterable, Sendable {
    case normal
    /// Literal text plus C-style escapes (\n, \t, \0, \xHH, \uHHHH, \\).
    case extended
    case regex
}

public struct SearchOptions: Sendable {
    public var mode: SearchMode
    public var matchCase: Bool
    public var wholeWord: Bool
    public var wrapAround: Bool
    public var backward: Bool
    /// Regex only: make `.` match newlines too.
    public var dotMatchesNewline: Bool

    public init(
        mode: SearchMode = .normal, matchCase: Bool = false, wholeWord: Bool = false,
        wrapAround: Bool = true, backward: Bool = false, dotMatchesNewline: Bool = false
    ) {
        self.mode = mode
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.wrapAround = wrapAround
        self.backward = backward
        self.dotMatchesNewline = dotMatchesNewline
    }
}

public struct SearchMatch: Equatable, Sendable {
    public let range: NSRange
    /// Capture groups, for regex replacement. Index 0 is the whole match.
    public let groups: [NSRange]
    public init(range: NSRange, groups: [NSRange] = []) {
        self.range = range
        self.groups = groups
    }
}

public enum SearchError: Error, Equatable {
    case invalidRegex(String)
    case emptyPattern
}

/// Find/replace for a single buffer.
///
/// Regex uses ICU via `NSRegularExpression`, whereas Notepad++ uses Boost.
/// `\K`, conditionals `(?(1)...)`, recursion `(?R)` and `\g{NAME}` have no ICU
/// equivalent — see docs/ARCHITECTURE.md. Patterns are never silently rewritten;
/// an unsupported construct surfaces as `invalidRegex`.
public struct SearchEngine: Sendable {
    public let options: SearchOptions
    private let pattern: String

    public init(pattern: String, options: SearchOptions) {
        self.pattern = pattern
        self.options = options
    }

    /// Decodes the escapes Notepad++ accepts in Extended mode.
    public static func decodeExtended(_ input: String) -> String {
        var result = ""
        var iterator = Array(input)
        var index = 0
        while index < iterator.count {
            guard iterator[index] == "\\", index + 1 < iterator.count else {
                result.append(iterator[index]); index += 1; continue
            }
            let next = iterator[index + 1]
            index += 2
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "0": result.append("\0")
            case "a": result.append("\u{07}")
            case "b": result.append("\u{08}")
            case "f": result.append("\u{0C}")
            case "v": result.append("\u{0B}")
            case "\\": result.append("\\")
            case "x", "u":
                let width = (next == "x") ? 2 : 4
                let digits = String(iterator[index..<min(index + width, iterator.count)])
                if digits.count == width, let value = UInt32(digits, radix: 16),
                   let scalar = Unicode.Scalar(value) {
                    result.unicodeScalars.append(scalar)
                    index += width
                } else {
                    // Not a valid escape — emit it literally rather than guessing.
                    result.append("\\"); result.append(next)
                }
            default:
                result.append("\\"); result.append(next)
            }
        }
        return result
    }

    /// Builds the effective regular expression for any mode. Normal and Extended
    /// are implemented by escaping the literal and reusing one match path, so
    /// whole-word and case options behave identically across modes.
    private func makeRegex() throws -> NSRegularExpression {
        guard !pattern.isEmpty else { throw SearchError.emptyPattern }
        var expression: String
        switch options.mode {
        case .normal:
            expression = NSRegularExpression.escapedPattern(for: pattern)
        case .extended:
            expression = NSRegularExpression.escapedPattern(for: Self.decodeExtended(pattern))
        case .regex:
            expression = pattern
        }
        if options.wholeWord {
            expression = "\\b(?:\(expression))\\b"
        }
        var flags: NSRegularExpression.Options = []
        if !options.matchCase { flags.insert(.caseInsensitive) }
        if options.dotMatchesNewline { flags.insert(.dotMatchesLineSeparators) }
        do {
            return try NSRegularExpression(pattern: expression, options: flags)
        } catch {
            throw SearchError.invalidRegex(error.localizedDescription)
        }
    }

    /// Every match in `range` (defaults to the whole string).
    public func matches(in text: String, range: NSRange? = nil) throws -> [SearchMatch] {
        let regex = try makeRegex()
        let content = text as NSString
        let searchRange = range ?? NSRange(location: 0, length: content.length)
        return regex.matches(in: text, options: [], range: searchRange).map { result in
            SearchMatch(
                range: result.range,
                groups: (0..<result.numberOfRanges).map { result.range(at: $0) }
            )
        }
    }

    public func count(in text: String, range: NSRange? = nil) throws -> Int {
        try matches(in: text, range: range).count
    }

    /// The next match after `location`, honouring direction and wrap-around.
    public func find(in text: String, from location: Int, within range: NSRange? = nil) throws -> SearchMatch? {
        let all = try matches(in: text, range: range)
        guard !all.isEmpty else { return nil }

        if options.backward {
            if let previous = all.last(where: { $0.range.location < location }) { return previous }
            return options.wrapAround ? all.last : nil
        }
        if let next = all.first(where: { $0.range.location >= location }) { return next }
        return options.wrapAround ? all.first : nil
    }

    /// Replaces one match. In regex mode `replacement` may reference capture
    /// groups with `$1`; in other modes it is inserted literally.
    public func replace(in text: String, match: SearchMatch, with replacement: String) throws -> String {
        let content = text as NSString
        guard options.mode == .regex else {
            return content.replacingCharacters(in: match.range, with: replacement)
        }
        let regex = try makeRegex()
        let expanded = regex.replacementString(
            for: regex.firstMatch(in: text, options: [], range: match.range)!,
            in: text, offset: 0, template: replacement
        )
        return content.replacingCharacters(in: match.range, with: expanded)
    }

    /// Replaces every match. Returns the new text and how many were replaced.
    public func replaceAll(in text: String, with replacement: String, range: NSRange? = nil) throws -> (text: String, count: Int) {
        let regex = try makeRegex()
        let content = text as NSString
        let searchRange = range ?? NSRange(location: 0, length: content.length)
        let total = regex.numberOfMatches(in: text, options: [], range: searchRange)
        guard total > 0 else { return (text, 0) }

        let template = (options.mode == .regex)
            ? replacement
            : NSRegularExpression.escapedTemplate(for: replacement)
        let updated = regex.stringByReplacingMatches(
            in: text, options: [], range: searchRange, withTemplate: template
        )
        return (updated, total)
    }
}
