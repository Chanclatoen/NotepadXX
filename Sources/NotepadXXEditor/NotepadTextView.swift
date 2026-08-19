import AppKit
import CodeEditTextView

/// The text view, with the clipboard behaviours Notepad++ has.
///
/// Subclassed rather than handled in the controller because Copy, Cut and
/// Paste arrive at the first responder, which is the view.
final class NotepadTextView: TextView {
    /// Copy the whole line when nothing is selected.
    var copiesWholeLineWhenEmpty = true
    /// Strip trailing whitespace from pasted text.
    var trimsTrailingWhitespaceOnPaste = false
    /// Re-indent pasted text to the block it lands in.
    var reindentsOnPaste = false
    /// Columns a tab stands for, for re-indenting.
    var indentWidth = 4

    override func copy(_ sender: AnyObject) {
        guard copiesWholeLineWhenEmpty, hasEmptySelection else {
            super.copy(sender)
            return
        }
        let range = ClipboardBehaviour.lineRange(around: selectedRangeForClipboard.location, in: string)
        guard range.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((string as NSString).substring(with: range), forType: .string)
    }

    /// Cut with no selection takes the whole line away, to match the copy.
    override func cut(_ sender: AnyObject) {
        guard copiesWholeLineWhenEmpty, hasEmptySelection else {
            super.cut(sender)
            return
        }
        copy(sender)
        let range = ClipboardBehaviour.lineRange(around: selectedRangeForClipboard.location, in: string)
        guard range.length > 0 else { return }
        replaceCharacters(in: range, with: "")
    }

    override func paste(_ sender: AnyObject) {
        guard trimsTrailingWhitespaceOnPaste || reindentsOnPaste,
              let pasted = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        var text = pasted
        if trimsTrailingWhitespaceOnPaste {
            text = ClipboardBehaviour.trimmingTrailingWhitespace(text)
        }
        if reindentsOnPaste {
            text = ClipboardBehaviour.reindented(text, toMatch: indentAtCaret, tabWidth: indentWidth)
        }
        insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// The indentation of the line the caret is on, which is what pasted text
    /// is lined up with.
    private var indentAtCaret: String {
        let content = string as NSString
        let caret = min(selectedRangeForClipboard.location, content.length)
        let line = content.substring(with: content.lineRange(for: NSRange(location: caret, length: 0)))
        return String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private var hasEmptySelection: Bool {
        let selections = selectionManager?.textSelections ?? []
        return selections.count == 1 && selections[0].range.length == 0
    }

    private var selectedRangeForClipboard: NSRange {
        selectionManager?.textSelections.first?.range ?? NSRange(location: 0, length: 0)
    }
}
