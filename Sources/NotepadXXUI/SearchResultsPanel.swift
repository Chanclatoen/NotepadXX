import AppKit
import NotepadXXCore
import NotepadXXDesign

/// Search Results, docked at the bottom of the window.
///
/// Hits are grouped by file: the file row carries a name, a dimmed path and a
/// count; each hit row carries a right-aligned line number and the source line
/// with the match highlighted and its indentation preserved. A collapsed group
/// keeps its count, so collapsing never hides information.
public final class SearchResultsPanel: NSObject, DockablePanel {
    public let panelIdentifier = "searchResults"
    public let panelTitle = "Search Results"
    public let preferredPosition = DockPosition.bottom

    /// Called with the file and 1-based line of an activated hit.
    public var onSelectHit: ((URL, Int) -> Void)?
    /// ⇧⏎ opens the hit in the other split pane.
    public var onSelectHitInOtherPane: ((URL, Int) -> Void)?

    private let outlineView = ResultsOutlineView()
    private let scrollView = NSScrollView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let container = NSView()
    private let emptyState = DSEmptyState(
        symbol: "text.magnifyingglass",
        title: "No results yet",
        message: "Run a search to see matches grouped by file.")

    private var results: [FileSearchResult] = []
    private var query = ""

    public override init() {
        super.init()
        buildLayout()
    }

    public var contentView: NSView { container }

    /// The summary line, e.g. "“descriptor” · 37 hits in 4 of 218 files".
    public var summary: String { summaryLabel.stringValue }

    public var fileCount: Int { results.count }
    public var hitCount: Int { results.reduce(0) { $0 + $1.hits.count } }

    private func buildLayout() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hit"))
        column.width = 640
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = nil
        outlineView.rowHeight = DS.Metric.listRow
        outlineView.backgroundColor = DS.Color.panel
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.selectionHighlightStyle = .regular
        outlineView.target = self
        outlineView.doubleAction = #selector(activateSelectedRow)
        outlineView.onActivate = { [weak self] inOtherPane in
            self?.activateSelection(inOtherPane: inOtherPane)
        }
        outlineView.onCopy = { [weak self] in self?.copySelection() }
        outlineView.setAccessibilityLabel("Search results")

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DS.Color.panel
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = DS.Font.small()
        summaryLabel.textColor = DS.Color.textSecondary
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = DS.Font.small()
        hintLabel.textColor = DS.Color.textTertiary
        hintLabel.stringValue = "↑↓ hit · ⌥↑↓ file · ⏎ open · ⇧⏎ open in other pane · ⌘C copy with paths"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let collapseAll = DSToolbarButton(symbol: "rectangle.compress.vertical", label: "Collapse All",
                                          target: self, action: #selector(collapseAll))
        let copy = DSToolbarButton(symbol: "doc.on.doc", label: "Copy All Results",
                                   target: self, action: #selector(copyEverything))
        let clear = DSToolbarButton(symbol: "trash", label: "Clear Results",
                                    target: self, action: #selector(clear))
        let actions = NSStackView(views: [summaryLabel, NSView(), collapseAll, copy, clear])
        actions.orientation = .horizontal
        actions.spacing = DS.Space.xs
        actions.translatesAutoresizingMaskIntoConstraints = false

        emptyState.translatesAutoresizingMaskIntoConstraints = false

        for subview in [actions, scrollView, hintLabel, emptyState] {
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            actions.topAnchor.constraint(equalTo: container.topAnchor, constant: DS.Space.xs),
            actions.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DS.Space.m),
            actions.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DS.Space.m),

            scrollView.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: DS.Space.xs),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -DS.Space.xs),

            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DS.Space.m),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor,
                                                constant: -DS.Space.m),
            hintLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DS.Space.xs),

            emptyState.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
        updateEmptyState()
    }

    // MARK: Content

    public func present(results: [FileSearchResult], summary: String, query: String = "") {
        self.results = results
        self.query = query
        summaryLabel.stringValue = summary
        outlineView.reloadData()
        for result in results { outlineView.expandItem(result) }
        updateEmptyState()
        if !results.isEmpty {
            outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        }
    }

    @objc public func clear() {
        results = []
        summaryLabel.stringValue = ""
        outlineView.reloadData()
        updateEmptyState()
    }

    @objc private func collapseAll() {
        // Collapsed groups keep their counts, so nothing is lost by collapsing.
        for result in results { outlineView.collapseItem(result) }
    }

    private func updateEmptyState() {
        emptyState.isHidden = !results.isEmpty
        scrollView.isHidden = results.isEmpty
        hintLabel.isHidden = results.isEmpty
    }

    public func panelDidBecomeVisible() {}

    // MARK: Activation

    @objc private func activateSelectedRow() {
        activateSelection(inOtherPane: false)
    }

    private func activateSelection(inOtherPane: Bool) {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return }
        if let hit = outlineView.item(atRow: row) as? FileSearchHit {
            if inOtherPane {
                onSelectHitInOtherPane?(hit.url, hit.lineNumber)
            } else {
                onSelectHit?(hit.url, hit.lineNumber)
            }
        } else if let result = outlineView.item(atRow: row) as? FileSearchResult {
            // Activating a file row opens the file at its first hit.
            guard let first = result.hits.first else { return }
            onSelectHit?(first.url, first.lineNumber)
        }
    }

    /// ⌘C copies the selected lines with their paths, so a result can be
    /// pasted somewhere it still makes sense.
    @objc public func copySelection() {
        let text = copyText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyEverything() {
        selectAll()
        copySelection()
    }

    /// Selects every row, for the panel's copy-everything action.
    public func selectAll() {
        outlineView.selectRowIndexes(IndexSet(0..<outlineView.numberOfRows), byExtendingSelection: false)
    }

    /// Exposed so the behaviour can be checked without the pasteboard.
    public func copyText() -> String {
        let selected = outlineView.selectedRowIndexes
        let rows = selected.isEmpty ? IndexSet(0..<outlineView.numberOfRows) : selected
        var lines: [String] = []
        for row in rows {
            if let result = outlineView.item(atRow: row) as? FileSearchResult {
                lines.append("\(result.url.path) (\(result.hits.count))")
            } else if let hit = outlineView.item(atRow: row) as? FileSearchHit {
                lines.append("\(hit.url.path):\(hit.lineNumber): \(hit.lineText)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension SearchResultsPanel: NSOutlineViewDataSource {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return results.count }
        if let result = item as? FileSearchResult { return result.hits.count }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return results[index] }
        return (item as! FileSearchResult).hits[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is FileSearchResult
    }
}

extension SearchResultsPanel: NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView,
                            viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let result = item as? FileSearchResult {
            return SearchResultFileRow(result: result)
        }
        if let hit = item as? FileSearchHit {
            return SearchResultHitRow(hit: hit, query: query)
        }
        return nil
    }
}

/// The outline view, with the keyboard map the design specifies.
final class ResultsOutlineView: NSOutlineView {
    /// Called with true when the hit should open in the other pane.
    var onActivate: ((Bool) -> Void)?
    var onCopy: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 36, 76:  // Return, Enter
            onActivate?(shift)
        case 126 where option:  // ⌥↑ — previous file
            moveToFile(previous: true)
        case 125 where option:  // ⌥↓ — next file
            moveToFile(previous: false)
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c" {
            onCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌥↑ / ⌥↓ jump between file groups rather than single hits.
    private func moveToFile(previous: Bool) {
        let rows = (0..<numberOfRows).filter { item(atRow: $0) is FileSearchResult }
        guard !rows.isEmpty else { return }
        let current = selectedRow
        let target = previous
            ? rows.last(where: { $0 < current }) ?? rows.last
            : rows.first(where: { $0 > current }) ?? rows.first
        guard let target else { return }
        selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        scrollRowToVisible(target)
    }
}

/// A file group: name, dimmed path, hit count.
final class SearchResultFileRow: NSView {
    init(result: FileSearchResult) {
        super.init(frame: .zero)
        let name = NSTextField(labelWithString: result.url.lastPathComponent)
        name.font = DS.Font.denseEmphasis()
        name.textColor = DS.Color.textPrimary

        let path = NSTextField(labelWithString: result.url.deletingLastPathComponent().path)
        path.font = DS.Font.small()
        path.textColor = DS.Color.textTertiary
        path.lineBreakMode = .byTruncatingHead

        let count = NSTextField(labelWithString: "\(result.hits.count)")
        count.font = DS.Font.statusNumeric()
        count.textColor = DS.Color.textSecondary

        let row = NSStackView(views: [name, path, NSView(), count])
        row.orientation = .horizontal
        row.spacing = DS.Space.s
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityLabel("\(result.url.lastPathComponent), \(result.hits.count) hits")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// A hit: right-aligned line number, then the source line with the match
/// highlighted and its indentation preserved.
final class SearchResultHitRow: NSView {
    init(hit: FileSearchHit, query: String) {
        super.init(frame: .zero)
        let number = NSTextField(labelWithString: "\(hit.lineNumber)")
        number.font = DS.Font.statusNumeric()
        number.textColor = DS.Color.textTertiary
        number.alignment = .right
        number.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let line = NSTextField(labelWithAttributedString: Self.highlighted(hit: hit, query: query))
        line.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [number, line])
        row.orientation = .horizontal
        row.spacing = DS.Space.m
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DS.Space.m),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityLabel("line \(hit.lineNumber), \(hit.lineText.trimmingCharacters(in: .whitespaces))")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The match is highlighted inside the line. Indentation is kept, because
    /// it is often the only clue about where in a file the hit sits.
    private static func highlighted(hit: FileSearchHit, query: String) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: hit.lineText,
            attributes: [.font: DS.Font.mono(11), .foregroundColor: DS.Color.textPrimary])
        let line = hit.lineText as NSString
        // Prefer the range the search itself reported; fall back to the query
        // text when a caller did not supply one.
        var range = hit.rangeInLine
        if range.location == NSNotFound || NSMaxRange(range) > line.length {
            range = query.isEmpty ? NSRange(location: NSNotFound, length: 0)
                                  : line.range(of: query, options: .caseInsensitive)
        }
        if range.location != NSNotFound, NSMaxRange(range) <= line.length {
            text.addAttributes([.backgroundColor: DS.Color.searchMatch], range: range)
        }
        return text
    }
}
