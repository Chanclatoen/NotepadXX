import AppKit
import NotepadXXCore

/// Multi-cursor editing.
///
/// Notepad++ uses Ctrl+click to add a caret and Ctrl+F3 for select-next. On
/// macOS Ctrl+click is the system's secondary-click gesture, so a caret is
/// added with Option+click and the keyboard shortcuts follow the Mac
/// convention every other editor here uses (Cmd+D / Cmd+Shift+L). The
/// behaviour is Notepad++'s; only the chords are native.
extension MainWindowController {

    @objc public func selectNextOccurrenceAction(_ sender: Any?) {
        if currentEditor?.selectNextOccurrence() != true { NSSound.beep() }
        refreshStatusForCarets()
    }

    @objc public func selectAllOccurrencesAction(_ sender: Any?) {
        if currentEditor?.selectAllOccurrences() != true { NSSound.beep() }
        refreshStatusForCarets()
    }

    @objc public func removeLastCaretAction(_ sender: Any?) {
        if currentEditor?.removeLastCaret() != true { NSSound.beep() }
        refreshStatusForCarets()
    }

    @objc public func collapseCaretsAction(_ sender: Any?) {
        currentEditor?.collapseToSingleCaret()
        refreshStatusForCarets()
    }

    /// Puts a caret at the start of every line the selection touches — the
    /// quickest route from a block selection to per-line editing.
    @objc public func splitSelectionIntoLinesAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        let text = editor.text
        var carets: [NSRange] = []
        for range in editor.selectedRanges where range.length > 0 {
            let lines = ColumnSelection.position(ofOffset: range.location, in: text).line
                ... ColumnSelection.position(ofOffset: NSMaxRange(range) - 1, in: text).line
            for line in lines {
                let offset = ColumnSelection.offset(
                    of: TextPosition(line: line, column: .max), in: text
                )
                carets.append(NSRange(location: offset, length: 0))
            }
        }
        guard !carets.isEmpty else { NSSound.beep(); return }
        editor.selectedRanges = carets
        refreshStatusForCarets()
    }

    func refreshStatusForCarets() {
        refreshUI()
    }

    /// Option+click adds a caret. Installed as a local monitor because the
    /// engine's mouseDown is not open for overriding.
    func installMultiCaretMouseMonitor() {
        guard multiCaretMonitor == nil else { return }
        multiCaretMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option,
                  let editor = self.currentEditor,
                  event.window === self.window,
                  let offset = editor.offset(at: event.locationInWindow)
            else { return event }

            // Only claim the click when it lands in the text, not the gutter or
            // a panel — Option+drag is also how a column selection is made, and
            // that must keep working.
            let local = editor.textView.convert(event.locationInWindow, from: nil)
            guard editor.textView.bounds.contains(local) else { return event }

            editor.addCaret(at: offset)
            self.refreshStatusForCarets()
            return nil
        }
    }
}
