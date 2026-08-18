import AppKit
import NotepadXXCore

/// Function List: symbols in the current document, click to jump.
@MainActor
public final class FunctionListPanel: NSObject, DockablePanel {
    public let panelIdentifier = "functionList"
    public let panelTitle = "Function List"
    public let preferredPosition = DockPosition.right

    public var symbolProvider: (() -> [Symbol])?
    public var onSelect: ((Symbol) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let filterField = NSSearchField()
    private let container = NSView()
    private var symbols: [Symbol] = []
    private var filtered: [Symbol] = []

    public override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("symbol"))
        column.width = 220
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .small
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        filterField.placeholderString = "Filter"
        filterField.target = self
        filterField.action = #selector(filterChanged)
        filterField.controlSize = .small

        for view in [filterField, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            filterField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            filterField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            scrollView.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    public var contentView: NSView { container }

    public func panelDidBecomeVisible() { reload() }

    public func reload() {
        symbols = symbolProvider?() ?? []
        applyFilter()
    }

    private func applyFilter() {
        let query = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        filtered = query.isEmpty
            ? symbols
            : symbols.filter { $0.name.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
    }

    @objc private func filterChanged() { applyFilter() }

    @objc private func rowClicked() {
        let row = tableView.selectedRow
        guard filtered.indices.contains(row) else { return }
        onSelect?(filtered[row])
    }
}

extension FunctionListPanel: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let symbol = filtered[row]
        let field = NSTextField(labelWithString: "\(symbol.name)  ·  \(symbol.kind)")
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

/// Folder as Workspace: browse a directory tree, click to open a file.
@MainActor
public final class FolderWorkspacePanel: NSObject, DockablePanel {
    public let panelIdentifier = "folderWorkspace"
    public let panelTitle = "Folder as Workspace"
    public let preferredPosition = DockPosition.left

    public var onOpenFile: ((URL) -> Void)?

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private var roots: [URL] = []
    private var childrenCache: [URL: [URL]] = [:]

    public override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.width = 220
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(rowActivated)
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
    }

    public var contentView: NSView { scrollView }

    public func addRoot(_ url: URL) {
        guard !roots.contains(url) else { return }
        roots.append(url)
        childrenCache.removeAll()
        outlineView.reloadData()
    }

    public func removeAllRoots() {
        roots.removeAll()
        childrenCache.removeAll()
        outlineView.reloadData()
    }

    /// Directory contents, cached and sorted with folders first.
    private func children(of url: URL) -> [URL] {
        if let cached = childrenCache[url] { return cached }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = contents.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
        childrenCache[url] = sorted
        return sorted
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    @objc private func rowActivated() {
        let row = outlineView.clickedRow
        guard row >= 0, let url = outlineView.item(atRow: row) as? URL else { return }
        if isDirectory(url) {
            outlineView.isItemExpanded(url) ? outlineView.collapseItem(url) : outlineView.expandItem(url)
        } else {
            onOpenFile?(url)
        }
    }
}

extension FolderWorkspacePanel: NSOutlineViewDataSource, NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let url = item as? URL else { return roots.count }
        return isDirectory(url) ? children(of: url).count : 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let url = item as? URL else { return roots[index] }
        return children(of: url)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? URL).map(isDirectory) ?? false
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let url = item as? URL else { return nil }
        let field = NSTextField(labelWithString: url.lastPathComponent)
        field.font = .systemFont(ofSize: 11)
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }
}

/// Clipboard History.
///
/// macOS exposes no pasteboard history API, so this polls `changeCount` and can
/// only record copies made while NotepadXX is running — a genuine platform
/// limitation, not an omission.
@MainActor
public final class ClipboardHistoryPanel: NSObject, DockablePanel {
    public let panelIdentifier = "clipboardHistory"
    public let panelTitle = "Clipboard History"
    public let preferredPosition = DockPosition.right

    public var onPaste: ((String) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var entries: [String] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    public var maximumEntries = 50

    public override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 220
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .small
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowActivated)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        startPolling()
    }

    /// Stops pasteboard polling. Call before discarding the panel.
    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    public var contentView: NSView { scrollView }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.capturePasteboardIfChanged()
        }
    }

    func capturePasteboardIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        record(text)
    }

    /// Most recent first, de-duplicated, capped.
    func record(_ text: String) {
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
        if entries.count > maximumEntries { entries.removeLast(entries.count - maximumEntries) }
        tableView.reloadData()
    }

    var recordedEntries: [String] { entries }

    @objc private func rowActivated() {
        let row = tableView.clickedRow
        guard entries.indices.contains(row) else { return }
        onPaste?(entries[row])
    }
}

extension ClipboardHistoryPanel: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let preview = entries[row]
            .replacingOccurrences(of: "\n", with: "\u{21B5}")
            .prefix(120)
        let field = NSTextField(labelWithString: String(preview))
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

/// Character Panel: insert a character by code point.
@MainActor
public final class CharacterPanel: NSObject, DockablePanel {
    public let panelIdentifier = "characterPanel"
    public let panelTitle = "Character Panel"
    public let preferredPosition = DockPosition.bottom

    public var onInsert: ((String) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    /// ASCII plus Latin-1, matching what Notepad++ shows by default.
    private let codePoints: [Int] = Array(32...126) + Array(160...255)

    public override init() {
        super.init()
        for (identifier, width) in [("value", 50), ("hex", 50), ("char", 50), ("name", 260)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = identifier.capitalized
            column.width = CGFloat(width)
            tableView.addTableColumn(column)
        }
        tableView.rowSizeStyle = .small
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowActivated)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
    }

    public var contentView: NSView { scrollView }

    @objc private func rowActivated() {
        let row = tableView.clickedRow
        guard codePoints.indices.contains(row),
              let scalar = Unicode.Scalar(codePoints[row]) else { return }
        onInsert?(String(Character(scalar)))
    }
}

extension CharacterPanel: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { codePoints.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard codePoints.indices.contains(row), let scalar = Unicode.Scalar(codePoints[row]) else { return nil }
        let value = codePoints[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "value": text = String(value)
        case "hex": text = String(format: "0x%02X", value)
        case "char": text = String(Character(scalar))
        default: text = scalar.properties.name ?? ""
        }
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        return field
    }
}
