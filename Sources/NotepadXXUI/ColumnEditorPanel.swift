import AppKit
import NotepadXXCore

/// Notepad++'s Column Editor dialog (Edit > Column Editor, Alt+C).
///
/// The rectangular *selection* itself comes from the text engine (Option+drag);
/// this dialog is the batch-insert half that engine does not provide.
public final class ColumnEditorPanel: NSWindowController {
    public enum Result {
        case text(String)
        case numbers(initial: Int, increment: Int, repeatCount: Int,
                     leadingZeros: Bool, format: ColumnSelection.NumberFormat)
    }

    public var onInsert: ((Result) -> Void)?

    private let modeControl = NSSegmentedControl(
        labels: ["Text to Insert", "Number to Insert"],
        trackingMode: .selectOne, target: nil, action: nil
    )
    private let textField = NSTextField(string: "")
    private let initialField = NSTextField(string: "1")
    private let incrementField = NSTextField(string: "1")
    private let repeatField = NSTextField(string: "1")
    private let leadingZeros = NSButton(checkboxWithTitle: "Leading zeros", target: nil, action: nil)
    private let formatControl = NSSegmentedControl(
        labels: ["Dec", "Oct", "Hex", "Bin"],
        trackingMode: .selectOne, target: nil, action: nil
    )

    public init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        window.title = "Column Editor"
        super.init(window: window)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        modeControl.selectedSegment = 0
        formatControl.selectedSegment = 0

        let numberGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Initial number:"), initialField],
            [NSTextField(labelWithString: "Increase by:"), incrementField],
            [NSTextField(labelWithString: "Repeat:"), repeatField],
            [NSTextField(labelWithString: "Format:"), formatControl],
            [NSView(), leadingZeros],
        ])
        numberGrid.rowSpacing = 6
        numberGrid.columnSpacing = 10

        let insert = NSButton(title: "Insert", target: self, action: #selector(insertTapped))
        insert.bezelStyle = .rounded
        insert.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded

        let buttons = NSStackView(views: [cancel, insert])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [
            modeControl,
            labelled("Text:", textField),
            numberGrid,
            buttons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            initialField.widthAnchor.constraint(equalToConstant: 80),
            incrementField.widthAnchor.constraint(equalToConstant: 80),
            repeatField.widthAnchor.constraint(equalToConstant: 80),
        ])
        window.contentView = content
    }

    private func labelled(_ title: String, _ field: NSTextField) -> NSStackView {
        let row = NSStackView(views: [NSTextField(labelWithString: title), field])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    @objc private func insertTapped() {
        let result: Result
        if modeControl.selectedSegment == 0 {
            result = .text(textField.stringValue)
        } else {
            let formats: [ColumnSelection.NumberFormat] = [.decimal, .octal, .hexadecimal, .binary]
            result = .numbers(
                initial: Int(initialField.stringValue) ?? 1,
                increment: Int(incrementField.stringValue) ?? 1,
                repeatCount: max(1, Int(repeatField.stringValue) ?? 1),
                leadingZeros: leadingZeros.state == .on,
                format: formats[max(0, min(3, formatControl.selectedSegment))]
            )
        }
        onInsert?(result)
        window?.close()
    }

    @objc private func cancelTapped() { window?.close() }
}
