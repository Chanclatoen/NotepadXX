import AppKit
import NotepadXXCore
import NotepadXXDesign

/// The one search surface: Find, Replace, Find in Files and Mark are four modes
/// of a single non-activating utility panel.
///
/// The panel is built once and rows are shown or hidden per mode, so the field
/// order never changes and muscle memory survives switching modes. It does not
/// take key focus away from the document, so live match highlighting keeps
/// working behind it.
public final class SearchPanelController: NSWindowController {
    public enum Mode: Int, CaseIterable {
        case find, replace, findInFiles, mark

        var title: String {
            switch self {
            case .find: return "Find"
            case .replace: return "Replace"
            case .findInFiles: return "Find in Files"
            case .mark: return "Mark"
            }
        }
    }

    public struct Request {
        public init(pattern: String, replacement: String, options: SearchOptions, inSelection: Bool,
                    directory: URL? = nil, filters: String = "", exclusions: String = "",
                    includeSubfolders: Bool = true, includeHidden: Bool = false,
                    markStyle: MarkStyle = MarkStyle(index: 0),
                    bookmarkMatchingLines: Bool = false, purgeMarks: Bool = false) {
            self.pattern = pattern
            self.replacement = replacement
            self.options = options
            self.inSelection = inSelection
            self.directory = directory
            self.filters = filters
            self.exclusions = exclusions
            self.includeSubfolders = includeSubfolders
            self.includeHidden = includeHidden
            self.markStyle = markStyle
            self.bookmarkMatchingLines = bookmarkMatchingLines
            self.purgeMarks = purgeMarks
        }

        public let pattern: String
        public let replacement: String
        public let options: SearchOptions
        public let inSelection: Bool
        public let directory: URL?
        public let filters: String
        public let exclusions: String
        public let includeSubfolders: Bool
        public let includeHidden: Bool
        public let markStyle: MarkStyle
        public let bookmarkMatchingLines: Bool
        public let purgeMarks: Bool
    }

    // MARK: Callbacks

    public var onFindNext: ((Request) -> Void)?
    public var onFindPrevious: ((Request) -> Void)?
    public var onCount: ((Request) -> Void)?
    public var onReplace: ((Request) -> Void)?
    public var onReplaceAll: ((Request) -> Void)?
    public var onReplaceAllInOpenDocuments: ((Request) -> Void)?
    public var onFindAll: ((Request) -> Void)?
    public var onFindInFiles: ((Request) -> Void)?
    public var onReplaceInFiles: ((Request) -> Void)?
    public var onCancelSearch: (() -> Void)?
    public var onMarkAll: ((Request) -> Void)?
    public var onClearMarks: ((Request) -> Void)?
    public var onCopyMarkedText: ((Request) -> Void)?
    /// Called as the pattern is edited, so matches highlight live.
    public var onPatternChanged: ((Request) -> Void)?
    /// Called when the mode changes, so the caller can persist it.
    public var onModeChanged: ((Mode) -> Void)?

    // MARK: Controls

    private let modeTabs = NSSegmentedControl(
        labels: Mode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)

    private let findField = NSComboBox()
    private let replaceField = NSComboBox()
    private let directoryField = NSTextField(string: "")
    private let filtersField = NSTextField(string: "")
    private let exclusionsField = NSTextField(string: "")

    private let searchMode = NSSegmentedControl(
        labels: ["Normal", "Extended", "Regex"], trackingMode: .selectOne, target: nil, action: nil)
    private let modeHint = NSTextField(labelWithString: "⌥⌘X cycles")

    private let matchCase = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let wholeWord = NSButton(checkboxWithTitle: "Whole word only", target: nil, action: nil)
    private let wrapAround = NSButton(checkboxWithTitle: "Wrap around", target: nil, action: nil)
    private let inSelection = NSButton(checkboxWithTitle: "In selection", target: nil, action: nil)
    private let dotNewline = NSButton(checkboxWithTitle: "Dot matches newline", target: nil, action: nil)
    private let subfolders = NSButton(checkboxWithTitle: "In all sub-folders", target: nil, action: nil)
    private let hiddenFolders = NSButton(checkboxWithTitle: "In hidden folders", target: nil, action: nil)
    private let followDocument = NSButton(checkboxWithTitle: "Follow current document", target: nil, action: nil)
    private let bookmarkLines = NSButton(checkboxWithTitle: "Bookmark matching lines", target: nil, action: nil)
    private let purgeMarks = NSButton(checkboxWithTitle: "Purge for each search", target: nil, action: nil)

    private let markStyles = MarkStylePicker()
    private let statusLine = SearchStatusLine()
    private let progress = NSProgressIndicator()

    // Rows, so modes can show and hide whole lines without disturbing order.
    private var findRow = NSView()
    private var replaceRow = NSView()
    private var directoryRow = NSView()
    private var filtersRow = NSView()
    private var markStyleRow = NSView()
    private var modeRow = NSView()
    private var optionsRow = NSView()
    private var scopeRow = NSView()
    private var advancedRow = NSView()
    private var actionsRow = NSStackView()

    private var actionButtons: [Mode: [NSButton]] = [:]

    public private(set) var mode: Mode = .find {
        didSet {
            guard mode != oldValue else { return }
            applyMode()
            onModeChanged?(mode)
        }
    }

    /// True while a Find in Files scan is running: actions that would fight the
    /// scan are disabled rather than queued.
    public private(set) var isScanning = false

    public init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Find & Replace"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Clicking a field focuses it, but showing the panel does not pull focus
        // out of the document, so live highlighting keeps running.
        panel.becomesKeyOnlyIfNeeded = true
        panel.setFrameAutosaveName("NotepadXX.SearchPanel")
        super.init(window: panel)
        buildLayout()
        applyMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layout

    private func buildLayout() {
        guard let window else { return }

        modeTabs.target = self
        modeTabs.action = #selector(modeTabChanged)
        modeTabs.selectedSegment = 0
        modeTabs.setAccessibilityLabel("Search mode")

        searchMode.target = self
        searchMode.action = #selector(searchModeChanged)
        searchMode.selectedSegment = 0
        modeHint.font = DS.Font.small()
        modeHint.textColor = DS.Color.textTertiary

        for field in [findField, replaceField] {
            field.usesDataSource = false
            field.completes = false
            field.numberOfVisibleItems = 10
            field.delegate = self
        }
        findField.setAccessibilityLabel("Find what")
        replaceField.setAccessibilityLabel("Replace with")
        directoryField.placeholderString = "~/Projects"
        filtersField.placeholderString = "*.swift;*.h"
        exclusionsField.placeholderString = "build/;.git/"

        wrapAround.state = .on
        subfolders.state = .on

        for checkbox in [matchCase, wholeWord, wrapAround, inSelection, dotNewline,
                         subfolders, hiddenFolders, followDocument, bookmarkLines, purgeMarks] {
            checkbox.target = self
            checkbox.action = #selector(optionChanged)
            checkbox.font = DS.Font.body()
        }

        progress.style = .bar
        progress.isIndeterminate = false
        progress.isHidden = true
        progress.controlSize = .small

        findRow = labelled("Find what:", findField)
        replaceRow = labelled("Replace with:", replaceField)

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseDirectory))
        chooseButton.bezelStyle = .rounded
        directoryRow = labelled("Directory:", stack([directoryField, chooseButton], spacing: DS.Space.m))
        filtersRow = labelled("Filters:", stack([
            filtersField, NSTextField(labelWithString: "Exclude:"), exclusionsField,
        ], spacing: DS.Space.m))

        markStyleRow = labelled("Mark style:", markStyles)
        modeRow = labelled("Mode:", stack([searchMode, modeHint], spacing: DS.Space.l))
        optionsRow = labelled("Options:", stack([matchCase, wholeWord, wrapAround], spacing: DS.Space.l))
        scopeRow = labelled("Scope:", stack([subfolders, hiddenFolders, followDocument], spacing: DS.Space.l))
        advancedRow = labelled("Advanced:", stack([dotNewline, inSelection], spacing: DS.Space.l))

        buildActions()

        let stackView = NSStackView(views: [
            modeTabs, findRow, replaceRow, directoryRow, filtersRow, markStyleRow,
            modeRow, optionsRow, scopeRow, advancedRow, statusLine, progress, actionsRow,
        ])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = DS.Space.m
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DS.Space.xl),
            stackView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -DS.Space.xl),
            stackView.topAnchor.constraint(equalTo: content.topAnchor, constant: DS.Space.xl),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor,
                                              constant: -DS.Space.xl),
            modeTabs.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            modeTabs.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            actionsRow.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            replaceField.widthAnchor.constraint(equalTo: findField.widthAnchor),
            directoryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            filtersField.widthAnchor.constraint(equalToConstant: 150),
            exclusionsField.widthAnchor.constraint(equalToConstant: 150),
            progress.widthAnchor.constraint(equalTo: stackView.widthAnchor),
        ])
        window.contentView = content
    }

    private func buildActions() {
        actionsRow.orientation = .horizontal
        actionsRow.spacing = DS.Space.m
        actionButtons = [
            .find: [action("Count", #selector(count)),
                    action("Previous", #selector(findPrevious)),
                    action("Next", #selector(findNext), isDefault: true)],
            .replace: [action("Next", #selector(findNext)),
                       action("Replace", #selector(replace)),
                       action("All in Open Docs", #selector(replaceAllInOpenDocuments)),
                       action("Replace All", #selector(replaceAll), isDefault: true)],
            .findInFiles: [action("Cancel", #selector(cancelScan)),
                           action("Replace in Files", #selector(replaceInFiles)),
                           action("Find All", #selector(findInFiles), isDefault: true)],
            .mark: [action("Copy Marked Text", #selector(copyMarkedText)),
                    action("Clear Marks", #selector(clearMarks)),
                    action("Mark All", #selector(markAll), isDefault: true)],
        ]
    }

    private func action(_ title: String, _ selector: Selector, isDefault: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: selector)
        button.bezelStyle = .rounded
        if isDefault { button.keyEquivalent = "\r" }
        return button
    }

    private func labelled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.font = DS.Font.body()
        label.textColor = DS.Color.textSecondary
        label.widthAnchor.constraint(equalToConstant: 84).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = DS.Space.m
        return row
    }

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = spacing
        return row
    }

    // MARK: Modes

    /// Rows are hidden rather than rebuilt, so the field order is identical in
    /// every mode and only rows below are added.
    private func applyMode() {
        modeTabs.selectedSegment = mode.rawValue
        window?.title = mode == .mark ? "Mark" : "Find & Replace"

        replaceRow.isHidden = !(mode == .replace || mode == .findInFiles)
        directoryRow.isHidden = mode != .findInFiles
        filtersRow.isHidden = mode != .findInFiles
        scopeRow.isHidden = mode != .findInFiles
        markStyleRow.isHidden = mode != .mark

        // Options differ per mode; the row itself never moves.
        wrapAround.isHidden = mode == .findInFiles || mode == .mark
        inSelection.isHidden = mode == .findInFiles
        dotNewline.isHidden = mode == .mark
        bookmarkLines.isHidden = mode != .mark
        purgeMarks.isHidden = mode != .mark
        advancedRow.isHidden = mode == .findInFiles

        if mode == .mark {
            replaceOptionViews(in: advancedRow, with: [bookmarkLines, purgeMarks])
        } else {
            replaceOptionViews(in: advancedRow, with: [dotNewline, inSelection])
        }

        actionsRow.setViews(actionButtons[mode] ?? [], in: .leading)
        updateActionAvailability()
        validatePattern()
        resizeToFitMode()
    }

    /// Each mode adds rows below, so the panel is sized to the mode it is in.
    private func resizeToFitMode() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let fitting = content.fittingSize
        window.setContentSize(NSSize(width: max(560, fitting.width), height: fitting.height))
    }

    private func replaceOptionViews(in row: NSView, with views: [NSView]) {
        guard let outer = row as? NSStackView,
              let inner = outer.views.compactMap({ $0 as? NSStackView }).first else { return }
        inner.setViews(views, in: .leading)
    }

    @objc private func modeTabChanged() {
        mode = Mode(rawValue: modeTabs.selectedSegment) ?? .find
    }

    @objc private func searchModeChanged() {
        validatePattern()
        notifyPatternChanged()
    }

    @objc private func optionChanged() {
        notifyPatternChanged()
    }

    /// Whether the panel closes once a search has been run. Notepad++ can do
    /// either; Preferences decides.
    public var closesAfterUse = false

    /// Applies the defaults the panel opens with.
    public func applyDefaults(searchMode mode: SearchMode, wrapsAround: Bool, closesAfterUse: Bool) {
        switch mode {
        case .normal: searchMode.selectedSegment = 0
        case .extended: searchMode.selectedSegment = 1
        case .regex: searchMode.selectedSegment = 2
        }
        wrapAround.state = wrapsAround ? .on : .off
        self.closesAfterUse = closesAfterUse
    }

    /// ⌥⌘X cycles Normal → Extended → Regex, as the design specifies.
    public func cycleSearchMode() {
        searchMode.selectedSegment = (searchMode.selectedSegment + 1) % searchMode.segmentCount
        searchModeChanged()
    }

    public func show(mode: Mode) {
        self.mode = mode
        showWindow(nil)
        focusSearchField()
    }

    // MARK: Status

    /// The panel's status line is the only place ordinary search outcomes are
    /// reported — no alert dialogs for "not found".
    public func showStatus(_ message: String, kind: SearchStatusLine.Kind = .neutral) {
        statusLine.show(message, kind: kind)
    }

    public func showScanProgress(scanned: Int, total: Int, hits: Int) {
        isScanning = true
        progress.isHidden = false
        progress.maxValue = Double(max(total, 1))
        progress.doubleValue = Double(scanned)
        showStatus("Scanning \(scanned) of \(total) files · \(hits) hits so far", kind: .working)
        updateActionAvailability()
    }

    public func endScan() {
        isScanning = false
        progress.isHidden = true
        updateActionAvailability()
    }

    /// Replace in Files never runs while a scan is in progress, and no action
    /// runs on an invalid pattern.
    private func updateActionAvailability() {
        let valid = patternIsValid
        for (buttonMode, buttons) in actionButtons {
            for button in buttons {
                switch button.title {
                case "Cancel": button.isEnabled = isScanning
                case "Replace in Files": button.isEnabled = valid && !isScanning
                default: button.isEnabled = valid && !(buttonMode == .findInFiles && isScanning)
                }
            }
        }
    }

    // MARK: Validation

    private(set) var patternIsValid = true

    /// Regex is checked as it is typed, so an unfinished capture group reports
    /// itself in the status line instead of failing when a button is pressed.
    private func validatePattern() {
        let pattern = findField.stringValue
        guard currentSearchMode == .regex, !pattern.isEmpty else {
            patternIsValid = true
            updateActionAvailability()
            return
        }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            patternIsValid = true
        } catch {
            patternIsValid = false
            showStatus("Invalid pattern — \(cleaned(error))", kind: .error)
        }
        updateActionAvailability()
    }

    private func cleaned(_ error: Error) -> String {
        let text = (error as NSError).localizedDescription
        // Foundation prefixes the useful part with boilerplate.
        return text.replacingOccurrences(of: "The operation couldn’t be completed. ", with: "")
    }

    // MARK: History

    /// Both combo fields keep the session's history, newest first.
    public func setHistory(patterns: [String], replacements: [String]) {
        findField.removeAllItems()
        findField.addItems(withObjectValues: patterns)
        replaceField.removeAllItems()
        replaceField.addItems(withObjectValues: replacements)
    }

    // MARK: Focus

    public func focusSearchField() { window?.makeFirstResponder(findField) }
    public func focusReplaceField() { window?.makeFirstResponder(replaceField) }

    /// What the status line currently reports, so a caller (and a test) can
    /// read the outcome the user sees.
    public var statusMessage: String { statusLine.message }

    public var currentPattern: String { findField.stringValue }
    public var currentOptions: SearchOptions { request.options }

    public func setPattern(_ pattern: String) {
        findField.stringValue = pattern
        validatePattern()
    }

    public func setDirectory(_ url: URL) {
        directoryField.stringValue = url.path
    }

    private var currentSearchMode: SearchMode {
        [.normal, .extended, .regex][max(0, searchMode.selectedSegment)]
    }

    // MARK: Request

    public var request: Request {
        Request(
            pattern: findField.stringValue,
            replacement: replaceField.stringValue,
            options: SearchOptions(
                mode: currentSearchMode,
                matchCase: matchCase.state == .on,
                wholeWord: wholeWord.state == .on,
                wrapAround: wrapAround.state == .on,
                backward: false,
                dotMatchesNewline: dotNewline.state == .on
            ),
            inSelection: inSelection.state == .on,
            directory: directoryField.stringValue.isEmpty
                ? nil : URL(fileURLWithPath: (directoryField.stringValue as NSString).expandingTildeInPath),
            filters: filtersField.stringValue,
            exclusions: exclusionsField.stringValue,
            includeSubfolders: subfolders.state == .on,
            includeHidden: hiddenFolders.state == .on,
            markStyle: MarkStyle(index: markStyles.selectedIndex),
            bookmarkMatchingLines: bookmarkLines.state == .on,
            purgeMarks: purgeMarks.state == .on
        )
    }

    private var backwardRequest: Request {
        let base = request
        var options = base.options
        options.backward = true
        return Request(pattern: base.pattern, replacement: base.replacement,
                       options: options, inSelection: base.inSelection,
                       directory: base.directory, filters: base.filters,
                       exclusions: base.exclusions, includeSubfolders: base.includeSubfolders,
                       includeHidden: base.includeHidden, markStyle: base.markStyle,
                       bookmarkMatchingLines: base.bookmarkMatchingLines, purgeMarks: base.purgeMarks)
    }

    private func notifyPatternChanged() {
        guard patternIsValid else { return }
        onPatternChanged?(request)
    }

    // MARK: Actions

    @objc private func findNext() { onFindNext?(request) }
    @objc private func findPrevious() { onFindPrevious?(backwardRequest) }
    @objc private func count() { onCount?(request) }
    @objc private func replace() { onReplace?(request) }
    @objc private func replaceAll() { onReplaceAll?(request) }
    @objc private func replaceAllInOpenDocuments() { onReplaceAllInOpenDocuments?(request) }
    @objc private func findInFiles() { onFindInFiles?(request) }
    @objc private func replaceInFiles() { onReplaceInFiles?(request) }
    @objc private func cancelScan() { onCancelSearch?() }
    @objc private func markAll() { onMarkAll?(request) }
    @objc private func clearMarks() { onClearMarks?(request) }
    @objc private func copyMarkedText() { onCopyMarkedText?(request) }
    @objc public func findAll() { onFindAll?(request) }

    @objc private func chooseDirectory() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.prompt = "Choose"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        setDirectory(url)
    }
}

extension SearchPanelController: NSComboBoxDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSComboBox) === findField else { return }
        validatePattern()
        if patternIsValid { statusLine.clear() }
        notifyPatternChanged()
    }
}

/// The status line: one row that reports the outcome of a search, coloured and
/// glyphed so the state does not rest on hue alone.
public final class SearchStatusLine: NSView {
    public enum Kind { case neutral, success, warning, error, working }

    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = DS.Font.body()
        label.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [glyph, label])
        row.orientation = .horizontal
        row.spacing = DS.Space.s
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 18),
        ])
        clear()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func clear() {
        label.stringValue = ""
        glyph.image = nil
    }

    public func show(_ message: String, kind: Kind) {
        label.stringValue = message
        label.textColor = colour(for: kind)
        glyph.image = symbol(for: kind)
        setAccessibilityLabel(message)
    }

    public var message: String { label.stringValue }

    private func colour(for kind: Kind) -> NSColor {
        switch kind {
        case .neutral, .working: return DS.Color.textSecondary
        case .success: return DS.Color.success
        case .warning: return DS.Color.warning
        case .error: return DS.Color.error
        }
    }

    /// A glyph as well as a colour, so the outcome is readable without hue.
    private func symbol(for kind: Kind) -> NSImage? {
        switch kind {
        case .neutral: return nil
        case .working: return DS.symbol("clock", pointSize: 11, color: DS.Color.textSecondary)
        case .success: return DS.symbol("checkmark.circle", pointSize: 11, color: DS.Color.success)
        case .warning: return DS.symbol("exclamationmark.triangle", pointSize: 11, color: DS.Color.warning)
        case .error: return DS.symbol("xmark.octagon", pointSize: 11, color: DS.Color.error)
        }
    }
}

/// The five mark styles. Each differs in fill *and* outline so overlapping
/// marks stay distinguishable, and VoiceOver announces "mark style 3" rather
/// than naming a colour.
public final class MarkStylePicker: NSView {
    public private(set) var selectedIndex = 0 { didSet { needsDisplay = true } }
    public var counts: [Int] = Array(repeating: 0, count: 5) { didSet { needsDisplay = true } }

    private let swatch = NSSize(width: 34, height: 20)

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Mark style")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: swatch.width * 5 + DS.Space.s * 4),
            heightAnchor.constraint(equalToConstant: swatch.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    private func rect(for index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * (swatch.width + DS.Space.s), y: 0,
               width: swatch.width, height: swatch.height)
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for index in 0..<5 where rect(for: index).contains(point) {
            selectedIndex = index
            setAccessibilityValue("mark style \(index + 1)")
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let styles = DS.MarkStyleAppearance.styles()
        for index in 0..<5 {
            let box = rect(for: index)
            let style = styles[min(index, styles.count - 1)]
            style.draw(in: box.insetBy(dx: 1, dy: 1))

            if index == selectedIndex {
                DS.Color.brand.setStroke()
                let ring = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: DS.Radius.button, yRadius: DS.Radius.button)
                ring.lineWidth = 2
                ring.stroke()
            }

            if counts.indices.contains(index), counts[index] > 0 {
                let label = "\(counts[index])" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: DS.Font.small(), .foregroundColor: DS.Color.textPrimary,
                ]
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
                           withAttributes: attributes)
            }
        }
    }
}
