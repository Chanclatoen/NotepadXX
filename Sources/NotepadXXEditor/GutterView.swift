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
    /// Fold regions, so the margin can draw expand/collapse boxes.
    public var foldStartLines: Set<Int> = [] { didSet { needsDisplay = true } }
    public var collapsedFoldLines: Set<Int> = [] { didSet { needsDisplay = true } }
    public var showFoldMargin = true { didSet { needsDisplay = true } }
    /// Called when a fold box is clicked.
    public var onToggleFold: ((Int) -> Void)?

    /// 0-based lines edited earlier this session and since saved.
    public var savedChangedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    public var showChangeHistory = true { didSet { needsDisplay = true } }
    public var currentLine: Int = 0 { didSet { needsDisplay = true } }

    private let horizontalPadding: CGFloat = 8
    private let markerWidth: CGFloat = 10
    private let foldMarginWidth: CGFloat = 14

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
        return width + horizontalPadding * 2 + markerWidth + (showFoldMargin ? foldMarginWidth : 0)
    }

    /// Clicking a fold box toggles that region.
    public override func mouseDown(with event: NSEvent) {
        guard showFoldMargin, let textView, let layoutManager = textView.layoutManager,
              let clipView = textView.enclosingScrollView?.contentView else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard point.x >= bounds.width - foldMarginWidth else { return }

        let documentY = point.y + clipView.bounds.origin.y
        guard let position = layoutManager.textLineForPosition(max(0, documentY)) else { return }
        if foldStartLines.contains(position.index) { onToggleFold?(position.index) }
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

            if showChangeHistory {
                // Unsaved edits are amber, saved-this-session edits green, so
                // the margin distinguishes "not on disk" from "I touched this".
                if changedLines.contains(index) {
                    NSColor.systemOrange.withAlphaComponent(0.85).setFill()
                    NSRect(x: 0, y: y, width: 3, height: height).fill()
                } else if savedChangedLines.contains(index) {
                    NSColor.systemGreen.withAlphaComponent(0.7).setFill()
                    NSRect(x: 0, y: y, width: 3, height: height).fill()
                }
            }
            if showBookmarks && bookmarkedLines.contains(index) {
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: 4, y: y + height / 2 - 3, width: 6, height: 6)).fill()
            }
            if showLineNumbers {
                attributes[.foregroundColor] = (index == currentLine) ? currentLineColor : textColor
                let label = String(index + 1) as NSString
                let size = label.size(withAttributes: attributes)
                let numberRight = bounds.width - horizontalPadding - (showFoldMargin ? foldMarginWidth : 0)
                label.draw(
                    at: NSPoint(x: numberRight - size.width, y: y + (height - size.height) / 2),
                    withAttributes: attributes
                )
            }

            // Fold box: a square with a minus when open, a plus when collapsed,
            // matching Notepad++'s default fold margin.
            if showFoldMargin, foldStartLines.contains(index) {
                let boxSize: CGFloat = 9
                let box = NSRect(
                    x: bounds.width - foldMarginWidth + (foldMarginWidth - boxSize) / 2,
                    y: y + (height - boxSize) / 2,
                    width: boxSize, height: boxSize
                )
                NSColor.textBackgroundColor.setFill()
                box.fill()
                textColor.setStroke()
                NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)).stroke()

                let path = NSBezierPath()
                let midY = box.midY
                path.move(to: NSPoint(x: box.minX + 2, y: midY))
                path.line(to: NSPoint(x: box.maxX - 2, y: midY))
                if collapsedFoldLines.contains(index) {
                    let midX = box.midX
                    path.move(to: NSPoint(x: midX, y: box.minY + 2))
                    path.line(to: NSPoint(x: midX, y: box.maxY - 2))
                }
                path.lineWidth = 1
                textColor.setStroke()
                path.stroke()
            }

            guard let next = layoutManager.textLineForIndex(index + 1) else { break }
            position = next
        }
    }
}
