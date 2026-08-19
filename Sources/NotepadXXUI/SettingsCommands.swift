import AppKit
import NotepadXXDesign
import NotepadXXCore

/// Settings menu: Preferences, Style Configurator and the Shortcut Mapper.
extension MainWindowController {

    @objc public func showPreferencesAction(_ sender: Any?) {
        guard let store = preferencesStore else { return }
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(
                store: store, themeStore: themeStore
            ) { [weak self] preferences in
                self?.applyPreferences(preferences)
            }
        }
        preferencesWindow?.showWindow(nil)
        preferencesWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc public func showShortcutMapperAction(_ sender: Any?) {
        guard let map = shortcutMap else { return }
        if shortcutWindow == nil {
            shortcutWindow = ShortcutMapperWindowController(map: map) { [weak self] in
                self?.applyShortcuts()
            }
        }
        shortcutWindow?.showWindow(nil)
        shortcutWindow?.window?.makeKeyAndOrderFront(nil)
    }

    /// Pushes preference changes into the live editors immediately, so the
    /// window is not a form you have to close before anything happens.
    public func applyPreferences(_ preferences: Preferences) {
        showSpaces = preferences.showWhitespace
        showLineEndings = preferences.showEndOfLine
        editorFontSize = preferences.fontSize
        tabWidth = preferences.tabWidth

        for editor in allEditors {
            editor.setInvisibles(spaces: showSpaces, tabs: showTabs, lineEndings: showLineEndings)
            editor.setFontSize(preferences.fontSize)
            editor.setWrapLines(preferences.wordWrap)
            editor.smartHighlightEnabled = preferences.smartHighlight
            editor.braceMatchingEnabled = preferences.braceMatching
            editor.gutterView?.showLineNumbers = preferences.showLineNumbers
            editor.gutterView?.showBookmarks = preferences.showBookmarkMargin
            editor.gutterView?.showChangeHistory = preferences.showChangeHistoryMargin
            editor.edgeColumn = preferences.edgeColumn
            editor.clickableURLs = preferences.clickableURLs
            editor.autoCompleteEnabled = preferences.autoCompletionEnabled
            editor.autoCompleteFromWords = preferences.autoCompletionFromWords
            editor.autoCompleteFromKeywords = preferences.autoCompletionFromKeywords
            editor.autoCompleteMinimumCharacters = preferences.autoCompletionMinimumCharacters
            editor.pathCompletionEnabled = preferences.pathCompletion
            editor.showCallTips = preferences.showCallTips
            editor.closeBracketsEnabled = preferences.closeBracketsAndQuotes
            editor.closeTagsEnabled = preferences.closeTags
            editor.autoIndentEnabled = preferences.autoIndent
            editor.showsCurrentLineHighlight = preferences.highlightCurrentLine
            editor.showWrapSymbol = preferences.showWrapSymbol
            editor.caretWidth = CGFloat(preferences.caretWidth)
            editor.caretBlinks = preferences.caretBlinks
            editor.scrollsBeyondLastLine = preferences.scrollBeyondLastLine
            editor.caretScrollMargin = preferences.caretScrollMargin
            editor.copiesWholeLineWhenEmpty = preferences.copyWholeLineWhenNothingSelected
            editor.trimsTrailingWhitespaceOnPaste = preferences.trimTrailingWhitespaceOnPaste
            // Per-language overrides win over the defaults, which is what
            // makes them worth having.
            let language = documents.first { editorControllers(for: $0).contains(editor) }?.languageName
            let indentation = preferences.indentation(forLanguage: language)
            editor.indentUsesSpaces = indentation.usesSpaces
            editor.indentWidth = indentation.width
            editor.reindentsOnPaste = preferences.reindentOnPaste
            editor.gutterView?.needsDisplay = true
            editor.applyTheme(resolvedTheme(named: preferences.themeName))
        }
        if let layout = DocumentTabStrip.Layout(rawValue: preferences.tabLayoutRawValue),
           layout != tabBar.tabLayout {
            tabBar.tabLayout = layout
            applyTabLayoutConstraints()
        }
        statusBar.isHidden = !preferences.showStatusBar
        tabBar.isHidden = !preferences.showTabBar
        toolbar.isHidden = !preferences.showToolbar
        applyChromeTheme(resolvedTheme(named: preferences.themeName),
                         followsSystem: preferences.themeName == EditorTheme.systemThemeName)
    }

    /// Themes the toolbar, tab bar and status bar to match the editor, so the
    /// window reads as one surface rather than a light editor in dark chrome.
    /// Sets the window's appearance from the theme. The chrome paints itself
    /// from semantic tokens, so everything below follows automatically — there
    /// is no second palette to keep in step.
    /// The theme to actually use. "System" resolves to the light or dark
    /// built-in according to the appearance the window is in, so the editor
    /// never stays light inside dark chrome.
    public func resolvedTheme(named name: String) -> EditorTheme {
        if let theme = themeStore?.theme(named: name), name != EditorTheme.systemThemeName {
            return theme
        }
        return isDarkAppearance ? .defaultDark : .defaultLight
    }

    /// Whether the window (or the app, before there is one) is in dark mode.
    var isDarkAppearance: Bool {
        let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Applies a theme to the window chrome.
    ///
    /// A theme the user named forces the matching appearance, so light chrome
    /// never frames a dark editor. "System" leaves the window following the
    /// Mac, which is what `followsSystem` says.
    public func applyChromeTheme(_ theme: EditorTheme?, followsSystem: Bool = false) {
        window?.appearance = followsSystem ? nil : AppearanceTheme.chrome(for: theme).appearance
        repaintChrome()
    }

    /// Marks the chrome for redraw. The components resolve their own tokens, so
    /// there is nothing to push into them.
    func repaintChrome() {
        for view in [toolbar as NSView?, tabBar as NSView?, statusBar as NSView?].compactMap({ $0 }) {
            view.needsDisplay = true
        }
    }

    /// Re-applies the theme when the Mac switches between light and dark, so
    /// a "System" theme is not merely the appearance at launch.
    public func appearanceDidChange() {
        guard preferencesStore?.preferences.themeName == EditorTheme.systemThemeName else { return }
        // Re-theme only. Assigning the window's appearance here would undo the
        // change that caused this call, and re-trigger it.
        let theme = resolvedTheme(named: EditorTheme.systemThemeName)
        for editor in allEditors { editor.applyTheme(theme) }
        repaintChrome()
        refreshUI()
    }

    /// Re-applies key equivalents from the Shortcut Mapper onto the menu bar.
    public func applyShortcuts() {
        guard let map = shortcutMap, let mainMenu = NSApp.mainMenu else { return }
        applyShortcuts(from: map, to: mainMenu)
    }

    private func applyShortcuts(from map: ShortcutMap, to menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                applyShortcuts(from: map, to: submenu)
            }
            guard let action = item.action else { continue }
            let identifier = NSStringFromSelector(action)
            guard let command = map.commands.first(where: { $0.id == identifier }) else { continue }
            if let binding = command.binding {
                item.keyEquivalent = binding.key
                item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: binding.modifiers)
            } else {
                item.keyEquivalent = ""
            }
        }
    }

    /// Builds the rebindable command list from the live menu bar, so the mapper
    /// stays in step with the menus instead of duplicating them by hand.
    public static func discoverCommands(in menu: NSMenu, category: ShortcutCommand.Category = .main)
        -> [ShortcutCommand] {
        var found: [ShortcutCommand] = []
        for item in menu.items {
            if let submenu = item.submenu {
                found += discoverCommands(in: submenu, category: category)
            }
            guard let action = item.action, !item.title.isEmpty else { continue }
            let identifier = NSStringFromSelector(action)
            guard !found.contains(where: { $0.id == identifier }) else { continue }
            let binding = item.keyEquivalent.isEmpty
                ? nil
                : KeyBinding(key: item.keyEquivalent,
                             modifiers: item.keyEquivalentModifierMask.rawValue)
            found.append(ShortcutCommand(
                id: identifier, title: item.title, category: category, binding: binding
            ))
        }
        return found
    }
}

extension MainWindowController {
    /// Help opens the project page, which is where the documentation lives.
    @objc public func showHelpAction(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/Chanclatoen/NotepadXX") else { return }
        NSWorkspace.shared.open(url)
    }
}
