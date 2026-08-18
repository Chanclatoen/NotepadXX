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

        let container = NSView()
        for subview in [gutterView!, scrollView!] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        let widthConstraint = gutterView.widthAnchor.constraint(equalToConstant: 44)
        gutterWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
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
        updateGutterWidth()
    }

    /// Sets the language and re-highlights. Passing nil clears highlighting.
    public func setLanguage(_ language: LanguageDefinition?) {
        self.language = language
        if let language {
            let highlighter = SyntaxHighlighter(language: language)
            highlighter.setText(textView.string)
            self.highlighter = highlighter
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
        highlightVisibleRegion()
        gutterView?.needsDisplay = true
    }

    public var fontSize: CGFloat { baseFont.pointSize }

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
        }
        updateGutterWidth()
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
