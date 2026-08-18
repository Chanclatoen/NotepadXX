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

    /// Called whenever the buffer changes, so the document and status bar update.
    public var onTextChange: ((String) -> Void)?
    /// Called when the caret or selection moves.
    public var onSelectionChange: ((NSRange) -> Void)?

    private var wrapLines: Bool

    /// Syntax highlighting. Nil language means plain text.
    private var highlighter: SyntaxHighlighter?
    public var theme: SyntaxTheme = .system
    public private(set) var language: LanguageDefinition?
    private var baseFont: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

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
        view = scrollView
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

    /// 1-based line and column for the caret, for the status bar.
    public func caretPosition() -> (line: Int, column: Int) {
        let location = selectedRange.location
        let content = textView.string as NSString
        guard location <= content.length else { return (1, 1) }
        var line = 1
        var lineStart = 0
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: location),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosing, _ in
            line += 1
            lineStart = NSMaxRange(enclosing)
        }
        return (line, location - lineStart + 1)
    }
}

extension EditorViewController: @preconcurrency TextViewDelegate {
    public func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        if let highlighter {
            let editedLine = highlighter.line(containing: min(range.location, max(0, textView.string.utf16.count - 1)))
            highlighter.textDidChange(textView.string, editedLine: editedLine)
            highlightVisibleRegion()
        }
        onTextChange?(textView.string)
    }

    public func textViewDidChangeSelection(_ textView: TextView) {
        onSelectionChange?(selectedRange)
    }
}
