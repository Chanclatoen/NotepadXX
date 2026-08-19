import AppKit
import NotepadXXDesign
import NotepadXXCore

/// View menu: display symbols, zoom, and bookmark navigation.
extension MainWindowController {

    // MARK: - Show Symbol

    @objc public func toggleShowWhitespaceAction(_ sender: Any?) {
        showSpaces.toggle()
        applyInvisibles()
    }

    @objc public func toggleShowTabsAction(_ sender: Any?) {
        showTabs.toggle()
        applyInvisibles()
    }

    @objc public func toggleShowEndOfLineAction(_ sender: Any?) {
        showLineEndings.toggle()
        applyInvisibles()
    }

    @objc public func toggleIndentGuideAction(_ sender: Any?) {
        showIndentGuides.toggle()
        for editor in allEditors { editor.showIndentGuides = showIndentGuides }
        refreshToolbarState()
    }

    @objc public func toggleShowAllCharactersAction(_ sender: Any?) {
        let turningOn = !(showSpaces && showTabs && showLineEndings)
        showSpaces = turningOn
        showTabs = turningOn
        showLineEndings = turningOn
        applyInvisibles()
    }

    /// Applies to every open editor, not just the active one, so the setting
    /// behaves like a preference rather than a per-tab quirk.
    func applyInvisibles() {
        for editor in allEditors {
            editor.setInvisibles(spaces: showSpaces, tabs: showTabs, lineEndings: showLineEndings)
        }
        refreshToolbarState()
    }

    /// Keeps the toolbar's pressed buttons in step with the actual state.
    func refreshToolbarState() {
        var active: Set<String> = []
        if showSpaces && showTabs && showLineEndings { active.insert("Show All Characters") }
        if showIndentGuides { active.insert("Indent Guide") }
        if currentEditor?.textView.wrapLines == true { active.insert("Word Wrap") }
        if dockHost?.isVisible("documentMap") == true { active.insert("Document Map") }
        if dockHost?.isVisible("functionList") == true { active.insert("Function List") }
        if macroRecorder.isRecording { active.insert("Start/Stop Recording") }
        toolbar?.activeToggles = active
    }

    // MARK: - Zoom

    @objc public func zoomInAction(_ sender: Any?) { adjustFontSize(by: 1) }
    @objc public func zoomOutAction(_ sender: Any?) { adjustFontSize(by: -1) }

    @objc public func zoomRestoreAction(_ sender: Any?) {
        editorFontSize = 12
        for editor in allEditors { editor.setFontSize(editorFontSize) }
    }

    private func adjustFontSize(by delta: CGFloat) {
        editorFontSize = min(max(6, editorFontSize + delta), 96)
        for editor in allEditors { editor.setFontSize(editorFontSize) }
    }

    // MARK: - Bookmarks

    @objc public func toggleBookmarkAction(_ sender: Any?) {
        guard let editor = currentEditor else { return }
        toggleBookmark(atLine: editor.caretPosition().line - 1)
    }

    /// 0-based. Used by the menu command and by clicking the gutter's bookmark lane.
    public func toggleBookmark(atLine line: Int) {
        guard let editor = currentEditor, let document = activeDocument else { return }
        var marks = bookmarks[document.id] ?? Bookmarks()
        marks.toggle(line)
        bookmarks[document.id] = marks
        editor.gutterView?.bookmarkedLines = marks.lines
    }

    @objc public func nextBookmarkAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument,
              let marks = bookmarks[document.id],
              let target = marks.next(after: editor.caretPosition().line - 1) else { return }
        editor.goToLine(target + 1)
    }

    @objc public func previousBookmarkAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument,
              let marks = bookmarks[document.id],
              let target = marks.previous(before: editor.caretPosition().line - 1) else { return }
        editor.goToLine(target + 1)
    }

    @objc public func clearBookmarksAction(_ sender: Any?) {
        guard let document = activeDocument else { return }
        bookmarks[document.id] = Bookmarks()
        currentEditor?.gutterView?.bookmarkedLines = []
    }

    @objc public func invertBookmarksAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument else { return }
        var marks = bookmarks[document.id] ?? Bookmarks()
        marks.invert(totalLines: max(1, LineOperations.split(editor.text).lines.count))
        bookmarks[document.id] = marks
        editor.gutterView?.bookmarkedLines = marks.lines
    }

    @objc public func copyBookmarkedLinesAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument,
              let marks = bookmarks[document.id], !marks.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(marks.markedText(in: editor.text), forType: .string)
    }

    @objc public func removeBookmarkedLinesAction(_ sender: Any?) {
        guard let editor = currentEditor, let document = activeDocument,
              let marks = bookmarks[document.id], !marks.isEmpty else { return }
        editor.replaceAll(with: marks.removingMarkedLines(from: editor.text))
        bookmarks[document.id] = Bookmarks()
        editor.gutterView?.bookmarkedLines = []
    }

    @objc public func cutBookmarkedLinesAction(_ sender: Any?) {
        copyBookmarkedLinesAction(sender)
        removeBookmarkedLinesAction(sender)
    }

    // MARK: - Tab bar layout

    @objc public func useHorizontalTabsAction(_ sender: Any?) { setTabLayout(.horizontal) }
    @objc public func useMultiLineTabsAction(_ sender: Any?) { setTabLayout(.wrapped) }
    @objc public func useVerticalTabsAction(_ sender: Any?) { setTabLayout(.vertical) }

    /// The rail is a genuinely different arrangement: it sits beside the editor
    /// rather than above it, so the constraints swap with the layout.
    public func setTabLayout(_ layout: DocumentTabStrip.Layout) {
        tabBar.tabLayout = layout
        applyTabLayoutConstraints()
        try? preferencesStore?.update { $0.tabLayoutRawValue = layout.rawValue }
        refreshUI()
    }

    // MARK: - Change history

    @objc public func nextChangeAction(_ sender: Any?) {
        guard let editor = currentEditor,
              let target = editor.changeHistory.nextChange(after: editor.caretPosition().line - 1)
        else { NSSound.beep(); return }
        editor.goToLine(target + 1)
    }

    @objc public func previousChangeAction(_ sender: Any?) {
        guard let editor = currentEditor,
              let target = editor.changeHistory.previousChange(before: editor.caretPosition().line - 1)
        else { NSSound.beep(); return }
        editor.goToLine(target + 1)
    }

    @objc public func toggleChangeHistoryMarginAction(_ sender: Any?) {
        showChangeHistory.toggle()
        for editor in allEditors { editor.gutterView?.showChangeHistory = showChangeHistory }
    }

    /// Opens the link under the caret. Notepad++ makes URLs clickable; on macOS
    /// the caret-based command also keeps it reachable from the keyboard.
    @objc public func openLinkAction(_ sender: Any?) {
        if currentEditor?.openLinkAtCaret() != true { NSSound.beep() }
    }

    // MARK: - Window chrome

    @objc public func toggleFullScreenAction(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }

    /// macOS has no per-app "always on top", but a floating window level is the
    /// behavioural equivalent.
    @objc public func toggleAlwaysOnTopAction(_ sender: Any?) {
        guard let window else { return }
        let floating = window.level == .floating
        window.level = floating ? .normal : .floating
    }

    /// Distraction-free: hide the tab bar, status bar and every panel.
    @objc public func toggleDistractionFreeAction(_ sender: Any?) {
        isDistractionFree.toggle()
        tabBar.isHidden = isDistractionFree
        statusBar.isHidden = isDistractionFree
        if isDistractionFree {
            hiddenPanelIdentifiers = visiblePanelIdentifiers()
            for identifier in hiddenPanelIdentifiers { dockHost?.hide(identifier) }
        } else {
            for identifier in hiddenPanelIdentifiers { dockHost?.show(identifier) }
            hiddenPanelIdentifiers = []
        }
    }
}
