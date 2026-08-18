import AppKit

/// Mirrors Notepad++'s status bar fields: document length and line count, the
/// current selection, caret position, line ending, and encoding.
final class StatusBarView: NSView {
    private let lengthField = StatusBarView.makeLabel()
    private let positionField = StatusBarView.makeLabel()
    private let lineEndingField = StatusBarView.makeLabel()
    private let encodingField = StatusBarView.makeLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let stack = NSStackView(views: [lengthField, positionField, lineEndingField, encodingField])
        stack.orientation = .horizontal
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        field.textColor = .secondaryLabelColor
        return field
    }

    func update(
        length: Int, lines: Int, selection: Int,
        line: Int, column: Int,
        lineEnding: String, encoding: String
    ) {
        lengthField.stringValue = "length: \(length)  lines: \(lines)"
        positionField.stringValue = "Ln: \(line)  Col: \(column)  Sel: \(selection)"
        lineEndingField.stringValue = lineEnding
        encodingField.stringValue = encoding
    }
}
