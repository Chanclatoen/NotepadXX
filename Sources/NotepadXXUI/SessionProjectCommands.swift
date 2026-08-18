import AppKit
import NotepadXXCore

/// Named sessions and project files, on the File menu as in Notepad++.
extension MainWindowController {

    @objc public func saveSessionAction(_ sender: Any?) {
        guard let store = namedSessions else { return }
        let alert = NSAlert()
        alert.messageText = "Save session as"
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try? store.save(name: name, documents: documents, activeIndex: activeIndex)
        rebuildSessionMenu()
    }

    @objc public func loadSessionAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let name = item.representedObject as? String,
              let session = namedSessions?.load(name: name) else { return }

        var missing: [String] = []
        for path in session.filePaths {
            let url = URL(fileURLWithPath: path)
            if !openOrFocus(url: url) { missing.append((path as NSString).lastPathComponent) }
        }
        if session.filePaths.indices.contains(session.activeIndex),
           let index = indexOfDocument(for: URL(fileURLWithPath: session.filePaths[session.activeIndex])) {
            selectTab(at: index)
        }
        // Say which files could not be reopened rather than quietly dropping them.
        if !missing.isEmpty {
            presentError("Some files in “\(name)” could not be opened",
                         detail: missing.joined(separator: ", "))
        }
    }

    @objc public func deleteSessionAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let name = item.representedObject as? String else { return }
        namedSessions?.delete(name: name)
        rebuildSessionMenu()
    }

    public func rebuildSessionMenu() {
        guard let fileItem = NSApp.mainMenu?.items.first(where: { $0.title == "File" }),
              let sessionItem = fileItem.submenu?.items.first(where: { $0.title == "Sessions" })
        else { return }

        let menu = NSMenu(title: "Sessions")
        let save = menu.addItem(withTitle: "Save Current Session…",
                                action: #selector(saveSessionAction(_:)), keyEquivalent: "")
        save.target = self
        menu.addItem(.separator())

        let names = namedSessions?.names ?? []
        if names.isEmpty {
            let empty = menu.addItem(withTitle: "No Saved Sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        for name in names {
            let item = menu.addItem(withTitle: name,
                                    action: #selector(loadSessionAction(_:)), keyEquivalent: "")
            item.representedObject = name
            item.target = self
        }
        if !names.isEmpty {
            menu.addItem(.separator())
            let deleteParent = NSMenuItem(title: "Delete Session", action: nil, keyEquivalent: "")
            let deleteMenu = NSMenu()
            for name in names {
                let item = deleteMenu.addItem(withTitle: name,
                                              action: #selector(deleteSessionAction(_:)), keyEquivalent: "")
                item.representedObject = name
                item.target = self
            }
            deleteParent.submenu = deleteMenu
            menu.addItem(deleteParent)
        }
        sessionItem.submenu = menu
    }

    // MARK: - Projects

    @objc public func newProjectAction(_ sender: Any?) {
        guard let store = projectStore else { return }
        let alert = NSAlert()
        alert.messageText = "New project"
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var project = Project(name: name)
        // Seed with the open files, which is almost always what is wanted.
        project.root.filePaths = documents.compactMap { $0.fileURL?.path }
        try? store.save(project)
        activeProjectName = name
        rebuildProjectMenu()
    }

    @objc public func openProjectAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let name = item.representedObject as? String,
              let project = projectStore?.project(named: name) else { return }
        activeProjectName = name

        for path in project.allFilePaths {
            openOrFocus(url: URL(fileURLWithPath: path))
        }
        let missing = project.missingFilePaths()
        if !missing.isEmpty {
            presentError("Some files in “\(name)” are missing",
                         detail: missing.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
        }
    }

    @objc public func addOpenFilesToProjectAction(_ sender: Any?) {
        guard let store = projectStore, let name = activeProjectName,
              var project = store.project(named: name) else {
            presentError("No project is open", detail: "Create or open a project first.")
            return
        }
        let existing = Set(project.allFilePaths)
        let additions = documents.compactMap { $0.fileURL?.path }.filter { !existing.contains($0) }
        project.root.filePaths.append(contentsOf: additions)
        try? store.save(project)
        rebuildProjectMenu()
    }

    public func rebuildProjectMenu() {
        guard let fileItem = NSApp.mainMenu?.items.first(where: { $0.title == "File" }),
              let projectItem = fileItem.submenu?.items.first(where: { $0.title == "Projects" })
        else { return }

        let menu = NSMenu(title: "Projects")
        for (title, selector) in [
            ("New Project…", #selector(newProjectAction(_:))),
            ("Add Open Files to Project", #selector(addOpenFilesToProjectAction(_:))),
        ] {
            let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: "")
            item.target = self
        }
        menu.addItem(.separator())

        let projects = projectStore?.projects ?? []
        if projects.isEmpty {
            let empty = menu.addItem(withTitle: "No Projects", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        for project in projects {
            let item = menu.addItem(withTitle: project.name,
                                    action: #selector(openProjectAction(_:)), keyEquivalent: "")
            item.representedObject = project.name
            item.target = self
            item.state = project.name == activeProjectName ? .on : .off
        }
        projectItem.submenu = menu
    }
}
