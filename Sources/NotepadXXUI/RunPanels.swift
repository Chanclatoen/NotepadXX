import AppKit
import NotepadXXCore
import NotepadXXDesign

/// Run a shell command against the current document.
///
/// A modeless panel, like the other command dialogs: it remembers what was
/// typed, commits on Return and closes on Escape.
public final class RunPanelController: NSWindowController {
    /// Called with the command, and whether its output should be captured.
    public var onRun: ((String, Bool, Bool) -> Void)?
    public var onSave: ((String) -> Void)?
    /// Supplies the variables the "Insert a variable" menu offers.
    public var variableProvider: (() -> [String])?

    private let commandField = NSTextField(string: "")
    private let variableButton = NSPopUpButton()
    private let captureOutput = NSButton(checkboxWithTitle: "Capture output in the Run panel",
                                         target: nil, action: nil)
    private let saveFirst = NSButton(checkboxWithTitle: "Save the document first",
                                     target: nil, action: nil)

    public init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 180),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Run"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("NotepadXX.RunPanel")
        super.init(window: panel)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        commandField.placeholderString = "/usr/bin/env python3 $(FULL_CURRENT_PATH)"
        commandField.font = DS.Font.mono(12)
        commandField.setAccessibilityLabel("Command")
        commandField.target = self
        commandField.action = #selector(run)

        captureOutput.state = .on
        for checkbox in [captureOutput, saveFirst] { checkbox.font = DS.Font.body() }

        let variables = variableProvider?() ?? RunContext.variableNames
        variableButton.addItem(withTitle: "Insert a variable…")
        variableButton.addItems(withTitles: variables.map { "$(\($0))" })
        variableButton.target = self
        variableButton.action = #selector(insertVariable)
        variableButton.setAccessibilityLabel("Insert a variable")

        let run = NSButton(title: "Run", target: self, action: #selector(self.run))
        run.keyEquivalent = "\r"
        let save = NSButton(title: "Save…", target: self, action: #selector(saveCommand))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(dismiss))
        cancel.keyEquivalent = "\u{1b}"
        for button in [run, save, cancel] { button.bezelStyle = .rounded }

        let hint = NSTextField(labelWithString: "\(variables.count) available")
        hint.font = DS.Font.small()
        hint.textColor = DS.Color.textTertiary

        let variableRow = NSStackView(views: [variableButton, hint])
        variableRow.orientation = .horizontal
        variableRow.spacing = DS.Space.m

        let buttons = NSStackView(views: [NSView(), save, cancel, run])
        buttons.orientation = .horizontal
        buttons.spacing = DS.Space.m

        let stack = NSStackView(views: [commandField, variableRow, captureOutput, saveFirst, buttons])
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
            commandField.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            commandField.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            buttons.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])
        window.contentView = content
    }

    public func present() {
        showWindow(nil)
        window?.makeFirstResponder(commandField)
    }

    public var command: String { commandField.stringValue }
    public var capturesOutput: Bool { captureOutput.state == .on }
    public var savesFirst: Bool { saveFirst.state == .on }

    public func setCommand(_ command: String) { commandField.stringValue = command }

    @objc private func insertVariable() {
        guard variableButton.indexOfSelectedItem > 0,
              let title = variableButton.titleOfSelectedItem else { return }
        commandField.stringValue += title
        variableButton.selectItem(at: 0)
    }

    @objc private func run() {
        guard !command.isEmpty else { NSSound.beep(); return }
        onRun?(command, capturesOutput, savesFirst)
    }

    @objc private func saveCommand() {
        guard !command.isEmpty else { NSSound.beep(); return }
        onSave?(command)
    }

    @objc private func dismiss() { close() }
}

/// Run a recorded macro a number of times, or to the end of the document.
public final class RunMacroPanelController: NSWindowController {
    /// Called with the macro name and how many times to run it; nil means "to
    /// the end of the document".
    public var onRun: ((String, Int?) -> Void)?

    private let macroButton = NSPopUpButton()
    private let timesField = NSTextField(string: "10")
    private let modeControl = NSSegmentedControl(
        labels: ["Run n times", "To end of file"], trackingMode: .selectOne, target: nil, action: nil)
    private let stepsLabel = NSTextField(labelWithString: "")

    public init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 170),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Run a Macro Multiple Times"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("NotepadXX.RunMacroPanel")
        super.init(window: panel)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildLayout() {
        guard let window else { return }
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        macroButton.setAccessibilityLabel("Macro")
        timesField.alignment = .right
        timesField.setAccessibilityLabel("How many times")
        timesField.target = self
        timesField.action = #selector(run)
        stepsLabel.font = DS.Font.small()
        stepsLabel.textColor = DS.Color.textSecondary

        let run = NSButton(title: "Run", target: self, action: #selector(self.run))
        run.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(dismiss))
        cancel.keyEquivalent = "\u{1b}"
        for button in [run, cancel] { button.bezelStyle = .rounded }

        let buttons = NSStackView(views: [NSView(), cancel, run])
        buttons.orientation = .horizontal
        buttons.spacing = DS.Space.m

        let countRow = NSStackView(views: [modeControl, timesField])
        countRow.orientation = .horizontal
        countRow.spacing = DS.Space.m

        let stack = NSStackView(views: [macroButton, countRow, stepsLabel, buttons])
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
            buttons.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            timesField.widthAnchor.constraint(equalToConstant: 64),
        ])
        window.contentView = content
    }

    /// Shows the panel for the macros available, reporting how many steps the
    /// chosen one holds — the run is one undo step whatever the count.
    public func present(macros: [String], stepCount: Int) {
        macroButton.removeAllItems()
        macroButton.addItems(withTitles: macros.isEmpty ? ["Current recording"] : macros)
        stepsLabel.stringValue =
            "Recorded steps: \(stepCount) · one undo step covers the whole run."
        modeChanged()
        showWindow(nil)
    }

    public var selectedMacro: String { macroButton.titleOfSelectedItem ?? "" }
    /// nil means "to the end of the file".
    public var repetitions: Int? {
        modeControl.selectedSegment == 1 ? nil : max(1, Int(timesField.stringValue) ?? 1)
    }

    @objc private func modeChanged() {
        timesField.isEnabled = modeControl.selectedSegment == 0
    }

    @objc private func run() {
        onRun?(selectedMacro, repetitions)
        close()
    }

    @objc private func dismiss() { close() }
}

/// Where a run command's output goes when the Run panel is asked to capture it.
public final class RunOutputPanel: NSObject, DockablePanel {
    public let panelIdentifier = "runOutput"
    public let panelTitle = "Run Output"
    public let preferredPosition = DockPosition.bottom

    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let container = NSView()
    private let statusLabel = NSTextField(labelWithString: "")

    public override init() {
        super.init()
        textView.isEditable = false
        textView.font = DS.Font.mono(11)
        textView.drawsBackground = true
        textView.backgroundColor = DS.Color.content
        textView.textColor = DS.Color.textPrimary
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = DS.Font.small()
        statusLabel.textColor = DS.Color.textSecondary
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(statusLabel)
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: DS.Space.xs),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DS.Space.m),
            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: DS.Space.xs),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    public var contentView: NSView { container }

    public func begin(command: String) {
        statusLabel.stringValue = "Running \(command)"
        textView.string = ""
    }

    public func append(_ text: String) {
        textView.string += text
        textView.scrollToEndOfDocument(nil)
    }

    public func finish(status: Int32) {
        statusLabel.stringValue = status == 0
            ? "Finished"
            : "Finished with status \(status)"
    }

    /// What the panel is showing, so a caller can check the output arrived.
    public var output: String { textView.string }
    public var status: String { statusLabel.stringValue }
}
