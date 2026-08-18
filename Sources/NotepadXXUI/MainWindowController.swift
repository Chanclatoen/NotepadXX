import AppKit
import NotepadXXCore
import NotepadXXEditor

/// The main editing window: tab strip, editor, status bar.
public final class MainWindowController: NSWindowController {
    public struct EditorTab {
        public let document: TextDocument
        public var pane: Int
        public init(document: TextDocument, pane: Int = 0) {
            self.document = document
            self.pane = pane
        }
    }

    public private(set) var tabs: [EditorTab] = []
    public var documents: [TextDocument] { tabs.map(\.document) }
    public private(set) var activeIndex: Int = 0

    var tabBar: TabBarView!
    var statusBar: StatusBarView!
    private var editorContainer: NSView!
    var editors: [UUID: EditorViewController] = [:]
    private var untitledCounter = 0
    /// Indentation width used by tab/space conversion commands.
    public var tabWidth: Int = 4
    var installedFindPanel: FindPanelController?
    var installedResultsPanel: SearchResultsPanelController?
    var installedColumnEditor: ColumnEditorPanel?
    // View-menu display state, applied to every editor so it behaves like a
    // preference rather than a per-tab quirk.
    var showSpaces = false
    var showTabs = false
    var showLineEndings = false
    var editorFontSize: CGFloat = 12
    var isDistractionFree = false
    var showChangeHistory = true
    var tabBarHeightConstraint: NSLayoutConstraint?
    var hiddenPanelIdentifiers: [String] = []
    /// Bookmarked lines, keyed by document id.
    var bookmarks: [UUID: Bookmarks] = [:]
    var tabAttributes: [UUID: TabAttributes] = [:]

    var editorSplit: NSSplitView!
    var secondaryContainer: NSView!
    private var secondaryActiveIndex = 0
    var dockHost: DockHostView?
    var functionListPanel: FunctionListPanel?
    var folderWorkspacePanel: FolderWorkspacePanel?
    var documentMapPanel: DocumentMapPanel?
    var projectPanel: ProjectPanel?
    var preferencesStore: PreferencesStore?
    var themeStore: ThemeStore?
    var shortcutMap: ShortcutMap?
    var preferencesWindow: PreferencesWindowController?
    var shortcutWindow: ShortcutMapperWindowController?
    var recentFiles: RecentFiles?
    var namedSessions: NamedSessionStore?
    var projectStore: ProjectStore?
    var activeProjectName: String?
    var pluginRegistry: PluginRegistry?
    var pluginHost: PluginHost?
    var pluginsAdminWindow: PluginsAdminWindowController?
    var udlEditorWindow: UDLEditorWindowController?
    let macroRecorder = MacroRecorder()
    var lastRecordedSteps: [MacroStep] = []
    var macroStore: MacroStore?
    var runCommandStore: RunCommandStore?

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
        if let support = try? SessionStore.defaultDirectory() {
            macroStore = try? MacroStore(directory: support)
            runCommandStore = try? RunCommandStore(directory: support)
            preferencesStore = try? PreferencesStore(directory: support)
            themeStore = try? ThemeStore(directory: support)
            pluginRegistry = try? PluginRegistry(directory: support)
            namedSessions = try? NamedSessionStore(directory: support)
            projectStore = try? ProjectStore(directory: support)
            recentFiles = RecentFiles(
                directory: support,
                limit: preferencesStore?.preferences.recentFilesLimit ?? 15
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        let content = NSView()

        tabBar = TabBarView()
        tabBar.onSelect = { [weak self] index in self?.activate(index: index) }
        tabBar.onClose = { [weak self] index in self?.close(index: index) }
        tabBar.onReorder = { [weak self] from, to in self?.moveTab(from: from, to: to) }
        tabBar.onContextMenu = { [weak self] index, point in
            self?.showTabContextMenu(forTabAt: index, at: point)
        }

        let host = DockHostView()
        dockHost = host
        installPanels(into: host)

        // The editor area is a split: the second pane appears only when a
        // document is moved or cloned into it.
        editorSplit = NSSplitView()
        editorSplit.isVertical = true
        editorSplit.dividerStyle = .thin
        editorContainer = NSView()
        secondaryContainer = NSView()
        editorSplit.addArrangedSubview(editorContainer)
        editorContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        secondaryContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        editorSplit.translatesAutoresizingMaskIntoConstraints = false
        host.editorContainer.addSubview(editorSplit)
        NSLayoutConstraint.activate([
            editorSplit.topAnchor.constraint(equalTo: host.editorContainer.topAnchor),
            editorSplit.leadingAnchor.constraint(equalTo: host.editorContainer.leadingAnchor),
            editorSplit.trailingAnchor.constraint(equalTo: host.editorContainer.trailingAnchor),
            editorSplit.bottomAnchor.constraint(equalTo: host.editorContainer.bottomAnchor),
        ])
        statusBar = StatusBarView()

        for subview in [tabBar!, host as NSView, statusBar!] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }

        let tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: 28)
        tabBarHeightConstraint = tabBarHeight
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: content.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBarHeight,

            host.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            statusBar.topAnchor.constraint(equalTo: host.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
        ])

        // Dropping files onto the window opens them.
        let dropView = FileDropView()
        dropView.onDrop = { [weak self] urls in
            for url in urls { self?.openOrFocus(url: url) }
        }
        dropView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(dropView, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            dropView.topAnchor.constraint(equalTo: content.topAnchor),
            dropView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            dropView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        window.contentView = content
    }

    // MARK: - Document lifecycle

    public func adopt(documents restored: [TextDocument], activeIndex index: Int) {
        tabs = restored.map { EditorTab(document: $0, pane: $0.paneIndex) }
        untitledCounter = restored.filter { $0.isUntitled }.count
        activate(index: index)
        refreshTabs()
    }

    @discardableResult
    public func newDocument() -> TextDocument {
        untitledCounter += 1
        let document = TextDocument()
        document.untitledName = "new \(untitledCounter)"
        tabs.append(EditorTab(document: document))
        activate(index: tabs.count - 1)
        refreshTabs()
        return document
    }

    public func editorController(for document: TextDocument) -> EditorViewController {
        if let existing = editors[document.id] { return existing }
        let controller = EditorViewController()
        controller.loadViewIfNeeded()
        if document.languageName == nil { autoDetectLanguage(for: document) }
        controller.setLanguage(document.languageName.flatMap { LanguageRegistry.shared.language(named: $0) })
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
        let document = tabs.remove(at: index).document
        // Keep the editor alive if the same document is still open in the other
        // pane; discarding it would blank that pane.
        if !tabs.contains(where: { $0.document === document }) {
            editors.removeValue(forKey: document.id)
        }
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
        refreshPanels()
    }

    /// Shows or hides the second pane and installs its editor.
    func rebuildPanes() {
        let secondary = tabs.enumerated().filter { $0.element.pane == 1 }
        let shouldShow = !secondary.isEmpty

        if shouldShow && secondaryContainer.superview == nil {
            editorSplit.addArrangedSubview(secondaryContainer)
            // NSSplitView otherwise hands almost all the width to the new pane,
            // collapsing the first to just its gutter. Split evenly once laid out.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.editorSplit.arrangedSubviews.count > 1 else { return }
                self.editorSplit.setPosition(self.editorSplit.bounds.width / 2, ofDividerAt: 0)
            }
        } else if !shouldShow && secondaryContainer.superview != nil {
            editorSplit.removeArrangedSubview(secondaryContainer)
            secondaryContainer.removeFromSuperview()
        }
        guard shouldShow else { return }

        secondaryActiveIndex = min(secondaryActiveIndex, secondary.count - 1)
        let document = secondary[secondaryActiveIndex].element.document
        let controller = editorController(for: document)

        secondaryContainer.subviews.forEach { $0.removeFromSuperview() }
        let editorView = controller.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        secondaryContainer.addSubview(editorView)
        NSLayoutConstraint.activate([
            editorView.topAnchor.constraint(equalTo: secondaryContainer.topAnchor),
            editorView.leadingAnchor.constraint(equalTo: secondaryContainer.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: secondaryContainer.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: secondaryContainer.bottomAnchor),
        ])
    }

    private func refreshTabs() {
        tabBar.configure(
            titles: tabs.map { $0.document.displayName + ($0.pane == 1 ? " ⧉" : "") },
            dirtyFlags: tabs.map { $0.document.isDirty },
            selected: activeIndex,
            pinned: tabs.map { attributes(for: $0.document).isPinned },
            colours: tabs.map { colour(for: attributes(for: $0.document)) }
        )
        rebuildPanes()
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
        tabs.append(EditorTab(document: document, pane: document.paneIndex))
        activate(index: tabs.count - 1)
        refreshTabs()
    }

    /// Adds a second tab for an already-open document, in the other pane.
    func appendClone(of document: TextDocument, inPane pane: Int) {
        tabs.append(EditorTab(document: document, pane: pane))
        refreshTabs()
    }

    /// Every editor that currently exists, including the second pane's.
    var allEditors: [EditorViewController] { Array(editors.values) }

    var activeDocument: TextDocument? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex].document : nil
    }

    func visiblePanelIdentifiers() -> [String] {
        ["functionList", "folderWorkspace", "clipboardHistory", "characterPanel", "documentMap", "projectPanel"]
            .filter { dockHost?.isVisible($0) == true }
    }

    /// Sets the tab list without re-activating, for reordering.
    func setTabs(_ newTabs: [EditorTab]) {
        tabs = newTabs
        activeIndex = min(activeIndex, max(0, tabs.count - 1))
        refreshTabs()
    }

    /// Replaces the tab list wholesale, clamping the active index.
    func replaceTabs(_ newTabs: [EditorTab]) {
        tabs = newTabs
        activeIndex = min(activeIndex, max(0, tabs.count - 1))
        if tabs.isEmpty { newDocument() } else { activate(index: activeIndex) }
        refreshTabs()
    }

    /// Reassigns the pane of the tab at `index`.
    func setPane(_ pane: Int, forTabAt index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].pane = pane
        tabs[index].document.paneIndex = pane
        refreshTabs()
    }

    /// The tab already showing `url`, if any. Paths are resolved through
    /// symlinks so /var and /private/var forms of the same file match.
    public func indexOfDocument(for url: URL) -> Int? {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        return documents.firstIndex {
            $0.fileURL?.resolvingSymlinksInPath().standardizedFileURL == target
        }
    }

    /// Focuses the tab for `url`, opening it only if it is not already open.
    /// Opening the same file twice would give two tabs editing one file, where
    /// saving one silently discards the other's changes.
    @discardableResult
    public func openOrFocus(url: URL) -> Bool {
        if let index = indexOfDocument(for: url) {
            selectTab(at: index)
            return true
        }
        guard let document = try? TextDocument.load(contentsOf: url) else { return false }
        appendDocument(document)
        noteRecentlyOpened(url)
        return true
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
            tabs.append(EditorTab(document: document))
        }
        activate(index: tabs.count - 1)
        refreshTabs()
    }

    @objc public func saveDocumentAction(_ sender: Any?) {
        guard documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        if document.isUntitled { saveDocumentAsAction(sender); return }
        try? document.save()
        currentEditor?.documentDidSave()
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
            editors[document.id]?.documentDidSave()
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
