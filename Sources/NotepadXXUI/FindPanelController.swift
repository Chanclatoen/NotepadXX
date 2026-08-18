import AppKit
import NotepadXXCore

/// Notepad++'s Find/Replace dialog. Modeless, so it stays open while you work.
public final class FindPanelController: NSWindowController {
    public struct Request {
        public init(pattern: String, replacement: String, options: SearchOptions, inSelection: Bool) {
            self.pattern = pattern
            self.replacement = replacement
            self.options = options
            self.inSelection = inSelection
        }

        public let pattern: String
        public let replacement: String
        public let options: SearchOptions
        public let inSelection: Bool
    }

    public var onFindNext: ((Request) -> Void)?
    public var onFindPrevious: ((Request) -> Void)?
    public var onCount: ((Request) -> Void)?
    public var onReplace: ((Request) -> Void)?
    public var onReplaceAll: ((Request) -> Void)?
    public var onFindAll: ((Request) -> Void)?

    private let findField = NSTextField(string: "")
    private let replaceField = NSTextField(string: "")
    private let modeControl = NSSegmentedControl(labels: ["Normal", "Extended", "Regular expression"],
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let matchCase = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let wholeWord = NSButton(checkboxWithTitle: "Match whole word only", target: nil, action: nil)
    private let wrapAround = NSButton(checkboxWithTitle: "Wrap around", target: nil, action: nil)
    private let inSelection = NSButton(checkboxWithTitle: "In selection", target: nil, action: nil)
    private let dotNewline = NSButton(checkboxWithTitle: ". matches newline", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    public init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        window.title = "Find"
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        super.init(window: window)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        wrapAround.state = .on
        modeControl.selectedSegment = 0

        let findRow = labelled("Find what:", findField)
        let replaceRow = labelled("Replace with:", replaceField)

        let optionsGrid = NSGridView(views: [
            [matchCase, wrapAround],
            [wholeWord, inSelection],
            [dotNewline, NSView()],
        ])
        optionsGrid.rowSpacing = 4
        optionsGrid.columnSpacing = 16

        let buttons = NSStackView(views: [
            button("Find Next", #selector(findNext)),
            button("Find Previous", #selector(findPrevious)),
            button("Count", #selector(count)),
            button("Find All", #selector(findAll)),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let replaceButtons = NSStackView(views: [
            button("Replace", #selector(replace)),
            button("Replace All", #selector(replaceAll)),
        ])
        replaceButtons.orientation = .horizontal
        replaceButtons.spacing = 8

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [
            findRow, replaceRow, modeControl, optionsGrid, buttons, replaceButtons, statusLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            replaceField.widthAnchor.constraint(equalTo: findField.widthAnchor),
        ])
        window.contentView = content
    }

    private func labelled(_ title: String, _ field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 96).isActive = true
        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    /// Shows a result message, e.g. "12 matches".
    public func showStatus(_ message: String) { statusLabel.stringValue = message }

    public func focusSearchField() {
        window?.makeFirstResponder(findField)
    }

    public var currentPattern: String { findField.stringValue }
    public var currentOptions: SearchOptions { request.options }

    private var request: Request {
        let mode: SearchMode = [.normal, .extended, .regex][max(0, modeControl.selectedSegment)]
        return Request(
            pattern: findField.stringValue,
            replacement: replaceField.stringValue,
            options: SearchOptions(
                mode: mode,
                matchCase: matchCase.state == .on,
                wholeWord: wholeWord.state == .on,
                wrapAround: wrapAround.state == .on,
                backward: false,
                dotMatchesNewline: dotNewline.state == .on
            ),
            inSelection: inSelection.state == .on
        )
    }

    private var backwardRequest: Request {
        let base = request
        var options = base.options
        options.backward = true
        return Request(pattern: base.pattern, replacement: base.replacement,
                       options: options, inSelection: base.inSelection)
    }

    @objc private func findNext() { onFindNext?(request) }
    @objc private func findPrevious() { onFindPrevious?(backwardRequest) }
    @objc private func count() { onCount?(request) }
    @objc private func findAll() { onFindAll?(request) }
    @objc private func replace() { onReplace?(request) }
    @objc private func replaceAll() { onReplaceAll?(request) }
}
