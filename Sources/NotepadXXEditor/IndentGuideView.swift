import AppKit
import CodeEditTextView
import NotepadXXCore

/// Faint vertical lines at each indent level, as Notepad++ draws them.
///
/// Overlaid on the text rather than drawn by the engine, so toggling it never
/// invalidates layout on a large document. Only the visible lines are measured.
final class IndentGuideView: NSView {
    weak var editor: EditorViewController?
    var colour: NSColor = .separatorColor
    var tabWidth = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Deliberately not layer-backed. A transparent layer retains whatever
        // was drawn on a previous pass, leaving stale guides below the text;
        // an unlayered view is composited fresh each time.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Line positions come from the layout manager in top-down coordinates, so
    /// this view must be flipped too. Without it a guide for line 2 draws near
    /// the bottom of the view instead of the top.
    override var isFlipped: Bool { true }

    /// Clicks must reach the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let editor, editor.showIndentGuides,
              let layoutManager = editor.textView.layoutManager,
              let clipView = editor.textView.enclosingScrollView?.contentView else { return }

        let content = editor.textView.string as NSString
        guard content.length > 0 else { return }

        let font = NSFont.monospacedSystemFont(ofSize: editor.fontSize, weight: .regular)
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        guard advance > 0 else { return }

        let scrollOffset = clipView.bounds.origin.y
        colour.setStroke()

        let lineCount = layoutManager.lineCount
        guard lineCount > 0,
              var position = layoutManager.textLineForPosition(max(0, dirtyRect.minY + scrollOffset))
        else { return }

        while position.yPos - scrollOffset < dirtyRect.maxY {
            // Stop at the end of the document. Walking past it repeats the last
            // line's geometry and paints guides into empty space below the text.
            guard position.index < lineCount else { break }
            let range = NSIntersectionRange(position.range, NSRange(location: 0, length: content.length))
            if range.length > 0 {
                let line = content.substring(with: range)
                let indent = FoldingEngine.indentWidth(of: line, tabWidth: tabWidth)
                // A guide per indent step, skipping column 0.
                var column = tabWidth
                while column <= indent {
                    let x = advance * CGFloat(column)
                    if x < bounds.width {
                        let path = NSBezierPath()
                        let y = position.yPos - scrollOffset
                        path.move(to: NSPoint(x: x + 0.5, y: y))
                        path.line(to: NSPoint(x: x + 0.5, y: y + position.height))
                        path.lineWidth = 1
                        path.stroke()
                    }
                    column += tabWidth
                }
            }
            guard position.index + 1 < lineCount,
                  let next = layoutManager.textLineForIndex(position.index + 1),
                  next.yPos > position.yPos else { break }
            position = next
        }
    }
}
