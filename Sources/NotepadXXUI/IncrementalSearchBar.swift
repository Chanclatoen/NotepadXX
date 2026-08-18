import AppKit

/// A slim search strip shown above the status bar, as Notepad++'s incremental
/// search is. Matching happens as you type; Escape puts the caret back where
/// it started.
final class IncrementalSearchBar: NSView {
    var onQueryChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: ((String) -> Void)?

    private let field = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        field.placeholderString = "Incremental search"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.target = self
        field.action = #selector(queryChanged)
        field.delegate = self

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed

        let close = NSButton(title: "✕", target: self, action: #selector(cancel))
        close.isBordered = false

        let stack = NSStackView(views: [field, statusLabel, close])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 280),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func focus() { window?.makeFirstResponder(field) }
    var query: String { field.stringValue }

    func showNotFound(_ notFound: Bool) {
        statusLabel.stringValue = notFound ? "No match" : ""
    }

    @objc private func queryChanged() { onQueryChanged?(field.stringValue) }
    @objc private func cancel() { onCancel?() }
}

extension IncrementalSearchBar: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Return commits the search and hands focus back to the editor.
            onCommit?(field.stringValue)
            return true
        case #selector(NSResponder.moveDown(_:)):
            onNext?()
            return true
        default:
            return false
        }
    }
}
