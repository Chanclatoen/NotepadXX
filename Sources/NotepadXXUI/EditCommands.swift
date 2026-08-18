import AppKit
import NotepadXXCore
import NotepadXXEditor

/// Edit menu commands. Each maps to an entry in docs/parity/01-file-edit.md.
///
/// Line operations act on the lines touched by the selection; case and blank
/// operations act on the selection when there is one and the whole document
/// otherwise, matching Notepad++.
extension MainWindowController {

    var currentEditor: EditorViewController? {
        guard documents.indices.contains(activeIndex) else { return nil }
        return editorController(for: documents[activeIndex])
    }

    /// Applies a whole-document transform.
    private func applyToDocument(_ transform: (String) -> String) {
        guard let editor = currentEditor else { return }
        editor.replaceAll(with: transform(editor.text))
    }

    /// Applies to the selection if there is one, otherwise the whole document.
    private func applyToSelectionOrDocument(_ transform: (String) -> String) {
        guard let editor = currentEditor else { return }
        let selection = editor.selectedRange
        if selection.length > 0 {
            let content = editor.text as NSString
            editor.replaceSelection(with: transform(content.substring(with: selection)))
        } else {
            editor.replaceAll(with: transform(editor.text))
        }
    }

    private func applyToSelectedLines(_ transform: (String, ClosedRange<Int>) -> String) {
        guard let editor = currentEditor else { return }
        let lines = editor.selectedLineRange()
        editor.replaceAll(with: transform(editor.text, lines))
    }

    // MARK: - Line operations

    @objc public func duplicateLinesAction(_ sender: Any?) {
        applyToSelectedLines { LineOperations.duplicate($0, range: $1) }
    }
    @objc public func removeLinesAction(_ sender: Any?) {
        applyToSelectedLines { LineOperations.remove($0, range: $1) }
    }
    @objc public func moveLinesUpAction(_ sender: Any?) {
        applyToSelectedLines { LineOperations.moveUp($0, range: $1) }
    }
    @objc public func moveLinesDownAction(_ sender: Any?) {
        applyToSelectedLines { LineOperations.moveDown($0, range: $1) }
    }
    @objc public func joinLinesAction(_ sender: Any?) {
        applyToSelectedLines { LineOperations.joinLines($0, range: $1) }
    }
    @objc public func removeConsecutiveDuplicatesAction(_ sender: Any?) {
        applyToDocument { LineOperations.removeConsecutiveDuplicates($0) }
    }
    @objc public func removeAllDuplicatesAction(_ sender: Any?) {
        applyToDocument { LineOperations.removeAllDuplicates($0) }
    }

    // MARK: - Sorting

    @objc public func sortLinesAscendingAction(_ sender: Any?) {
        applyToDocument { LineOperations.sort($0, mode: .lexicographic(caseSensitive: false)) }
    }
    @objc public func sortLinesDescendingAction(_ sender: Any?) {
        applyToDocument { LineOperations.sort($0, mode: .lexicographic(caseSensitive: false), ascending: false) }
    }
    @objc public func sortLinesIntegerAction(_ sender: Any?) {
        applyToDocument { LineOperations.sort($0, mode: .integer) }
    }
    @objc public func sortLinesDecimalAction(_ sender: Any?) {
        applyToDocument { LineOperations.sort($0, mode: .decimal) }
    }
    @objc public func reverseLineOrderAction(_ sender: Any?) {
        applyToDocument { LineOperations.sort($0, mode: .reverseOrder) }
    }
    @objc public func randomizeLineOrderAction(_ sender: Any?) {
        applyToDocument { LineOperations.sort($0, mode: .randomize) }
    }

    // MARK: - Blank operations

    @objc public func trimTrailingSpaceAction(_ sender: Any?) {
        applyToDocument { LineOperations.trimTrailingWhitespace($0) }
    }
    @objc public func trimLeadingSpaceAction(_ sender: Any?) {
        applyToDocument { LineOperations.trimLeadingWhitespace($0) }
    }
    @objc public func trimBothEndsAction(_ sender: Any?) {
        applyToDocument { LineOperations.trimBothEnds($0) }
    }
    @objc public func removeEmptyLinesAction(_ sender: Any?) {
        applyToDocument { LineOperations.removeEmptyLines($0, keepingWhitespaceOnly: true) }
    }
    @objc public func removeBlankLinesAction(_ sender: Any?) {
        applyToDocument { LineOperations.removeEmptyLines($0, keepingWhitespaceOnly: false) }
    }
    @objc public func tabsToSpacesAction(_ sender: Any?) {
        applyToDocument { LineOperations.tabsToSpaces($0, width: tabWidth) }
    }
    @objc public func leadingSpacesToTabsAction(_ sender: Any?) {
        applyToDocument { LineOperations.leadingSpacesToTabs($0, width: tabWidth) }
    }

    // MARK: - Case conversion

    @objc public func convertUpperCaseAction(_ sender: Any?) { applyCase(.upper) }
    @objc public func convertLowerCaseAction(_ sender: Any?) { applyCase(.lower) }
    @objc public func convertProperCaseAction(_ sender: Any?) { applyCase(.proper) }
    @objc public func convertProperCaseBlendAction(_ sender: Any?) { applyCase(.properBlend) }
    @objc public func convertSentenceCaseAction(_ sender: Any?) { applyCase(.sentence) }
    @objc public func convertInvertCaseAction(_ sender: Any?) { applyCase(.invert) }
    @objc public func convertRandomCaseAction(_ sender: Any?) { applyCase(.random) }

    private func applyCase(_ conversion: CaseConversion) {
        applyToSelectionOrDocument { conversion.apply(to: $0) }
    }

    // MARK: - EOL conversion

    @objc public func convertToWindowsEOLAction(_ sender: Any?) { setLineEnding(.crlf) }
    @objc public func convertToUnixEOLAction(_ sender: Any?) { setLineEnding(.lf) }
    @objc public func convertToMacEOLAction(_ sender: Any?) { setLineEnding(.cr) }

    private func setLineEnding(_ ending: LineEnding) {
        guard documents.indices.contains(activeIndex) else { return }
        documents[activeIndex].lineEnding = ending
        documents[activeIndex].markDirty()
        refreshUI()
    }

    // MARK: - Insert

    @objc public func insertDateTimeAction(_ sender: Any?) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        currentEditor?.replaceSelection(with: formatter.string(from: Date()))
    }
}

/// Encoding menu commands.
///
/// Notepad++ separates two operations that are easy to confuse:
/// "Encode in X" reinterprets the existing bytes under a different encoding
/// (visible characters change), while "Convert to X" keeps the characters and
/// changes the bytes written on save.
extension MainWindowController {
    @objc public func encodeInUTF8Action(_ sender: Any?) { reinterpret(as: .utf8) }
    @objc public func encodeInUTF8BOMAction(_ sender: Any?) { reinterpret(as: .utf8BOM) }
    @objc public func encodeInANSIAction(_ sender: Any?) { reinterpret(as: .ansi) }

    @objc public func convertToUTF8Action(_ sender: Any?) { convertEncoding(to: .utf8) }
    @objc public func convertToUTF8BOMAction(_ sender: Any?) { convertEncoding(to: .utf8BOM) }
    @objc public func convertToANSIAction(_ sender: Any?) { convertEncoding(to: .ansi) }

    private func reinterpret(as encoding: FileEncoding) {
        guard documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        do {
            try document.reinterpret(as: encoding)
            currentEditor?.replaceAll(with: document.text)
            refreshUI()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Can't reinterpret as \(encoding.displayName)"
            alert.informativeText = "The file's bytes are not valid in that encoding, so the document was left unchanged."
            alert.runModal()
        }
    }

    private func convertEncoding(to encoding: FileEncoding) {
        guard documents.indices.contains(activeIndex) else { return }
        documents[activeIndex].convert(to: encoding)
        refreshUI()
    }
}
