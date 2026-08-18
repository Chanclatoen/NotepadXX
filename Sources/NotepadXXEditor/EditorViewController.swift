import AppKit
import CodeEditTextView
import NotepadXXCore

/// Hosts the text engine for a single document.
///
/// **Performance contract.** The `TextView` is always created *empty* and
/// installed in a sized scroll view before any content is assigned. Constructing
/// it with a populated string lays out every line in the document at once — one
/// NSView per line through an O(n) AppKit z-order scan — which is quadratic and
/// takes over a minute on a 100k-line file. Loading via `setText` after the view
/// is in the hierarchy keeps layout virtualised to the viewport. See
/// docs/ARCHITECTURE.md. Do not add an initialiser that takes text.
public final class EditorViewController: NSViewController {
    public private(set) var textView: TextView!
    public private(set) var scrollView: NSScrollView!
    public private(set) var gutterView: GutterView!
    private var gutterWidthConstraint: NSLayoutConstraint?

    /// Called whenever the buffer changes, so the document and status bar update.
    public var onTextChange: ((String) -> Void)?
    /// Called when the caret or selection moves.
    public var onSelectionChange: ((NSRange) -> Void)?

    private var wrapLines: Bool

    /// Syntax highlighting. Nil language means plain text.
    private var highlighter: SyntaxHighlighter?
    public var theme: SyntaxTheme = .system

    /// Applies a stored `EditorTheme`, converting its hex colours.
    public func applyTheme(_ editorTheme: EditorTheme) {
        func color(_ hex: String?) -> NSColor? {
            guard let hex, let rgb = HexColor.components(hex) else { return nil }
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        var colors: [TokenType: NSColor] = [:]
        for token in TokenType.allCases {
            if let value = color(editorTheme.color(for: token)) { colors[token] = value }
        }
        theme = SyntaxTheme(
            colors: colors,
            italicTokens: Set(editorTheme.italicTokens.compactMap(TokenType.init(rawValue:))),
            boldTokens: Set(editorTheme.boldTokens.compactMap(TokenType.init(rawValue:))),
            plainColor: color(editorTheme.foreground) ?? .labelColor,
            backgroundColor: color(editorTheme.background) ?? .textBackgroundColor
        )
        // TextView draws through its layer; the scroll view owns the backdrop.
        scrollView.backgroundColor = theme.backgroundColor
        textView.layer?.backgroundColor = theme.backgroundColor.cgColor
        gutterView?.textColor = color(editorTheme.gutterForeground) ?? .tertiaryLabelColor
        gutterView?.backgroundColor = theme.backgroundColor
        gutterView?.needsDisplay = true
        highlightVisibleRegion()
    }
    public private(set) var language: LanguageDefinition?
    private var baseFont: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    /// Whitespace / tab / EOL rendering.
    public let invisibles = InvisibleCharacterRenderer()
    /// Highlights every other occurrence of the word under the caret.
    public var smartHighlightEnabled = true
    /// Highlights the bracket partnering the one at the caret.
    public var braceMatchingEnabled = true
    public var showsCurrentLineHighlight = true
    /// Column for the vertical edge guide; 0 disables it.
    public var edgeColumn = 0 { didSet { edgeGuideView?.column = edgeColumn } }
    /// Cmd-click opens links, as in Notepad++'s clickable URLs.
    public var clickableURLs = true
    /// Vertical guides at each indent level.
    public var showIndentGuides = true {
        didSet {
            indentGuideView?.isHidden = !showIndentGuides
            indentGuideView?.needsDisplay = true
        }
    }
    private var indentGuideView: IndentGuideView?

    // MARK: - Autocomplete
    public let completionPopup = CompletionPopup()
    public var autoCompleteEnabled = true
    public var autoCompleteMinimumCharacters = 3
    public var autoCompleteFromWords = true
    public var autoCompleteFromKeywords = true
    public var pathCompletionEnabled = true
    public var showCallTips = true
    /// API entries for the current language, supplied by the window controller.
    public var completionEntries: [CompletionEntry] = []

    /// Reports every text insertion so a macro can record it.
    public var onTextInserted: ((String) -> Void)?
    /// Called when a fold box in the gutter is clicked.
    public var onToggleFold: ((Int) -> Void)?

    /// Every caret or selection currently active.
    public var selectedRanges: [NSRange] {
        get { textView.selectionManager.textSelections.map(\.range) }
        set { textView.selectionManager.setSelectedRanges(Occurrences.normalized(newValue)) }
    }

    /// Adds a caret without disturbing the existing ones.
    public func addCaret(at offset: Int) {
        let length = (textView.string as NSString).length
        let clamped = min(max(0, offset), length)
        // A second caret in the same place would double every keystroke.
        guard !selectedRanges.contains(where: { $0.location == clamped && $0.length == 0 }) else { return }
        selectedRanges = selectedRanges + [NSRange(location: clamped, length: 0)]
    }

    /// Collapses a multi-selection back to a single caret at the first one.
    public func collapseToSingleCaret() {
        guard let first = selectedRanges.min(by: { $0.location < $1.location }) else { return }
        textView.selectionManager.setSelectedRange(NSRange(location: first.location, length: first.length))
    }

    /// Selects the next occurrence of the current selection, adding a caret.
    /// With nothing selected, selects the word under the caret first — the
    /// behaviour every editor with this feature shares.
    @discardableResult
    public func selectNextOccurrence() -> Bool {
        let existing = selectedRanges
        guard let last = existing.max(by: { $0.location < $1.location }) else { return false }

        let needle: String
        if last.length > 0 {
            needle = (textView.string as NSString).substring(with: last)
        } else {
            guard let word = Occurrences.word(at: last.location, in: textView.string) else { return false }
            // First press just selects the word under the caret.
            selectedRanges = existing.filter { $0 != last } + [word.range]
            return true
        }

        guard let next = Occurrences.next(of: needle, in: textView.string, after: last.location),
              !existing.contains(next) else { return false }
        selectedRanges = existing + [next]
        textView.scrollToVisible(textView.layoutManager.rectForOffset(next.location) ?? .zero)
        return true
    }

    /// Puts a caret on every occurrence of the current selection or word.
    @discardableResult
    public func selectAllOccurrences() -> Bool {
        guard let current = selectedRanges.first else { return false }
        let needle: String
        let wholeWord: Bool
        if current.length > 0 {
            needle = (textView.string as NSString).substring(with: current)
            wholeWord = false
        } else {
            guard let word = Occurrences.word(at: current.location, in: textView.string) else { return false }
            needle = word.text
            wholeWord = true
        }

        let matches = Occurrences.all(of: needle, in: textView.string, wholeWord: wholeWord)
        guard !matches.isEmpty else { return false }
        selectedRanges = matches
        return true
    }

    /// Removes the most recently added caret.
    @discardableResult
    public func removeLastCaret() -> Bool {
        let ranges = selectedRanges
        guard ranges.count > 1 else { return false }
        selectedRanges = Array(ranges.dropLast())
        return true
    }

    /// Highlights marked ranges, one list per Mark style.
    ///
    /// Emphases are keyed per style so clearing one style does not disturb the
    /// others, and marks are inactive so they never move the caret.
    public func applyMarks(_ rangesByStyle: [[NSRange]]) {
        guard let manager = textView.emphasisManager else { return }
        for (index, ranges) in rangesByStyle.enumerated() {
            let id = "mark\(index)"
            manager.removeEmphases(for: id)
            guard !ranges.isEmpty else { continue }
            manager.addEmphases(
                ranges.map { Emphasis(range: $0, style: .standard, inactive: true) }, for: id
            )
        }
    }

    /// Scrolls a range into view, used by incremental search.
    public func scrollRangeToVisible(_ range: NSRange) {
        guard let rect = textView.layoutManager.rectForOffset(range.location) else { return }
        textView.scrollToVisible(rect)
    }

    /// The document offset under a point in the text view, for modifier-click.
    public func offset(at pointInWindow: NSPoint) -> Int? {
        let local = textView.convert(pointInWindow, from: nil)
        return textView.layoutManager.textOffsetAtPoint(local)
    }
    /// Lines changed since load/save, drawn in the gutter.
    public private(set) var changeHistory = ChangeHistory()
    private var edgeGuideView: EdgeGuideView?

    public init(wrapLines: Bool = false) {
        self.wrapLines = wrapLines
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wrapLines
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        // Empty on purpose — see the performance contract above.
        textView = TextView(string: "", wrapLines: wrapLines)
        textView.delegate = self
        scrollView.documentView = textView

        // The gutter is a sibling pinned to the left of the scroll view rather
        // than an NSRulerView: the ruler machinery assumes an NSTextView-shaped
        // client and stops CodeEditTextView from drawing.
        textView.layoutManager.invisibleCharacterDelegate = invisibles

        gutterView = GutterView()
        gutterView.textView = textView
        gutterView.onToggleFold = { [weak self] line in self?.onToggleFold?(line) }

        completionPopup.onCommit = { [weak self] text in self?.insertCompletion(text) }

        let container = NSView()
        for subview in [gutterView!, scrollView!] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        let widthConstraint = gutterView.widthAnchor.constraint(equalToConstant: 44)
        // The edge guide overlays the text. It goes in the container rather
        // than inside the scroll view: NSScrollView retiles its own subviews
        // and paints over anything foreign added to it.
        let guideView = EdgeGuideView()
        guideView.column = edgeColumn
        guideView.font = baseFont
        guideView.translatesAutoresizingMaskIntoConstraints = false
        edgeGuideView = guideView
        container.addSubview(guideView, positioned: .above, relativeTo: scrollView)

        let indentView = IndentGuideView()
        indentView.editor = self
        indentView.translatesAutoresizingMaskIntoConstraints = false
        indentGuideView = indentView
        container.addSubview(indentView, positioned: .above, relativeTo: scrollView)

        gutterWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            guideView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            guideView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            guideView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            guideView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            indentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            indentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            indentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            indentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            gutterView.topAnchor.constraint(equalTo: container.topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutterView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            widthConstraint,

            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Redraw line numbers as the text scrolls under them.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewportChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        view = container
    }

    @objc private func viewportChanged() {
        gutterView?.needsDisplay = true
        indentGuideView?.needsDisplay = true
        highlightVisibleRegion()
    }

    /// Resizes the gutter when the line count gains a digit.
    private func updateGutterWidth() {
        guard let gutterView, let constraint = gutterWidthConstraint else { return }
        let width = gutterView.requiredWidth()
        if abs(constraint.constant - width) > 0.5 { constraint.constant = width }
        gutterView.needsDisplay = true
    }

    /// Replaces the buffer. Safe for very large documents.
    public func load(text: String) {
        loadViewIfNeeded()
        // Ensure the view has a real size before content arrives, so the layout
        // manager only materialises the visible viewport.
        if textView.frame.width == 0 {
            textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        }
        textView.setText(text)
        highlighter?.setText(text)
        highlightVisibleRegion()
        refreshFoldMarkers()
        updateGutterWidth()
    }

    /// Sets the language and re-highlights. Passing nil clears highlighting.
    public func setLanguage(_ language: LanguageDefinition?) {
        self.language = language
        if let language {
            let highlighter = SyntaxHighlighter(language: language)
            highlighter.setText(textView.string)
            self.highlighter = highlighter
            refreshFoldMarkers()
        } else {
            self.highlighter = nil
            clearHighlighting()
        }
        highlightVisibleRegion()
    }

    private func clearHighlighting() {
        guard let storage = textView.textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.foregroundColor: theme.plainColor, .font: baseFont], range: whole)
        storage.endEditing()
    }

    /// Highlights the lines currently on screen (plus a margin), which is what
    /// keeps highlighting affordable on very large documents.
    public func highlightVisibleRegion() {
        guard let highlighter, let storage = textView.textStorage, storage.length > 0 else { return }

        let visible = scrollView.documentVisibleRect
        let startOffset = textView.layoutManager.textOffsetAtPoint(
            CGPoint(x: 0, y: max(0, visible.minY))
        ) ?? 0
        let endOffset = textView.layoutManager.textOffsetAtPoint(
            CGPoint(x: 0, y: visible.maxY)
        ) ?? storage.length

        let margin = 200   // lines of slack so scrolling stays smooth
        let firstLine = max(0, highlighter.line(containing: min(startOffset, storage.length)) - margin)
        let lastLine = min(highlighter.lineCount - 1,
                           highlighter.line(containing: min(endOffset, max(0, storage.length - 1))) + margin)
        guard firstLine <= lastLine else { return }

        let tokens = highlighter.tokens(forLines: firstLine...lastLine)
        let regionStart = min(startOffset, storage.length)
        let regionEnd = min(max(endOffset, regionStart), storage.length)
        let region = NSRange(location: regionStart, length: regionEnd - regionStart)

        storage.beginEditing()
        storage.setAttributes([.foregroundColor: theme.plainColor, .font: baseFont], range: region)
        for token in tokens {
            let clamped = NSIntersectionRange(token.range, NSRange(location: 0, length: storage.length))
            guard clamped.length > 0 else { continue }
            storage.setAttributes(theme.attributes(for: token.type, baseFont: baseFont), range: clamped)
        }
        storage.endEditing()
    }

    public var text: String { textView.string }

    public var selectedRange: NSRange {
        get { textView.selectionManager.textSelections.first?.range ?? NSRange(location: 0, length: 0) }
        set { textView.selectionManager.setSelectedRange(newValue) }
    }

    /// Applies View > Show Symbol options and repaints.
    public func setInvisibles(spaces: Bool, tabs: Bool, lineEndings: Bool) {
        invisibles.showSpaces = spaces
        invisibles.showTabs = tabs
        invisibles.showLineEndings = lineEndings
        invisibles.optionsChanged()
        // The engine caches per-character styles; force a re-layout so the
        // change is visible immediately rather than on the next edit.
        textView.layoutManager.invalidateLayoutForRect(textView.visibleRect)
        textView.needsDisplay = true
    }

    /// Zoom, as Notepad++'s View > Zoom In/Out/Restore.
    public func setFontSize(_ size: CGFloat) {
        let clamped = min(max(6, size), 96)
        baseFont = NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
        invisibles.font = baseFont
        textView.font = baseFont
        edgeGuideView?.font = baseFont

        // Re-apply the font to the text that already exists. Setting
        // textView.font only changes the typing attributes; every character
        // already in the storage carries its own .font attribute written by
        // the highlighter, so without this the document keeps the old size.
        if let storage = textView.textStorage, storage.length > 0 {
            let whole = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.font, value: baseFont, range: whole)
            storage.endEditing()
            // Line heights are cached per line; invalidating the range forces
            // them to be measured again, which is what actually moves the text.
            textView.layoutManager.invalidateLayoutForRange(whole)
        }
        textView.layoutManager.setNeedsLayout()
        textView.layoutManager.layoutLines()
        _ = textView.updateFrameIfNeeded()

        // The gutter scales with the text, as Notepad++'s line numbers do.
        gutterView?.font = .monospacedDigitSystemFont(ofSize: max(8, clamped - 1), weight: .regular)
        updateGutterWidth()
        highlightVisibleRegion()
        indentGuideView?.needsDisplay = true
        gutterView?.needsDisplay = true
    }

    public var fontSize: CGFloat { baseFont.pointSize }

    /// Read-only tabs reject edits, matching Notepad++'s per-tab read-only flag
    /// (which is independent of the file's permissions on disk).
    public var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    /// Shows or updates the completion list as the user types.
    ///
    /// Only plain typing triggers it — a paste or a programmatic edit should
    /// not pop a list open, which is why the inserted string is checked.
    func updateCompletions(afterInserting inserted: String) {
        guard autoCompleteEnabled else { completionPopup.hide(); return }
        guard inserted.count == 1, let character = inserted.first else {
            completionPopup.hide()
            return
        }

        let location = selectedRange.location
        // Path completion takes over inside a path-like token.
        if pathCompletionEnabled, character == "/" || character == "~" {
            presentCompletions(AutoCompletion.pathSuggestions(in: textView.string, at: location))
            return
        }
        guard character.isLetter || character.isNumber || character == "_" else {
            completionPopup.hide()
            return
        }

        let prefix = AutoCompletion.currentPrefix(in: textView.string, at: location)
        guard prefix.count >= autoCompleteMinimumCharacters else {
            completionPopup.hide()
            return
        }
        presentCompletions(AutoCompletion.suggestions(
            in: textView.string, at: location, language: language,
            includeWords: autoCompleteFromWords, includeKeywords: autoCompleteFromKeywords,
            apiEntries: showCallTips ? completionEntries : []
        ))
    }

    private func presentCompletions(_ items: [CompletionItem]) {
        guard !items.isEmpty else { completionPopup.hide(); return }
        let caret = textView.layoutManager.rectForOffset(selectedRange.location)
            ?? NSRect(x: 0, y: 0, width: 1, height: 16)
        completionPopup.show(items: items, below: caret, in: textView)
    }

    /// Replaces the partially typed word with the chosen completion.
    func insertCompletion(_ text: String) {
        let location = selectedRange.location
        let prefix = AutoCompletion.currentPrefix(in: textView.string, at: location)
        let start = location - (prefix as NSString).length
        guard start >= 0 else { return }
        textView.replaceCharacters(in: NSRange(location: start, length: (prefix as NSString).length),
                                   with: text)
    }

    /// Recomputes fold regions for the gutter's fold boxes.
    public func refreshFoldMarkers() {
        guard let language else {
            gutterView?.foldStartLines = []
            return
        }
        // Only worth computing for documents small enough that folding is
        // useful; a million-line log does not need fold boxes.
        let text = textView.string
        guard (text as NSString).length < 2_000_000 else {
            gutterView?.foldStartLines = []
            return
        }
        let folds = FoldingEngine.folds(in: text, language: language)
        gutterView?.foldStartLines = Set(folds.map(\.start))
    }

    /// Called after the document is written to disk: modified marks become
    /// saved marks.
    public func documentDidSave() {
        changeHistory.didSave()
        gutterView?.changedLines = changeHistory.modifiedLines
        gutterView?.savedChangedLines = changeHistory.savedLines
    }

    public func resetChangeHistory() {
        changeHistory.reset()
        gutterView?.changedLines = []
        gutterView?.savedChangedLines = []
    }

    /// Opens the link under the caret, if any. Returns false when there is none.
    @discardableResult
    public func openLinkAtCaret() -> Bool {
        guard clickableURLs,
              let url = URLDetection.link(at: selectedRange.location, in: textView.string) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// The 0-based line range currently on screen, for the Document Map.
    public func visibleLineRange() -> ClosedRange<Int> {
        guard let highlighter else { return 0...0 }
        let visible = scrollView.documentVisibleRect
        let length = (textView.string as NSString).length
        let start = textView.layoutManager.textOffsetAtPoint(CGPoint(x: 0, y: max(0, visible.minY))) ?? 0
        let end = textView.layoutManager.textOffsetAtPoint(CGPoint(x: 0, y: visible.maxY)) ?? length
        let first = highlighter.line(containing: min(start, length))
        let last = highlighter.line(containing: min(max(end, start), length))
        return first...max(first, last)
    }

    /// Emphasises the bracket matching the one at the caret, and every other
    /// occurrence of the word under the caret.
    func updateContextualEmphasis() {
        guard let manager = textView.emphasisManager else { return }
        manager.removeEmphases(for: "braceMatch")
        manager.removeEmphases(for: "smartHighlight")

        let content = textView.string as NSString
        let caret = selectedRange

        if braceMatchingEnabled, caret.length == 0 {
            // Check the character on either side of the caret, as editors do.
            for probe in [caret.location, caret.location - 1] where probe >= 0 && probe < content.length {
                if let partner = BraceMatching.match(in: textView.string, at: probe, language: language) {
                    manager.addEmphases([
                        Emphasis(range: NSRange(location: probe, length: 1), style: .outline(color: .systemTeal)),
                        Emphasis(range: NSRange(location: partner, length: 1), style: .outline(color: .systemTeal)),
                    ], for: "braceMatch")
                    break
                }
            }
        }

        if smartHighlightEnabled {
            let word = caret.length > 0
                ? content.substring(with: caret)
                : AutoCompletion.currentPrefix(in: textView.string, at: caret.location)
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only highlight real identifiers, and never the whole document.
            if trimmed.count >= 2, trimmed.count <= 80,
               trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                var emphases: [Emphasis] = []
                var searchRange = NSRange(location: 0, length: content.length)
                while searchRange.length > 0 {
                    let found = content.range(of: trimmed, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }
                    if found != caret { emphases.append(Emphasis(range: found, style: .standard, inactive: true)) }
                    let next = NSMaxRange(found)
                    searchRange = NSRange(location: next, length: max(0, content.length - next))
                    if emphases.count > 500 { break }   // guard on huge documents
                }
                if !emphases.isEmpty { manager.addEmphases(emphases, for: "smartHighlight") }
            }
        }
    }

    public func setWrapLines(_ wrap: Bool) {
        guard wrap != wrapLines else { return }
        wrapLines = wrap
        textView.wrapLines = wrap
        scrollView.hasHorizontalScroller = !wrap
    }

    /// The 0-based inclusive line range covered by the current selection.
    /// A caret with no selection yields the single line it sits on.
    public func selectedLineRange() -> ClosedRange<Int> {
        let content = textView.string as NSString
        let selection = selectedRange
        let firstLine = lineIndex(at: selection.location, in: content)
        let lastLocation = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let lastLine = lineIndex(at: max(lastLocation, selection.location), in: content)
        return firstLine...max(firstLine, lastLine)
    }

    private func lineIndex(at location: Int, in content: NSString) -> Int {
        guard location > 0 else { return 0 }
        var index = 0
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: min(location, content.length)),
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in index += 1 }
        return index
    }

    /// Replaces the whole buffer, preserving the caret position where possible.
    public func replaceAll(with newText: String) {
        let caret = selectedRange.location
        textView.setText(newText)
        let clamped = min(caret, (newText as NSString).length)
        selectedRange = NSRange(location: clamped, length: 0)
        onTextChange?(newText)
    }

    /// Replaces just the selected range.
    public func replaceSelection(with replacement: String) {
        let selection = selectedRange
        textView.replaceCharacters(in: selection, with: replacement)
        onTextChange?(textView.string)
    }

    /// Moves the caret to the start of a 1-based line and scrolls it into view.
    public func goToLine(_ line: Int) {
        let content = textView.string as NSString
        var starts: [Int] = [0]
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: content.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosing, _ in starts.append(NSMaxRange(enclosing)) }
        let index = min(max(0, line - 1), max(0, starts.count - 1))
        let location = starts[index]
        selectedRange = NSRange(location: min(location, content.length), length: 0)
        textView.scrollToVisible(NSRect(origin: .zero, size: .zero))
        textView.scrollSelectionToVisible()
    }

    /// Moves the caret to a 1-based column on a 1-based line, clamped to the
    /// line's length so an out-of-range column lands at the end rather than
    /// spilling onto the next line.
    public func moveToColumn(_ column: Int, onLine line: Int) {
        goToLine(line)
        let content = textView.string as NSString
        let lineStart = selectedRange.location
        var lineEnd = lineStart
        while lineEnd < content.length,
              content.substring(with: NSRange(location: lineEnd, length: 1)) != "\n" {
            lineEnd += 1
        }
        let target = min(lineStart + max(0, column - 1), lineEnd)
        selectedRange = NSRange(location: target, length: 0)
    }

    /// 1-based line and column for the caret, for the status bar.
    ///
    /// Counts line terminators before the caret rather than enumerating
    /// substrings: enumeration reports a trailing partial line even when no
    /// newline was crossed, which put the caret one line too far whenever it sat
    /// at the end of a line.
    public func caretPosition() -> (line: Int, column: Int) {
        let content = textView.string as NSString
        let location = min(max(0, selectedRange.location), content.length)
        guard location > 0 else { return (1, 1) }

        var line = 1
        var lineStart = 0
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: location),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosing, _ in
            let end = NSMaxRange(enclosing)
            // Only count a line when the enclosing range actually consumed a
            // terminator, i.e. it extends past the substring itself.
            if end <= location, end > lineStart, self.endsWithNewline(content, enclosing) {
                line += 1
                lineStart = end
            }
        }
        return (line, location - lineStart + 1)
    }

    private func endsWithNewline(_ content: NSString, _ range: NSRange) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= content.length else { return false }
        let last = content.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1))
        return last == "\n" || last == "\r"
    }

}

extension EditorViewController: @preconcurrency TextViewDelegate {
    public func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        if let highlighter {
            let editedLine = highlighter.line(containing: min(range.location, max(0, textView.string.utf16.count - 1)))
            highlighter.textDidChange(textView.string, editedLine: editedLine)
            highlightVisibleRegion()

            // A replacement spanning newlines shifts every mark below it.
            let removedLines = range.length > 0 ? 0 : 0
            let addedLines = string.filter { $0 == "\n" }.count
            if addedLines != removedLines {
                changeHistory.shift(fromLine: editedLine + 1, by: addedLines - removedLines)
            }
            changeHistory.recordEdit(inLines: editedLine...(editedLine + addedLines))
            gutterView?.changedLines = changeHistory.modifiedLines
            gutterView?.savedChangedLines = changeHistory.savedLines
        }
        updateGutterWidth()
        refreshFoldMarkers()
        if !string.isEmpty { onTextInserted?(string) }
        updateCompletions(afterInserting: string)
        onTextChange?(textView.string)
    }

    public func textViewDidChangeSelection(_ textView: TextView) {
        // Keep the current-line highlight in the gutter in step with the caret.
        if let highlighter {
            gutterView?.currentLine = highlighter.line(containing: selectedRange.location)
        }
        updateContextualEmphasis()
        onSelectionChange?(selectedRange)
    }
}
