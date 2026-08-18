import AppKit

/// The vertical line marking a column limit (Notepad++'s "vertical edge").
///
/// It floats above the text rather than being drawn by the text engine, so
/// toggling it never invalidates layout on a large document.
final class EdgeGuideView: NSView {
    var column: Int = 0 { didSet { needsDisplay = true } }
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet { needsDisplay = true }
    }
    var colour: NSColor = .separatorColor { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Deliberately not layer-backed. A transparent layer retains whatever
        // was drawn on a previous pass, leaving stale guides below the text;
        // an unlayered view is composited fresh each time.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Clicks must reach the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard column > 0 else { return }
        // Monospaced, so one character's advance times the column is exact.
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        let x = advance * CGFloat(column)
        guard x > 0, x < bounds.width else { return }

        colour.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x + 0.5, y: 0))
        path.line(to: NSPoint(x: x + 0.5, y: bounds.height))
        path.lineWidth = 1
        path.stroke()
    }
}
