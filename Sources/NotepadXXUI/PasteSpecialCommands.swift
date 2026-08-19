import AppKit
import NotepadXXCore

/// Notepad++'s Paste Special submenu, plus copy-as conversions.
extension MainWindowController {

    /// Pastes the clipboard with any formatting discarded.
    @objc public func pasteAsPlainTextAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let board = NSPasteboard.general

        // Prefer real plain text; fall back to stripping an HTML flavour, which
        // is what a copy from a browser usually leaves behind.
        if let text = board.string(forType: .string) {
            editor.replaceSelection(with: text)
        } else if let html = board.string(forType: .html) {
            editor.replaceSelection(with: PasteSpecial.plainText(from: html))
        } else {
            NSSound.beep()
        }
    }

    /// Pastes the HTML source itself rather than its rendered text.
    @objc public func pasteHTMLContentAction(_ sender: Any?) {
        guard let editor = currentEditor,
              let html = NSPasteboard.general.string(forType: .html) else { NSSound.beep(); return }
        editor.replaceSelection(with: html)
    }

    /// Pastes the RTF source, matching Notepad++'s "Paste RTF Content".
    @objc public func pasteRTFContentAction(_ sender: Any?) {
        guard let editor = currentEditor,
              let data = NSPasteboard.general.data(forType: .rtf),
              let rtf = String(data: data, encoding: .utf8) else { NSSound.beep(); return }
        editor.replaceSelection(with: rtf)
    }

    @objc public func copyAsHTMLAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let selection = editor.selectedRange
        let text = selection.length > 0
            ? (editor.text as NSString).substring(with: selection)
            : editor.text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PasteSpecial.html(from: text), forType: .string)
    }

    /// Copies the selection with its file path and line, for pasting into a
    /// message or ticket.
    @objc public func copyWithLocationAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument else { return }
        let selection = editor.selectedRange
        let text = selection.length > 0
            ? (editor.text as NSString).substring(with: selection)
            : editor.text
        let name = document.fileURL?.lastPathComponent ?? document.displayName
        let line = editor.caretPosition().line
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(name):\(line)\n\(text)", forType: .string)
    }
}
