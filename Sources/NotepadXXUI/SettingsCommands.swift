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
            editor.autoIndentEnabled = preferences.autoIndent
            editor.indentUsesSpaces = preferences.replaceTabsBySpaces
            editor.indentWidth = preferences.tabWidth
            editor.gutterView?.needsDisplay = true
            if let theme = themeStore?.theme(named: preferences.themeName) {
                editor.applyTheme(theme)
            }
        }
        if let layout = DocumentTabStrip.Layout(rawValue: preferences.tabLayoutRawValue),
           layout != tabBar.tabLayout {
            tabBar.tabLayout = layout
            applyTabLayoutConstraints()
        }
        statusBar.isHidden = !preferences.showStatusBar
        tabBar.isHidden = !preferences.showTabBar
        toolbar.isHidden = !preferences.showToolbar
        applyChromeTheme(themeStore?.theme(named: preferences.themeName))
    }

    /// Themes the toolbar, tab bar and status bar to match the editor, so the
    /// window reads as one surface rather than a light editor in dark chrome.
    /// Sets the window's appearance from the theme. The chrome paints itself
    /// from semantic tokens, so everything below follows automatically — there
    /// is no second palette to keep in step.
    public func applyChromeTheme(_ theme: EditorTheme?) {
        window?.appearance = AppearanceTheme.chrome(for: theme).appearance
        for view in [toolbar as NSView?, tabBar as NSView?, statusBar as NSView?].compactMap({ $0 }) {
            view.needsDisplay = true
        }
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
