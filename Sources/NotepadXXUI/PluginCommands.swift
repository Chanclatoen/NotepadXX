import AppKit
import NotepadXXCore

/// Plugins menu and the bridge that gives scripts access to the editor.
extension MainWindowController: PluginEditorBridge {

    // MARK: - PluginEditorBridge

    public func pluginCurrentText() -> String { currentEditor?.text ?? "" }

    public func pluginSetText(_ text: String) { currentEditor?.replaceAll(with: text) }

    public func pluginSelectedRange() -> NSRange {
        currentEditor?.selectedRange ?? NSRange(location: 0, length: 0)
    }

    public func pluginSetSelectedRange(_ range: NSRange) {
        currentEditor?.selectedRange = range
    }

    public func pluginReplaceSelection(with text: String) {
        currentEditor?.replaceSelection(with: text)
    }

    public func pluginCurrentFilePath() -> String? { activeDocument?.fileURL?.path }

    public func pluginDocumentCount() -> Int { tabs.count }

    public func pluginShowMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    public func pluginLog(_ message: String) {
        NSLog("[plugin] %@", message)
    }

    // MARK: - Loading

    /// Loads enabled plugins and rebuilds the Plugins menu.
    public func reloadPlugins() {
        guard let registry = pluginRegistry else { return }
        registry.reload()
        let host = PluginHost(bridge: self)
        host.loadAll(registry.enabledPlugins)
        pluginHost = host
        rebuildPluginsMenu()
    }

    func rebuildPluginsMenu() {
        guard let item = NSApp.mainMenu?.items.first(where: { $0.title == "Plugins" }) else { return }
        let menu = NSMenu(title: "Plugins")
        menu.addItem(withTitle: "Plugins Admin…",
                     action: #selector(showPluginsAdminAction(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open Plugins Folder",
                     action: #selector(openPluginsFolderAction(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let enabled = pluginRegistry?.enabledPlugins ?? []
        if enabled.isEmpty {
            let empty = menu.addItem(withTitle: "No plugins installed", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        }
        for plugin in enabled {
            let parent = NSMenuItem(title: plugin.manifest.name, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: plugin.manifest.name)
            for command in plugin.manifest.commands
            where pluginHost?.hasHandler(pluginIdentifier: plugin.id, commandID: command.id) == true {
                let entry = submenu.addItem(
                    withTitle: command.title,
                    action: #selector(runPluginCommandAction(_:)),
                    keyEquivalent: command.keyEquivalent ?? ""
                )
                // The menu item carries which plugin command to run.
                entry.representedObject = "\(plugin.id)\u{1F}\(command.id)"
                entry.target = self
            }
            if submenu.items.isEmpty {
                let none = submenu.addItem(withTitle: "No commands", action: nil, keyEquivalent: "")
                none.isEnabled = false
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        item.submenu = menu
    }

    @objc public func runPluginCommandAction(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let payload = item.representedObject as? String else { return }
        let parts = payload.split(separator: "\u{1F}", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }

        if let error = pluginHost?.invoke(pluginIdentifier: parts[0], commandID: parts[1]) {
            // A failing plugin reports why rather than doing nothing.
            let alert = NSAlert()
            alert.messageText = "Plugin command failed"
            alert.informativeText = error
            alert.runModal()
        }
        refreshUI()
    }

    @objc public func openPluginsFolderAction(_ sender: Any?) {
        guard let registry = pluginRegistry else { return }
        NSWorkspace.shared.open(registry.pluginsDirectory)
    }

    @objc public func showPluginsAdminAction(_ sender: Any?) {
        guard let registry = pluginRegistry else { return }
        if pluginsAdminWindow == nil {
            pluginsAdminWindow = PluginsAdminWindowController(registry: registry) { [weak self] in
                self?.reloadPlugins()
            }
        }
        pluginsAdminWindow?.showWindow(nil)
        pluginsAdminWindow?.window?.makeKeyAndOrderFront(nil)
    }
}
