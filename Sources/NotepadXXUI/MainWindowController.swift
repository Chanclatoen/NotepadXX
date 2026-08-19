import AppKit
import NotepadXXDesign
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

    var tabBar: DocumentTabStrip!
    var statusBar: DSStatusBar!
    private var editorContainer: NSView!
    /// One editor per document *per pane*.
    ///
    /// A view has one superview, so a document opened in both panes needs two
    /// editors — with a single shared one, cloning left the first pane empty.
    /// The design wants exactly this: edits stay in sync between clones, folds
    /// and carets do not.
    struct EditorKey: Hashable {
        let document: UUID
        let pane: Int
    }
    var editors: [EditorKey: EditorViewController] = [:]
    private var untitledCounter = 0
    /// Indentation width used by tab/space conversion commands.
    public var tabWidth: Int = 4
    var installedFindPanel: SearchPanelController?
    var installedGoToPanel: GoToPanelController?
    /// The running Find in Files scan, if there is one.
    var activeFileSearch: SearchCancellationToken?
    var documentSwitcherMonitor: Any?
    var installedRunPanel: RunPanelController?
    var installedRunMacroPanel: RunMacroPanelController?
    var runOutputPanel: RunOutputPanel?
    var searchResultsPanel: SearchResultsPanel?
    var installedColumnEditor: ColumnEditorPanel?
    // View-menu display state, applied to every editor so it behaves like a
    // preference rather than a per-tab quirk.
    var showSpaces = false
    var showTabs = false
    var showLineEndings = false
    var editorFontSize: CGFloat = 12
    var isDistractionFree = false
    var showChangeHistory = true
    var showIndentGuides = true
    var isOverwriteMode = false
    var toolbar: DSToolbar!
    var tabBarHeightConstraint: NSLayoutConstraint?
    var tabBarWidthConstraint: NSLayoutConstraint?
    /// Constraints that differ between the top strip and the side rail.
    var horizontalTabConstraints: [NSLayoutConstraint] = []
    var verticalTabConstraints: [NSLayoutConstraint] = []
    var multiCaretMonitor: Any?
    var searchHistory: SearchHistory?
    var lastSearchOptions = SearchOptions()
    /// Marked ranges per document, for the Mark tab's five styles.
    var markedRanges: [UUID: MarkedRanges] = [:]
    var activeMarkStyle = 0
    var incrementalBar: IncrementalSearchBar?
    var incrementalOrigin = 0
    var syncVerticalScroll = false
    var syncHorizontalScroll = false
    var scrollSyncObservers: [Any] = []
    var isMirroringScroll = false
    var documentSwitcher: DocumentSwitcherPanel?
    /// Document ids, most recently used first.
    var documentMRU: [UUID] = []
    private var incrementalHeightConstraint: NSLayoutConstraint?
    var hiddenPanelIdentifiers: [String] = []
    /// Bookmarked lines, keyed by document id.
    var bookmarks: [UUID: Bookmarks] = [:]
    var tabAttributes: [UUID: TabAttributes] = [:]

    var editorSplit: EvenSplitView!
    var secondaryContainer: NSView!
    private var secondaryActiveIndex = 0
    /// The pane-0 tab being shown, so activating a pane-1 tab leaves it alone.
    private var primaryActiveDocumentID: UUID?
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
    var completionData: CompletionDataStore?
    /// Folded regions per document, keyed by the fold's first line.
    var collapsedFolds: [UUID: Set<Int>] = [:]
    var namedSessions: NamedSessionStore?
    var projectStore: ProjectStore?
    var activeProjectName: String?
    var pluginRegistry: PluginRegistry?
    var pluginHost: PluginHost?
    var pluginRepository: PluginRepository?
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
        installMultiCaretMouseMonitor()
        if let support = try? SessionStore.defaultDirectory() {
            macroStore = try? MacroStore(directory: support)
            runCommandStore = try? RunCommandStore(directory: support)
            preferencesStore = try? PreferencesStore(directory: support)
            themeStore = try? ThemeStore(directory: support)
            pluginRegistry = try? PluginRegistry(directory: support)
            // The bundled starter catalogue ships with the app; users can add
            // their own repository URLs.
            var sources: [URL] = []
            if let bundled = Bundle.main.url(forResource: "plugin-catalogue", withExtension: "json") {
                sources.append(bundled)
            }
            let userCatalogue = support.appendingPathComponent("plugin-sources.json")
            if let data = try? Data(contentsOf: userCatalogue),
               let extra = try? JSONDecoder().decode([String].self, from: data) {
                sources.append(contentsOf: extra.compactMap(URL.init(string:)))
            }
            pluginRepository = PluginRepository(directory: support, sourceURLs: sources)
            namedSessions = try? NamedSessionStore(directory: support)
            projectStore = try? ProjectStore(directory: support)
            completionData = try? CompletionDataStore(directory: support)
            searchHistory = SearchHistory.load(from: support)
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
        let content = AppearanceObservingView()

        toolbar = DSToolbar()
        toolbar.commandTarget = self
        toolbar.configure(groups: ToolbarCatalogue.groups())
        toolbar.bind(to: self)

        tabBar = DocumentTabStrip()
        tabBar.onSelect = { [weak self] index in self?.activate(index: index) }
        tabBar.onClose = { [weak self] index in self?.close(index: index) }
        // The "n / total" button lists every document, so one that has
        // scrolled out of sight is still one click away.
        tabBar.onShowTabList = { [weak self] anchor in self?.showTabListMenu(from: anchor) }
        tabBar.onReorder = { [weak self] from, to in self?.moveTab(from: from, to: to) }
        tabBar.onContextMenu = { [weak self] index, point in
            self?.showTabContextMenu(forTabAt: index, at: point)
        }
        // Wrapped rows are genuine layout: the strip grows and the editor shrinks.
        tabBar.onExtentChanged = { [weak self] height in
            self?.tabBarHeightConstraint?.constant = height
        }

        let host = DockHostView()
        dockHost = host
        installPanels(into: host)

        // The editor area is a split: the second pane appears only when a
        // document is moved or cloned into it.
        editorSplit = EvenSplitView()
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
        statusBar = DSStatusBar()

        for subview in [toolbar!, tabBar!, host as NSView, statusBar!] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }

        let tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: DS.Metric.tabStrip)
        tabBarHeightConstraint = tabBarHeight
        tabBarWidthConstraint = tabBar.widthAnchor.constraint(
            equalToConstant: DocumentTabStrip.railWidth
        )
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Two arrangements. Horizontal and wrapped put the strip above the
        // editor; the rail puts it beside, so these swap rather than stretch.
        horizontalTabConstraints = [
            tabBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBarHeight,
            host.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ]
        verticalTabConstraints = [
            tabBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            tabBarWidthConstraint!,
            host.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ]
        NSLayoutConstraint.activate(horizontalTabConstraints)

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

        content.onAppearanceChange = { [weak self] in self?.appearanceDidChange() }
        installDocumentSwitcherShortcut()
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
        // A new document starts in the format the user chose, rather than in
        // whatever the type's defaults happen to be.
        if let preferences = preferencesStore?.preferences {
            document.encoding = FileEncoding(
                String.Encoding(rawValue: preferences.defaultEncodingRawValue),
                hasBOM: preferences.defaultEncodingHasBOM)
            document.lineEnding = LineEnding(rawValue: preferences.defaultLineEndingRawValue) ?? .lf
            document.languageName = preferences.defaultLanguageName
        }
        tabs.append(EditorTab(document: document))
        activate(index: tabs.count - 1)
        refreshTabs()
        return document
    }

    public func editorController(for document: TextDocument) -> EditorViewController {
        editorController(for: document, inPane: paneOf(document))
    }

    /// The pane a document's tab currently sits in.
    private func paneOf(_ document: TextDocument) -> Int {
        tabs.first { $0.document === document }?.pane ?? 0
    }

    public func editorController(for document: TextDocument, inPane pane: Int) -> EditorViewController {
        let key = EditorKey(document: document.id, pane: pane)
        if let existing = editors[key] { return existing }
        let controller = EditorViewController()
        controller.loadViewIfNeeded()
        if document.languageName == nil { autoDetectLanguage(for: document) }
        controller.setLanguage(document.languageName.flatMap { LanguageRegistry.shared.language(named: $0) })
        controller.load(text: document.text)
        controller.onTextChange = { [weak self, weak document, weak controller] text in
            guard let document else { return }
            document.text = text
            // A clone in the other pane shows the same document, so it has to
            // show the same text.
            self?.syncClones(of: document, from: controller, text: text)
            self?.refreshTabs()
            self?.refreshStatus()
        }
        controller.onSelectionChange = { [weak self] _ in self?.refreshStatus() }
        // Typing is recorded while a macro is being captured. Without this the
        // recorder exists but never sees anything, so playback does nothing.
        controller.onTextInserted = { [weak self] text in
            guard let self, self.macroRecorder.isRecording else { return }
            self.macroRecorder.record(.insertText(text))
        }
        controller.onToggleFold = { [weak self] line in self?.toggleFold(atLine: line) }
        controller.onToggleBookmark = { [weak self] line in self?.toggleBookmark(atLine: line) }
        controller.completionEntries = completionData?.entries(
            forLanguage: document.languageName
        ) ?? []
        // An editor created after focus was last applied would otherwise
        // default to focused, and two panes would both look live.
        controller.isPaneFocused = !isSplit || pane == currentFocusedPane
        editors[key] = controller
        return controller
    }

    /// The pane holding the active tab.
    var currentFocusedPane: Int {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex].pane : 0
    }

    /// Only the focused pane shows a live caret and the current-line tint; the
    /// other is visibly the one that is not being typed into.
    private func applyPaneFocus() {
        guard isSplit else {
            for editor in allEditors { editor.isPaneFocused = true }
            return
        }
        for (key, editor) in editors {
            editor.isPaneFocused = key.pane == currentFocusedPane
        }
    }

    /// Every editor showing this document, across both panes.
    func editorControllers(for document: TextDocument) -> [EditorViewController] {
        (0...1).compactMap { editors[EditorKey(document: document.id, pane: $0)] }
    }

    /// Pushes an edit to the same document's editor in the other pane.
    private func syncClones(of document: TextDocument,
                            from source: EditorViewController?, text: String) {
        for pane in 0...1 {
            let key = EditorKey(document: document.id, pane: pane)
            guard let sibling = editors[key], sibling !== source, sibling.text != text else { continue }
            // Keep the clone's caret where it was; only the text is shared.
            let caret = sibling.selectedRange
            sibling.replaceAll(with: text)
            let length = (text as NSString).length
            sibling.selectedRange = NSRange(location: min(caret.location, length), length: 0)
        }
    }

    private func activate(index: Int) {
        guard documents.indices.contains(index) else { return }
        activeIndex = index
        // Each pane keeps its own active tab. Activating a tab in the other
        // pane must not change what this one is showing.
        if tabs[index].pane == 0 { primaryActiveDocumentID = tabs[index].document.id }
        let primaryDocument = tabs.first { $0.pane == 0 && $0.document.id == primaryActiveDocumentID }?.document
            ?? tabs.first { $0.pane == 0 }?.document
            ?? documents[index]
        primaryActiveDocumentID = primaryDocument.id
        let controller = editorController(for: primaryDocument, inPane: 0)

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
        noteDocumentUsed(documents[index])
        updateScrollSyncObservers()
        refreshTabs()
        refreshStatus()
    }

    private func close(index: Int) {
        guard documents.indices.contains(index) else { return }
        // Notepad++ keeps unsaved buffers by default, so this asks only when
        // the user has said they want to be asked.
        if preferencesStore?.preferences.confirmCloseUnsaved == true, documents[index].isDirty {
            confirmDiscard(of: documents[index]) { [weak self] shouldClose in
                guard shouldClose else { return }
                self?.performClose(index: index)
            }
            return
        }
        performClose(index: index)
    }

    private func performClose(index: Int) {
        guard documents.indices.contains(index) else { return }
        let document = tabs.remove(at: index).document
        // Drop only the editors for panes this document no longer occupies;
        // discarding the other pane's would blank it.
        let remainingPanes = Set(tabs.filter { $0.document === document }.map(\.pane))
        for pane in 0...1 where !remainingPanes.contains(pane) {
            editors.removeValue(forKey: EditorKey(document: document.id, pane: pane))
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
            // collapsing the first to just its gutter. The even split is asked
            // for rather than applied here: at this moment the split has not
            // been laid out yet, so dividing by its current width would divide
            // by the wrong number.
            editorSplit.balanceOnNextLayout()
        } else if !shouldShow && secondaryContainer.superview != nil {
            editorSplit.removeArrangedSubview(secondaryContainer)
            secondaryContainer.removeFromSuperview()
        }
        guard shouldShow else { return }

        secondaryActiveIndex = min(secondaryActiveIndex, secondary.count - 1)
        let document = secondary[secondaryActiveIndex].element.document
        let controller = editorController(for: document, inPane: 1)

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
        let qualifiers = Self.qualifiers(for: tabs.map(\.document))
        let focusedPane = currentFocusedPane
        // Each pane shows its own active tab.
        let activeInPane: [Int: ObjectIdentifier] = [
            0: tabs.first { $0.pane == 0 && $0.document.id == primaryActiveDocumentID }
                .map { ObjectIdentifier($0.document) }
                ?? tabs.first { $0.pane == 0 }.map { ObjectIdentifier($0.document) },
            1: tabs(inPane: 1).indices.contains(secondaryActiveIndex)
                ? ObjectIdentifier(tabs(inPane: 1)[secondaryActiveIndex].document)
                : tabs.first { $0.pane == 1 }.map { ObjectIdentifier($0.document) },
        ].compactMapValues { $0 }
        // A document open in both panes: the copy in the other pane is a clone.
        let clonedDocuments = Set(
            Dictionary(grouping: tabs, by: { ObjectIdentifier($0.document) })
                .filter { $0.value.count > 1 }.keys)
        tabBar.configure(items: tabs.map { tab in
            let attributes = self.attributes(for: tab.document)
            return DSTabItem(
                title: TabTitle.shortened(tab.document.displayName),
                qualifier: clonedDocuments.contains(ObjectIdentifier(tab.document)) && tab.pane == 1
                    ? "clone"
                    : qualifiers[ObjectIdentifier(tab.document)],
                isActive: activeInPane[tab.pane] == ObjectIdentifier(tab.document),
                isInFocusedPane: tab.pane == focusedPane,
                isDirty: tab.document.isDirty,
                isPinned: attributes.isPinned,
                isReadOnly: tab.document.isReadOnly,
                showsCloseButton: self.preferencesStore?.preferences.tabCloseButtonOnEachTab ?? true,
                accent: self.colour(for: attributes),
                inSecondPane: tab.pane == 1,
                toolTip: tab.document.fileURL?.path ?? tab.document.displayName
            )
        })
        if tabBar.tabLayout != .vertical {
            tabBarHeightConstraint?.constant = tabBar.requiredExtent(
                forWidth: window?.frame.width ?? DS.Metric.windowDefault.width
            )
        }
        rebuildPanes()
        applyPaneFocus()
        window?.title = documents.indices.contains(activeIndex) ? documents[activeIndex].displayName : "NotepadXX"
    }

    /// The folder shown beside a tab's name, for the documents whose names
    /// collide. Only those: qualifying every tab would add noise to the ones
    /// that were never ambiguous.
    static func qualifiers(for documents: [TextDocument]) -> [ObjectIdentifier: String] {
        var byName: [String: [TextDocument]] = [:]
        for document in documents {
            byName[document.displayName, default: []].append(document)
        }
        var result: [ObjectIdentifier: String] = [:]
        for (_, colliding) in byName where colliding.count > 1 {
            for document in colliding {
                guard let url = document.fileURL else { continue }
                result[ObjectIdentifier(document)] = url.deletingLastPathComponent().lastPathComponent
            }
        }
        return result
    }

    private func refreshStatus() {
        guard documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        let controller = editorController(for: document)
        let caret = controller.caretPosition()
        // With several carets the totals span every selection, not just the
        // first, or the status bar under-reports what a keystroke will affect.
        let ranges = controller.selectedRanges
        let content = document.text as NSString
        let totalSelected = ranges.reduce(0) { $0 + $1.length }
        let selectedText = ranges
            .filter { $0.length > 0 && NSMaxRange($0) <= content.length }
            .map { content.substring(with: $0) }
            .joined(separator: "\n")

        statusBar.update(DSStatusBar.Model(
            documentType: document.languageName ?? "Normal text file",
            length: content.length,
            lines: document.text.isEmpty ? 1 : LineEnding.counts(in: document.text).lf + 1,
            caretLine: caret.line,
            caretColumn: caret.column,
            selectionCharacters: totalSelected,
            selectionLines: selectedText.isEmpty ? 0 : LineEnding.counts(in: selectedText).lf + 1,
            caretCount: ranges.count,
            lineEnding: document.lineEnding.displayName,
            lineEndingShort: document.lineEnding.shortName,
            encoding: document.encoding.displayName,
            isOverwrite: isOverwriteMode,
            paneNote: paneNote()
        ))
        refreshToolbarState()
    }

    /// "pane 1 of 2 · scroll linked" while a split is open, so the caret's
    /// pane is never in doubt. Empty when there is only one pane.
    private func paneNote() -> String {
        guard isSplit, tabs.indices.contains(activeIndex) else { return "" }
        let pane = tabs[activeIndex].pane + 1
        let linked = syncVerticalScroll ? " · scroll linked" : ""
        return "pane \(pane) of 2\(linked)"
    }

    /// Focuses an existing tab.
    public func selectTab(at index: Int) { activate(index: index) }

    /// Adds a document as a new tab and focuses it.
    public func appendDocument(_ document: TextDocument) {
        tabs.append(EditorTab(document: document, pane: document.paneIndex))
        activate(index: tabs.count - 1)
        refreshTabs()
    }

    /// Opens a document in the pane beside the current one, as a new tab.
    /// Used to show the on-disk version of a file next to the edited one.
    func openBeside(_ document: TextDocument) {
        // Put it straight into the other pane. Toggling the split would move
        // the tab as well, and the two moves would cancel out.
        let currentPane = tabs.indices.contains(activeIndex) ? tabs[activeIndex].pane : 0
        tabs.append(EditorTab(document: document, pane: currentPane == 0 ? 1 : 0))
        activate(index: tabs.count - 1)
        refreshTabs()
    }

    /// Adds a second tab for an already-open document, in the other pane.
    func appendClone(of document: TextDocument, inPane pane: Int) {
        tabs.append(EditorTab(document: document, pane: pane))
        refreshTabs()
    }

    /// Shows the incremental search strip above the status bar.
    func showIncrementalBar() {
        guard let bar = incrementalBar, let content = window?.contentView else { return }
        if bar.superview == nil {
            bar.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(bar)
            let height = bar.heightAnchor.constraint(equalToConstant: IncrementalSearchBar.height)
            incrementalHeightConstraint = height
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
                height,
            ])
        }
        bar.isHidden = false
        incrementalHeightConstraint?.constant = 28
        bar.focus()
    }

    func hideIncrementalBar() {
        incrementalBar?.isHidden = true
        incrementalHeightConstraint?.constant = 0
        if let editor = currentEditor { window?.makeFirstResponder(editor.textView) }
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

    /// Applies the constraint set for the current tab layout.
    func applyTabLayoutConstraints() {
        let vertical = tabBar.tabLayout == .vertical
        NSLayoutConstraint.deactivate(vertical ? horizontalTabConstraints : verticalTabConstraints)
        NSLayoutConstraint.activate(vertical ? verticalTabConstraints : horizontalTabConstraints)
        if !vertical {
            tabBarHeightConstraint?.constant = tabBar.requiredExtent(
                forWidth: window?.frame.width ?? DS.Metric.windowDefault.width
            )
        }
        tabBar.needsLayout = true
        window?.contentView?.needsLayout = true
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
        // A folded region is physically absent from the buffer, so restore
        // every fold before writing or the file would lose those lines.
        unfoldAll()
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
            for pane in 0...1 {
                editors[EditorKey(document: document.id, pane: pane)]?.documentDidSave()
            }
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

/// The window's content view, which reports appearance changes so a
/// system-following theme can be re-applied.
final class AppearanceObservingView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// A split view that can be asked to divide its panes evenly once it knows how
/// wide it is.
///
/// Setting the divider position straight after adding a pane divides by the
/// width the split had *before* layout, which left one pane a sliver however
/// large the window was.
public final class EvenSplitView: NSSplitView {
    private var needsBalance = false

    public func balanceOnNextLayout() {
        needsBalance = true
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        guard needsBalance, arrangedSubviews.count > 1, bounds.width > 1 else { return }
        needsBalance = false
        setPosition(bounds.width / 2, ofDividerAt: 0)
    }
}
