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
