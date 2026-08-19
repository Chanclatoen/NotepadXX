import AppKit
import NotepadXXEditor
import NotepadXXCore

/// Notepad++'s Synchronize Vertical / Horizontal Scrolling.
///
/// Both panes scroll together, which is what makes a side-by-side comparison
/// useful. Offsets are mirrored rather than proportions, so two files that
/// differ in length stay aligned line-for-line at the top.
extension MainWindowController {

    @objc public func toggleSyncVerticalScrollAction(_ sender: Any?) {
        syncVerticalScroll.toggle()
        updateScrollSyncObservers()
    }

    @objc public func toggleSyncHorizontalScrollAction(_ sender: Any?) {
        syncHorizontalScroll.toggle()
        updateScrollSyncObservers()
    }

    func updateScrollSyncObservers() {
        for object in scrollSyncObservers {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: object
            )
        }
        scrollSyncObservers = []
        guard syncVerticalScroll || syncHorizontalScroll, isSplit else { return }

        // Target/selector rather than a closure observer: capturing the editor
        // in a nonisolated closure and using it on the main actor is a data
        // race under Swift 6. An @objc method on this main-actor class avoids
        // the capture entirely.
        for editor in visiblePaneEditors {
            let clip = editor.scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(paneDidScroll(_:)),
                name: NSView.boundsDidChangeNotification, object: clip
            )
            scrollSyncObservers.append(clip)
        }
    }

    /// A pane scrolled; mirror it into the other one.
    @objc func paneDidScroll(_ notification: Notification) {
        guard let clip = notification.object as? NSClipView,
              let source = visiblePaneEditors.first(where: { $0.scrollView.contentView === clip })
        else { return }
        mirrorScroll(from: source)
    }

    /// The editor showing in each pane, primary first.
    var visiblePaneEditors: [EditorViewController] {
        var found: [EditorViewController] = []
        if let primary = currentEditor { found.append(primary) }
        if let secondary = tabs(inPane: 1).first.flatMap({ editors[$0.document.id] }) {
            found.append(secondary)
        }
        return found
    }

    private func mirrorScroll(from source: EditorViewController) {
        // Reentrancy guard: moving the other pane fires its own notification.
        guard !isMirroringScroll else { return }
        isMirroringScroll = true
        defer { isMirroringScroll = false }

        let origin = source.scrollView.contentView.bounds.origin
        for editor in visiblePaneEditors where editor !== source {
            var target = editor.scrollView.contentView.bounds.origin
            if syncVerticalScroll { target.y = origin.y }
            if syncHorizontalScroll { target.x = origin.x }
            editor.scrollView.contentView.scroll(to: target)
            editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
        }
    }
}

/// Ctrl+Tab document switcher: an MRU list, like Notepad++'s.
@MainActor
public final class DocumentSwitcherPanel: NSWindowController {
    private let tableView = NSTableView()
    private var entries: [(title: String, subtitle: String)] = []
    public var onChoose: ((Int) -> Void)?

    public init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                             styleMask: [.titled, .utilityWindow],
                             backing: .buffered, defer: false)
        window.title = "Documents"
        super.init(window: window)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("doc"))
        column.width = 400
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(choose)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        window.contentView = scroll
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func present(entries: [(title: String, subtitle: String)], selecting index: Int) {
        self.entries = entries
        tableView.reloadData()
        if entries.indices.contains(index) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        // Wraps, so repeated Ctrl+Tab cycles rather than stopping at the end.
        let next = (tableView.selectedRow + delta + entries.count) % entries.count
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc public func choose() {
        let row = tableView.selectedRow
        window?.close()
        guard entries.indices.contains(row) else { return }
        onChoose?(row)
    }
}

extension DocumentSwitcherPanel: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        let subtitle = NSTextField(labelWithString: entry.subtitle)
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }
}

extension MainWindowController {
    /// Documents in most-recently-used order, which is what makes Ctrl+Tab
    /// useful: the previous document is always one press away.
    var mruOrder: [Int] {
        let known = documentMRU.compactMap { id in tabs.firstIndex { $0.document.id == id } }
        let rest = tabs.indices.filter { !known.contains($0) }
        return known + rest
    }

    /// ⌃⇥ walks the recency order, as it does on the rest of the system.
    func installDocumentSwitcherShortcut() {
        guard documentSwitcherMonitor == nil else { return }
        documentSwitcherMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window,
                  event.keyCode == 48,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control else {
                return event
            }
            self.showDocumentSwitcherAction(nil)
            return nil
        }
    }

    @objc public func showDocumentSwitcherAction(_ sender: Any?) {
        guard tabs.count > 1 else { NSSound.beep(); return }
        if documentSwitcher == nil {
            let panel = DocumentSwitcherPanel()
            panel.onChoose = { [weak self] row in
                guard let self else { return }
                let order = self.mruOrder
                guard order.indices.contains(row) else { return }
                self.selectTab(at: order[row])
            }
            documentSwitcher = panel
        }
        let order = mruOrder
        let entries = order.map { index -> (String, String) in
            let document = tabs[index].document
            return (document.displayName, document.fileURL?.path ?? "unsaved")
        }
        // Preselect the previous document, not the current one.
        documentSwitcher?.present(entries: entries, selecting: min(1, entries.count - 1))
    }

    /// Records the active document as most recent.
    func noteDocumentUsed(_ document: TextDocument) {
        documentMRU.removeAll { $0 == document.id }
        documentMRU.insert(document.id, at: 0)
    }
}
