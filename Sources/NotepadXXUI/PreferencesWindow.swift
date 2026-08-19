import AppKit
import NotepadXXCore

/// The Preferences window.
///
/// Pages are described as data — a label plus a keypath into `Preferences` —
/// and the controls are generated from that. Adding a setting is adding a row
/// here, not writing layout code, which is what keeps ~100 settings tractable.
@MainActor
public final class PreferencesWindowController: NSWindowController {

    public enum Control {
        case toggle(String, WritableKeyPath<Preferences, Bool>)
        case number(String, WritableKeyPath<Preferences, Int>, range: ClosedRange<Int>)
        case decimal(String, WritableKeyPath<Preferences, Double>, range: ClosedRange<Double>)
        case text(String, WritableKeyPath<Preferences, String>)
        case choice(String, WritableKeyPath<Preferences, String>, options: [String])
    }

    public struct Page {
        public let title: String
        public let controls: [Control]
    }

    private let store: PreferencesStore
    private let themeStore: ThemeStore?
    private let onChange: (Preferences) -> Void

    private let pageList = NSTableView()
    private let detailContainer = NSView()
    private var pages: [Page] = []
    private var trampolines: [ActionTrampoline] = []

    public init(store: PreferencesStore, themeStore: ThemeStore?, onChange: @escaping (Preferences) -> Void) {
        self.store = store
        self.themeStore = themeStore
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Preferences"
        super.init(window: window)
        pages = Self.makePages(themeNames: themeStore?.allThemes.map(\.name) ?? ["System"])
        buildLayout()
        pageList.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showPage(at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public static func makePages(themeNames: [String]) -> [Page] {
        [
            Page(title: "General", controls: [
                .toggle("Show toolbar", \.showToolbar),
                .toggle("Show status bar", \.showStatusBar),
                .toggle("Show tab bar", \.showTabBar),
                .choice("Tab layout", \.tabLayoutRawValue,
                        options: ["horizontal", "wrapped", "vertical"]),
                .toggle("Close button on each tab", \.tabCloseButtonOnEachTab),
                .toggle("Confirm before closing unsaved documents", \.confirmCloseUnsaved),
            ]),
            Page(title: "Editing", controls: [
                .toggle("Show line numbers", \.showLineNumbers),
                .toggle("Show bookmark margin", \.showBookmarkMargin),
                .toggle("Show change history margin", \.showChangeHistoryMargin),
                .toggle("Highlight current line", \.highlightCurrentLine),
                .toggle("Show indent guides", \.showIndentGuides),
                .toggle("Word wrap", \.wordWrap),
                .toggle("Smart highlighting", \.smartHighlight),
                .toggle("Brace matching", \.braceMatching),
                .toggle("Clickable URLs", \.clickableURLs),
                .toggle("Scroll beyond last line", \.scrollBeyondLastLine),
                .number("Vertical edge column (0 = off)", \.edgeColumn, range: 0...300),
                .number("Caret width", \.caretWidth, range: 1...5),
                .decimal("Caret blink rate (seconds)", \.caretBlinkRate, range: 0...2),
            ]),
            Page(title: "Show Symbol", controls: [
                .toggle("Show white space", \.showWhitespace),
                .toggle("Show end of line", \.showEndOfLine),
                .toggle("Show wrap symbol", \.showWrapSymbol),
            ]),
            Page(title: "Indentation", controls: [
                .number("Tab width", \.tabWidth, range: 1...16),
                .toggle("Replace tabs by spaces", \.replaceTabsBySpaces),
                .toggle("Auto-indent", \.autoIndent),
            ]),
            Page(title: "Backup & Session", controls: [
                .toggle("Remember the previous session", \.rememberSession),
                .toggle("Periodic backup of unsaved work", \.periodicBackup),
                .number("Backup interval (seconds)", \.backupIntervalSeconds, range: 1...600),
            ]),
            Page(title: "File Status", controls: [
                .toggle("Detect changes made by other programs", \.detectFileChanges),
                .toggle("Reload changed files without asking", \.reloadChangedFilesSilently),
            ]),
            Page(title: "Recent Files", controls: [
                .number("Number of files remembered", \.recentFilesLimit, range: 0...50),
                .toggle("Show the full path", \.recentFilesShowFullPath),
            ]),
            Page(title: "Auto-Completion", controls: [
                .toggle("Enable auto-completion", \.autoCompletionEnabled),
                .toggle("Suggest words from the document", \.autoCompletionFromWords),
                .toggle("Suggest language keywords", \.autoCompletionFromKeywords),
                .number("Characters before suggesting", \.autoCompletionMinimumCharacters, range: 1...10),
                .toggle("Show call tips", \.showCallTips),
                .toggle("Complete file paths", \.pathCompletion),
            ]),
            Page(title: "Searching", controls: [
                .toggle("Wrap around", \.searchWrapAround),
                .toggle("Keep the Find dialog open", \.findDialogStaysOpen),
                .choice("Default search mode", \.searchDefaultModeRawValue,
                        options: ["normal", "extended", "regex"]),
            ]),
            Page(title: "Appearance", controls: [
                .text("Font name", \.fontName),
                .decimal("Font size", \.fontSize, range: 6...96),
                .choice("Theme", \.themeName, options: themeNames),
            ]),
        ]
    }

    private func buildLayout() {
        guard let window else { return }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.width = 180
        pageList.addTableColumn(column)
        pageList.headerView = nil
        pageList.dataSource = self
        pageList.delegate = self
        pageList.rowSizeStyle = .default

        let listScroll = NSScrollView()
        listScroll.documentView = pageList
        listScroll.hasVerticalScroller = true

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetTapped))
        reset.bezelStyle = .rounded

        let content = NSView()
        for subview in [listScroll, detailContainer, reset] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: content.topAnchor),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            listScroll.bottomAnchor.constraint(equalTo: reset.topAnchor, constant: -8),
            listScroll.widthAnchor.constraint(equalToConstant: 190),

            reset.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            reset.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            detailContainer.topAnchor.constraint(equalTo: content.topAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }

    private func showPage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        detailContainer.subviews.forEach { $0.removeFromSuperview() }
        trampolines.removeAll()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        for control in pages[index].controls {
            stack.addArrangedSubview(makeView(for: control))
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
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -18),
            // The stack drives the document height so scrolling matches content.
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18),
        ])
        scroll.documentView = documentView
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        scroll.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
        ])
    }

    private func makeView(for control: Control) -> NSView {
        switch control {
        case .toggle(let label, let keyPath):
            let button = NSButton(checkboxWithTitle: label, target: nil, action: nil)
            button.state = store.preferences[keyPath: keyPath] ? .on : .off
            bind(button) { [weak self] in
                self?.apply { $0[keyPath: keyPath] = button.state == .on }
            }
            return button

        case .number(let label, let keyPath, let range):
            let field = NSTextField(string: String(store.preferences[keyPath: keyPath]))
            bind(field) { [weak self] in
                let value = min(max(range.lowerBound, Int(field.stringValue) ?? range.lowerBound), range.upperBound)
                field.stringValue = String(value)
                self?.apply { $0[keyPath: keyPath] = value }
            }
            return Self.row(label, field, width: 80)

        case .decimal(let label, let keyPath, let range):
            let field = NSTextField(string: String(store.preferences[keyPath: keyPath]))
            bind(field) { [weak self] in
                let value = min(max(range.lowerBound, Double(field.stringValue) ?? range.lowerBound), range.upperBound)
                field.stringValue = String(value)
                self?.apply { $0[keyPath: keyPath] = value }
            }
            return Self.row(label, field, width: 80)

        case .text(let label, let keyPath):
            let field = NSTextField(string: store.preferences[keyPath: keyPath])
            bind(field) { [weak self] in
                self?.apply { $0[keyPath: keyPath] = field.stringValue }
            }
            return Self.row(label, field, width: 220)

        case .choice(let label, let keyPath, let options):
            let popup = NSPopUpButton()
            popup.addItems(withTitles: options)
            popup.selectItem(withTitle: store.preferences[keyPath: keyPath])
            bind(popup) { [weak self] in
                self?.apply { $0[keyPath: keyPath] = popup.titleOfSelectedItem ?? options[0] }
            }
            return Self.row(label, popup, width: 220)
        }
    }

    private static func row(_ label: String, _ control: NSView, width: CGFloat) -> NSView {
        let field = NSTextField(labelWithString: label)
        let stack = NSStackView(views: [field, control])
        stack.orientation = .horizontal
        stack.spacing = 10
        control.widthAnchor.constraint(equalToConstant: width).isActive = true
        return stack
    }

    /// Wires a control to a closure, keeping the trampoline alive.
    private func bind(_ control: NSControl, _ handler: @escaping () -> Void) {
        let trampoline = ActionTrampoline(handler)
        trampolines.append(trampoline)
        control.target = trampoline
        control.action = #selector(ActionTrampoline.fire)
    }

    private func apply(_ mutate: (inout Preferences) -> Void) {
        try? store.update(mutate)
        onChange(store.preferences)
    }

    @objc private func resetTapped() {
        try? store.resetToDefaults()
        onChange(store.preferences)
        showPage(at: max(0, pageList.selectedRow))
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard pages.indices.contains(row) else { return nil }
        return NSTextField(labelWithString: pages[row].title)
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        showPage(at: pageList.selectedRow)
    }
}

/// A top-down coordinate space, so stacked settings read from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Lets a control carry a closure instead of needing its own selector.
/// Instances are retained by the window controller rather than through
/// associated objects, which strict concurrency rejects.
final class ActionTrampoline: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}
