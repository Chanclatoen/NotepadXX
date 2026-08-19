import AppKit
import NotepadXXCore

/// Find Next/Previous, the Mark tab, and incremental search.
extension MainWindowController {

    // MARK: - Find next / previous without the dialog

    /// The pattern to reuse for Find Next: whatever was last searched, or the
    /// selection if the user selected something since.
    private var reusablePattern: String? {
        if let editor = currentEditor, editor.selectedRange.length > 0 {
            return (editor.text as NSString).substring(with: editor.selectedRange)
        }
        return searchHistory?.patterns.first
    }

    @objc public func findNextAction(_ sender: Any?) {
        guard let pattern = reusablePattern, !pattern.isEmpty else {
            showFindPanelAction(sender)
            return
        }
        performFind(.init(pattern: pattern, replacement: "",
                          options: lastSearchOptions, inSelection: false))
    }

    @objc public func findPreviousAction(_ sender: Any?) {
        guard let pattern = reusablePattern, !pattern.isEmpty else {
            showFindPanelAction(sender)
            return
        }
        var options = lastSearchOptions
        options.backward = true
        performFind(.init(pattern: pattern, replacement: "", options: options, inSelection: false))
    }

    /// Notepad++'s "Select and Find Next": take the word under the caret, then
    /// jump to its next occurrence.
    @objc public func selectAndFindNextAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        if editor.selectedRange.length == 0,
           let word = Occurrences.word(at: editor.selectedRange.location, in: editor.text) {
            editor.selectedRange = word.range
        }
        findNextAction(sender)
    }

    // MARK: - Mark

    @objc public func markAllAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument else { return }
        let pattern = editor.selectedRange.length > 0
            ? (editor.text as NSString).substring(with: editor.selectedRange)
            : (searchHistory?.patterns.first ?? "")
        guard !pattern.isEmpty else { NSSound.beep(); return }

        let ranges = Occurrences.all(of: pattern, in: editor.text)
        guard !ranges.isEmpty else { NSSound.beep(); return }

        var marks = markedRanges[document.id] ?? MarkedRanges()
        marks.set(ranges, for: MarkStyle(index: activeMarkStyle))
        markedRanges[document.id] = marks
        applyMarks(for: document)
    }

    @objc public func clearMarksAction(_ sender: Any?) {
        guard let document = activeDocument else { return }
        markedRanges[document.id] = MarkedRanges()
        applyMarks(for: document)
    }

    @objc public func copyMarkedTextAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument,
              let marks = markedRanges[document.id], !marks.isEmpty else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(marks.markedText(in: editor.text), forType: .string)
    }

    @objc public func selectMarkStyleAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let index = item.representedObject as? Int else { return }
        activeMarkStyle = index
    }

    /// Draws the marks. Each style keeps its own id so styles can be cleared
    /// independently, as Notepad++'s five styles are.
    func applyMarks(for document: TextDocument) {
        guard let editor = currentEditor else { return }
        let marks = markedRanges[document.id] ?? MarkedRanges()
        editor.applyMarks(MarkStyle.all.map { marks.ranges(for: $0) })
    }

    // MARK: - Incremental search

    /// Notepad++'s incremental search bar: matches update as you type and
    /// Escape restores where you started.
    @objc public func incrementalSearchAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        if incrementalBar == nil {
            let bar = IncrementalSearchBar()
            bar.onQueryChanged = { [weak self] query in
                guard let self, let editor = self.currentEditor else { return }
                guard !query.isEmpty else {
                    editor.selectedRange = NSRange(location: self.incrementalOrigin, length: 0)
                    bar.showNotFound(false)
                    return
                }
                // Report the position in the match list, not merely that
                // something was found: "4 of 17" says how much is left.
                let all = Occurrences.all(of: query, in: editor.text)
                if let match = Occurrences.next(of: query, in: editor.text,
                                                after: self.incrementalOrigin - 1) {
                    editor.selectedRange = match
                    editor.scrollRangeToVisible(match)
                    let index = (all.firstIndex { $0.location == match.location } ?? 0) + 1
                    bar.showMatch(index, of: all.count)
                    // Wrapping past the end is worth saying, since the caret
                    // appears to jump backwards.
                    if match.location < self.incrementalOrigin, all.count > 1 {
                        bar.showNotFound(false)
                    }
                } else {
                    bar.showNotFound(true, wrapped: !all.isEmpty)
                }
            }
            bar.onNext = { [weak self] in self?.findNextAction(nil) }
            bar.onPrevious = { [weak self] in self?.findPreviousAction(nil) }
            bar.onOptionsChanged = { [weak self] in
                // Re-run the search so a changed option takes effect on what
                // is already typed, rather than only on the next keystroke.
                self?.incrementalBar.map { $0.onQueryChanged?($0.query) }
            }
            bar.onCancel = { [weak self] in
                guard let self else { return }
                self.currentEditor?.selectedRange = NSRange(location: self.incrementalOrigin, length: 0)
                self.hideIncrementalBar()
            }
            bar.onCommit = { [weak self] query in
                self?.searchHistory?.record(query, in: .pattern)
                self?.hideIncrementalBar()
            }
            incrementalBar = bar
        }
        incrementalOrigin = editor.selectedRange.location
        showIncrementalBar()
    }
}
