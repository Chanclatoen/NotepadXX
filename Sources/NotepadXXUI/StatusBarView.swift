import AppKit

/// Notepad++'s status bar: six segments, divided, in the same order.
///
/// The fields and their order are muscle memory for Notepad++ users, so this
/// mirrors them exactly — document type, length/lines, caret position and
/// selection, line ending, encoding, and insert/overwrite mode.
public final class StatusBarView: NSView {
    private let typeField = StatusBarView.makeLabel()
    private let lengthField = StatusBarView.makeLabel()
    private let positionField = StatusBarView.makeLabel()
    private let lineEndingField = StatusBarView.makeLabel()
    private let encodingField = StatusBarView.makeLabel()
    private let insertField = StatusBarView.makeLabel()

    /// Clicking a segment is how Notepad++ exposes some of these; the handler
    /// lets the window controller wire up menus.
    var onClickSegment: ((Segment) -> Void)?
    enum Segment { case type, length, position, lineEnding, encoding, insertMode }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Proportions roughly match Notepad++: a wide type field, then the
        // numeric fields, then the narrow mode indicators.
        let segments: [(NSTextField, CGFloat)] = [
            (typeField, 180), (lengthField, 190), (positionField, 230),
            (lineEndingField, 130), (encodingField, 110), (insertField, 50),
        ]
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, (field, width)) in segments.enumerated() {
            if index > 0 { stack.addArrangedSubview(makeDivider()) }
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
            let cell = NSView()
            cell.translatesAutoresizingMaskIntoConstraints = false
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cell.heightAnchor.constraint(equalToConstant: 22),
            ])
            stack.addArrangedSubview(cell)
        }

        let topLine = NSBox()
        topLine.boxType = .separator
        topLine.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(topLine)
        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func makeDivider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(box)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 1),
            box.heightAnchor.constraint(equalToConstant: 14),
            box.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            box.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.widthAnchor.constraint(equalToConstant: 1),
        ])
        return container
    }

    private static func makeLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func applyChrome(background: NSColor, text: NSColor) {
        layer?.backgroundColor = background.cgColor
        for field in [typeField, lengthField, positionField,
                      lineEndingField, encodingField, insertField] {
            field.textColor = text
        }
    }

    public func update(
        documentType: String,
        length: Int, lines: Int,
        selection: Int, selectedLines: Int,
        line: Int, column: Int,
        lineEnding: String, encoding: String,
        isOverwrite: Bool
    ) {
        typeField.stringValue = documentType
        lengthField.stringValue = "length : \(length)    lines : \(lines)"
        // Notepad++ shows selection as "characters : lines".
        positionField.stringValue = "Ln : \(line)    Col : \(column)    Sel : \(selection) | \(selectedLines)"
        lineEndingField.stringValue = lineEnding
        encodingField.stringValue = encoding
        insertField.stringValue = isOverwrite ? "OVR" : "INS"
    }
}
