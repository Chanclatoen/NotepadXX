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

        let documentMap = DocumentMapPanel()
        documentMap.contentProvider = { [weak self] in
            guard let self, let editor = self.currentEditor, let document = self.activeDocument else { return nil }
            return (document.text, editor.visibleLineRange())
        }
        documentMap.onJumpToLine = { [weak self] line in
            self?.currentEditor?.goToLine(line + 1)
        }
        self.documentMapPanel = documentMap

        let projects = ProjectPanel()
        projects.projectProvider = { [weak self] in
            guard let self, let name = self.activeProjectName else { return nil }
            return self.projectStore?.project(named: name)
        }
        projects.onOpenFile = { [weak self] url in self?.openOrFocus(url: url) }
        projects.onRemoveFile = { [weak self] path in
            guard let self, let store = self.projectStore, let name = self.activeProjectName,
                  var project = store.project(named: name) else { return }
            project.root.filePaths.removeAll { $0 == path }
            try? store.save(project)
        }
        self.projectPanel = projects

        for panel in [functionList, workspace, clipboard, characters, documentMap, projects] as [DockablePanel] {
            host.register(panel)
        }
        self.functionListPanel = functionList
        self.folderWorkspacePanel = workspace
    }

    @objc public func toggleFunctionListAction(_ sender: Any?) { dockHost?.toggle("functionList") }
    @objc public func toggleDocumentMapAction(_ sender: Any?) { dockHost?.toggle("documentMap") }
    @objc public func toggleProjectPanelAction(_ sender: Any?) { dockHost?.toggle("projectPanel") }

    /// Floats whichever panel the menu item names, or re-docks it if already floating.
    @objc public func toggleFloatPanelAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let identifier = item.representedObject as? String,
              let host = dockHost else { return }
        host.isFloating(identifier) ? host.dock(identifier) : host.float(identifier)
    }

    /// Builds the "Float Panel" submenu from the registered panels.
    public func buildFloatPanelMenu() -> NSMenu {
        let menu = NSMenu(title: "Float Panel")
        for (identifier, title) in [
            ("functionList", "Function List"), ("documentMap", "Document Map"),
            ("projectPanel", "Project"), ("folderWorkspace", "Folder as Workspace"),
            ("clipboardHistory", "Clipboard History"), ("characterPanel", "Character Panel"),
        ] {
            let item = menu.addItem(withTitle: title,
                                    action: #selector(toggleFloatPanelAction(_:)), keyEquivalent: "")
            item.representedObject = identifier
            item.target = self
            item.state = dockHost?.isFloating(identifier) == true ? .on : .off
        }
        return menu
    }
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
        documentMapPanel?.reload()
        projectPanel?.reload()
        dockHost?.refreshVisiblePanels()
    }
}
