import AppKit
import NotepadXXCore

/// File menu commands beyond new/open/save.
extension MainWindowController {

    // MARK: - Recent files

    public func rebuildRecentMenu() {
        guard let fileItem = NSApp.mainMenu?.items.first(where: { $0.title == "File" }),
              let recentItem = fileItem.submenu?.items.first(where: { $0.title == "Open Recent" })
        else { return }

        let menu = NSMenu(title: "Open Recent")
        let paths = recentFiles?.paths ?? []
        if paths.isEmpty {
            let empty = menu.addItem(withTitle: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        let showFullPath = preferencesStore?.preferences.recentFilesShowFullPath ?? false
        for path in paths {
            let title = showFullPath ? path : (path as NSString).lastPathComponent
            let item = menu.addItem(withTitle: title,
                                    action: #selector(openRecentAction(_:)), keyEquivalent: "")
            item.representedObject = path
            item.target = self
        }
        if !paths.isEmpty {
            menu.addItem(.separator())
            let openAll = menu.addItem(withTitle: "Open All Recent Files",
                                       action: #selector(openAllRecentAction(_:)), keyEquivalent: "")
            openAll.target = self
            let clear = menu.addItem(withTitle: "Clear Recent Files List",
                                     action: #selector(clearRecentAction(_:)), keyEquivalent: "")
            clear.target = self
        }
        recentItem.submenu = menu
    }

    @objc public func openRecentAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let path = item.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        guard openOrFocus(url: url) else {
            // A stale entry is dropped rather than left to fail again.
            recentFiles?.remove(path)
            rebuildRecentMenu()
            presentError("Could not open \((path as NSString).lastPathComponent)",
                         detail: "The file may have been moved or deleted.")
            return
        }
        noteRecentlyOpened(url)
    }

    @objc public func openAllRecentAction(_ sender: Any?) {
        for path in recentFiles?.paths ?? [] {
            openOrFocus(url: URL(fileURLWithPath: path))
        }
    }

    @objc public func clearRecentAction(_ sender: Any?) {
        recentFiles?.clear()
        rebuildRecentMenu()
    }

    public func noteRecentlyOpened(_ url: URL) {
        recentFiles?.record(url.path)
        rebuildRecentMenu()
    }

    // MARK: - File operations on the active document

    @objc public func renameFileAction(_ sender: Any?) {
        guard let document = activeDocument, let url = document.fileURL else { NSSound.beep(); return }

        let alert = NSAlert()
        alert.messageText = "Rename “\(url.lastPathComponent)”"
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != url.lastPathComponent else { return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            presentError("A file named “\(newName)” already exists.", detail: nil)
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            document.relocate(to: destination)
            recentFiles?.remove(url.path)
            noteRecentlyOpened(destination)
            refreshUI()
        } catch {
            presentError("Could not rename the file", detail: error.localizedDescription)
        }
    }

    @objc public func moveFileAction(_ sender: Any?) {
        guard let document = activeDocument, let url = document.fileURL else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.message = "Move the file to a new location"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: url, to: destination)
            document.relocate(to: destination)
            noteRecentlyOpened(destination)
            refreshUI()
        } catch {
            presentError("Could not move the file", detail: error.localizedDescription)
        }
    }

    /// Notepad++ "Move to Recycle Bin"; the macOS equivalent is the Trash.
    @objc public func moveToTrashAction(_ sender: Any?) {
        guard let document = activeDocument, let url = document.fileURL else { NSSound.beep(); return }
        let confirm = NSAlert()
        confirm.messageText = "Move “\(url.lastPathComponent)” to the Trash?"
        confirm.addButton(withTitle: "Move to Trash")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            recentFiles?.remove(url.path)
            rebuildRecentMenu()
            closeTabAction(nil)
        } catch {
            presentError("Could not move the file to the Trash", detail: error.localizedDescription)
        }
    }

    @objc public func reloadFromDiskAction(_ sender: Any?) {
        guard let document = activeDocument, let url = document.fileURL else { NSSound.beep(); return }
        if document.isDirty {
            let confirm = NSAlert()
            confirm.messageText = "Reload “\(url.lastPathComponent)” from disk?"
            confirm.informativeText = "Unsaved changes will be lost."
            confirm.addButton(withTitle: "Reload")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }
        guard let reloaded = try? TextDocument.load(contentsOf: url) else {
            presentError("Could not reload the file", detail: nil)
            return
        }
        document.adoptContents(of: reloaded)
        currentEditor?.load(text: document.text)
        currentEditor?.resetChangeHistory()
        refreshUI()
    }

    @objc public func copyFullPathAction(_ sender: Any?) {
        guard let path = activeDocument?.fileURL?.path else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc public func copyFileNameAction(_ sender: Any?) {
        guard let name = activeDocument?.displayName else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
    }

    @objc public func copyDirectoryPathAction(_ sender: Any?) {
        guard let path = activeDocument?.fileURL?.deletingLastPathComponent().path else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    /// Notepad++ "Open Containing Folder in Explorer".
    @objc public func revealInFinderAction(_ sender: Any?) {
        guard let url = activeDocument?.fileURL else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Notepad++ opens a command prompt here; Terminal is the analogue.
    @objc public func openInTerminalAction(_ sender: Any?) {
        let directory = activeDocument?.fileURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([directory], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc public func saveACopyAsAction(_ sender: Any?) {
        guard let document = activeDocument else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.displayName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A copy must not retarget the open document.
        let copy = TextDocument(
            fileURL: nil, text: document.text,
            encoding: document.encoding, lineEnding: document.lineEnding
        )
        do { try copy.save(to: url) }
        catch { presentError("Could not save a copy", detail: String(describing: error)) }
    }

    // MARK: - Printing

    @objc public func printDocumentAction(_ sender: Any?) {
        guard let document = activeDocument else { return }
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        textView.string = LineEnding.normalize(document.text, to: .lf)
        textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)

        let info = NSPrintInfo.shared
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.jobTitle = document.displayName
        operation.run()
    }

    // MARK: - File change detection

    /// Checks open documents against disk. Called when the app becomes active,
    /// which is when the user would notice a change made elsewhere.
    public func checkForExternalChanges() {
        guard preferencesStore?.preferences.detectFileChanges ?? true else { return }
        let silent = preferencesStore?.preferences.reloadChangedFilesSilently ?? false

        var needsPrompt: [TextDocument] = []
        for tab in tabs {
            let document = tab.document
            guard document.hasChangedOnDisk(), let url = document.fileURL else { continue }

            // An unsaved edit must never be discarded without asking, whatever
            // the silent-reload preference says.
            if silent && !document.isDirty {
                if let reloaded = try? TextDocument.load(contentsOf: url) {
                    document.adoptContents(of: reloaded)
                    if let editor = editors[document.id] { editor.load(text: document.text) }
                }
                continue
            }
            needsPrompt.append(document)
        }

        // Each prompt is a sheet on this window, asked one at a time.
        promptForExternalChanges(needsPrompt)
        refreshUI()
    }

    func presentError(_ message: String, detail: String?) {
        let alert = NSAlert()
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.runModal()
    }
}
