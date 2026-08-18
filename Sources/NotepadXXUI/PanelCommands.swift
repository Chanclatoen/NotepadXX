import AppKit
import NotepadXXCore

/// View-menu panel toggles and the wiring between panels and the editor.
extension MainWindowController {

    /// Creates panels once and connects them to the active document.
    func installPanels(into host: DockHostView) {
        let functionList = FunctionListPanel()
        functionList.symbolProvider = { [weak self] in
            guard let self, self.documents.indices.contains(self.activeIndex) else { return [] }
            let document = self.documents[self.activeIndex]
            return FunctionListExtractor.symbols(in: document.text, languageName: document.languageName)
        }
        functionList.onSelect = { [weak self] symbol in
            self?.currentEditor?.goToLine(symbol.line + 1)
        }

        let workspace = FolderWorkspacePanel()
        workspace.onOpenFile = { [weak self] url in
            self?.openOrFocus(url: url)
        }

        let clipboard = ClipboardHistoryPanel()
        clipboard.onPaste = { [weak self] text in
            self?.currentEditor?.replaceSelection(with: text)
        }

        let characters = CharacterPanel()
        characters.onInsert = { [weak self] text in
            self?.currentEditor?.replaceSelection(with: text)
        }

        for panel in [functionList, workspace, clipboard, characters] as [DockablePanel] {
            host.register(panel)
        }
        self.functionListPanel = functionList
        self.folderWorkspacePanel = workspace
    }

    @objc public func toggleFunctionListAction(_ sender: Any?) { dockHost?.toggle("functionList") }
    @objc public func toggleClipboardHistoryAction(_ sender: Any?) { dockHost?.toggle("clipboardHistory") }
    @objc public func toggleCharacterPanelAction(_ sender: Any?) { dockHost?.toggle("characterPanel") }

    @objc public func openFolderAsWorkspaceAction(_ sender: Any?) {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.prompt = "Open as Workspace"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        folderWorkspacePanel?.addRoot(url)
        dockHost?.show("folderWorkspace")
    }

    /// Refreshes panels that depend on the active document.
    func refreshPanels() {
        functionListPanel?.reload()
        dockHost?.refreshVisiblePanels()
    }
}
