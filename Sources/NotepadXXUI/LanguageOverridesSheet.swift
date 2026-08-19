import AppKit
import NotepadXXCore
import NotepadXXDesign

/// The Indentation page's "Language Overrides…" sheet.
///
/// The design keeps long lists off the page and behind a sheet, so the page
/// stays a short stack of groups. An override here wins over the defaults on
/// the page behind it.
@MainActor
public final class LanguageOverridesSheetController: NSWindowController {
    private let store: PreferencesStore
    private let languages: [String]
    private let onChange: () -> Void

    private let tableView = NSTableView()
    private var overrides: [String: Preferences.IndentOverride] = [:]

    public init(store: PreferencesStore, languages: [String], onChange: @escaping () -> Void) {
        self.store = store
        self.languages = languages.sorted()
        self.onChange = onChange
        self.overrides = store.preferences.indentOverrides
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Language Overrides"
        super.init(window: window)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        for (identifier, title, width) in [("language", "Language", 180),
                                           ("width", "Indent", 90),
                                           ("kind", "Using", 130)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = CGFloat(width)
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = DS.Metric.control + 4

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let explain = NSTextField(labelWithString:
            "A language with no override follows the defaults on the Indentation page.")
        explain.font = DS.Font.small()
        explain.textColor = DS.Color.textSecondary

        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let clear = NSButton(title: "Clear All", target: self, action: #selector(clearAll))
        clear.bezelStyle = .rounded

        let buttons = NSStackView(views: [clear, NSView(), done])
        buttons.orientation = .horizontal
        buttons.spacing = DS.Space.m

        let stack = NSStackView(views: [explain, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DS.Space.m
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DS.Space.xl),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -DS.Space.xl),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: DS.Space.xl),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -DS.Space.xl),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 250),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.contentView = content
    }

    /// The overrides as they stand, so the effect can be checked.
    public var currentOverrides: [String: Preferences.IndentOverride] { overrides }

    public func setOverride(_ override: Preferences.IndentOverride?, for language: String) {
        overrides[language] = override
        save()
    }

    @objc private func clearAll() {
        overrides = [:]
        tableView.reloadData()
        save()
    }

    @objc private func finish() {
        save()
        window?.sheetParent?.endSheet(window!)
    }

    private func save() {
        try? store.update { $0.indentOverrides = overrides }
        onChange()
    }
}

extension LanguageOverridesSheetController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { languages.count }

    public func tableView(_ tableView: NSTableView,
                          viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard languages.indices.contains(row) else { return nil }
        let language = languages[row]
        let override = overrides[language]

        switch tableColumn?.identifier.rawValue {
        case "language":
            let label = NSTextField(labelWithString: language)
            label.textColor = override == nil ? DS.Color.textSecondary : DS.Color.textPrimary
            return label

        case "width":
            let field = NSTextField(string: override.map { "\($0.width)" } ?? "")
            field.placeholderString = "\(store.preferences.tabWidth)"
            field.alignment = .right
            field.target = self
            field.action = #selector(widthChanged(_:))
            field.tag = row
            field.setAccessibilityLabel("\(language) indent size")
            return field

        case "kind":
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["Default", "Spaces", "Tabs"])
            popup.selectItem(at: override.map { $0.usesSpaces ? 1 : 2 } ?? 0)
            popup.target = self
            popup.action = #selector(kindChanged(_:))
            popup.tag = row
            popup.setAccessibilityLabel("\(language) indents with")
            return popup

        default:
            return nil
        }
    }

    @objc private func widthChanged(_ sender: NSTextField) {
        guard languages.indices.contains(sender.tag) else { return }
        let language = languages[sender.tag]
        guard let width = Int(sender.stringValue), width > 0 else {
            overrides[language] = nil
            save()
            return
        }
        let usesSpaces = overrides[language]?.usesSpaces ?? store.preferences.replaceTabsBySpaces
        overrides[language] = Preferences.IndentOverride(width: width, usesSpaces: usesSpaces)
        save()
    }

    @objc private func kindChanged(_ sender: NSPopUpButton) {
        guard languages.indices.contains(sender.tag) else { return }
        let language = languages[sender.tag]
        guard sender.indexOfSelectedItem > 0 else {
            overrides[language] = nil
            save()
            tableView.reloadData()
            return
        }
        let width = overrides[language]?.width ?? store.preferences.tabWidth
        overrides[language] = Preferences.IndentOverride(
            width: width, usesSpaces: sender.indexOfSelectedItem == 1)
        save()
        tableView.reloadData()
    }
}
