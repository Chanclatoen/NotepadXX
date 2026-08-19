import Foundation

/// What the clipboard commands do beyond moving text.
///
/// The rules live here so they can be checked without a text view: what gets
/// copied when nothing is selected, and what a paste does to the text on its
/// way in.
public enum ClipboardBehaviour {

    /// The range Copy should take when the selection is empty.
    ///
    /// Notepad++ (and most editors) copy the whole line including its newline,
    /// so pasting it puts a complete line back rather than a fragment.
    public static func lineRange(around caret: Int, in text: String) -> NSRange {
        let content = text as NSString
        guard content.length > 0 else { return NSRange(location: 0, length: 0) }
        let clamped = min(max(0, caret), content.length)
        return content.lineRange(for: NSRange(location: clamped, length: 0))
    }

    /// Re-indents pasted text to sit in the block it lands in.
    ///
    /// The block keeps its internal shape: every line moves by the same amount,
    /// so nested code stays nested. Lines that are only whitespace are left
    /// empty rather than filled with the new indent.
    public static func reindented(_ text: String, toMatch targetIndent: String,
                                  tabWidth: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return text }

        let sourceIndent = String(first.prefix { $0 == " " || $0 == "\t" })
        let sourceWidth = width(of: sourceIndent, tabWidth: tabWidth)
        let targetWidth = width(of: targetIndent, tabWidth: tabWidth)
        let shift = targetWidth - sourceWidth
        guard shift != 0 else { return text }

        let usesTabs = targetIndent.contains("\t")
        return lines.enumerated().map { index, line -> String in
            // The first line already sits at the caret, which is at the target
            // indent; only the lines after it need moving.
            guard index > 0 else { return String(line.drop { $0 == " " || $0 == "\t" }) }
            guard !line.allSatisfy({ $0 == " " || $0 == "\t" }) else { return "" }

            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let body = line.dropFirst(indent.count)
            let moved = max(0, width(of: indent, tabWidth: tabWidth) + shift)
            return indentString(width: moved, tabWidth: tabWidth, usesTabs: usesTabs) + body
        }
        .joined(separator: "\n")
    }

    /// The visual width of an indent, counting a tab as `tabWidth` columns.
    static func width(of indent: String, tabWidth: Int) -> Int {
        indent.reduce(0) { total, character in
            character == "\t" ? total + tabWidth - (total % max(1, tabWidth)) : total + 1
        }
    }

    private static func indentString(width: Int, tabWidth: Int, usesTabs: Bool) -> String {
        guard usesTabs, tabWidth > 0 else { return String(repeating: " ", count: width) }
        return String(repeating: "\t", count: width / tabWidth)
            + String(repeating: " ", count: width % tabWidth)
    }

    /// Removes trailing spaces and tabs from every line of pasted text.
    ///
    /// The final line keeps no newline of its own, so pasting mid-line does not
    /// introduce one.
    public static func trimmingTrailingWhitespace(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                var trimmed = line
                while let last = trimmed.last, last == " " || last == "\t" {
                    trimmed = trimmed.dropLast()
                }
                return trimmed
            }
            .joined(separator: "\n")
    }
}
