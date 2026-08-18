import AppKit
import NotepadXXCore

/// Code folding: collapsing a region hides its lines.
///
/// The text engine has no notion of hidden lines, so folding is done by
/// removing the folded text from the buffer and keeping it aside, then putting
/// it back on unfold. The document's own text is left untouched, so a fold is
/// never saved to disk and cannot lose content.
extension MainWindowController {

    /// Text removed by each active fold, keyed by document then start line.
    private static var foldedText: [UUID: [Int: String]] = [:]

    func toggleFold(atLine line: Int) {
        guard let editor = currentEditor, let document = activeDocument,
              let language = editor.language else { return }

        var folds = collapsedFolds[document.id] ?? []
        var stored = Self.foldedText[document.id] ?? [:]

        if folds.contains(line) {
            // Unfold: put the hidden text back after the fold's first line.
            guard let hidden = stored[line] else { return }
            let (lines, trailing) = LineOperations.split(editor.text)
            guard lines.indices.contains(line) else { return }
            var rebuilt = lines
            rebuilt.insert(contentsOf: LineOperations.split(hidden).lines, at: line + 1)
            editor.replaceAll(with: LineOperations.join(rebuilt, hadTrailingNewline: trailing))
            stored[line] = nil
            folds.remove(line)
        } else {
            // Fold: lift the region's body out, leaving its first line visible.
            let regions = FoldingEngine.folds(in: editor.text, language: language)
            guard let region = regions.first(where: { $0.start == line }) else { return }
            let (lines, trailing) = LineOperations.split(editor.text)
            guard region.end < lines.count, region.end > region.start else { return }

            let body = Array(lines[(region.start + 1)...region.end])
            stored[line] = body.joined(separator: "\n")
            var rebuilt = lines
            rebuilt.removeSubrange((region.start + 1)...region.end)
            editor.replaceAll(with: LineOperations.join(rebuilt, hadTrailingNewline: trailing))
            folds.insert(line)
        }

        collapsedFolds[document.id] = folds
        Self.foldedText[document.id] = stored
        editor.gutterView?.collapsedFoldLines = folds
        editor.refreshFoldMarkers()
        refreshUI()
    }

    /// Restores every fold in the active document, used before saving so the
    /// file on disk is never missing folded lines.
    func unfoldAll() {
        guard let document = activeDocument else { return }
        for line in (collapsedFolds[document.id] ?? []).sorted(by: >) {
            toggleFold(atLine: line)
        }
    }

    @objc public func toggleFoldAtCaretAction(_ sender: Any?) {
        guard let editor = currentEditor, let language = editor.language else { return }
        let line = editor.caretPosition().line - 1
        let regions = FoldingEngine.folds(in: editor.text, language: language)
        guard let region = FoldingEngine.innermostFold(containing: line, in: regions) else {
            NSSound.beep()
            return
        }
        toggleFold(atLine: region.start)
    }

    @objc public func foldAllAction(_ sender: Any?) {
        guard let editor = currentEditor, let language = editor.language else { return }
        // Fold from the bottom up so earlier line numbers stay valid.
        for region in FoldingEngine.folds(in: editor.text, language: language).sorted(by: { $0.start > $1.start }) {
            if collapsedFolds[activeDocument?.id ?? UUID()]?.contains(region.start) != true {
                toggleFold(atLine: region.start)
            }
        }
    }

    @objc public func unfoldAllAction(_ sender: Any?) { unfoldAll() }
}
