import AppKit
import NotepadXXCore
import NotepadXXEditor

/// Search menu commands and the Find dialog wiring.
extension MainWindowController {

    /// Find, Replace, Find in Files and Mark are the same panel in different
    /// modes. Every entry point routes through here, so there is one workflow
    /// rather than a dialog for some searches and a folder picker for others.
    public func showSearchPanel(mode: SearchPanelController.Mode) {
        let panel = findPanel()
        panel.setHistory(patterns: searchHistory?.patterns ?? [],
                         replacements: searchHistory?.replacements ?? [])
        // Seed the field from the selection, as Notepad++ does.
        if let editor = currentEditor, editor.selectedRange.length > 0 {
            panel.setPattern((editor.text as NSString).substring(with: editor.selectedRange))
        }
        if mode == .findInFiles, let directory = folderWorkspacePanel?.primaryRoot ?? activeDocument?.fileURL?.deletingLastPathComponent() {
            panel.setDirectory(directory)
        }
        panel.show(mode: mode)
        if mode == .replace { panel.focusReplaceField() }
    }

    @objc public func showReplacePanelAction(_ sender: Any?) {
        showSearchPanel(mode: .replace)
    }

    @objc public func showFindInFilesAction(_ sender: Any?) {
        showSearchPanel(mode: .findInFiles)
    }

    @objc public func showMarkPanelAction(_ sender: Any?) {
        showSearchPanel(mode: .mark)
    }

    /// ⌥⌘X cycles Normal → Extended → Regex without leaving the field.
    @objc public func cycleSearchModeAction(_ sender: Any?) {
        findPanel().cycleSearchMode()
    }

    /// Records what was searched for, so Find Next and the dropdowns work.
    func rememberSearch(_ request: SearchPanelController.Request) {
        lastSearchOptions = request.options
        searchHistory?.record(request.pattern, in: .pattern)
        if !request.replacement.isEmpty {
            searchHistory?.record(request.replacement, in: .replacement)
        }
        if let support = try? SessionStore.defaultDirectory() {
            searchHistory?.save(to: support)
        }
    }

    @objc public func showFindPanelAction(_ sender: Any?) {
        showSearchPanel(mode: .find)
    }

    func findPanel() -> SearchPanelController {
        if let existing = installedFindPanel { return existing }
        let panel = SearchPanelController()
        panel.onFindNext = { [weak self] in self?.performFind($0) }
        panel.onFindPrevious = { [weak self] in self?.performFind($0) }
        panel.onCount = { [weak self] in self?.performCount($0) }
        panel.onReplace = { [weak self] in self?.performReplace($0) }
        panel.onReplaceAll = { [weak self] in self?.performReplaceAll($0) }
        panel.onFindAll = { [weak self] in self?.performFindAll($0) }
        panel.onReplaceAllInOpenDocuments = { [weak self] in self?.performReplaceAllInOpenDocuments($0) }
        panel.onFindInFiles = { [weak self] in self?.performFindInFiles($0) }
        panel.onCancelSearch = { [weak self] in self?.cancelFileSearch() }
        panel.onReplaceInFiles = { [weak self] in self?.performReplaceInFiles($0) }
        panel.onMarkAll = { [weak self] in self?.performMarkAll($0) }
        panel.onClearMarks = { [weak self] _ in self?.clearMarksAction(nil) }
        panel.onCopyMarkedText = { [weak self] _ in self?.copyMarkedTextAction(nil) }
        panel.onPatternChanged = { [weak self] in self?.previewMatches($0) }
        panel.onModeChanged = { [weak self] mode in
            try? self?.preferencesStore?.update { $0.searchPanelModeRawValue = mode.rawValue }
        }
        if let stored = preferencesStore?.preferences.searchPanelModeRawValue,
           let restored = SearchPanelController.Mode(rawValue: stored) {
            panel.show(mode: restored)
        }
        // Preferences supply what the panel opens with.
        if let preferences = preferencesStore?.preferences {
            panel.applyDefaults(
                searchMode: SearchMode(rawValue: preferences.searchDefaultModeRawValue) ?? .normal,
                wrapsAround: preferences.searchWrapAround,
                closesAfterUse: !preferences.findDialogStaysOpen)
        }
        installedFindPanel = panel
        return panel
    }

    /// Restricts the search to the selection when "In selection" is ticked.
    private func scope(for request: SearchPanelController.Request, editor: EditorViewController) -> NSRange? {
        guard request.inSelection else { return nil }
        let selection = editor.selectedRange
        return selection.length > 0 ? selection : nil
    }

    private func engine(_ request: SearchPanelController.Request) -> SearchEngine {
        SearchEngine(pattern: request.pattern, options: request.options)
    }

    private func report(_ error: Error) {
        if case SearchError.invalidRegex(let detail) = error {
            findPanel().showStatus("Invalid pattern — \(detail)", kind: .error)
        } else if case SearchError.emptyPattern = error {
            findPanel().showStatus("Enter something to find.", kind: .warning)
        } else {
            findPanel().showStatus("\(error)", kind: .error)
        }
    }

    func performFind(_ request: SearchPanelController.Request) {
        rememberSearch(request)
        guard let editor = currentEditor else { return }
        do {
            let from = request.options.backward
                ? editor.selectedRange.location
                : NSMaxRange(editor.selectedRange)
            guard let match = try engine(request).find(
                in: editor.text, from: from, within: scope(for: request, editor: editor)
            ) else {
                findPanel().showStatus("Can't find \"\(request.pattern)\"", kind: .warning)
                NSSound.beep()
                return
            }
            editor.selectedRange = match.range
            reportMatchPosition(for: request, at: match.range)
        } catch { report(error) }
    }

    func performCount(_ request: SearchPanelController.Request) {
        guard let editor = currentEditor else { return }
        do {
            let total = try engine(request).count(
                in: editor.text, range: scope(for: request, editor: editor)
            )
            findPanel().showStatus("\(total) match\(total == 1 ? "" : "es")", kind: .success)
        } catch { report(error) }
    }

    func performReplace(_ request: SearchPanelController.Request) {
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
                findPanel().showStatus("Replaced 1", kind: .success)
            } else {
                performFind(request)
            }
        } catch { report(error) }
    }

    func performReplaceAll(_ request: SearchPanelController.Request) {
        rememberSearch(request)
        guard let editor = currentEditor else { return }
        do {
            let (updated, count) = try engine(request).replaceAll(
                in: editor.text, with: request.replacement, range: scope(for: request, editor: editor)
            )
            if count > 0 { editor.replaceAll(with: updated) }
            findPanel().showStatus("Replaced \(count) occurrence\(count == 1 ? "" : "s")",
                                   kind: count > 0 ? .success : .warning)
        } catch { report(error) }
    }

    func performFindAll(_ request: SearchPanelController.Request) {
        guard let editor = currentEditor, documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        do {
            let url = document.fileURL ?? URL(fileURLWithPath: document.displayName)
            let hits = try FindInFiles(engine: engine(request)).search(text: editor.text, url: url)
            showSearchResults([FileSearchResult(url: url, hits: hits)],
                              summary: "\(hits.count) hits in \(document.displayName)")
        } catch { report(error) }
    }

    /// Shows hits in the docked Search Results panel, opening the dock if the
    /// user had it closed.
    func showSearchResults(_ results: [FileSearchResult], summary: String, query: String = "") {
        guard let panel = searchResultsPanel else { return }
        dockHost?.show("searchResults")
        panel.present(results: results, summary: summary, query: query)
    }

    /// Opens a hit in the other split pane, for ⇧⏎ in the results list. The
    /// split is opened first if it is not already showing, because the point
    /// of the shortcut is to see the hit beside what is already open.
    func revealInOtherPane(url: URL, line: Int) {
        guard openOrFocus(url: url) else { return }
        if !isSplit { toggleSplitViewAction(nil) }
        moveToOtherViewAction(nil)
        currentEditor?.goToLine(line)
    }

    /// Focuses the tab for `url` (opening it if needed) and scrolls to `line`.
    func reveal(url: URL, line: Int) {
        guard openOrFocus(url: url) else { return }
        currentEditor?.goToLine(line)
    }

    // MARK: - Find in Files

    /// The menu item opens the panel in Find in Files mode. The scan itself is
    /// driven from the panel, so there is one place that owns the pattern,
    /// the directory and the filters.
    @objc public func findInFilesAction(_ sender: Any?) {
        showSearchPanel(mode: .findInFiles)
    }

    func performFindInFiles(_ request: SearchPanelController.Request) {
        guard let directory = request.directory else {
            findPanel().showStatus("Choose a directory to search.", kind: .warning)
            return
        }
        guard !request.pattern.isEmpty else {
            findPanel().showStatus("Enter something to find.", kind: .warning)
            return
        }
        rememberSearch(request)

        // Scan off the main thread. A synchronous walk of a large tree freezes
        // the window, which also means the panel's progress and its Cancel
        // button could never do anything.
        let searcher = findInFiles(for: request)
        let buffers = unsavedBuffers()
        let cancelled = SearchCancellationToken()
        activeFileSearch = cancelled
        findPanel().showScanProgress(scanned: 0, total: 1, hits: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let results = try searcher.search(
                    directory: directory, openBuffers: buffers,
                    isCancelled: { cancelled.isCancelled },
                    onProgress: { progress in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                guard !cancelled.isCancelled else { return }
                                self.findPanel().showScanProgress(
                                    scanned: progress.scanned, total: progress.total,
                                    hits: progress.hits)
                            }
                        }
                    })
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.finishFindInFiles(results, request: request, cancelled: cancelled.isCancelled)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.findPanel().endScan()
                        self.report(error)
                    }
                }
            }
        }
    }

    private func finishFindInFiles(_ results: [FileSearchResult],
                                   request: SearchPanelController.Request,
                                   cancelled: Bool) {
        findPanel().endScan()
        activeFileSearch = nil
        guard !cancelled else {
            findPanel().showStatus("Search cancelled.", kind: .neutral)
            return
        }
        let total = results.reduce(0) { $0 + $1.hits.count }
        findPanel().showStatus(
            "\(total) hit\(total == 1 ? "" : "s") in \(results.count) file\(results.count == 1 ? "" : "s")",
            kind: total > 0 ? .success : .warning)
        showSearchResults(results,
                          summary: "“\(request.pattern)” · \(total) hits in \(results.count) files",
                          query: request.pattern)
    }

    /// Stops a running scan.
    func cancelFileSearch() {
        activeFileSearch?.cancel()
        findPanel().endScan()
        findPanel().showStatus("Search cancelled.", kind: .neutral)
    }

    /// Replace in Files always confirms first and reports a file-level summary.
    func performReplaceInFiles(_ request: SearchPanelController.Request) {
        guard let directory = request.directory, !request.pattern.isEmpty else {
            findPanel().showStatus("Choose a directory and enter something to find.", kind: .warning)
            return
        }
        do {
            let results = try findInFiles(for: request).search(
                directory: directory, openBuffers: unsavedBuffers())
            let total = results.reduce(0) { $0 + $1.hits.count }
            guard total > 0 else {
                findPanel().showStatus("Nothing to replace.", kind: .warning)
                return
            }

            let alert = NSAlert()
            alert.messageText = "Replace in \(results.count) file\(results.count == 1 ? "" : "s")?"
            alert.informativeText = """
                \(total) occurrence\(total == 1 ? "" : "s") of “\(request.pattern)” will be replaced \
                with “\(request.replacement)”. Files that are open are changed in their edited state \
                and left unsaved.
                """
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                findPanel().showStatus("Replace cancelled.", kind: .neutral)
                return
            }

            var changedFiles = 0
            var replaced = 0
            for result in results {
                guard let text = try? String(contentsOf: result.url, encoding: .utf8) else { continue }
                let (updated, count) = try engine(request).replaceAll(
                    in: text, with: request.replacement, range: nil)
                guard count > 0 else { continue }
                try updated.write(to: result.url, atomically: true, encoding: .utf8)
                changedFiles += 1
                replaced += count
                // An open document must show the new text, not its stale buffer.
                if let index = documents.firstIndex(where: { $0.fileURL == result.url }) {
                    documents[index].text = updated
                    if index == activeIndex { currentEditor?.replaceAll(with: updated) }
                }
            }
            findPanel().showStatus(
                "Replaced \(replaced) occurrence\(replaced == 1 ? "" : "s") in \(changedFiles) file\(changedFiles == 1 ? "" : "s")",
                kind: .success)
        } catch { report(error) }
    }

    func performReplaceAllInOpenDocuments(_ request: SearchPanelController.Request) {
        rememberSearch(request)
        var replaced = 0
        var changedDocuments = 0
        do {
            for index in documents.indices {
                let (updated, count) = try engine(request).replaceAll(
                    in: documents[index].text, with: request.replacement, range: nil)
                guard count > 0 else { continue }
                documents[index].text = updated
                replaced += count
                changedDocuments += 1
                if index == activeIndex { currentEditor?.replaceAll(with: updated) }
            }
            findPanel().showStatus(
                "Replaced \(replaced) in \(changedDocuments) open document\(changedDocuments == 1 ? "" : "s")",
                kind: replaced > 0 ? .success : .warning)
        } catch { report(error) }
    }

    func performMarkAll(_ request: SearchPanelController.Request) {
        guard let editor = currentEditor, let document = activeDocument else { return }
        guard !request.pattern.isEmpty else {
            findPanel().showStatus("Enter something to mark.", kind: .warning)
            return
        }
        do {
            let ranges = try engine(request).matches(in: editor.text).map(\.range)
            var marks = request.purgeMarks ? MarkedRanges() : (markedRanges[document.id] ?? MarkedRanges())
            marks.set(ranges, for: request.markStyle)
            markedRanges[document.id] = marks
            applyMarks(for: document)

            var bookmarked = 0
            if request.bookmarkMatchingLines {
                var marksForLines = bookmarks[document.id] ?? Bookmarks()
                let content = editor.text as NSString
                for range in ranges {
                    let line = content.substring(to: range.location)
                        .reduce(into: 0) { count, character in if character == "\n" { count += 1 } }
                    if !marksForLines.lines.contains(line) {
                        marksForLines.toggle(line)
                        bookmarked += 1
                    }
                }
                bookmarks[document.id] = marksForLines
                editor.gutterView?.bookmarkedLines = marksForLines.lines
            }

            let bookmarkNote = request.bookmarkMatchingLines ? " · \(bookmarked) bookmarks set" : ""
            findPanel().showStatus("\(ranges.count) mark\(ranges.count == 1 ? "" : "s")\(bookmarkNote)",
                                   kind: ranges.isEmpty ? .warning : .success)
        } catch { report(error) }
    }

    /// Live feedback as the pattern is typed: the count, without moving the caret.
    func previewMatches(_ request: SearchPanelController.Request) {
        guard let editor = currentEditor, !request.pattern.isEmpty else {
            findPanel().showStatus("")
            return
        }
        guard let total = try? engine(request).count(in: editor.text, range: nil) else { return }
        findPanel().showStatus(total == 0 ? "No matches" : "\(total) match\(total == 1 ? "" : "es")",
                               kind: total == 0 ? .warning : .neutral)
    }

    /// Reports which match the caret is on, e.g. "Match 4 of 17 · line 21".
    private func reportMatchPosition(for request: SearchPanelController.Request, at range: NSRange) {
        guard let editor = currentEditor,
              let matches = try? engine(request).matches(in: editor.text) else { return }
        let index = matches.firstIndex { $0.range.location == range.location }
        let line = editor.caretPosition().line
        if let index {
            findPanel().showStatus("Match \(index + 1) of \(matches.count) · line \(line)", kind: .neutral)
        } else {
            findPanel().showStatus("")
        }
    }

    /// One place that turns a panel request into a configured file search.
    private func findInFiles(for request: SearchPanelController.Request) -> FindInFiles {
        FindInFiles(
            engine: engine(request),
            options: FindInFilesOptions(
                filters: request.filters, exclusions: request.exclusions,
                inSubfolders: request.includeSubfolders, inHiddenFolders: request.includeHidden
            )
        )
    }

    private func unsavedBuffers() -> [String: String] {
        var buffers: [String: String] = [:]
        for document in documents {
            if let path = document.fileURL?.path { buffers[path] = document.text }
        }
        return buffers
    }

    @objc public func goToLineDialogAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let panel = goToPanel()
        panel.present(currentLine: editor.caretPosition().line,
                      lineCount: max(1, editor.lineCount),
                      characterCount: (editor.text as NSString).length)
    }

    func goToPanel() -> GoToPanelController {
        if let existing = installedGoToPanel { return existing }
        let panel = GoToPanelController()
        panel.onGo = { [weak self] target, value in
            guard let editor = self?.currentEditor else { return false }
            switch target {
            case .line:
                guard value >= 1, value <= max(1, editor.lineCount) else { return false }
                editor.goToLine(value)
            case .offset:
                let length = (editor.text as NSString).length
                guard value >= 0, value <= length else { return false }
                editor.selectedRange = NSRange(location: value, length: 0)
                editor.scrollToCaret()
            }
            return true
        }
        installedGoToPanel = panel
        return panel
    }
}
