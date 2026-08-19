import AppKit
import NotepadXXDesign

/// Go to line or offset.
///
/// A modeless utility panel rather than a modal alert: the design makes every
/// command dialog modeless, remembering its last values, committing on Return
/// and closing on Escape. A modal alert here would block the document you are
/// trying to navigate.
public final class GoToPanelController: NSWindowController {
    public enum Target: Int { case line, offset }

    /// Called with the target and the value typed. Returns whether it worked,
    /// so an out-of-range value can be reported instead of silently ignored.
    public var onGo: ((Target, Int) -> Bool)?

    private let targetControl = NSSegmentedControl(
        labels: ["Line", "Offset"], trackingMode: .selectOne, target: nil, action: nil)
    private let valueField = NSTextField(string: "")
    private let currentLabel = NSTextField(labelWithString: "")
    private let rangeLabel = NSTextField(labelWithString: "")

    public init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Go to…"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("NotepadXX.GoToPanel")
        super.init(window: panel)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        targetControl.selectedSegment = 0
        targetControl.target = self
        targetControl.action = #selector(targetChanged)
        targetControl.setAccessibilityLabel("Go to line or offset")

        valueField.alignment = .right
        valueField.setAccessibilityLabel("Destination")
        valueField.target = self
        valueField.action = #selector(commit)

        for label in [currentLabel, rangeLabel] {
            label.font = DS.Font.small()
            label.textColor = DS.Color.textSecondary
        }

        let go = NSButton(title: "Go", target: self, action: #selector(commit))
        go.bezelStyle = .rounded
        go.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(dismiss))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [NSView(), cancel, go])
        buttons.orientation = .horizontal
        buttons.spacing = DS.Space.m

        let stack = NSStackView(views: [targetControl, valueField, currentLabel, rangeLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DS.Space.m
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DS.Space.xl),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -DS.Space.xl),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: DS.Space.xl),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -DS.Space.xl),
            targetControl.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            valueField.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            valueField.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        window.contentView = content
    }

    /// Shows the panel, telling the user where they are and what is in range.
    public func present(currentLine: Int, lineCount: Int, characterCount: Int) {
        self.lineCount = lineCount
        self.characterCount = characterCount
        currentLabel.stringValue = "You are here: line \(currentLine)"
        updateRange()
        showWindow(nil)
        window?.makeFirstResponder(valueField)
        // The panel keeps its last value, so the field opens selected rather
        // than empty: typing replaces it, Return repeats the last jump.
        valueField.currentEditor()?.selectAll(nil)
    }

    private var lineCount = 1
    private var characterCount = 0

    public var target: Target { Target(rawValue: targetControl.selectedSegment) ?? .line }
    public var value: Int? { Int(valueField.stringValue) }

    private func updateRange() {
        let upper = target == .line ? lineCount : characterCount
        rangeLabel.stringValue = "Range: 1 – \(max(1, upper))"
    }

    @objc private func targetChanged() { updateRange() }

    @objc private func commit() {
        guard let value else {
            rangeLabel.stringValue = "Type a number between 1 and \(max(1, lineCount))"
            NSSound.beep()
            return
        }
        if onGo?(target, value) == true {
            close()
        } else {
            rangeLabel.stringValue = "Out of range — 1 – \(max(1, target == .line ? lineCount : characterCount))"
            NSSound.beep()
        }
    }

    @objc private func dismiss() { close() }
}
