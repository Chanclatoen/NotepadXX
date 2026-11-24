import AppKit
import NotepadXXCore
import NotepadXXEditor

/// Edit > Comment/Uncomment, Indent/Unindent and Split Lines.
///
/// Comment syntax comes from the document's language, so one command does the
/// right thing in every language that has a comment form.
extension MainWindowController {

    /// The active language's comment tokens, or nil for plain text.
    private func commentSyntax() -> (line: String?, open: String?, close: String?)? {
        guard let language = activeDocument?.languageName
            .flatMap({ LanguageRegistry.shared.language(named: $0) }) else { return nil }
        let line = language.lineCommentTokens.first
        let open = language.blockCommentOpen, close = language.blockCommentClose
        guard line != nil || (open != nil && close != nil) else { return nil }
        return (line, open, close)
    }

    /// Comments or uncomments the lines the selection touches. A language with
    /// only a block comment (HTML, CSS) wraps those lines in it instead.
    @objc public func toggleLineCommentAction(_ sender: Any?) {
        guard let editor = currentEditor, let syntax = commentSyntax() else { NSSound.beep(); return }
        guard let token = syntax.line else {
            wrapLinesInBlockComment(editor, open: syntax.open ?? "", close: syntax.close ?? "")
            return
        }
        let lines = editor.selectedLineRange()
        let updated = LineOperations.toggleLineComment(editor.text, range: lines, token: token)
        editor.replaceAll(with: updated)
        editor.selectedRange = LineOperations.characterRange(ofLines: lines, in: updated)
    }

    @objc public func toggleBlockCommentAction(_ sender: Any?) {
        guard let editor = currentEditor, let syntax = commentSyntax(),
              let open = syntax.open, let close = syntax.close else { NSSound.beep(); return }
        let edit = LineOperations.toggleBlockComment(
            editor.text, selection: editor.selectedRange, open: open, close: close)
        editor.replaceAll(with: edit.text)
        editor.selectedRange = edit.selection
    }

    private func wrapLinesInBlockComment(_ editor: EditorViewController, open: String, close: String) {
        let lines = editor.selectedLineRange()
        let span = LineOperations.characterRange(ofLines: lines, in: editor.text)
        let edit = LineOperations.toggleBlockComment(editor.text, selection: span, open: open, close: close)
        editor.replaceAll(with: edit.text)
        editor.selectedRange = edit.selection
    }

    // MARK: - Indent

    private var indentation: (width: Int, usesSpaces: Bool) {
        preferencesStore?.preferences.indentation(forLanguage: activeDocument?.languageName) ?? (4, false)
    }

    @objc public func indentLinesAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let (width, usesSpaces) = indentation
        let lines = editor.selectedLineRange()
        let updated = LineOperations.indent(
            editor.text, range: lines, unit: usesSpaces ? String(repeating: " ", count: width) : "\t")
        editor.replaceAll(with: updated)
        editor.selectedRange = LineOperations.characterRange(ofLines: lines, in: updated)
    }

    @objc public func unindentLinesAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let lines = editor.selectedLineRange()
        let updated = LineOperations.unindent(editor.text, range: lines, width: indentation.width)
        editor.replaceAll(with: updated)
        editor.selectedRange = LineOperations.characterRange(ofLines: lines, in: updated)
    }

    // MARK: - Split lines

    /// Breaks the selected lines at the edge column (80 when none is set).
    @objc public func splitLinesAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let edge = preferencesStore?.preferences.edgeColumn ?? 0
        let lines = editor.selectedLineRange()
        let updated = LineOperations.splitLines(editor.text, range: lines, width: edge > 0 ? edge : 80)
        guard updated != editor.text else { return }
        editor.replaceAll(with: updated)
    }
}
