import AppKit
import NotepadXXCore
import NotepadXXDesign

/// Document Map: a scaled-down overview of the whole file with a viewport
/// indicator, click to jump.
///
/// Lines are drawn as bars proportional to their length rather than as tiny
/// text. Rendering real glyphs at this scale is unreadable and, on a 900k-line
/// file, would cost far more than the map is worth.
@MainActor
public final class DocumentMapPanel: NSObject, DockablePanel {
    public let panelIdentifier = "documentMap"
    public let panelTitle = "Document Map"
    public let preferredPosition = DockPosition.right

    /// Supplies the document text and the currently visible line range.
    public var contentProvider: (() -> (text: String, visibleLines: ClosedRange<Int>)?)?
    public var onJumpToLine: ((Int) -> Void)?

    private let mapView = MapView()

    public override init() {
        super.init()
        mapView.onClickLine = { [weak self] line in self?.onJumpToLine?(line) }
    }

    public var contentView: NSView { mapView }

    public func panelDidBecomeVisible() { reload() }

    public func reload() {
        guard let content = contentProvider?() else {
            mapView.configure(lineLengths: [], visibleLines: 0...0)
            return
        }
        let (lines, _) = LineOperations.split(content.text)
        mapView.configure(
            lineLengths: lines.map { $0.count },
            visibleLines: content.visibleLines
        )
    }
}

private final class MapView: NSView {
    var onClickLine: ((Int) -> Void)?
    private var lineLengths: [Int] = []
    private var visibleLines: ClosedRange<Int> = 0...0

    override var isFlipped: Bool { true }

    func configure(lineLengths: [Int], visibleLines: ClosedRange<Int>) {
        self.lineLengths = lineLengths
        self.visibleLines = visibleLines
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.Color.content.setFill()
        // Fill this view's own bounds. `dirtyRect` can be larger than the view
        // when the tree is rendered through its layer, and filling it paints
        // over whatever sits above — here, the panel's own header.
        bounds.intersection(dirtyRect).fill()
        guard !lineLengths.isEmpty, bounds.height > 0 else { return }

        let scale = bounds.height / CGFloat(lineLengths.count)
        let barHeight = max(0.5, min(2, scale))
        let widest = CGFloat(max(1, lineLengths.max() ?? 1))
        let usableWidth = bounds.width - 8

        DS.Color.textTertiary.setFill()
        for (index, length) in lineLengths.enumerated() where length > 0 {
            let y = CGFloat(index) * scale
            // Clamp so a very long line does not run past the panel.
            let width = min(usableWidth, usableWidth * CGFloat(length) / widest)
            NSRect(x: 4, y: y, width: width, height: barHeight).fill()
        }

        // Viewport indicator — only when there is something out of view. With
        // the whole document on screen the indicator would cover the map and
        // mark nothing.
        guard visibleLines.count < lineLengths.count else { return }
        let top = CGFloat(visibleLines.lowerBound) * scale
        let height = max(4, CGFloat(visibleLines.count) * scale)
        DS.Color.brandTint.setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: height).fill()
        DS.Color.brand.setStroke()
        NSBezierPath(rect: NSRect(x: 0.5, y: top + 0.5, width: bounds.width - 1, height: height - 1)).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard !lineLengths.isEmpty, bounds.height > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let line = Int(point.y / bounds.height * CGFloat(lineLengths.count))
        onClickLine?(min(max(0, line), lineLengths.count - 1))
    }
}
