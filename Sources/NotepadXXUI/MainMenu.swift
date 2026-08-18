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
        root.addItem(macroMenu())
        root.addItem(runMenu())
        root.addItem(windowMenu())
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

    private static func applicationMenu() -> NSMenuItem {
        submenu("NotepadXX") { menu in
            menu.addItem(withTitle: "About NotepadXX",
                         action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            let hide = menu.addItem(withTitle: "Hide NotepadXX",
                                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            hide.target = NSApp
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit NotepadXX",
                                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
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
                add(sub, "Duplicate Current Line", #selector(MainWindowController.duplicateLinesAction(_:)), "d")
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
            add(menu, "Column Editor…", #selector(MainWindowController.columnEditorAction(_:)), "c", [.command, .option])
            add(menu, "Insert Date/Time", #selector(MainWindowController.insertDateTimeAction(_:)))
        }
    }

    private static func searchMenu() -> NSMenuItem {
        submenu("Search") { menu in
            add(menu, "Find…", #selector(MainWindowController.showFindPanelAction(_:)), "f")
            add(menu, "Replace…", #selector(MainWindowController.showFindPanelAction(_:)), "h")
            add(menu, "Find in Files…", #selector(MainWindowController.findInFilesAction(_:)), "f", [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Go to Line…", #selector(MainWindowController.goToLineDialogAction(_:)), "l")
        }
    }

    private static func viewMenu() -> NSMenuItem {
        submenu("View") { menu in
            add(menu, "Word Wrap", #selector(MainWindowController.toggleWordWrapAction(_:)))
            menu.addItem(.separator())
            add(menu, "Toggle Split View", #selector(MainWindowController.toggleSplitViewAction(_:)))
            add(menu, "Move to Other View", #selector(MainWindowController.moveToOtherViewAction(_:)))
            add(menu, "Clone to Other View", #selector(MainWindowController.cloneToOtherViewAction(_:)))
            add(menu, "Close Split", #selector(MainWindowController.closeSplitAction(_:)))
            menu.addItem(.separator())
            add(menu, "Function List", #selector(MainWindowController.toggleFunctionListAction(_:)))
            add(menu, "Folder as Workspace…", #selector(MainWindowController.openFolderAsWorkspaceAction(_:)))
            add(menu, "Clipboard History", #selector(MainWindowController.toggleClipboardHistoryAction(_:)))
            add(menu, "Character Panel", #selector(MainWindowController.toggleCharacterPanelAction(_:)))
            menu.addItem(.separator())
            add(menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
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
        add(menu, "Import User Defined Language…", #selector(MainWindowController.importUDLAction(_:)))
        add(menu, "Export Current Language…", #selector(MainWindowController.exportUDLAction(_:)))
        item.submenu = menu
        return item
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

    private static func windowMenu() -> NSMenuItem {
        submenu("Window") { menu in
            let minimise = menu.addItem(withTitle: "Minimize",
                                        action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            minimise.keyEquivalentModifierMask = [.command]
        }
    }
}
