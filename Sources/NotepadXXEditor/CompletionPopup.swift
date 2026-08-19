import AppKit
import NotepadXXDesign
import NotepadXXCore

/// The autocomplete list that appears as you type, plus the call tip.
///
/// A borderless child window rather than a view inside the editor, so it can
/// overhang the editor's bounds near the right or bottom edge the way every
/// other editor's completion list does.
@MainActor
public final class CompletionPopup: NSObject {
    public private(set) var isVisible = false
    /// Called with the chosen item's text.
    public var onCommit: ((String) -> Void)?

    private var window: NSWindow?
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let tipField = NSTextField(labelWithString: "")
    private var items: [CompletionItem] = []
    private weak var host: NSView?
    /// Claims arrow keys, Return, Tab and Escape while the list is up.
    ///
    /// A local monitor rather than a TextView subclass: keyDown is not open in
    /// the engine's text view, and the list is a child window that never takes
    /// focus, so events would otherwise go straight to the editor and Return
    /// would insert a newline instead of accepting a suggestion.
    private var keyMonitor: Any?

    public override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.width = 320
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .small
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(commitSelection)
        tableView.backgroundColor = .controlBackgroundColor

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        tipField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        tipField.textColor = .secondaryLabelColor
        tipField.lineBreakMode = .byTruncatingTail
    }

    public var selectedItem: CompletionItem? {
        items.indices.contains(tableView.selectedRow) ? items[tableView.selectedRow] : nil
    }

    /// Shows the list anchored below the caret.
    public func show(items: [CompletionItem], below caretRect: NSRect, in view: NSView) {
        guard !items.isEmpty else { hide(); return }
        self.items = items
        self.host = view

        let rowHeight: CGFloat = Self.rowHeight
        let visibleRows = min(items.count, 10)
        let tipHeight: CGFloat = items.first?.detail == nil ? 0 : 18
        let size = NSSize(width: 340, height: CGFloat(visibleRows) * rowHeight + 8 + tipHeight)

        let panel = window ?? makeWindow()
        window = panel
        layout(in: panel, size: size, showTip: tipHeight > 0)

        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        updateTip()

        // Position under the caret, in screen coordinates.
        guard let screenRect = view.window?.convertToScreen(view.convert(caretRect, to: nil)) else { return }
        var origin = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height - 2)
        // Flip above the caret when there is no room below.
        if let screen = view.window?.screen, origin.y < screen.visibleFrame.minY {
            origin.y = screenRect.maxY + 2
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if !isVisible {
            view.window?.addChildWindow(panel, ordered: .above)
            isVisible = true
            installKeyMonitor()
        }
    }

    public func hide() {
        guard isVisible, let window else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        isVisible = false
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch event.keyCode {
            case 125: self.moveSelection(by: 1); return nil      // down
            case 126: self.moveSelection(by: -1); return nil     // up
            case 36, 48: self.commitSelection(); return nil      // return, tab
            case 53: self.hide(); return nil                     // escape
            default: return event
            }
        }
    }

    /// Arrow-key navigation while the list is up.
    public func moveSelection(by delta: Int) {
        guard isVisible, !items.isEmpty else { return }
        let next = min(max(0, tableView.selectedRow + delta), items.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        updateTip()
    }

    @objc public func commitSelection() {
        guard let item = selectedItem else { return }
        hide()
        onCommit?(item.text)
    }

    private func updateTip() {
        tipField.stringValue = selectedItem?.detail ?? ""
    }

    private func makeWindow() -> NSWindow {
        let panel = NSWindow(contentRect: .zero, styleMask: [.borderless],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        // The popup must never steal focus, or typing would stop reaching the
        // editor the moment suggestions appeared.
        panel.ignoresMouseEvents = false
        return panel
    }

    private func layout(in panel: NSWindow, size: NSSize, showTip: Bool) {
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = DS.Color.panel.cgColor
        content.layer?.cornerRadius = 5
        content.layer?.borderWidth = 1
        content.layer?.borderColor = DS.Color.controlBorder.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        tipField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)
        content.addSubview(tipField)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -4),
            tipField.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 2),
            tipField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            tipField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            tipField.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
            tipField.heightAnchor.constraint(equalToConstant: showTip ? 14 : 0),
        ])
        panel.contentView = content
    }
}

extension CompletionPopup: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row]
        // The design's row: a kind letter, a mono label, and the type
        // right-aligned so the eye can scan one edge.
        let kind = NSTextField(labelWithString: Self.kindLetter(for: item.kind))
        kind.font = DS.Font.smallEmphasis()
        kind.textColor = DS.Color.textTertiary
        kind.alignment = .center
        kind.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let label = NSTextField(labelWithString: item.text)
        label.font = DS.Font.mono(11)
        label.textColor = DS.Color.textPrimary
        label.lineBreakMode = .byTruncatingTail

        let type = NSTextField(labelWithString: item.detail ?? "")
        type.font = DS.Font.small()
        type.textColor = DS.Color.textTertiary
        type.alignment = .right
        type.lineBreakMode = .byTruncatingHead

        let row = NSStackView(views: [kind, label, NSView(), type])
        row.orientation = .horizontal
        row.spacing = DS.Space.s
        row.setAccessibilityLabel("\(item.text), \(Self.kindName(for: item.kind))")
        return row
    }

    static let rowHeight: CGFloat = 20

    private static func kindLetter(for kind: CompletionItem.Kind) -> String {
        switch kind {
        case .keyword: return "K"
        case .function: return "F"
        case .path: return "/"
        case .word: return "W"
        }
    }

    private static func kindName(for kind: CompletionItem.Kind) -> String {
        switch kind {
        case .keyword: return "keyword"
        case .function: return "function"
        case .path: return "path"
        case .word: return "word in this document"
        }
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateTip()
    }
}
