import AppKit
import NotepadXXCore
import NotepadXXDesign

/// The Shortcut Mapper: every rebindable command, grouped by category, with
/// conflict detection.
@MainActor
public final class ShortcutMapperWindowController: NSWindowController {
    private let map: ShortcutMap
    private let onChange: () -> Void

    private let categoryControl = NSSegmentedControl(
        labels: ShortcutCommand.Category.allCases.map { $0.rawValue.capitalized },
        trackingMode: .selectOne, target: nil, action: nil
    )
    private let tableView = NSTableView()
    private let filterField = NSSearchField()
    private let conflictsOnlyBox = NSButton(checkboxWithTitle: "Conflicts only", target: nil, action: nil)
    private let conflictLabel = NSTextField(labelWithString: "")
    private var rows: [ShortcutCommand] = []
    private var conflictedIDs: Set<String> = []
    /// The bindings this build ships with, for Restore Defaults.
    private let defaults: [ShortcutCommand]

    public init(map: ShortcutMap, onChange: @escaping () -> Void) {
        self.map = map
        self.onChange = onChange
        self.defaults = map.commands
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Shortcut Mapper"
        super.init(window: window)
        buildLayout()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        categoryControl.selectedSegment = 0
        categoryControl.target = self
        categoryControl.action = #selector(reload)

        filterField.placeholderString = "Filter"
        filterField.target = self
        filterField.action = #selector(reload)

        for (identifier, title, width) in [("command", "Command", 340), ("shortcut", "Shortcut", 160)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = CGFloat(width)
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editSelected)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true

        conflictsOnlyBox.target = self
        conflictsOnlyBox.action = #selector(reload)
        conflictLabel.font = DS.Font.small()

        let modify = NSButton(title: "Modify…", target: self, action: #selector(editSelected))
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearSelected))
        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        for button in [modify, clear, restore] { button.bezelStyle = .rounded }

        let buttons = NSStackView(views: [conflictLabel, NSView(), restore, clear, modify])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let content = NSView()
        for subview in [categoryControl, filterField, conflictsOnlyBox, scroll, buttons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            categoryControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            categoryControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            filterField.centerYAnchor.constraint(equalTo: categoryControl.centerYAnchor),
            filterField.leadingAnchor.constraint(equalTo: categoryControl.trailingAnchor, constant: 12),
            filterField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            conflictsOnlyBox.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 8),
            conflictsOnlyBox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            scroll.topAnchor.constraint(equalTo: conflictsOnlyBox.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),

            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.contentView = content
    }

    @objc private func reload() {
        let category = ShortcutCommand.Category.allCases[
            max(0, min(categoryControl.selectedSegment, ShortcutCommand.Category.allCases.count - 1))
        ]
        let query = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        let conflicting = Set(map.conflictingCommands().map(\.id))

        rows = map.commands(in: category).filter { command in
            let matchesQuery = query.isEmpty || command.title.localizedCaseInsensitiveContains(query)
            let matchesFilter = conflictsOnlyBox.state == .off || conflicting.contains(command.id)
            return matchesQuery && matchesFilter
        }
        conflictedIDs = conflicting

        // A count, not a silent list: an unnoticed conflict means a command
        // that quietly never fires.
        let total = conflicting.count
        conflictLabel.stringValue = total == 0
            ? "No conflicts"
            : "\(total / 2) conflict\(total / 2 == 1 ? "" : "s") — a shortcut is claimed twice"
        conflictLabel.textColor = total == 0 ? DS.Color.textSecondary : DS.Color.warning
        tableView.reloadData()
    }

    /// Restores every binding to the build's defaults.
    @objc private func restoreDefaults() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Restore every shortcut to its default?"
        alert.informativeText = "Your rebindings are discarded. Nothing else changes."
        let restore = alert.addButton(withTitle: "Restore")
        restore.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.map.resetToDefaults(self.defaults)
            self.onChange()
            self.reload()
        }
    }

    @objc private func clearSelected() {
        guard rows.indices.contains(tableView.selectedRow) else { return }
        try? map.assign(nil, to: rows[tableView.selectedRow].id)
        onChange()
        reload()
    }

    @objc private func editSelected() {
        guard rows.indices.contains(tableView.selectedRow), let window else { return }
        let command = rows[tableView.selectedRow]

        let alert = NSAlert()
        alert.messageText = "Shortcut for “\(command.title)”"
        alert.informativeText = "Hold the modifiers and press a key. Esc cancels, ⌫ removes the shortcut."

        let recorder = ShortcutRecorderField(binding: command.binding)
        alert.accessoryView = recorder
        alert.addButton(withTitle: "Assign")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = recorder

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.apply(recorder.binding, to: command)
        }
    }

    /// Applies a recorded binding, refusing or confirming as its conflict
    /// severity requires.
    private func apply(_ binding: KeyBinding?, to command: ShortcutCommand) {
        guard let binding else {
            // ⌫ cleared it: the command keeps its menu item, without a key.
            try? map.assign(nil, to: command.id)
            onChange()
            reload()
            return
        }

        if let conflict = map.conflict(for: binding, assigningTo: command.id) {
            switch conflict.severity {
            case .reserved:
                // Refused with a sentence naming the owner, never a beep alone.
                let refusal = NSAlert()
                refusal.messageText = "\(binding.displayString) belongs to macOS"
                refusal.informativeText = conflict.explanation
                refusal.addButton(withTitle: "OK")
                window.map { refusal.beginSheetModal(for: $0) { _ in } }
                return
            case .hard:
                let choice = NSAlert()
                choice.messageText = "\(binding.displayString) is already used"
                choice.informativeText = conflict.explanation
                choice.addButton(withTitle: "Reassign")
                choice.addButton(withTitle: "Cancel")
                window.map { host in
                    choice.beginSheetModal(for: host) { [weak self] response in
                        guard response == .alertFirstButtonReturn, let self else { return }
                        try? self.map.assign(binding, to: command.id, force: true)
                        self.onChange()
                        self.reload()
                    }
                }
                return
            case .soft:
                // Both commands keep the key; scope decides which one fires.
                try? map.assign(binding, to: command.id, allowingShadow: true)
            }
        } else {
            try? map.assign(binding, to: command.id)
        }
        onChange()
        reload()
    }

}

extension ShortcutMapperWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let command = rows[row]
        let text = tableColumn?.identifier.rawValue == "shortcut"
            ? (command.binding?.displayString ?? "—")
            : command.title
        let field = NSTextField(labelWithString: text)
        field.font = tableColumn?.identifier.rawValue == "shortcut"
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 12)
        // A conflicted row is coloured *and* marked, so the flag does not rest
        // on hue alone.
        if conflictedIDs.contains(command.id) {
            field.textColor = DS.Color.warning
            if tableColumn?.identifier.rawValue == "shortcut" {
                field.stringValue = "⚠ \(text)"
            }
            field.setAccessibilityLabel("\(command.title), shortcut in conflict")
        }
        return field
    }
}
