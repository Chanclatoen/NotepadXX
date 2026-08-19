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
        guard trimsTrailingWhitespaceOnPaste,
              let pasted = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        insertText(ClipboardBehaviour.trimmingTrailingWhitespace(pasted),
                   replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private var hasEmptySelection: Bool {
        let selections = selectionManager?.textSelections ?? []
        return selections.count == 1 && selections[0].range.length == 0
    }

    private var selectedRangeForClipboard: NSRange {
        selectionManager?.textSelections.first?.range ?? NSRange(location: 0, length: 0)
    }
}
