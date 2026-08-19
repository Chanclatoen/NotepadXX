import AppKit

/// The 26 pt status bar: six segments divided by hairlines.
///
/// Order matches the design — document type, length and lines, caret and
/// selection, line ending, encoding, insert mode — and the caret segment takes
/// the slack. As the window narrows, segments shed detail in a fixed order
/// rather than truncating arbitrarily or clipping.
@MainActor
public final class DSStatusBar: NSView {
    public struct Model {
        public var documentType: String
        public var length: Int
        public var lines: Int
        public var caretLine: Int
        public var caretColumn: Int
        public var selectionCharacters: Int
        public var selectionLines: Int
        public var caretCount: Int
        public var lineEnding: String
        public var lineEndingShort: String
        public var encoding: String
        public var isOverwrite: Bool

        public init(documentType: String = "Normal text file", length: Int = 0, lines: Int = 1,
                    caretLine: Int = 1, caretColumn: Int = 1,
                    selectionCharacters: Int = 0, selectionLines: Int = 0, caretCount: Int = 1,
                    lineEnding: String = "Unix (LF)", lineEndingShort: String = "LF",
                    encoding: String = "UTF-8", isOverwrite: Bool = false) {
            self.documentType = documentType
            self.length = length
            self.lines = lines
            self.caretLine = caretLine
            self.caretColumn = caretColumn
            self.selectionCharacters = selectionCharacters
            self.selectionLines = selectionLines
            self.caretCount = caretCount
            self.lineEnding = lineEnding
            self.lineEndingShort = lineEndingShort
            self.encoding = encoding
            self.isOverwrite = isOverwrite
        }
    }

    /// How much detail the bar is showing, driven by available width.
    public enum Density { case full, medium, compact }

    public var onPickLanguage: (() -> Void)?
    public var onPickLineEnding: (() -> Void)?
    public var onPickEncoding: (() -> Void)?
    public var onToggleInsertMode: (() -> Void)?

    private let typeSegment = DSStatusSegment(accessibilityLabel: "Document type", showsMenu: true)
    private let lengthSegment = DSStatusSegment(accessibilityLabel: "Document length")
    private let caretSegment = DSStatusSegment(accessibilityLabel: "Caret position and selection")
    private let lineEndingSegment = DSStatusSegment(accessibilityLabel: "Line ending", showsMenu: true)
    private let encodingSegment = DSStatusSegment(accessibilityLabel: "Text encoding", showsMenu: true)
    private let insertSegment = DSStatusSegment(accessibilityLabel: "Insert or overwrite mode")

    private var model = Model()
    public private(set) var density: Density = .full

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: DS.Metric.statusBar).isActive = true

        insertSegment.setFont(DS.Font.statusNumeric())
        insertSegment.hideTrailingSeparator()

        typeSegment.onClick = { [weak self] in self?.onPickLanguage?() }
        lineEndingSegment.onClick = { [weak self] in self?.onPickLineEnding?() }
        encodingSegment.onClick = { [weak self] in self?.onPickEncoding?() }
        insertSegment.onClick = { [weak self] in self?.onToggleInsertMode?() }

        for segment in segments { addSubview(segment) }

        let rule = DSSeparator(.structural)
        addSubview(rule)
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel("Status bar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var segments: [DSStatusSegment] {
        [typeSegment, lengthSegment, caretSegment, lineEndingSegment, encodingSegment, insertSegment]
    }

    public override func updateLayer() {
        layer?.backgroundColor = DS.Color.titleBar.cgColor
    }

    public func update(_ model: Model) {
        self.model = model
        applyDensity()
    }

    public override func layout() {
        super.layout()
        // Choose density from the width available, then lay the segments out.
        let newDensity: Density
        if bounds.width >= 900 { newDensity = .full }
        else if bounds.width >= 680 { newDensity = .medium }
        else { newDensity = .compact }

        if newDensity != density {
            density = newDensity
            applyDensity()
        }

        var x: CGFloat = 0
        let flexible = caretSegment
        var fixedWidth: CGFloat = 0
        for segment in segments where segment !== flexible {
            fixedWidth += segment.fittingSize.width + DS.Space.xl
        }
        let flexibleWidth = max(120, bounds.width - fixedWidth)

        for segment in segments {
            let width = segment === flexible ? flexibleWidth : segment.fittingSize.width + DS.Space.xl
            segment.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
        }
    }

    private func applyDensity() {
        let numeric = DS.Font.statusNumeric()

        switch density {
        case .full:
            typeSegment.text = model.documentType
            lengthSegment.text = "length \(model.length)    lines \(model.lines)"
            lineEndingSegment.text = model.lineEnding
        case .medium:
            typeSegment.text = shortType(model.documentType)
            lengthSegment.text = "\(model.lines) ln"
            lineEndingSegment.text = model.lineEnding
        case .compact:
            typeSegment.text = shortType(model.documentType)
            lengthSegment.text = "\(model.lines) ln"
            lineEndingSegment.text = model.lineEndingShort
        }

        // The caret segment is the one that must always be readable.
        if model.caretCount > 1 {
            caretSegment.text = density == .compact
                ? "Ln \(model.caretLine)  Col \(model.caretColumn)  ⌶\(model.caretCount)"
                : "Ln \(model.caretLine)    Col \(model.caretColumn)    \(model.caretCount) carets    Sel \(model.selectionCharacters) | \(model.selectionLines)"
            caretSegment.textColor = DS.Color.caret
        } else {
            caretSegment.text = density == .compact
                ? "Ln \(model.caretLine)  Col \(model.caretColumn)"
                : "Ln \(model.caretLine)    Col \(model.caretColumn)    Sel \(model.selectionCharacters) | \(model.selectionLines)"
            caretSegment.textColor = DS.Color.textPrimary
        }
        caretSegment.setFont(numeric)

        encodingSegment.text = model.encoding
        insertSegment.text = model.isOverwrite ? "OVR" : "INS"
        needsLayout = true
    }

    /// "Swift source file" becomes "Swift" when space is short.
    private func shortType(_ type: String) -> String {
        type.split(separator: " ").first.map(String.init) ?? type
    }
}
