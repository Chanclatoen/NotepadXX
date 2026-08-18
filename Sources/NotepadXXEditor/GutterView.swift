import AppKit
import CodeEditTextView

/// The margin to the left of the text: line numbers, bookmarks and the change
/// history stripe.
///
/// Only the lines actually on screen are drawn. Drawing all of them would undo
/// the virtualisation that lets a 900k-line file open instantly.
public final class GutterView: NSView {
    public weak var textView: TextView?

    public var showLineNumbers = true { didSet { needsDisplay = true } }
    public var showBookmarks = true { didSet { needsDisplay = true } }
    public var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    public var textColor: NSColor = .tertiaryLabelColor
    public var currentLineColor: NSColor = .labelColor
    public var backgroundColor: NSColor = .windowBackgroundColor

    /// 0-based bookmarked lines.
    public var bookmarkedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    /// 0-based lines edited since the last save.
    public var changedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    public var currentLine: Int = 0 { didSet { needsDisplay = true } }

    private let horizontalPadding: CGFloat = 8
    private let markerWidth: CGFloat = 10

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Width needed for the widest line number in the document.
    public func requiredWidth() -> CGFloat {
        guard showLineNumbers, let textView else { return markerWidth + horizontalPadding }
        let digits = max(2, String(max(1, textView.layoutManager.lineCount)).count)
        let sample = String(repeating: "0", count: digits)
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        return width + horizontalPadding * 2 + markerWidth
    }

    public override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
        guard let textView, let layoutManager = textView.layoutManager,
              let clipView = textView.enclosingScrollView?.contentView else { return }

        // The gutter is outside the scroll view, so translate our rect into the
        // text view's coordinates by the current scroll offset.
        let scrollOffset = clipView.bounds.origin.y
        let visible = NSRect(x: 0, y: dirtyRect.minY + scrollOffset,
                             width: 1, height: dirtyRect.height)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        guard var position = layoutManager.textLineForPosition(max(0, visible.minY)) else { return }
        while position.yPos < visible.maxY {
            let index = position.index
            let y = position.yPos - scrollOffset
            let height = position.height

            if changedLines.contains(index) {
                NSColor.systemYellow.withAlphaComponent(0.7).setFill()
                NSRect(x: 0, y: y, width: 3, height: height).fill()
            }
            if showBookmarks && bookmarkedLines.contains(index) {
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: 4, y: y + height / 2 - 3, width: 6, height: 6)).fill()
            }
            if showLineNumbers {
                attributes[.foregroundColor] = (index == currentLine) ? currentLineColor : textColor
                let label = String(index + 1) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(x: bounds.width - size.width - horizontalPadding,
                                y: y + (height - size.height) / 2),
                    withAttributes: attributes
                )
            }

            guard let next = layoutManager.textLineForIndex(index + 1) else { break }
            position = next
        }
    }
}
