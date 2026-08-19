import Foundation

/// Works out the indentation a newly created line should start with.
public enum AutoIndent {

    /// The leading whitespace of `line`, verbatim, so tabs stay tabs.
    public static func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    /// Indentation for the line created by pressing Return at `location`.
    ///
    /// Copies the current line's indent, and adds one level when that line
    /// opens a block. Notepad++ does the same, and getting it wrong is felt
    /// immediately because it happens on every Return.
    public static func indent(
        forNewLineAt location: Int, in text: String,
        language: LanguageDefinition?, tabWidth: Int, useSpaces: Bool
    ) -> String {
        let content = text as NSString
        guard location > 0, location <= content.length else { return "" }

        // The line the caret was on when Return was pressed.
        let lineRange = content.lineRange(for: NSRange(location: max(0, location - 1), length: 0))
        let line = content.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var indent = leadingWhitespace(of: line)

        guard let language, opensBlock(trimmed, language: language) else { return indent }
        indent += useSpaces ? String(repeating: " ", count: max(1, tabWidth)) : "\t"
        return indent
    }

    /// Whether a line opens a block, so the next line indents further.
    static func opensBlock(_ line: String, language: LanguageDefinition) -> Bool {
        guard !line.isEmpty else { return false }
        // Trailing block markers: `{` for C-family, `:` for Python, `do`/`then`
        // for shell-likes, taken from the language's fold markers.
        for marker in language.foldOpen where !marker.isEmpty {
            if line.hasSuffix(marker) { return true }
            // Word markers must match a whole trailing word, or "endif" would
            // look like it ends with "if".
            if marker.first?.isLetter == true {
                let words = line.split(whereSeparator: { !$0.isLetter })
                if words.last.map(String.init) == marker { return true }
            }
        }
        return false
    }

    /// Whether typing `text` should dedent the current line, e.g. a closing
    /// brace typed on an otherwise blank line.
    public static func shouldDedent(
        after typed: String, currentLine: String, language: LanguageDefinition?
    ) -> Bool {
        guard let language, currentLine.trimmingCharacters(in: .whitespaces).isEmpty ||
                currentLine.allSatisfy({ $0 == " " || $0 == "\t" }) else { return false }
        return language.foldClose.contains(typed)
    }

    /// Removes one indent level from the end of `indent`.
    public static func dedented(_ indent: String, tabWidth: Int) -> String {
        if indent.hasSuffix("\t") { return String(indent.dropLast()) }
        let spaces = min(max(1, tabWidth), indent.count)
        guard indent.suffix(spaces).allSatisfy({ $0 == " " }) else { return indent }
        return String(indent.dropLast(spaces))
    }
}

/// Clipboard conversions behind Notepad++'s Paste Special.
public enum PasteSpecial {
    /// Strips formatting, leaving the plain text a paste should insert.
    public static func plainText(from html: String) -> String {
        // Remove tags, then decode the handful of entities that matter.
        var text = html.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text
    }

    /// Wraps text as an HTML fragment, for Notepad++'s "Copy as HTML".
    public static func html(from text: String, escaping: Bool = true) -> String {
        let body = escaping ? escapeHTML(text) : text
        return "<pre>\(body)</pre>"
    }

    public static func escapeHTML(_ text: String) -> String {
        // Ampersand first, or the other replacements get double-escaped.
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
