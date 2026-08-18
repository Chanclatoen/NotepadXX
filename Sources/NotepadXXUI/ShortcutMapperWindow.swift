import AppKit
import NotepadXXCore

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
    private var rows: [ShortcutCommand] = []

    public init(map: ShortcutMap, onChange: @escaping () -> Void) {
        self.map = map
        self.onChange = onChange
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

        let modify = NSButton(title: "Modify…", target: self, action: #selector(editSelected))
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearSelected))
        for button in [modify, clear] { button.bezelStyle = .rounded }

        let buttons = NSStackView(views: [modify, clear])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let content = NSView()
        for subview in [categoryControl, filterField, scroll, buttons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            categoryControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            categoryControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            filterField.centerYAnchor.constraint(equalTo: categoryControl.centerYAnchor),
            filterField.leadingAnchor.constraint(equalTo: categoryControl.trailingAnchor, constant: 12),
            filterField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),

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
        rows = map.commands(in: category).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
        tableView.reloadData()
    }

    @objc private func clearSelected() {
        guard rows.indices.contains(tableView.selectedRow) else { return }
        try? map.assign(nil, to: rows[tableView.selectedRow].id)
        onChange()
        reload()
    }

    @objc private func editSelected() {
        guard rows.indices.contains(tableView.selectedRow) else { return }
        let command = rows[tableView.selectedRow]

        let alert = NSAlert()
        alert.messageText = "Shortcut for “\(command.title)”"
        alert.informativeText = "Type the key, then choose the modifiers."
        let keyField = NSTextField(string: command.binding?.key ?? "")
        let commandBox = NSButton(checkboxWithTitle: "⌘", target: nil, action: nil)
        let shiftBox = NSButton(checkboxWithTitle: "⇧", target: nil, action: nil)
        let optionBox = NSButton(checkboxWithTitle: "⌥", target: nil, action: nil)
        let controlBox = NSButton(checkboxWithTitle: "⌃", target: nil, action: nil)

        let existing = command.binding?.modifiers ?? 0
        commandBox.state = existing & (1 << 20) != 0 ? .on : .off
        shiftBox.state = existing & (1 << 17) != 0 ? .on : .off
        optionBox.state = existing & (1 << 19) != 0 ? .on : .off
        controlBox.state = existing & (1 << 18) != 0 ? .on : .off

        let stack = NSStackView(views: [keyField, commandBox, shiftBox, optionBox, controlBox])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 26)
        keyField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        alert.accessoryView = stack
        alert.addButton(withTitle: "Assign")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = keyField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        var modifiers: UInt = 0
        if commandBox.state == .on { modifiers |= (1 << 20) }
        if shiftBox.state == .on { modifiers |= (1 << 17) }
        if optionBox.state == .on { modifiers |= (1 << 19) }
        if controlBox.state == .on { modifiers |= (1 << 18) }

        let binding = KeyBinding(key: key, modifiers: modifiers)
        do {
            try map.assign(binding, to: command.id)
        } catch ShortcutMap.AssignError.conflict(let holders) {
            // Never leave two commands on one key silently; make the user choose.
            let conflict = NSAlert()
            conflict.messageText = "That shortcut is already used"
            conflict.informativeText = "Currently assigned to: \(holders.joined(separator: ", "))."
            conflict.addButton(withTitle: "Reassign")
            conflict.addButton(withTitle: "Cancel")
            guard conflict.runModal() == .alertFirstButtonReturn else { return }
            try? map.assign(binding, to: command.id, force: true)
        } catch {
            return
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
        return field
    }
}
