import AppKit
import CodeEditTextView
import NotepadXXDesign

/// The margin to the left of the text: bookmarks, line numbers, the change
/// history bar and the folding lane.
///
/// The four lanes have fixed widths, so toggling one never reflows the code.
/// The gutter shares the editor's background rather than reading as a panel.
///
/// Only the lines actually on screen are drawn. Drawing all of them would undo
/// the virtualisation that lets a 900k-line file open instantly.
public final class GutterView: NSView {
    public weak var textView: TextView?

    public var showLineNumbers = true { didSet { needsDisplay = true } }
    public var showBookmarks = true { didSet { needsDisplay = true } }
    public var font: NSFont = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    public var textColor: NSColor = DS.Color.gutterText
    public var currentLineColor: NSColor = DS.Color.gutterTextCurrent
    public var backgroundColor: NSColor = DS.Color.gutterBackground

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
    /// Called when the bookmark lane is clicked, as in Notepad++.
    public var onToggleBookmark: ((Int) -> Void)?

    /// 0-based lines edited earlier this session and since saved.
    public var savedChangedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    public var showChangeHistory = true { didSet { needsDisplay = true } }
    public var currentLine: Int = 0 { didSet { needsDisplay = true } }

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Lanes

    /// The four lanes, left to right. A hidden lane has zero width so the lanes
    /// beside it keep their own.
    private var bookmarkLaneWidth: CGFloat { showBookmarks ? DS.Metric.gutterBookmark : 0 }
    private var changeLaneWidth: CGFloat { showChangeHistory ? DS.Metric.gutterChangeBar : 0 }
    private var foldLaneWidth: CGFloat { showFoldMargin ? DS.Metric.gutterFolding : 0 }

    /// The number lane holds its design width until the document has more
    /// digits than fit, then grows to keep the numbers legible.
    private var numberLaneWidth: CGFloat {
        guard showLineNumbers else { return 0 }
        let digits = max(2, String(max(1, textView?.layoutManager?.lineCount ?? 1)).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let measured = sample.size(withAttributes: [.font: font]).width + DS.Space.s * 2
        return max(DS.Metric.gutterNumber, ceil(measured))
    }

    private var bookmarkLane: NSRect { NSRect(x: 0, y: 0, width: bookmarkLaneWidth, height: bounds.height) }
    private var numberLane: NSRect {
        NSRect(x: bookmarkLane.maxX, y: 0, width: numberLaneWidth, height: bounds.height)
    }
    private var changeLane: NSRect {
        NSRect(x: numberLane.maxX, y: 0, width: changeLaneWidth, height: bounds.height)
    }
    private var foldLane: NSRect {
        NSRect(x: changeLane.maxX, y: 0, width: foldLaneWidth, height: bounds.height)
    }

    /// Width needed for the widest line number in the document.
    public func requiredWidth() -> CGFloat {
        bookmarkLaneWidth + numberLaneWidth + changeLaneWidth + foldLaneWidth
    }

    // MARK: Interaction

    public override func mouseDown(with event: NSEvent) {
        guard let textView, let layoutManager = textView.layoutManager,
              let clipView = textView.enclosingScrollView?.contentView else { return }
        let point = convert(event.locationInWindow, from: nil)
        let documentY = point.y + clipView.bounds.origin.y
        guard let position = layoutManager.textLineForPosition(max(0, documentY)) else { return }

        if showFoldMargin, foldLane.contains(point) {
            if foldStartLines.contains(position.index) { onToggleFold?(position.index) }
        } else if showBookmarks, bookmarkLane.contains(point) {
            onToggleBookmark?(position.index)
        }
    }

    // MARK: Drawing

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

            drawChangeBar(line: index, y: y, height: height)
            drawBookmark(line: index, y: y, height: height)
            drawNumber(line: index, y: y, height: height, attributes: &attributes)
            drawFoldControl(line: index, y: y, height: height)

            guard let next = layoutManager.textLineForIndex(index + 1) else { break }
            position = next
        }
    }

    /// The shape the change bar takes for a line, if any.
    public enum ChangeBarShape: Equatable { case none, square, rounded }

    /// Amber square for an unsaved edit, green rounded bar once saved: the two
    /// differ in shape as well as hue, so the signal survives colour blindness.
    public func changeBarShape(forLine line: Int) -> ChangeBarShape {
        guard showChangeHistory else { return .none }
        if changedLines.contains(line) { return .square }
        if savedChangedLines.contains(line) { return .rounded }
        return .none
    }

    private func drawChangeBar(line: Int, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: changeLane.minX, y: y, width: changeLane.width, height: height)
        switch changeBarShape(forLine: line) {
        case .none:
            return
        case .square:
            DS.Color.changeModified.setFill()
            rect.fill()
        case .rounded:
            DS.Color.changeSaved.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 1),
                         xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
        }
    }

    private func drawBookmark(line: Int, y: CGFloat, height: CGFloat) {
        guard showBookmarks, bookmarkedLines.contains(line) else { return }
        guard let glyph = DS.symbol("bookmark.fill", pointSize: 10, color: DS.Color.bookmark) else { return }
        glyph.draw(in: NSRect(x: bookmarkLane.midX - glyph.size.width / 2,
                              y: y + (height - glyph.size.height) / 2,
                              width: glyph.size.width, height: glyph.size.height))
    }

    private func drawNumber(line: Int, y: CGFloat, height: CGFloat,
                            attributes: inout [NSAttributedString.Key: Any]) {
        guard showLineNumbers else { return }
        attributes[.foregroundColor] = (line == currentLine) ? currentLineColor : textColor
        let label = String(line + 1) as NSString
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: numberLane.maxX - DS.Space.s - size.width,
                               y: y + (height - size.height) / 2),
                   withAttributes: attributes)
    }

    /// A chevron rather than a boxed plus/minus: it matches the rest of the
    /// design's disclosure language and needs no border to read.
    private func drawFoldControl(line: Int, y: CGFloat, height: CGFloat) {
        guard showFoldMargin, foldStartLines.contains(line) else { return }
        let collapsed = collapsedFoldLines.contains(line)
        let name = collapsed ? "chevron.right" : "chevron.down"
        guard let glyph = DS.symbol(name, pointSize: 8, weight: .semibold,
                                    color: DS.Color.gutterText) else { return }
        glyph.draw(in: NSRect(x: foldLane.midX - glyph.size.width / 2,
                              y: y + (height - glyph.size.height) / 2,
                              width: glyph.size.width, height: glyph.size.height))
    }
}
