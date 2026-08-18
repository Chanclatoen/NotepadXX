import Foundation

/// Finds the partner of a bracket, for Notepad++'s brace matching and
/// "Select All Between Matching Braces".
public enum BraceMatching {
    static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    static let reversed: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// The matching bracket for the one at `location`, or nil when the caret is
    /// not on a bracket or the bracket is unbalanced.
    ///
    /// Brackets inside comments and string literals are skipped when a language
    /// is supplied — otherwise a brace in `"}"` would match a real one.
    public static func match(in text: String, at location: Int, language: LanguageDefinition? = nil) -> Int? {
        let content = text as NSString
        guard location >= 0, location < content.length else { return nil }
        let character = Character(content.substring(with: NSRange(location: location, length: 1)))

        let ignored = language.map { ignoredRanges(in: text, language: $0) } ?? []
        guard !isIgnored(location, ignored) else { return nil }

        if let closing = pairs[character] {
            return scan(content, from: location + 1, open: character, close: closing, step: 1, ignored: ignored)
        }
        if let opening = reversed[character] {
            return scan(content, from: location - 1, open: opening, close: character, step: -1, ignored: ignored)
        }
        return nil
    }

    /// The range between a matched pair, inclusive of both brackets.
    public static func enclosingRange(in text: String, at location: Int,
                                      language: LanguageDefinition? = nil) -> NSRange? {
        guard let partner = match(in: text, at: location, language: language) else { return nil }
        let start = min(location, partner)
        let end = max(location, partner)
        return NSRange(location: start, length: end - start + 1)
    }

    private static func scan(
        _ content: NSString, from start: Int, open: Character, close: Character,
        step: Int, ignored: [NSRange]
    ) -> Int? {
        var depth = 1
        var index = start
        while index >= 0 && index < content.length {
            if !isIgnored(index, ignored) {
                let character = Character(content.substring(with: NSRange(location: index, length: 1)))
                // Walking forward we descend on `open`; walking back, on `close`.
                if character == (step > 0 ? open : close) {
                    depth += 1
                } else if character == (step > 0 ? close : open) {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index += step
        }
        return nil
    }

    /// Comment and string ranges, which brackets inside are ignored.
    static func ignoredRanges(in text: String, language: LanguageDefinition) -> [NSRange] {
        Lexer(language: language).tokenize(text).tokens
            .filter { $0.type == .comment || $0.type == .commentLine
                   || $0.type == .string || $0.type == .character }
            .map(\.range)
    }

    private static func isIgnored(_ location: Int, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSLocationInRange(location, $0) }
    }
}
