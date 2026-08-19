import AppKit
import NotepadXXCore
import NotepadXXDesign

/// Plugins Admin: list, enable, install and remove plugins.
@MainActor
public final class PluginsAdminWindowController: NSWindowController {
    private let registry: PluginRegistry
    private let repository: PluginRepository?
    private let onChange: () -> Void
    private let tableView = NSTableView()
    private let tabControl = NSSegmentedControl(
        labels: ["Installed", "Available", "Updates"],
        trackingMode: .selectOne, target: nil, action: nil
    )
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var listings: [PluginListing] = []

    /// Which tab is showing.
    private enum Tab: Int { case installed, available, updates }
    private var tab: Tab { Tab(rawValue: tabControl.selectedSegment) ?? .installed }

    public init(registry: PluginRegistry, repository: PluginRepository? = nil,
                onChange: @escaping () -> Void) {
        self.repository = repository
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
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        searchField.placeholderString = "Search plugins"
        searchField.target = self
        searchField.action = #selector(tabChanged)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

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

        footnote.font = DS.Font.small()
        footnote.textColor = DS.Color.textTertiary
        footnote.stringValue = "Changes to enabled state take effect after relaunch. "
            + "Plug-ins run sandboxed and are verified against their published checksum before install."
        footnote.lineBreakMode = .byWordWrapping
        footnote.maximumNumberOfLines = 2

        let openFolder = NSButton(title: "Open Plug-ins Folder", target: self,
                                  action: #selector(openPluginsFolderTapped))
        let relaunch = NSButton(title: "Relaunch", target: self, action: #selector(relaunchTapped))
        for button in [openFolder, relaunch] { button.bezelStyle = .rounded }

        let installSelected = NSButton(title: "Install", target: self, action: #selector(installSelectedTapped))
        let install = NSButton(title: "Install from Folder…", target: self, action: #selector(installTapped))
        let remove = NSButton(title: "Remove", target: self, action: #selector(removeTapped))
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshTapped))
        for button in [installSelected, install, remove, refresh] { button.bezelStyle = .rounded }
        let buttons = NSStackView(views: [statusLabel, NSView(), openFolder, relaunch,
                                          installSelected, install, remove, refresh])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let content = NSView()
        for subview in [tabControl, searchField, scroll, footnote, buttons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: tabControl.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: tabControl.trailingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: footnote.topAnchor, constant: -10),
            footnote.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            footnote.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            footnote.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.contentView = content
    }

    /// Switches to the Available list and refreshes it.
    public func showAvailableTab() {
        tabControl.selectedSegment = 1
        refreshTapped()
    }

    @objc private func tabChanged() {
        tableView.reloadData()
        updateStatus()
    }

    @objc private func refreshTapped() {
        registry.reload()
        guard let repository else { tableView.reloadData(); onChange(); return }

        statusLabel.stringValue = "Refreshing…"
        Task { @MainActor in
            let failures = await repository.refresh()
            self.tableView.reloadData()
            self.updateStatus()
            if !failures.isEmpty {
                // Say which source failed rather than silently showing nothing.
                self.statusLabel.stringValue = "\(failures.count) source(s) unavailable"
            }
            self.onChange()
        }
    }

    private let footnote = NSTextField(labelWithString: "")

    /// Each tab carries its own count, so the work waiting in Updates is
    /// visible without opening it.
    private func updateTabCounts() {
        let installed = registry.plugins.count
        let available = repository.map { repo -> Int in
            let have = Set(registry.plugins.map(\.id))
            return repo.allListings.filter { !have.contains($0.identifier) }.count
        } ?? 0
        let updates = repository?.availableUpdates(installed: registry.plugins).count ?? 0

        for (index, label) in [("Installed", installed), ("Available", available),
                               ("Updates", updates)].enumerated() {
            tabControl.setLabel(label.1 > 0 ? "\(label.0)  \(label.1)" : label.0, forSegment: index)
        }
    }

    @objc private func openPluginsFolderTapped() {
        let directory = registry.pluginsDirectory
        // The folder may not exist yet on a fresh install; opening a missing
        // path does nothing and looks like a broken button.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    /// Enabling or disabling a plug-in only takes effect on a fresh launch, so
    /// the window offers the relaunch rather than leaving the user to do it.
    @objc private func relaunchTapped() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Relaunch NotepadXX?"
        alert.informativeText = "Open documents are restored. Unsaved edits are kept as snapshots."
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", Bundle.main.bundlePath]
            try? task.run()
            NSApp.terminate(nil)
        }
    }

    private func updateStatus() {
        updateTabCounts()
        switch tab {
        case .installed:
            statusLabel.stringValue = "\(registry.plugins.count) installed"
        case .available:
            statusLabel.stringValue = "\(currentListings().count) available"
        case .updates:
            let count = currentListings().count
            statusLabel.stringValue = count == 0 ? "Everything is up to date" : "\(count) update(s)"
        }
    }

    /// Listings for the active tab, filtered by the search field.
    private func currentListings() -> [PluginListing] {
        guard let repository else { return [] }
        let base: [PluginListing]
        switch tab {
        case .installed: base = []
        case .available:
            let installed = Set(registry.plugins.map(\.id))
            base = repository.allListings.filter { !installed.contains($0.identifier) }
        case .updates:
            base = repository.availableUpdates(installed: registry.plugins)
        }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    /// One-click install of the selected catalogue entry.
    @objc private func installSelectedTapped() {
        guard tab != .installed, let repository else { return }
        let rows = currentListings()
        guard rows.indices.contains(tableView.selectedRow) else { return }
        let listing = rows[tableView.selectedRow]

        statusLabel.stringValue = "Installing \(listing.name)…"
        Task { @MainActor in
            do {
                _ = try await repository.install(listing, into: self.registry.pluginsDirectory)
                self.registry.reload()
                self.tableView.reloadData()
                self.updateStatus()
                self.onChange()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not install \(listing.name)"
                alert.informativeText = Self.describe(error)
                alert.runModal()
                self.updateStatus()
            }
        }
    }

    /// Plain-language errors: a checksum failure in particular needs to read as
    /// a security refusal, not a network hiccup.
    static func describe(_ error: Error) -> String {
        guard let error = error as? PluginRepository.RepositoryError else {
            return String(describing: error)
        }
        switch error {
        case .checksumMismatch:
            return "The download did not match the checksum in the catalogue, so it was discarded. "
                 + "The file may be corrupt or tampered with."
        case .unreachable(let source): return "Could not reach \(source)."
        case .malformedCatalogue(let source): return "\(source) is not a valid plugin catalogue."
        case .notAnArchive(let name): return "\(name) is not a readable archive."
        case .noPluginInArchive: return "The archive does not contain a plugin.json."
        }
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
        refreshTapped()
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
        refreshTapped()
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard registry.plugins.indices.contains(row) else { return }
        registry.setEnabled(sender.state == .on, forIdentifier: registry.plugins[row].id)
        refreshTapped()
    }
}

extension PluginsAdminWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        tab == .installed ? registry.plugins.count : currentListings().count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tab != .installed {
            let rows = currentListings()
            guard rows.indices.contains(row) else { return nil }
            let listing = rows[row]
            switch tableColumn?.identifier.rawValue {
            case "enabled": return NSView()
            case "version": return NSTextField(labelWithString: listing.version)
            case "status":
                let field = NSTextField(labelWithString: listing.description)
                field.textColor = .secondaryLabelColor
                field.lineBreakMode = .byTruncatingTail
                return field
            default: return NSTextField(labelWithString: listing.name)
            }
        }

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
