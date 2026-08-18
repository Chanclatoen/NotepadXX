import AppKit
import NotepadXXCore
import NotepadXXEditor

/// The main editing window: tab strip, editor, status bar.
public final class MainWindowController: NSWindowController {
    public private(set) var documents: [TextDocument] = []
    public private(set) var activeIndex: Int = 0

    private var tabBar: TabBarView!
    private var statusBar: StatusBarView!
    private var editorContainer: NSView!
    private var editors: [UUID: EditorViewController] = [:]
    private var untitledCounter = 0
    /// Indentation width used by tab/space conversion commands.
    public var tabWidth: Int = 4
    var installedFindPanel: FindPanelController?
    var installedResultsPanel: SearchResultsPanelController?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "NotepadXX"
        window.setFrameAutosaveName("NotepadXXMainWindow")
        super.init(window: window)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        let content = NSView()

        tabBar = TabBarView()
        tabBar.onSelect = { [weak self] index in self?.activate(index: index) }
        tabBar.onClose = { [weak self] index in self?.close(index: index) }

        editorContainer = NSView()
        statusBar = StatusBarView()

        for subview in [tabBar!, editorContainer!, statusBar!] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: content.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 28),

            editorContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            editorContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            statusBar.topAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
        ])

        window.contentView = content
    }

    // MARK: - Document lifecycle

    public func adopt(documents restored: [TextDocument], activeIndex index: Int) {
        documents = restored
        untitledCounter = restored.filter { $0.isUntitled }.count
        activate(index: index)
        refreshTabs()
    }

    @discardableResult
    public func newDocument() -> TextDocument {
        untitledCounter += 1
        let document = TextDocument()
        document.untitledName = "new \(untitledCounter)"
        documents.append(document)
        activate(index: documents.count - 1)
        refreshTabs()
        return document
    }

    public func editorController(for document: TextDocument) -> EditorViewController {
        if let existing = editors[document.id] { return existing }
        let controller = EditorViewController()
        controller.loadViewIfNeeded()
        controller.load(text: document.text)
        controller.onTextChange = { [weak self, weak document] text in
            guard let document else { return }
            document.text = text
            self?.refreshTabs()
            self?.refreshStatus()
        }
        controller.onSelectionChange = { [weak self] _ in self?.refreshStatus() }
        editors[document.id] = controller
        return controller
    }

    private func activate(index: Int) {
        guard documents.indices.contains(index) else { return }
        activeIndex = index
        let controller = editorController(for: documents[index])

        editorContainer.subviews.forEach { $0.removeFromSuperview() }
        let editorView = controller.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.addSubview(editorView)
        NSLayoutConstraint.activate([
            editorView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            editorView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
        ])
        window?.makeFirstResponder(controller.textView)
        refreshTabs()
        refreshStatus()
    }

    private func close(index: Int) {
        guard documents.indices.contains(index) else { return }
        let document = documents.remove(at: index)
        editors.removeValue(forKey: document.id)
        if documents.isEmpty {
            newDocument()
        } else {
            activate(index: min(index, documents.count - 1))
        }
        refreshTabs()
    }

    /// Refreshes tab titles and the status bar after an external change.
    public func refreshUI() {
        refreshTabs()
        refreshStatus()
    }

    private func refreshTabs() {
        tabBar.configure(
            titles: documents.map { $0.displayName },
            dirtyFlags: documents.map { $0.isDirty },
            selected: activeIndex
        )
        window?.title = documents.indices.contains(activeIndex) ? documents[activeIndex].displayName : "NotepadXX"
    }

    private func refreshStatus() {
        guard documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        let controller = editorController(for: document)
        let caret = controller.caretPosition()
        let selection = controller.selectedRange
        statusBar.update(
            length: (document.text as NSString).length,
            lines: document.text.isEmpty ? 1 : LineEnding.counts(in: document.text).lf + 1,
            selection: selection.length,
            line: caret.line,
            column: caret.column,
            lineEnding: document.lineEnding.displayName,
            encoding: document.encoding.displayName
        )
    }

    /// Focuses an existing tab.
    public func selectTab(at index: Int) { activate(index: index) }

    /// Adds a document as a new tab and focuses it.
    public func appendDocument(_ document: TextDocument) {
        documents.append(document)
        activate(index: documents.count - 1)
        refreshTabs()
    }

    // MARK: - Menu actions

    @objc public func newDocumentAction(_ sender: Any?) { newDocument() }

    @objc public func openDocumentAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let document = try? TextDocument.load(contentsOf: url) else { continue }
            documents.append(document)
        }
        activate(index: documents.count - 1)
        refreshTabs()
    }

    @objc public func saveDocumentAction(_ sender: Any?) {
        guard documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        if document.isUntitled { saveDocumentAsAction(sender); return }
        try? document.save()
        refreshTabs()
    }

    @objc public func saveDocumentAsAction(_ sender: Any?) {
        guard documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.displayName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? document.save(to: url)
        refreshTabs()
    }

    @objc public func saveAllAction(_ sender: Any?) {
        for document in documents where !document.isUntitled && document.isDirty {
            try? document.save()
        }
        refreshTabs()
    }

    @objc public func closeTabAction(_ sender: Any?) { close(index: activeIndex) }

    @objc public func toggleWordWrapAction(_ sender: Any?) {
        guard documents.indices.contains(activeIndex) else { return }
        let controller = editorController(for: documents[activeIndex])
        controller.setWrapLines(!(controller.textView.wrapLines))
    }

    @objc public func goToLineAction(_ sender: Any?) {
        // Placeholder until the Go To dialog lands; keeps the menu item live.
        NSSound.beep()
    }
}
