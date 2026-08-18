import AppKit
import NotepadXXCore
import NotepadXXEditor

/// Search menu commands and the Find dialog wiring.
extension MainWindowController {

    /// Opens the panel already focused on Replace.
    @objc public func showReplacePanelAction(_ sender: Any?) {
        showFindPanelAction(sender)
        findPanel().focusReplaceField()
    }

    /// Opens the panel already focused on Find in Files.
    @objc public func showFindInFilesAction(_ sender: Any?) {
        showFindPanelAction(sender)
        findPanel().focusFindInFiles()
    }

    @objc public func showFindPanelAction(_ sender: Any?) {
        let panel = findPanel()
        panel.showWindow(nil)
        panel.focusSearchField()
    }

    func findPanel() -> FindPanelController {
        if let existing = installedFindPanel { return existing }
        let panel = FindPanelController()
        panel.onFindNext = { [weak self] in self?.performFind($0) }
        panel.onFindPrevious = { [weak self] in self?.performFind($0) }
        panel.onCount = { [weak self] in self?.performCount($0) }
        panel.onReplace = { [weak self] in self?.performReplace($0) }
        panel.onReplaceAll = { [weak self] in self?.performReplaceAll($0) }
        panel.onFindAll = { [weak self] in self?.performFindAll($0) }
        installedFindPanel = panel
        return panel
    }

    /// Restricts the search to the selection when "In selection" is ticked.
    private func scope(for request: FindPanelController.Request, editor: EditorViewController) -> NSRange? {
        guard request.inSelection else { return nil }
        let selection = editor.selectedRange
        return selection.length > 0 ? selection : nil
    }

    private func engine(_ request: FindPanelController.Request) -> SearchEngine {
        SearchEngine(pattern: request.pattern, options: request.options)
    }

    private func report(_ error: Error) {
        if case SearchError.invalidRegex(let detail) = error {
            findPanel().showStatus("Invalid regular expression: \(detail)")
        } else if case SearchError.emptyPattern = error {
            findPanel().showStatus("Enter something to find.")
        } else {
            findPanel().showStatus("\(error)")
        }
    }

    func performFind(_ request: FindPanelController.Request) {
        guard let editor = currentEditor else { return }
        do {
            let from = request.options.backward
                ? editor.selectedRange.location
                : NSMaxRange(editor.selectedRange)
            guard let match = try engine(request).find(
                in: editor.text, from: from, within: scope(for: request, editor: editor)
            ) else {
                findPanel().showStatus("Can't find \"\(request.pattern)\"")
                NSSound.beep()
                return
            }
            editor.selectedRange = match.range
            findPanel().showStatus("")
        } catch { report(error) }
    }

    func performCount(_ request: FindPanelController.Request) {
        guard let editor = currentEditor else { return }
        do {
            let total = try engine(request).count(
                in: editor.text, range: scope(for: request, editor: editor)
            )
            findPanel().showStatus("\(total) match\(total == 1 ? "" : "es")")
        } catch { report(error) }
    }

    func performReplace(_ request: FindPanelController.Request) {
        guard let editor = currentEditor else { return }
        do {
            let searcher = engine(request)
            let scoped = scope(for: request, editor: editor)
            // Replace the current selection if it is itself a match, otherwise
            // advance to the next one — the behaviour Notepad++ has.
            if let match = try searcher.find(in: editor.text, from: editor.selectedRange.location, within: scoped),
               match.range == editor.selectedRange {
                let updated = try searcher.replace(in: editor.text, match: match, with: request.replacement)
                editor.replaceAll(with: updated)
                editor.selectedRange = NSRange(location: match.range.location + (request.replacement as NSString).length, length: 0)
                findPanel().showStatus("Replaced 1")
            } else {
                performFind(request)
            }
        } catch { report(error) }
    }

    func performReplaceAll(_ request: FindPanelController.Request) {
        guard let editor = currentEditor else { return }
        do {
            let (updated, count) = try engine(request).replaceAll(
                in: editor.text, with: request.replacement, range: scope(for: request, editor: editor)
            )
            if count > 0 { editor.replaceAll(with: updated) }
            findPanel().showStatus("Replaced \(count) occurrence\(count == 1 ? "" : "s")")
        } catch { report(error) }
    }

    func performFindAll(_ request: FindPanelController.Request) {
        guard let editor = currentEditor, documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        do {
            let url = document.fileURL ?? URL(fileURLWithPath: document.displayName)
            let hits = try FindInFiles(engine: engine(request)).search(text: editor.text, url: url)
            showSearchResults([FileSearchResult(url: url, hits: hits)],
                              summary: "\(hits.count) hits in \(document.displayName)")
        } catch { report(error) }
    }

    /// Shows hits in the Search Results panel and wires row activation to jump
    /// to the file and line.
    func showSearchResults(_ results: [FileSearchResult], summary: String) {
        let panel: SearchResultsPanelController
        if let existing = installedResultsPanel {
            panel = existing
        } else {
            panel = SearchResultsPanelController()
            panel.onSelectHit = { [weak self] url, line in self?.reveal(url: url, line: line) }
            installedResultsPanel = panel
        }
        panel.present(results: results, summary: summary)
    }

    /// Focuses the tab for `url` (opening it if needed) and scrolls to `line`.
    func reveal(url: URL, line: Int) {
        guard openOrFocus(url: url) else { return }
        currentEditor?.goToLine(line)
    }

    // MARK: - Find in Files

    @objc public func findInFilesAction(_ sender: Any?) {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.prompt = "Search"
        guard picker.runModal() == .OK, let directory = picker.url else { return }

        let panel = findPanel()
        panel.showWindow(nil)
        let request = FindPanelController.Request(
            pattern: panel.currentPattern, replacement: "",
            options: panel.currentOptions, inSelection: false
        )
        guard !request.pattern.isEmpty else {
            panel.showStatus("Enter something to find, then choose Find in Files again.")
            return
        }
        do {
            // Unsaved buffers must be searched in their edited state.
            var buffers: [String: String] = [:]
            for document in documents {
                if let path = document.fileURL?.path { buffers[path] = document.text }
            }
            let results = try FindInFiles(engine: engine(request)).search(
                directory: directory, openBuffers: buffers
            )
            let total = results.reduce(0) { $0 + $1.hits.count }
            showSearchResults(results, summary: "\(total) hits in \(results.count) files")
        } catch { report(error) }
    }

    @objc public func goToLineDialogAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let alert = NSAlert()
        alert.messageText = "Go to line"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let line = Int(field.stringValue) else { return }
        editor.goToLine(line)
    }
}
