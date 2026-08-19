import Foundation

/// Closing brackets, quotes and tags as they are typed.
///
/// The rules are here rather than in the editor so they can be reasoned about
/// on their own: what gets closed, what gets skipped over, and — the part that
/// makes the difference between helpful and infuriating — when to do nothing.
public enum AutoClose {

    /// The pairs that close. Quotes are their own closer, which is why they
    /// need the extra "am I already inside one" check below.
    public static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`",
    ]

    /// What to do about a typed character.
    public enum Action: Equatable {
        /// Insert the closing character after the caret.
        case close(String)
        /// The closer is already there: step over it instead of adding another.
        case skip
        /// Leave it alone.
        case none
    }

    /// Decides what a typed character should do.
    ///
    /// - Parameters:
    ///   - typed: the character just inserted.
    ///   - text: the document *after* the insertion.
    ///   - caret: where the caret is now, after the insertion.
    public static func action(for typed: Character, in text: String, caret: Int) -> Action {
        let content = text as NSString
        let following = caret < content.length
            ? Character(content.substring(with: NSRange(location: caret, length: 1)))
            : nil

        // Typing the closer when it is already the next character steps over
        // it, so ")" typed at "(|)" leaves "()|" rather than "()|)".
        if let following, following == typed, pairs.values.contains(typed) || pairs[typed] == typed {
            return .skip
        }

        guard let closer = pairs[typed] else { return .none }

        // A quote in the middle of a word is an apostrophe, not an opening
        // quote: "don't" must not become "don''t".
        if typed == closer {
            let before = caret >= 2
                ? Character(content.substring(with: NSRange(location: caret - 2, length: 1)))
                : nil
            if let before, before.isLetter || before.isNumber { return .none }
            // An odd number of the same quote on the line means this one closes
            // an existing quote rather than opening a new one.
            if quoteIsClosing(typed, in: content, caret: caret) { return .none }
        }

        // Closing before a letter or digit swallows the word the user is about
        // to wrap, so only close at the end of a line or before punctuation.
        if let following, following.isLetter || following.isNumber { return .none }

        return .close(String(closer))
    }

    /// Whether this quote is closing one already open on the line.
    private static func quoteIsClosing(_ quote: Character, in content: NSString, caret: Int) -> Bool {
        let lineRange = content.lineRange(for: NSRange(location: max(0, caret - 1), length: 0))
        let upToCaret = content.substring(
            with: NSRange(location: lineRange.location, length: max(0, caret - lineRange.location)))
        // The one just typed counts, so an even total means it closed a pair.
        return upToCaret.filter { $0 == quote }.count % 2 == 0
    }

    /// The tag to close after `>` was typed, if any.
    ///
    /// `<div>` gives `</div>`. Self-closing tags, closing tags and the void
    /// elements that never take one are left alone, because inserting `</br>`
    /// is worse than inserting nothing.
    public static func closingTag(after caret: Int, in text: String) -> String? {
        let content = text as NSString
        guard caret > 0, caret <= content.length,
              content.substring(with: NSRange(location: caret - 1, length: 1)) == ">" else { return nil }

        let before = content.substring(to: caret)
        guard let open = before.lastIndex(of: "<") else { return nil }
        let tag = before[before.index(after: open)...].dropLast()   // drop the ">"

        guard !tag.isEmpty, !tag.hasPrefix("/"), !tag.hasSuffix("/"),
              !tag.hasPrefix("!"), !tag.hasPrefix("?") else { return nil }

        let name = String(tag.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        guard !name.isEmpty, name.first?.isLetter == true else { return nil }
        guard !voidElements.contains(name.lowercased()) else { return nil }
        return "</\(name)>"
    }

    /// HTML elements that never have a closing tag.
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]
}
