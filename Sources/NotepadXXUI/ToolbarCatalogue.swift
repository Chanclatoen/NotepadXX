import AppKit
import NotepadXXDesign

/// The toolbar's command set, in the design's groups and order.
///
/// The design specifies Phosphor glyphs; these are their SF Symbols
/// equivalents, chosen to keep the same reading at 16 pt.
enum ToolbarCatalogue {
    static func groups() -> [[DSToolbar.Item]] {
        [
            [
                .init(symbol: "doc.badge.plus", label: "New",
                      selector: #selector(MainWindowController.newDocumentAction(_:))),
                .init(symbol: "folder", label: "Open",
                      selector: #selector(MainWindowController.openDocumentAction(_:))),
                .init(symbol: "square.and.arrow.down", label: "Save",
                      selector: #selector(MainWindowController.saveDocumentAction(_:))),
                .init(symbol: "square.and.arrow.down.on.square", label: "Save All",
                      selector: #selector(MainWindowController.saveAllAction(_:))),
                .init(symbol: "xmark.square", label: "Close",
                      selector: #selector(MainWindowController.closeTabAction(_:))),
                .init(symbol: "printer", label: "Print",
                      selector: #selector(MainWindowController.printDocumentAction(_:))),
            ],
            [
                .init(symbol: "scissors", label: "Cut", selector: #selector(NSText.cut(_:))),
                .init(symbol: "doc.on.doc", label: "Copy", selector: #selector(NSText.copy(_:))),
                .init(symbol: "clipboard", label: "Paste", selector: #selector(NSText.paste(_:))),
            ],
            [
                .init(symbol: "arrow.uturn.backward", label: "Undo", selector: Selector(("undo:"))),
                .init(symbol: "arrow.uturn.forward", label: "Redo", selector: Selector(("redo:"))),
            ],
            [
                .init(symbol: "magnifyingglass", label: "Find",
                      selector: #selector(MainWindowController.showFindPanelAction(_:)), shortcut: "⌘F"),
                .init(symbol: "arrow.2.squarepath", label: "Replace",
                      selector: #selector(MainWindowController.showReplacePanelAction(_:)), shortcut: "⌥⌘F"),
                .init(symbol: "doc.text.magnifyingglass", label: "Find in Files",
                      selector: #selector(MainWindowController.showFindInFilesAction(_:)), shortcut: "⇧⌘F"),
            ],
            [
                .init(symbol: "plus.magnifyingglass", label: "Zoom In",
                      selector: #selector(MainWindowController.zoomInAction(_:)), shortcut: "⌘+"),
                .init(symbol: "minus.magnifyingglass", label: "Zoom Out",
                      selector: #selector(MainWindowController.zoomOutAction(_:)), shortcut: "⌘−"),
            ],
            [
                .init(symbol: "arrow.turn.down.left", label: "Word Wrap",
                      selector: #selector(MainWindowController.toggleWordWrapAction(_:)),
                      isToggle: true, shortcut: "⌥⌘W"),
                .init(symbol: "paragraphsign", label: "Show All Characters",
                      selector: #selector(MainWindowController.toggleShowAllCharactersAction(_:)),
                      isToggle: true),
                .init(symbol: "text.justify.left", label: "Indent Guides",
                      selector: #selector(MainWindowController.toggleIndentGuideAction(_:)),
                      isToggle: true),
            ],
            [
                .init(symbol: "map", label: "Document Map",
                      selector: #selector(MainWindowController.toggleDocumentMapAction(_:)),
                      isToggle: true, shortcut: "⌥⌘M"),
                .init(symbol: "list.bullet.indent", label: "Function List",
                      selector: #selector(MainWindowController.toggleFunctionListAction(_:)),
                      isToggle: true, shortcut: "⌥⌘L"),
                .init(symbol: "folder.badge.gearshape", label: "Folder as Workspace",
                      selector: #selector(MainWindowController.openFolderAsWorkspaceAction(_:))),
            ],
            [
                .init(symbol: "record.circle", label: "Start Recording",
                      selector: #selector(MainWindowController.toggleMacroRecordingAction(_:)),
                      isToggle: true, shortcut: "⇧⌘R"),
                .init(symbol: "play", label: "Playback",
                      selector: #selector(MainWindowController.playbackMacroAction(_:))),
                .init(symbol: "terminal", label: "Run…",
                      selector: #selector(MainWindowController.runCommandAction(_:)), shortcut: "⌘R"),
            ],
        ]
    }
}
