import AppKit
import NotepadXXCore

/// The Search Results panel. Rows are clickable and jump to the hit, which is
/// the part of Notepad++'s find-in-files workflow people actually rely on.
public final class SearchResultsPanelController: NSWindowController {
    /// Called with the file and 1-based line number of the clicked hit.
    public var onSelectHit: ((URL, Int) -> Void)?

    private let outlineView = NSOutlineView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private var results: [FileSearchResult] = []

    public init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        window.title = "Search results"
        super.init(window: window)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hit"))
        column.title = "Result"
        column.width = 660
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowSizeStyle = .small
        outlineView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        outlineView.target = self
        outlineView.doubleAction = #selector(rowActivated)

        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(summaryLabel)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            summaryLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }

    public func present(results: [FileSearchResult], summary: String) {
        self.results = results
        summaryLabel.stringValue = summary
        outlineView.reloadData()
        // Files expanded by default so hits are visible without a click.
        for result in results { outlineView.expandItem(result) }
        showWindow(nil)
    }

    @objc private func rowActivated() {
        let row = outlineView.clickedRow
        guard row >= 0, let hit = outlineView.item(atRow: row) as? FileSearchHit else { return }
        onSelectHit?(hit.url, hit.lineNumber)
    }
}

extension SearchResultsPanelController: NSOutlineViewDataSource {
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

extension SearchResultsPanelController: NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let text: String
        if let result = item as? FileSearchResult {
            text = "\(result.url.path)  (\(result.hits.count))"
        } else if let hit = item as? FileSearchHit {
            text = "  Line \(hit.lineNumber): \(hit.lineText)"
        } else {
            text = ""
        }
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
