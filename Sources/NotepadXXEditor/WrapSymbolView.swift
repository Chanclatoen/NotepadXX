import AppKit
import CodeEditTextView

/// Draws Notepad++'s wrap symbol: a return arrow at the end of every visual
/// line that was soft-broken by word wrap.
///
/// Only soft breaks are marked. A real line ending is not a wrap, and marking
/// it would say the opposite of what happened. Like the other overlays this
/// sits above the scroll view rather than inside it, so toggling it never
/// invalidates layout on a large document.
final class WrapSymbolView: NSView {
    weak var editor: EditorViewController?
    var colour: NSColor = .tertiaryLabelColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Line positions arrive top-down from the layout manager.
    override var isFlipped: Bool { true }

    /// Clicks must reach the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let editor, editor.showWrapSymbol,
              let layoutManager = editor.textView.layoutManager,
              let clipView = editor.textView.enclosingScrollView?.contentView else { return }
        // With wrapping off no line is ever soft-broken, so there is nothing to
        // mark; drawing anything here would be a symbol for something else.
        guard editor.wrapLines else { return }

        let scrollOffset = clipView.bounds.origin.y
        let symbol = "↵" as NSString
        let font = NSFont.monospacedSystemFont(ofSize: max(8, editor.fontSize - 2), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = symbol.size(withAttributes: attributes)

        let lineCount = layoutManager.lineCount
        guard lineCount > 0,
              var position = layoutManager.textLineForPosition(max(0, dirtyRect.minY + scrollOffset))
        else { return }

        while position.yPos - scrollOffset < dirtyRect.maxY {
            guard position.index < lineCount else { break }

            // A line laid out as several fragments was wrapped; each fragment
            // except the last ends at a soft break.
            let fragments = position.data.lineFragments
            if fragments.count > 1 {
                var fragmentTop = position.yPos - scrollOffset
                for (offset, fragment) in fragments.enumerated() {
                    defer { fragmentTop += fragment.height }
                    guard offset < fragments.count - 1 else { continue }
                    let x = fragment.data.width + 2
                    symbol.draw(at: NSPoint(x: x, y: fragmentTop + (fragment.height - size.height) / 2),
                                withAttributes: attributes)
                }
            }

            guard let next = layoutManager.textLineForIndex(position.index + 1) else { break }
            position = next
        }
    }
}
