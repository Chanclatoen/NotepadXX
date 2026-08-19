import AppKit
import NotepadXXCore
import NotepadXXDesign

/// The Preferences window.
///
/// Eleven pages in one 820 × 600 window, no tabs inside tabs. Each page is a
/// short stack of named groups whose labels align on one column, so the eye
/// scans a single edge. Settings are described as data — a label plus a keypath
/// into `Preferences` — and both the controls and the search index are built
/// from that description, so a setting cannot appear in one and not the other.
///
/// There is no OK button: every control commits on change and the open
/// documents repaint live.
@MainActor
public final class PreferencesWindowController: NSWindowController {

    public enum Control {
        case toggle(String, WritableKeyPath<Preferences, Bool>)
        /// Several related switches on one row: a short label in the label
        /// column, then a checkbox per option carrying its own text. This is
        /// what keeps the label column narrow enough to read down.
        case toggles(String, [(String, WritableKeyPath<Preferences, Bool>)])
        case number(String, WritableKeyPath<Preferences, Int>, range: ClosedRange<Int>)
        case decimal(String, WritableKeyPath<Preferences, Double>, range: ClosedRange<Double>)
        case text(String, WritableKeyPath<Preferences, String>)
        case optionalText(String, WritableKeyPath<Preferences, String?>)
        case choice(String, WritableKeyPath<Preferences, String>, options: [String])
        /// A text encoding, stored as `String.Encoding`'s raw value.
        case encoding(String, WritableKeyPath<Preferences, UInt>)

        /// Every preference this control writes. Two controls writing the same
        /// key would mean one of them silently disagrees with the other.
        public var boundKeyPaths: [AnyKeyPath] {
            switch self {
            case .toggle(_, let keyPath): return [keyPath]
            case .toggles(_, let options): return options.map { $0.1 }
            case .number(_, let keyPath, _): return [keyPath]
            case .decimal(_, let keyPath, _): return [keyPath]
            case .text(_, let keyPath): return [keyPath]
            case .optionalText(_, let keyPath): return [keyPath]
            case .choice(_, let keyPath, _): return [keyPath]
            case .encoding(_, let keyPath): return [keyPath]
            }
        }

        /// The label shown beside the control.
        public var label: String {
            switch self {
            case .toggle(let label, _), .text(let label, _): return label
            case .toggles(let label, _): return label
            case .optionalText(let label, _): return label
            case .number(let label, _, _), .decimal(let label, _, _): return label
            case .choice(let label, _, _): return label
            case .encoding(let label, _): return label
            }
        }
    }

    /// A named block of controls inside a page.
    public struct Group {
        public let name: String
        public let controls: [Control]

        public init(_ name: String, _ controls: [Control]) {
            self.name = name
            self.controls = controls
        }
    }

    public struct Page {
        public let title: String
        public let symbol: String
        public let summary: String
        public let groups: [Group]
        /// Appearance, Symbols and Indentation carry a preview because their
        /// effect is visual and immediate. A preview anywhere else is theatre.
        public let showsPreview: Bool

        public init(title: String, symbol: String, summary: String,
                    groups: [Group], showsPreview: Bool = false) {
            self.title = title
            self.symbol = symbol
            self.summary = summary
            self.groups = groups
            self.showsPreview = showsPreview
        }

        public var controls: [Control] { groups.flatMap(\.controls) }
    }

    private let store: PreferencesStore
    private let themeStore: ThemeStore?
    private let onChange: (Preferences) -> Void

    private let pageList = NSTableView()
    private let searchField = NSSearchField()
    private let detailContainer = NSView()
    private let pageTitleLabel = NSTextField(labelWithString: "")
    private let pageSummaryLabel = NSTextField(labelWithString: "")
    private let resetPageButton = NSButton()
    private var pages: [Page] = []
    private var trampolines: [ActionTrampoline] = []
    private var keyMonitor: Any?

    /// Non-empty while the search field filters the list.
    private var query = "" { didSet { applyQuery() } }
    /// Pages matching the query, with their hit counts.
    private var matches: [String: Int] = [:]

    private(set) var selectedPageIndex = 0

    /// The label column every page shares, so labels line up across pages.
    private let labelColumnWidth: CGFloat = 186

    public init(store: PreferencesStore, themeStore: ThemeStore?, onChange: @escaping (Preferences) -> Void) {
        self.store = store
        self.themeStore = themeStore
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Preferences"
        super.init(window: window)
        // "System" comes first: it is the default, and it follows the Mac.
        pages = Self.makePages(
            themeNames: [EditorTheme.systemThemeName] + (themeStore?.allThemes.map(\.name) ?? []))
        buildLayout()
        showPage(at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Removes the key monitor. Called when the window closes; a deinit cannot
    /// touch main-actor state.
    public func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - The settings model

    public static func makePages(themeNames: [String]) -> [Page] {
        [
            Page(title: "General", symbol: "gearshape",
                 summary: "Window chrome, and what the tab bar does when it runs out of room.",
                 groups: [
                    Group("Interface", [
                        .toggles("Show", [("Toolbar", \.showToolbar),
                                          ("Status bar", \.showStatusBar),
                                          ("Tab bar", \.showTabBar)]),
                    ]),
                    Group("Tab bar", [
                        .choice("When space runs out", \.tabLayoutRawValue,
                                options: ["horizontal", "wrapped", "vertical"]),
                        .toggles("Behaviour", [("Close button on every tab", \.tabCloseButtonOnEachTab),
                                               ("Confirm before closing an edited document",
                                                \.confirmCloseUnsaved)]),
                    ]),
                 ]),

            Page(title: "Editing", symbol: "cursorarrow",
                 summary: "Caret, current-line highlight and how text behaves as you edit.",
                 groups: [
                    Group("Caret", [
                        .number("Width", \.caretWidth, range: 1...5),
                        .toggles("Blink", [("Blink the caret", \.caretBlinks)]),
                    ]),
                    Group("Highlighting", [
                        .toggles("Highlight", [("The line containing the caret", \.highlightCurrentLine),
                                               ("Other occurrences of the selected word", \.smartHighlight),
                                               ("The matching bracket", \.braceMatching)]),
                    ]),
                    Group("Behaviour", [
                        .toggles("Text", [("Wrap long lines", \.wordWrap),
                                          ("Allow scrolling past the last line", \.scrollBeyondLastLine),
                                          ("Open links on click", \.clickableURLs)]),
                    ]),
                 ]),

            Page(title: "Symbols", symbol: "paragraphsign",
                 summary: "Everything visible that is not the text: invisible characters, guides and gutter lanes.",
                 groups: [
                    Group("Whitespace", [
                        .toggles("Show", [("Spaces and tabs", \.showWhitespace),
                                          ("End of line", \.showEndOfLine),
                                          ("The wrap symbol", \.showWrapSymbol)]),
                    ]),
                    Group("Guides", [
                        .toggles("Indent guides", [("Show indent guides", \.showIndentGuides)]),
                    ]),
                    Group("Gutter lanes", [
                        .toggles("Show", [("Line numbers", \.showLineNumbers),
                                          ("Bookmarks", \.showBookmarkMargin),
                                          ("Change history", \.showChangeHistoryMargin)]),
                    ]),
                    Group("Edge column", [
                        .number("Column", \.edgeColumn, range: 0...300),
                    ]),
                 ], showsPreview: true),

            Page(title: "Indentation", symbol: "increase.indent",
                 summary: "What the tab key inserts, and how new lines line up.",
                 groups: [
                    Group("Default", [
                        .number("Tab size", \.tabWidth, range: 1...16),
                        .toggles("Indent using", [("Spaces rather than tab characters",
                                                   \.replaceTabsBySpaces)]),
                    ]),
                    Group("Automatic", [
                        .toggles("On new lines", [("Match the previous line's indentation", \.autoIndent)]),
                    ]),
                 ], showsPreview: true),

            Page(title: "New Document", symbol: "doc.badge.plus",
                 summary: "What an untitled document is before it ever touches disk.",
                 groups: [
                    Group("Format", [
                        .choice("Line ending", \.defaultLineEndingRawValue,
                                options: LineEnding.allCases.map(\.rawValue)),
                        .encoding("Encoding", \.defaultEncodingRawValue),
                        .toggles("Byte order mark", [("Write a BOM", \.defaultEncodingHasBOM)]),
                    ]),
                    Group("Language", [
                        .optionalText("Default language", \.defaultLanguageName),
                    ]),
                 ]),

            Page(title: "Backup & Session", symbol: "clock.arrow.circlepath",
                 summary: "Crash safety for unsaved work, and what reopens next launch.",
                 groups: [
                    Group("Snapshots", [
                        .toggles("Unsaved work", [("Keep a snapshot of every edited document",
                                                   \.periodicBackup)]),
                        .number("Interval", \.backupIntervalSeconds, range: 1...600),
                        .optionalText("Folder", \.backupDirectory),
                    ]),
                    Group("Session", [
                        .toggles("At launch", [("Reopen the documents from last time", \.rememberSession)]),
                    ]),
                 ]),

            Page(title: "File Status", symbol: "arrow.triangle.2.circlepath",
                 summary: "What happens when a file changes underneath you.",
                 groups: [
                    Group("Monitoring", [
                        .toggles("Watch", [("Open files, for external changes", \.detectFileChanges),
                                           ("Reload silently when there are no unsaved edits",
                                            \.reloadChangedFilesSilently)]),
                    ]),
                 ]),

            Page(title: "Recent Files", symbol: "list.bullet",
                 summary: "The Open Recent menu and the launch list.",
                 groups: [
                    Group("List", [
                        .number("Remember", \.recentFilesLimit, range: 0...50),
                        .toggles("Display", [("Show the full path", \.recentFilesShowFullPath)]),
                    ]),
                 ]),

            Page(title: "Auto-Completion", symbol: "text.append",
                 summary: "Word completion, call tips and path completion.",
                 groups: [
                    Group("Trigger", [
                        .toggles("While typing", [("Suggest completions automatically",
                                                   \.autoCompletionEnabled)]),
                        .number("After", \.autoCompletionMinimumCharacters, range: 1...10),
                    ]),
                    Group("Sources", [
                        .toggles("Suggest from", [("Words in this document", \.autoCompletionFromWords),
                                                  ("Language keywords", \.autoCompletionFromKeywords),
                                                  ("File paths", \.pathCompletion)]),
                    ]),
                    Group("Assistance", [
                        .toggles("Call tips", [("Show parameter call tips", \.showCallTips)]),
                    ]),
                 ]),

            Page(title: "Searching", symbol: "magnifyingglass",
                 summary: "Defaults the search panel opens with.",
                 groups: [
                    Group("Defaults", [
                        .choice("Mode", \.searchDefaultModeRawValue,
                                options: SearchMode.allCases.map(\.rawValue)),
                        .toggles("Options", [("Wrap around", \.searchWrapAround)]),
                    ]),
                    Group("Panel", [
                        .toggles("After a search", [("Keep the panel open", \.findDialogStaysOpen)]),
                    ]),
                 ]),

            Page(title: "Appearance & Themes", symbol: "paintpalette",
                 summary: "Editor theme and the typeface used for code.",
                 groups: [
                    Group("Code font", [
                        .text("Typeface", \.fontName),
                        .decimal("Size", \.fontSize, range: 6...96),
                    ]),
                    Group("Theme", [
                        .choice("Editor theme", \.themeName, options: themeNames),
                    ]),
                 ], showsPreview: true),
        ]
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let window else { return }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.width = 200
        pageList.addTableColumn(column)
        pageList.headerView = nil
        pageList.dataSource = self
        pageList.delegate = self
        pageList.rowSizeStyle = .default
        pageList.style = .sourceList
        pageList.selectionHighlightStyle = .regular
        pageList.setAccessibilityLabel("Preference pages")

        let listScroll = NSScrollView()
        listScroll.documentView = pageList
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false

        searchField.placeholderString = "Search settings"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false

        let resetAll = NSButton(title: "Reset All Settings…", target: self,
                                action: #selector(resetAllTapped))
        resetAll.bezelStyle = .rounded

        // Page header: title, summary and the page's own reset.
        pageTitleLabel.font = DS.Font.pageTitle()
        pageTitleLabel.textColor = DS.Color.textPrimary
        pageSummaryLabel.font = DS.Font.small()
        pageSummaryLabel.textColor = DS.Color.textSecondary
        pageSummaryLabel.lineBreakMode = .byWordWrapping
        pageSummaryLabel.maximumNumberOfLines = 2
        resetPageButton.title = "Reset Page"
        resetPageButton.bezelStyle = .rounded
        resetPageButton.target = self
        resetPageButton.action = #selector(resetPageTapped)

        let headerText = NSStackView(views: [pageTitleLabel, pageSummaryLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 2
        let header = NSStackView(views: [headerText, NSView(), resetPageButton])
        header.orientation = .horizontal
        header.alignment = .top

        let content = PreferencesBackgroundView()
        for subview in [listScroll, searchField, resetAll, header, detailContainer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: content.topAnchor),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            listScroll.widthAnchor.constraint(equalToConstant: 210),
            listScroll.bottomAnchor.constraint(equalTo: searchField.topAnchor, constant: -DS.Space.m),

            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DS.Space.m),
            searchField.widthAnchor.constraint(equalToConstant: 186),
            searchField.bottomAnchor.constraint(equalTo: resetAll.topAnchor, constant: -DS.Space.m),

            resetAll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DS.Space.m),
            resetAll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -DS.Space.l),

            header.topAnchor.constraint(equalTo: content.topAnchor, constant: DS.Space.xl),
            header.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: DS.Space.xl),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -DS.Space.xl),

            detailContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: DS.Space.l),
            detailContainer.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        pageList.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        window.delegate = self
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handle(event) ? nil : event
        }
    }

    // MARK: - Search

    @objc private func searchChanged() {
        search(for: searchField.stringValue)
    }

    /// Filters every setting in the app, as typing in the field does.
    public func search(for text: String) {
        searchField.stringValue = text
        query = text.trimmingCharacters(in: .whitespaces)
    }

    /// ⌘F focuses the settings search field.
    public func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    /// The window's own shortcuts: ⌘F to search, ⌃⇥ and ⌃⇧⇥ between pages.
    /// They are handled here rather than in the main menu because they only
    /// mean anything while this window is in front.
    public func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "f" {
            focusSearchField()
            return true
        }
        if modifiers == .control, event.keyCode == 48 {
            selectNextPage()
            return true
        }
        if modifiers == [.control, .shift], event.keyCode == 48 {
            selectPreviousPage()
            return true
        }
        return false
    }

    /// Pages whose settings match the query, with a hit count each. An empty
    /// query matches everything, which is how the list looks at rest.
    private func applyQuery() {
        matches = [:]
        if !query.isEmpty {
            for page in pages {
                let hits = page.controls.filter { matchesQuery($0, page: page) }.count
                if hits > 0 { matches[page.title] = hits }
            }
        }
        pageList.reloadData()
        if !query.isEmpty, matches[pages[selectedPageIndex].title] == nil,
           let firstMatch = pages.firstIndex(where: { matches[$0.title] != nil }) {
            selectPage(at: firstMatch)
        } else {
            showPage(at: selectedPageIndex)
        }
    }

    private func matchesQuery(_ control: Control, page: Page) -> Bool {
        guard !query.isEmpty else { return true }
        var haystack = "\(control.label) \(page.title)"
        if case .toggles(_, let options) = control {
            haystack += " " + options.map(\.0).joined(separator: " ")
        }
        return haystack.lowercased().contains(query.lowercased())
    }

    /// How many settings the current query matches, for the result line.
    public var matchCount: Int { matches.values.reduce(0, +) }

    /// The number of settings matching on a page, for the sidebar's counts.
    public func hitCount(forPageTitled title: String) -> Int? { matches[title] }

    // MARK: - Pages

    /// ⌃⇥ and ⌃⇧⇥ move between pages.
    public func selectNextPage() { selectPage(at: selectedPageIndex + 1) }
    public func selectPreviousPage() { selectPage(at: selectedPageIndex - 1) }

    public func selectPage(at index: Int) {
        let wrapped = (index + pages.count) % pages.count
        pageList.selectRowIndexes(IndexSet(integer: wrapped), byExtendingSelection: false)
        showPage(at: wrapped)
    }

    private func showPage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        selectedPageIndex = index
        let page = pages[index]
        pageTitleLabel.stringValue = page.title
        pageSummaryLabel.stringValue = page.summary

        detailContainer.subviews.forEach { $0.removeFromSuperview() }
        trampolines.removeAll()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DS.Space.xl
        stack.translatesAutoresizingMaskIntoConstraints = false

        var shownControls = 0
        for group in page.groups {
            let visible = group.controls.filter { matchesQuery($0, page: page) }
            guard !visible.isEmpty else { continue }
            shownControls += visible.count
            stack.addArrangedSubview(makeGroupView(named: group.name, controls: visible))
        }

        if shownControls == 0 {
            stack.addArrangedSubview(DSEmptyState(
                symbol: "magnifyingglass",
                title: "No settings match “\(query)”",
                message: "Try a setting name, a file extension or a shortcut."))
        } else if page.showsPreview {
            stack.addArrangedSubview(makePreview(for: page))
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // A non-flipped document view lays content out from the bottom, which
        // puts it above the visible scroll region and shows an empty pane.
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: DS.Space.xs),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: DS.Space.xl),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: documentView.trailingAnchor,
                                            constant: -DS.Space.xl),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -DS.Space.xl),
        ])
        scroll.documentView = documentView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            scroll.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
        ])
    }

    /// A named group: a heading, then one grid whose first column is the shared
    /// label column, so every label on every page aligns on the same edge.
    private func makeGroupView(named name: String, controls: [Control]) -> NSView {
        let heading = NSTextField(labelWithString: name)
        heading.font = DS.Font.bodyEmphasis()
        heading.textColor = DS.Color.textPrimary

        let grid = NSGridView()
        grid.rowSpacing = DS.Space.s
        grid.columnSpacing = DS.Space.l
        grid.translatesAutoresizingMaskIntoConstraints = false

        for control in controls {
            let label = NSTextField(labelWithString: control.label)
            label.alignment = .right
            label.textColor = DS.Color.textSecondary
            label.lineBreakMode = .byTruncatingTail
            grid.addRow(with: [label, makeControlView(for: control)])
        }
        grid.column(at: 0).width = labelColumnWidth
        grid.column(at: 0).xPlacement = .trailing

        let stack = NSStackView(views: [heading, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DS.Space.s
        return stack
    }

    /// A live sample of the settings on pages whose effect is visual.
    private func makePreview(for page: Page) -> NSView {
        let preview = PreferencePreviewView(preferences: store.preferences, page: page.title)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 420).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let caption = NSTextField(labelWithString: "Preview")
        caption.font = DS.Font.bodyEmphasis()

        let stack = NSStackView(views: [caption, preview])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DS.Space.s
        return stack
    }

    // MARK: - Reset

    @objc private func resetPageTapped() { resetCurrentPage() }

    /// Resets the settings on the page being shown, and applies immediately.
    public func resetCurrentPage() {
        guard pages.indices.contains(selectedPageIndex) else { return }
        let page = pages[selectedPageIndex]
        let defaults = Preferences()
        try? store.update { preferences in
            for control in page.controls { Self.copy(control, from: defaults, into: &preferences) }
        }
        onChange(store.preferences)
        showPage(at: selectedPageIndex)
    }

    /// Resets every setting. The button asks first; this is what it does once
    /// the user has confirmed.
    public func resetEverything() {
        try? store.update { $0 = Preferences() }
        onChange(store.preferences)
        showPage(at: selectedPageIndex)
    }

    /// Resetting everything always confirms, in a sheet on this window rather
    /// than a free-floating alert. The destructive button is not the default,
    /// so Return cancels.
    @objc private func resetAllTapped() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset every setting to its factory value?"
        alert.informativeText = """
            Eleven pages of settings return to their defaults. Open documents, \
            sessions and installed plug-ins are untouched.
            """
        let reset = alert.addButton(withTitle: "Reset")
        reset.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: "Cancel")
        alert.window.defaultButtonCell = cancel.cell as? NSButtonCell

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.resetEverything()
        }
    }

    /// Copies one setting's value between two preference sets.
    private static func copy(_ control: Control, from source: Preferences, into target: inout Preferences) {
        switch control {
        case .toggle(_, let keyPath): target[keyPath: keyPath] = source[keyPath: keyPath]
        case .number(_, let keyPath, _): target[keyPath: keyPath] = source[keyPath: keyPath]
        case .decimal(_, let keyPath, _): target[keyPath: keyPath] = source[keyPath: keyPath]
        case .text(_, let keyPath): target[keyPath: keyPath] = source[keyPath: keyPath]
        case .optionalText(_, let keyPath): target[keyPath: keyPath] = source[keyPath: keyPath]
        case .choice(_, let keyPath, _): target[keyPath: keyPath] = source[keyPath: keyPath]
        case .encoding(_, let keyPath): target[keyPath: keyPath] = source[keyPath: keyPath]
        case .toggles(_, let options):
            for (_, keyPath) in options { target[keyPath: keyPath] = source[keyPath: keyPath] }
        }
    }

    // MARK: - Controls

    private func makeControlView(for control: Control) -> NSView {
        switch control {
        case .toggle(let label, let keyPath):
            let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            button.state = store.preferences[keyPath: keyPath] ? .on : .off
            button.setAccessibilityLabel(label)
            bind(button) { [weak self] in
                try? self?.store.update { $0[keyPath: keyPath] = button.state == .on }
                self?.commit()
            }
            return button

        case .toggles(let label, let options):
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = DS.Space.xxs
            for (title, keyPath) in options {
                let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
                button.state = store.preferences[keyPath: keyPath] ? .on : .off
                button.setAccessibilityLabel("\(label) \(title)")
                bind(button) { [weak self] in
                    try? self?.store.update { $0[keyPath: keyPath] = button.state == .on }
                    self?.commit()
                }
                stack.addArrangedSubview(button)
            }
            return stack

        case .number(let label, let keyPath, let range):
            let field = NSTextField(string: "\(store.preferences[keyPath: keyPath])")
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 72).isActive = true
            field.setAccessibilityLabel(label)
            bind(field) { [weak self] in
                let value = min(max(range.lowerBound, Int(field.stringValue) ?? range.lowerBound),
                                range.upperBound)
                field.stringValue = "\(value)"
                try? self?.store.update { $0[keyPath: keyPath] = value }
                self?.commit()
            }
            return field

        case .decimal(let label, let keyPath, let range):
            let field = NSTextField(string: "\(store.preferences[keyPath: keyPath])")
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 72).isActive = true
            field.setAccessibilityLabel(label)
            bind(field) { [weak self] in
                let value = min(max(range.lowerBound, Double(field.stringValue) ?? range.lowerBound),
                                range.upperBound)
                field.stringValue = "\(value)"
                try? self?.store.update { $0[keyPath: keyPath] = value }
                self?.commit()
            }
            return field

        case .text(let label, let keyPath):
            let field = NSTextField(string: store.preferences[keyPath: keyPath])
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
            field.setAccessibilityLabel(label)
            bind(field) { [weak self] in
                try? self?.store.update { $0[keyPath: keyPath] = field.stringValue }
                self?.commit()
            }
            return field

        case .optionalText(let label, let keyPath):
            let field = NSTextField(string: store.preferences[keyPath: keyPath] ?? "")
            field.placeholderString = "Default"
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
            field.setAccessibilityLabel(label)
            bind(field) { [weak self] in
                let text = field.stringValue.trimmingCharacters(in: .whitespaces)
                try? self?.store.update { $0[keyPath: keyPath] = text.isEmpty ? nil : text }
                self?.commit()
            }
            return field

        case .encoding(let label, let keyPath):
            let popup = NSPopUpButton()
            let encodings = Self.offeredEncodings
            popup.addItems(withTitles: encodings.map(\.name))
            let current = store.preferences[keyPath: keyPath]
            if let index = encodings.firstIndex(where: { $0.encoding.rawValue == current }) {
                popup.selectItem(at: index)
            }
            popup.setAccessibilityLabel(label)
            bind(popup) { [weak self] in
                let index = popup.indexOfSelectedItem
                guard encodings.indices.contains(index) else { return }
                try? self?.store.update { $0[keyPath: keyPath] = encodings[index].encoding.rawValue }
                self?.commit()
            }
            return popup

        case .choice(let label, let keyPath, let options):
            let popup = NSPopUpButton()
            popup.addItems(withTitles: options.map(Self.displayName))
            let current = store.preferences[keyPath: keyPath]
            if let index = options.firstIndex(of: current) { popup.selectItem(at: index) }
            popup.setAccessibilityLabel(label)
            bind(popup) { [weak self] in
                let index = popup.indexOfSelectedItem
                guard options.indices.contains(index) else { return }
                try? self?.store.update { $0[keyPath: keyPath] = options[index] }
                self?.commit()
            }
            return popup
        }
    }

    /// The encodings offered for new documents.
    static let offeredEncodings: [(name: String, encoding: String.Encoding)] = [
        ("UTF-8", .utf8),
        ("UTF-16 LE", .utf16LittleEndian),
        ("UTF-16 BE", .utf16BigEndian),
        ("Western (Mac OS Roman)", .macOSRoman),
        ("Western (ISO Latin 1)", .isoLatin1),
    ]

    /// Raw values are stored, but a menu should not read "\n".
    private static func displayName(_ rawValue: String) -> String {
        switch rawValue {
        case "\n": return "Unix (LF)"
        case "\r\n": return "Windows (CR LF)"
        case "\r": return "Classic Mac (CR)"
        case "horizontal": return "Horizontal"
        case "wrapped": return "Wrapped rows"
        case "vertical": return "Vertical rail"
        case "normal": return "Normal"
        case "extended": return "Extended"
        case "regex": return "Regular expression"
        default: return rawValue
        }
    }

    private func bind(_ control: NSControl, _ action: @escaping () -> Void) {
        let trampoline = ActionTrampoline(action)
        trampolines.append(trampoline)
        control.target = trampoline
        control.action = #selector(ActionTrampoline.fire)
    }

    /// Every control commits on change, and the documents repaint live.
    private func commit() {
        onChange(store.preferences)
    }
}

extension PreferencesWindowController: NSWindowDelegate {}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    public func tableView(_ tableView: NSTableView,
                          viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard pages.indices.contains(row) else { return nil }
        let page = pages[row]
        // A page with no matches is dimmed rather than hidden, so the list does
        // not jump around while a query is being typed.
        let dimmed = !query.isEmpty && matches[page.title] == nil

        let icon = NSImageView(image: DS.symbol(
            page.symbol, pointSize: 13,
            color: dimmed ? DS.Color.textDisabled : DS.Color.textSecondary) ?? NSImage())
        let title = NSTextField(labelWithString: page.title)
        title.lineBreakMode = .byTruncatingTail
        title.textColor = dimmed ? DS.Color.textDisabled : DS.Color.textPrimary

        // While searching, each page carries how many of its settings match.
        let count = NSTextField(labelWithString: matches[page.title].map(String.init) ?? "")
        count.font = DS.Font.statusNumeric()
        count.textColor = DS.Color.brand
        count.alignment = .right

        let cell = NSView()
        for subview in [icon, title, count] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: DS.Space.s),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: DS.Space.s),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -DS.Space.xs),

            count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -DS.Space.m),
            count.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.setAccessibilityLabel(matches[page.title].map { "\(page.title), \($0) matching settings" }
            ?? page.title)
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        showPage(at: pageList.selectedRow)
    }
}

/// A small live sample of the editor, shown on the pages whose settings are
/// visual: indentation, symbols and appearance.
final class PreferencePreviewView: NSView {
    private let preferences: Preferences
    private let page: String

    init(preferences: Preferences, page: String) {
        self.preferences = preferences
        self.page = page
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("Preview of the current settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        DS.Color.content.setFill()
        bounds.fill()
        DS.Color.controlBorder.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                     xRadius: DS.Radius.control, yRadius: DS.Radius.control).stroke()

        let font = NSFont(name: preferences.fontName, size: preferences.fontSize)
            ?? DS.Font.mono(CGFloat(preferences.fontSize))
        let indent = String(repeating: preferences.replaceTabsBySpaces ? " " : "\t",
                            count: preferences.replaceTabsBySpaces ? preferences.tabWidth : 1)
        let lines = [
            "func persist(_ session: Session) throws {",
            "\(indent)let payload = try encoder.encode(session)",
            "\(indent)try payload.write(to: url)",
            "}",
        ]

        var y = DS.Space.m
        let lineHeight = font.ascender - font.descender + font.leading
        for (index, line) in lines.enumerated() {
            let shown = preferences.showWhitespace
                ? line.replacingOccurrences(of: " ", with: "·").replacingOccurrences(of: "\t", with: "→")
                : line
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: index == 0 ? DS.SyntaxPalette.xcodeKeyword : DS.SyntaxPalette.xcodePlain,
            ]
            (shown as NSString).draw(at: NSPoint(x: DS.Space.xxl, y: y), withAttributes: attributes)
            y += lineHeight
        }

        // The edge column, when one is set, lands on the character cell.
        if preferences.edgeColumn > 0 {
            let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
            let x = DS.Space.xxl + advance * CGFloat(preferences.edgeColumn)
            if x < bounds.maxX {
                DS.Color.separator.setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.maxY))
                path.stroke()
            }
        }
    }
}

/// The window's background, painted from a token so the page reads the same
/// whichever appearance the window is in.
final class PreferencesBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DS.Color.windowBackground.setFill()
        dirtyRect.fill()
    }
}

/// Routes a control's action to a closure.
final class ActionTrampoline: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

/// Lays content out from the top, as a settings page should read.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
