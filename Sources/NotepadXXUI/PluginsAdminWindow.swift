import AppKit
import NotepadXXCore

/// Plugins Admin: list, enable, install and remove plugins.
@MainActor
public final class PluginsAdminWindowController: NSWindowController {
    private let registry: PluginRegistry
    private let onChange: () -> Void
    private let tableView = NSTableView()

    public init(registry: PluginRegistry, onChange: @escaping () -> Void) {
        self.registry = registry
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Plugins Admin"
        super.init(window: window)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        for (identifier, title, width) in [
            ("enabled", "", 30), ("name", "Plugin", 200),
            ("version", "Version", 70), ("status", "Status", 260),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = CGFloat(width)
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true

        let install = NSButton(title: "Install…", target: self, action: #selector(installTapped))
        let remove = NSButton(title: "Remove", target: self, action: #selector(removeTapped))
        let reload = NSButton(title: "Reload", target: self, action: #selector(reloadTapped))
        for button in [install, remove, reload] { button.bezelStyle = .rounded }
        let buttons = NSStackView(views: [install, remove, reload])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let content = NSView()
        for subview in [scroll, buttons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.contentView = content
    }

    @objc private func reloadTapped() {
        registry.reload()
        tableView.reloadData()
        onChange()
    }

    @objc private func installTapped() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Install"
        panel.message = "Choose a folder containing plugin.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try registry.install(from: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not install plugin"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
        reloadTapped()
    }

    @objc private func removeTapped() {
        let row = tableView.selectedRow
        guard registry.plugins.indices.contains(row) else { return }
        let plugin = registry.plugins[row]

        let confirm = NSAlert()
        confirm.messageText = "Remove “\(plugin.manifest.name)”?"
        confirm.informativeText = "Its folder will be deleted."
        confirm.addButton(withTitle: "Remove")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        try? registry.uninstall(identifier: plugin.id)
        reloadTapped()
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard registry.plugins.indices.contains(row) else { return }
        registry.setEnabled(sender.state == .on, forIdentifier: registry.plugins[row].id)
        reloadTapped()
    }
}

extension PluginsAdminWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { registry.plugins.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard registry.plugins.indices.contains(row) else { return nil }
        let plugin = registry.plugins[row]

        switch tableColumn?.identifier.rawValue {
        case "enabled":
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            box.state = plugin.isEnabled ? .on : .off
            box.tag = row
            // A plugin that failed to load cannot be meaningfully enabled.
            box.isEnabled = plugin.loadError == nil
            return box
        case "version":
            return NSTextField(labelWithString: plugin.manifest.version)
        case "status":
            let field = NSTextField(labelWithString: plugin.loadError ?? (plugin.manifest.description ?? "Ready"))
            field.textColor = plugin.loadError == nil ? .secondaryLabelColor : .systemRed
            field.lineBreakMode = .byTruncatingTail
            return field
        default:
            return NSTextField(labelWithString: plugin.manifest.name)
        }
    }
}
