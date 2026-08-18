import AppKit

/// The application menu bar. Structured to mirror Notepad++'s menu layout
/// (File / Edit / Search / View / Encoding / Language / Settings / Tools /
/// Macro / Run / Window / Help) while respecting macOS conventions — the app
/// menu is required by the OS and Notepad++'s "?" menu becomes "Help".
public enum MainMenu {
    public static func build() -> NSMenu {
        let root = NSMenu()

        root.addItem(applicationMenuItem())
        root.addItem(fileMenuItem())
        root.addItem(editMenuItem())
        root.addItem(searchMenuItem())
        root.addItem(viewMenuItem())
        return root
    }

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        build(menu)
        item.submenu = menu
        return item
    }

    private static func applicationMenuItem() -> NSMenuItem {
        submenu("NotepadXX") { menu in
            menu.addItem(withTitle: "About NotepadXX", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            let hide = menu.addItem(withTitle: "Hide NotepadXX", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            hide.target = NSApp
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "Quit NotepadXX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
        }
    }

    private static func fileMenuItem() -> NSMenuItem {
        submenu("File") { menu in
            menu.addItem(withTitle: "New", action: #selector(MainWindowController.newDocumentAction(_:)), keyEquivalent: "n")
            menu.addItem(withTitle: "Open…", action: #selector(MainWindowController.openDocumentAction(_:)), keyEquivalent: "o")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Save", action: #selector(MainWindowController.saveDocumentAction(_:)), keyEquivalent: "s")
            let saveAs = menu.addItem(withTitle: "Save As…", action: #selector(MainWindowController.saveDocumentAsAction(_:)), keyEquivalent: "s")
            saveAs.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(withTitle: "Save All", action: #selector(MainWindowController.saveAllAction(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeTabAction(_:)), keyEquivalent: "w")
        }
    }

    private static func editMenuItem() -> NSMenuItem {
        submenu("Edit") { menu in
            menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
            let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            redo.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(.separator())
            menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        }
    }

    private static func searchMenuItem() -> NSMenuItem {
        submenu("Search") { menu in
            menu.addItem(withTitle: "Go to Line…", action: #selector(MainWindowController.goToLineAction(_:)), keyEquivalent: "l")
        }
    }

    private static func viewMenuItem() -> NSMenuItem {
        submenu("View") { menu in
            menu.addItem(withTitle: "Word Wrap", action: #selector(MainWindowController.toggleWordWrapAction(_:)), keyEquivalent: "")
        }
    }
}
