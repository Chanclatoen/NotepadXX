import AppKit

/// The menu bar, mirroring Notepad++'s layout (File / Edit / Search / View /
/// Encoding / Language / Settings / Macro / Run / Window / Help) adapted to
/// macOS conventions: the app menu is required by the OS, and Notepad++'s "?"
/// menu becomes "Help".
///
/// Items are nil-targeted so they travel the responder chain and land on the
/// key window's controller, which is what keeps them enabled/disabled correctly.
public enum MainMenu {
    @MainActor
    public static func build() -> NSMenu {
        let root = NSMenu()
        root.addItem(applicationMenu())
        root.addItem(fileMenu())
        root.addItem(editMenu())
        root.addItem(searchMenu())
        root.addItem(viewMenu())
        root.addItem(encodingMenu())
        root.addItem(languageMenu())
        root.addItem(settingsMenu())
        root.addItem(macroMenu())
        root.addItem(runMenu())
        root.addItem(pluginsMenu())
        root.addItem(windowMenu())
        root.addItem(helpMenu())
        return root
    }

    // MARK: - Builders

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        build(menu)
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(
        _ menu: NSMenu, _ title: String, _ action: Selector,
        _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        return item
    }

    /// The application menu macOS expects: About, Preferences, Services, the
    /// three hide commands and Quit, in the standard order and with the
    /// standard shortcuts. Anything else here would be a surprise.
    private static func applicationMenu() -> NSMenuItem {
        submenu("NotepadXX") { menu in
            menu.addItem(withTitle: "About NotepadXX",
                         action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            menu.addItem(.separator())

            add(menu, "Settings…", #selector(MainWindowController.showPreferencesAction(_:)), ",")
            menu.addItem(.separator())

            let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            let servicesMenu = NSMenu(title: "Services")
            services.submenu = servicesMenu
            menu.addItem(services)
            NSApplication.shared.servicesMenu = servicesMenu
            menu.addItem(.separator())

            let hide = menu.addItem(withTitle: "Hide NotepadXX",
                                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            hide.target = NSApplication.shared
            let hideOthers = menu.addItem(withTitle: "Hide Others",
                                          action: #selector(NSApplication.hideOtherApplications(_:)),
                                          keyEquivalent: "h")
            hideOthers.keyEquivalentModifierMask = [.command, .option]
            hideOthers.target = NSApplication.shared
            let showAll = menu.addItem(withTitle: "Show All",
                                       action: #selector(NSApplication.unhideAllApplications(_:)),
                                       keyEquivalent: "")
            showAll.target = NSApplication.shared
            menu.addItem(.separator())

            let quit = menu.addItem(withTitle: "Quit NotepadXX",
                                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApplication.shared
        }
    }

    private static func fileMenu() -> NSMenuItem {
        submenu("File") { menu in
            add(menu, "New", #selector(MainWindowController.newDocumentAction(_:)), "n")
            add(menu, "Open…", #selector(MainWindowController.openDocumentAction(_:)), "o")
            menu.addItem(.separator())
            add(menu, "Save", #selector(MainWindowController.saveDocumentAction(_:)), "s")
            add(menu, "Save As…", #selector(MainWindowController.saveDocumentAsAction(_:)), "s", [.command, .shift])
            add(menu, "Save All", #selector(MainWindowController.saveAllAction(_:)), "s", [.command, .option])
            menu.addItem(.separator())
            add(menu, "Close Tab", #selector(MainWindowController.closeTabAction(_:)), "w")
        }
    }

    private static func editMenu() -> NSMenuItem {
        submenu("Edit") { menu in
            add(menu, "Undo", Selector(("undo:")), "z")
            add(menu, "Redo", Selector(("redo:")), "z", [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Cut", #selector(NSText.cut(_:)), "x")
            add(menu, "Copy", #selector(NSText.copy(_:)), "c")
            add(menu, "Paste", #selector(NSText.paste(_:)), "v")
            add(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())

            menu.addItem(submenu("Line Operations") { sub in
                add(sub, "Duplicate Current Line", #selector(MainWindowController.duplicateLinesAction(_:)),
                    "d", [.command, .shift])
                add(sub, "Remove Current Line", #selector(MainWindowController.removeLinesAction(_:)))
                add(sub, "Move Up Current Line", #selector(MainWindowController.moveLinesUpAction(_:)))
                add(sub, "Move Down Current Line", #selector(MainWindowController.moveLinesDownAction(_:)))
                add(sub, "Join Lines", #selector(MainWindowController.joinLinesAction(_:)))
                sub.addItem(.separator())
                add(sub, "Remove Consecutive Duplicate Lines", #selector(MainWindowController.removeConsecutiveDuplicatesAction(_:)))
                add(sub, "Remove Duplicate Lines", #selector(MainWindowController.removeAllDuplicatesAction(_:)))
                sub.addItem(.separator())
                add(sub, "Sort Lines Lexicographically Ascending", #selector(MainWindowController.sortLinesAscendingAction(_:)))
                add(sub, "Sort Lines Lexicographically Descending", #selector(MainWindowController.sortLinesDescendingAction(_:)))
                add(sub, "Sort Lines as Integers", #selector(MainWindowController.sortLinesIntegerAction(_:)))
                add(sub, "Sort Lines as Decimals", #selector(MainWindowController.sortLinesDecimalAction(_:)))
                add(sub, "Reverse Line Order", #selector(MainWindowController.reverseLineOrderAction(_:)))
                add(sub, "Randomize Line Order", #selector(MainWindowController.randomizeLineOrderAction(_:)))
            })

            menu.addItem(submenu("Convert Case To") { sub in
                add(sub, "UPPERCASE", #selector(MainWindowController.convertUpperCaseAction(_:)), "u", [.command, .shift])
                add(sub, "lowercase", #selector(MainWindowController.convertLowerCaseAction(_:)), "u")
                add(sub, "Proper Case", #selector(MainWindowController.convertProperCaseAction(_:)))
                add(sub, "Proper Case (blend)", #selector(MainWindowController.convertProperCaseBlendAction(_:)))
                add(sub, "Sentence case", #selector(MainWindowController.convertSentenceCaseAction(_:)))
                add(sub, "iNVERT cASE", #selector(MainWindowController.convertInvertCaseAction(_:)))
                add(sub, "ranDOm CasE", #selector(MainWindowController.convertRandomCaseAction(_:)))
            })

            menu.addItem(submenu("Blank Operations") { sub in
                add(sub, "Trim Trailing Space", #selector(MainWindowController.trimTrailingSpaceAction(_:)))
                add(sub, "Trim Leading Space", #selector(MainWindowController.trimLeadingSpaceAction(_:)))
                add(sub, "Trim Leading and Trailing Space", #selector(MainWindowController.trimBothEndsAction(_:)))
                sub.addItem(.separator())
                add(sub, "TAB to Space", #selector(MainWindowController.tabsToSpacesAction(_:)))
                add(sub, "Space to TAB (Leading)", #selector(MainWindowController.leadingSpacesToTabsAction(_:)))
                sub.addItem(.separator())
                add(sub, "Remove Empty Lines", #selector(MainWindowController.removeEmptyLinesAction(_:)))
                add(sub, "Remove Empty Lines (Containing Blank Characters)", #selector(MainWindowController.removeBlankLinesAction(_:)))
            })

            menu.addItem(submenu("EOL Conversion") { sub in
                add(sub, "Windows (CR LF)", #selector(MainWindowController.convertToWindowsEOLAction(_:)))
                add(sub, "Unix (LF)", #selector(MainWindowController.convertToUnixEOLAction(_:)))
                add(sub, "Macintosh (CR)", #selector(MainWindowController.convertToMacEOLAction(_:)))
            })

            menu.addItem(.separator())
            menu.addItem(.separator())
            let carets = NSMenuItem(title: "Multi-Select", action: nil, keyEquivalent: "")
            let caretMenu = NSMenu(title: "Multi-Select")
            add(caretMenu, "Select Next Occurrence",
                #selector(MainWindowController.selectNextOccurrenceAction(_:)), "d")
            add(caretMenu, "Select All Occurrences",
                #selector(MainWindowController.selectAllOccurrencesAction(_:)), "l", [.command, .shift])
            add(caretMenu, "Undo Last Caret",
                #selector(MainWindowController.removeLastCaretAction(_:)), "u", [.control, .shift])
            add(caretMenu, "Split Selection into Lines",
                #selector(MainWindowController.splitSelectionIntoLinesAction(_:)))
            add(caretMenu, "Collapse to Single Caret",
                #selector(MainWindowController.collapseCaretsAction(_:)))
            carets.submenu = caretMenu
            menu.addItem(carets)
            menu.addItem(.separator())
            add(menu, "Space to TAB (All)", #selector(MainWindowController.spacesToTabsAction(_:)))
            add(menu, "Column Editor…", #selector(MainWindowController.columnEditorAction(_:)), "c", [.command, .option])
            add(menu, "Insert Date/Time", #selector(MainWindowController.insertDateTimeAction(_:)))
        }
    }

    private static func searchMenu() -> NSMenuItem {
        submenu("Search") { menu in
            // Each item opens the same panel in its own mode, so there is one
            // search surface rather than a separate dialog per command.
            add(menu, "Find…", #selector(MainWindowController.showFindPanelAction(_:)), "f")
            add(menu, "Replace…", #selector(MainWindowController.showReplacePanelAction(_:)),
                "f", [.command, .option])
            add(menu, "Find in Files…", #selector(MainWindowController.showFindInFilesAction(_:)),
                "f", [.command, .shift])
            add(menu, "Mark…", #selector(MainWindowController.showMarkPanelAction(_:)), "m", [.command, .shift])
            menu.addItem(.separator())

            add(menu, "Find Next", #selector(MainWindowController.findNextAction(_:)), "g")
            add(menu, "Find Previous", #selector(MainWindowController.findPreviousAction(_:)), "g", [.command, .shift])
            add(menu, "Select and Find Next", #selector(MainWindowController.selectAndFindNextAction(_:)),
                "g", [.command, .option])
            add(menu, "Incremental Search", #selector(MainWindowController.incrementalSearchAction(_:)),
                "i", [.command, .option])
            add(menu, "Cycle Search Mode", #selector(MainWindowController.cycleSearchModeAction(_:)),
                "x", [.command, .option])
            menu.addItem(.separator())

            let marks = NSMenuItem(title: "Mark", action: nil, keyEquivalent: "")
            let markMenu = NSMenu(title: "Mark")
            add(markMenu, "Mark All", #selector(MainWindowController.markAllAction(_:)))
            add(markMenu, "Clear Marks", #selector(MainWindowController.clearMarksAction(_:)))
            add(markMenu, "Copy Marked Text", #selector(MainWindowController.copyMarkedTextAction(_:)))
            marks.submenu = markMenu
            menu.addItem(marks)

            let bookmarks = NSMenuItem(title: "Bookmark", action: nil, keyEquivalent: "")
            let bookmarkMenu = NSMenu(title: "Bookmark")
            add(bookmarkMenu, "Toggle Bookmark", #selector(MainWindowController.toggleBookmarkAction(_:)),
                "k", [.command, .shift])
            add(bookmarkMenu, "Next Bookmark", #selector(MainWindowController.nextBookmarkAction(_:)))
            add(bookmarkMenu, "Previous Bookmark", #selector(MainWindowController.previousBookmarkAction(_:)))
            add(bookmarkMenu, "Clear All Bookmarks", #selector(MainWindowController.clearBookmarksAction(_:)))
            add(bookmarkMenu, "Invert Bookmarks", #selector(MainWindowController.invertBookmarksAction(_:)))
            add(bookmarkMenu, "Copy Bookmarked Lines", #selector(MainWindowController.copyBookmarkedLinesAction(_:)))
            add(bookmarkMenu, "Cut Bookmarked Lines", #selector(MainWindowController.cutBookmarkedLinesAction(_:)))
            add(bookmarkMenu, "Remove Bookmarked Lines", #selector(MainWindowController.removeBookmarkedLinesAction(_:)))
            bookmarks.submenu = bookmarkMenu
            menu.addItem(bookmarks)

            menu.addItem(.separator())
            add(menu, "Go to Line…", #selector(MainWindowController.goToLineDialogAction(_:)), "l")
        }
    }

    private static func viewMenu() -> NSMenuItem {
        submenu("View") { menu in
            add(menu, "Word Wrap", #selector(MainWindowController.toggleWordWrapAction(_:)))
            menu.addItem(.separator())

            let symbols = NSMenuItem(title: "Show Symbol", action: nil, keyEquivalent: "")
            let symbolMenu = NSMenu(title: "Show Symbol")
            add(symbolMenu, "Show White Space", #selector(MainWindowController.toggleShowWhitespaceAction(_:)))
            add(symbolMenu, "Show Tabs", #selector(MainWindowController.toggleShowTabsAction(_:)))
            add(symbolMenu, "Show End of Line", #selector(MainWindowController.toggleShowEndOfLineAction(_:)))
            add(symbolMenu, "Show All Characters", #selector(MainWindowController.toggleShowAllCharactersAction(_:)))
            symbols.submenu = symbolMenu
            menu.addItem(symbols)

            let zoom = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
            let zoomMenu = NSMenu(title: "Zoom")
            add(zoomMenu, "Zoom In", #selector(MainWindowController.zoomInAction(_:)), "+")
            add(zoomMenu, "Zoom Out", #selector(MainWindowController.zoomOutAction(_:)), "-")
            add(zoomMenu, "Restore Default Zoom", #selector(MainWindowController.zoomRestoreAction(_:)), "0")
            zoom.submenu = zoomMenu
            menu.addItem(zoom)

            menu.addItem(.separator())
            add(menu, "Distraction Free Mode", #selector(MainWindowController.toggleDistractionFreeAction(_:)))
            add(menu, "Always on Top", #selector(MainWindowController.toggleAlwaysOnTopAction(_:)))
            add(menu, "Document Map", #selector(MainWindowController.toggleDocumentMapAction(_:)))
            add(menu, "Change History Margin", #selector(MainWindowController.toggleChangeHistoryMarginAction(_:)))
            menu.addItem(.separator())
            add(menu, "Toggle Fold at Caret", #selector(MainWindowController.toggleFoldAtCaretAction(_:)))
            add(menu, "Fold All", #selector(MainWindowController.foldAllAction(_:)))
            add(menu, "Unfold All", #selector(MainWindowController.unfoldAllAction(_:)))

            let tabLayout = NSMenuItem(title: "Tab Bar Layout", action: nil, keyEquivalent: "")
            let tabLayoutMenu = NSMenu(title: "Tab Bar Layout")
            add(tabLayoutMenu, "Horizontal", #selector(MainWindowController.useHorizontalTabsAction(_:)))
            add(tabLayoutMenu, "Multi-line", #selector(MainWindowController.useMultiLineTabsAction(_:)))
            add(tabLayoutMenu, "Vertical", #selector(MainWindowController.useVerticalTabsAction(_:)))
            tabLayout.submenu = tabLayoutMenu
            menu.addItem(tabLayout)
            let float = NSMenuItem(title: "Float Panel", action: nil, keyEquivalent: "")
            float.submenu = NSMenu(title: "Float Panel")
            menu.addItem(float)
            menu.addItem(.separator())
            add(menu, "Toggle Split View", #selector(MainWindowController.toggleSplitViewAction(_:)))
            add(menu, "Synchronize Vertical Scrolling",
                #selector(MainWindowController.toggleSyncVerticalScrollAction(_:)))
            add(menu, "Synchronize Horizontal Scrolling",
                #selector(MainWindowController.toggleSyncHorizontalScrollAction(_:)))
            add(menu, "Move to Other View", #selector(MainWindowController.moveToOtherViewAction(_:)))
            add(menu, "Clone to Other View", #selector(MainWindowController.cloneToOtherViewAction(_:)))
            add(menu, "Close Split", #selector(MainWindowController.closeSplitAction(_:)))
            menu.addItem(.separator())
            add(menu, "Function List", #selector(MainWindowController.toggleFunctionListAction(_:)))
            add(menu, "Folder as Workspace…", #selector(MainWindowController.openFolderAsWorkspaceAction(_:)))
            add(menu, "Project Panel", #selector(MainWindowController.toggleProjectPanelAction(_:)))
            add(menu, "Clipboard History", #selector(MainWindowController.toggleClipboardHistoryAction(_:)))
            add(menu, "Character Panel", #selector(MainWindowController.toggleCharacterPanelAction(_:)))
            add(menu, "Search Results", #selector(MainWindowController.toggleSearchResultsAction(_:)))
        }
    }

    private static func encodingMenu() -> NSMenuItem {
        submenu("Encoding") { menu in
            add(menu, "Encode in UTF-8", #selector(MainWindowController.encodeInUTF8Action(_:)))
            add(menu, "Encode in UTF-8-BOM", #selector(MainWindowController.encodeInUTF8BOMAction(_:)))
            add(menu, "Encode in ANSI", #selector(MainWindowController.encodeInANSIAction(_:)))
            menu.addItem(.separator())
            add(menu, "Convert to UTF-8", #selector(MainWindowController.convertToUTF8Action(_:)))
            add(menu, "Convert to UTF-8-BOM", #selector(MainWindowController.convertToUTF8BOMAction(_:)))
            add(menu, "Convert to ANSI", #selector(MainWindowController.convertToANSIAction(_:)))
        }
    }

    @MainActor
    private static func languageMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let menu = MainWindowController.buildLanguageMenu()
        menu.addItem(.separator())
        add(menu, "Define your language…", #selector(MainWindowController.defineLanguageAction(_:)))
        add(menu, "Import User Defined Language…", #selector(MainWindowController.importUDLAction(_:)))
        add(menu, "Export Current Language…", #selector(MainWindowController.exportUDLAction(_:)))
        item.submenu = menu
        return item
    }

    private static func settingsMenu() -> NSMenuItem {
        submenu("Settings") { menu in
            // Preferences itself is in the application menu, where macOS puts
            // it. Repeating it here would be two names for one command.
            add(menu, "Shortcut Mapper…", #selector(MainWindowController.showShortcutMapperAction(_:)))
        }
    }

    private static func macroMenu() -> NSMenuItem {
        submenu("Macro") { menu in
            add(menu, "Start/Stop Recording", #selector(MainWindowController.toggleMacroRecordingAction(_:)))
            add(menu, "Playback", #selector(MainWindowController.playbackMacroAction(_:)))
            add(menu, "Run a Macro Multiple Times…", #selector(MainWindowController.runMacroMultipleTimesAction(_:)))
            menu.addItem(.separator())
            add(menu, "Save Current Recorded Macro…", #selector(MainWindowController.saveCurrentMacroAction(_:)))
        }
    }

    private static func runMenu() -> NSMenuItem {
        submenu("Run") { menu in
            add(menu, "Run…", #selector(MainWindowController.runCommandAction(_:)), "r", [.command, .shift])
        }
    }

    private static func pluginsMenu() -> NSMenuItem {
        submenu("Plugins") { menu in
            add(menu, "Plugins Admin…", #selector(MainWindowController.showPluginsAdminAction(_:)))
            add(menu, "Open Plugins Folder", #selector(MainWindowController.openPluginsFolderAction(_:)))
        }
    }

    /// The Window menu macOS expects. Assigning it to `NSApp.windowsMenu` is
    /// what makes the system keep the list of open windows in it.
    private static func windowMenu() -> NSMenuItem {
        submenu("Window") { menu in
            let minimise = menu.addItem(withTitle: "Minimize",
                                        action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            minimise.keyEquivalentModifierMask = [.command]
            menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            // ⌃⇥ also opens it, handled as a key event: a menu item can carry
            // only one shortcut, and the design gives the list both.
            add(menu, "Open Documents…",
                #selector(MainWindowController.showDocumentSwitcherAction(_:)), "o", [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
            menu.addItem(.separator())
            menu.addItem(withTitle: "Bring All to Front",
                         action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
            NSApplication.shared.windowsMenu = menu
        }
    }

    /// Help. Assigning `helpMenu` is what puts macOS's own menu-search field
    /// at the top of it. The items here are Help's own — repeating Settings'
    /// commands under different names is what makes a menu bar confusing.
    private static func helpMenu() -> NSMenuItem {
        submenu("Help") { menu in
            add(menu, "NotepadXX Help", #selector(MainWindowController.showHelpAction(_:)), "?")
            NSApplication.shared.helpMenu = menu
        }
    }
}
