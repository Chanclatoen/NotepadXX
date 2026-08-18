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
        onTextChange?(textView.string)
    }

    public func textViewDidChangeSelection(_ textView: TextView) {
        onSelectionChange?(selectedRange)
    }
}
