import AppKit
import NotepadXXDesign

/// The incremental search strip: 26 pt, directly above the status bar.
///
/// Matching happens as you type and the strip reports which match you are on.
/// Escape closes it and puts the caret back where it started, which is the
/// difference between a search you can abandon and one you cannot.
final class IncrementalSearchBar: NSView {
    var onQueryChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: ((String) -> Void)?
    /// Called when Highlight all or Match case is toggled.
    var onOptionsChanged: (() -> Void)?

    static let height: CGFloat = 26

    private let titleLabel = NSTextField(labelWithString: "Incremental find")
    private let field = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let highlightAll = NSButton(checkboxWithTitle: "Highlight all", target: nil, action: nil)
    private let matchCase = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let hintLabel = NSTextField(
        labelWithString: "⌘F opens the full panel · Esc closes and keeps the caret")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        titleLabel.font = DS.Font.smallEmphasis()
        titleLabel.textColor = DS.Color.textSecondary

        field.placeholderString = "Find"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.controlSize = .small
        field.font = DS.Font.small()
        field.target = self
        field.action = #selector(queryChanged)
        field.delegate = self
        field.setAccessibilityLabel("Incremental find")

        countLabel.font = DS.Font.statusNumeric()
        countLabel.textColor = DS.Color.textSecondary

        for checkbox in [highlightAll, matchCase] {
            checkbox.font = DS.Font.small()
            checkbox.controlSize = .small
            checkbox.target = self
            checkbox.action = #selector(optionsChanged)
        }
        highlightAll.state = .on

        hintLabel.font = DS.Font.small()
        hintLabel.textColor = DS.Color.textTertiary

        let close = DSToolbarButton(symbol: "xmark", label: "Close incremental find",
                                    target: self, action: #selector(cancel))

        let stack = NSStackView(views: [titleLabel, field, countLabel, highlightAll, matchCase,
                                        NSView(), hintLabel, close])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = DS.Space.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.xs),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateLayer() {
        layer?.backgroundColor = DS.Color.panel.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        // A hairline against the editor above, so the strip reads as chrome.
        DS.Color.separatorStructural.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    func focus() { window?.makeFirstResponder(field) }
    var query: String { field.stringValue }

    /// Puts a query in the field and searches for it, as typing would.
    func setQuery(_ text: String) {
        field.stringValue = text
        onQueryChanged?(text)
    }
    var highlightsAll: Bool { highlightAll.state == .on }
    var matchesCase: Bool { matchCase.state == .on }

    /// Reports the position in the match list, e.g. "4 of 17".
    func showMatch(_ index: Int, of total: Int) {
        countLabel.stringValue = total == 0 ? "" : "\(index) of \(total)"
        countLabel.textColor = DS.Color.textSecondary
    }

    /// The strip is the only place incremental search speaks, so a failure is
    /// a sentence rather than a beep.
    func showNotFound(_ notFound: Bool, wrapped: Bool = false) {
        guard notFound else { return }
        countLabel.stringValue = wrapped
            ? "No matches — search wrapped and returned to the start"
            : "No matches"
        countLabel.textColor = DS.Color.warning
    }

    @objc private func queryChanged() { onQueryChanged?(field.stringValue) }
    @objc private func optionsChanged() { onOptionsChanged?() }
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
        case #selector(NSResponder.moveUp(_:)):
            onPrevious?()
            return true
        default:
            return false
        }
    }
}
