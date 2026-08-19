import AppKit
import NotepadXXCore

/// Macro and Run menu commands.
extension MainWindowController: MacroPlaybackTarget {

    // MARK: - Macro

    @objc public func toggleMacroRecordingAction(_ sender: Any?) {
        if macroRecorder.isRecording {
            lastRecordedSteps = macroRecorder.stop()
        } else {
            macroRecorder.start()
        }
        refreshUI()
    }

    @objc public func playbackMacroAction(_ sender: Any?) {
        guard !lastRecordedSteps.isEmpty else { NSSound.beep(); return }
        MacroPlayer.play(Macro(name: "current", steps: lastRecordedSteps), on: self)
    }

    @objc public func runMacroMultipleTimesAction(_ sender: Any?) {
        guard !lastRecordedSteps.isEmpty else { NSSound.beep(); return }
        let panel = runMacroPanel()
        panel.present(macros: macroStore?.macros.map(\.name) ?? [],
                      stepCount: lastRecordedSteps.count)
    }

    func runMacroPanel() -> RunMacroPanelController {
        if let existing = installedRunMacroPanel { return existing }
        let panel = RunMacroPanelController()
        panel.onRun = { [weak self] name, times in
            guard let self else { return }
            let steps = self.macroStore?.macros.first { $0.name == name }?.steps
                ?? self.lastRecordedSteps
            let macro = Macro(name: name, steps: steps)
            if let times {
                MacroPlayer.play(macro, on: self, times: times)
            } else {
                MacroPlayer.playUntilEndOfDocument(macro, on: self)
            }
        }
        installedRunMacroPanel = panel
        return panel
    }

    @objc public func saveCurrentMacroAction(_ sender: Any?) {
        guard !lastRecordedSteps.isEmpty else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Save macro"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        try? macroStore?.add(Macro(name: field.stringValue, steps: lastRecordedSteps))
    }

    // MARK: - MacroPlaybackTarget

    public func macroInsertText(_ text: String) {
        currentEditor?.replaceSelection(with: text)
    }

    public func macroRunCommand(_ selectorName: String) {
        NSApp.sendAction(Selector(selectorName), to: nil, from: self)
    }

    public func macroNavigate(_ movement: String) {
        guard let editor = currentEditor else { return }
        let selection = editor.selectedRange
        let length = (editor.text as NSString).length
        switch movement {
        case "moveLeft": editor.selectedRange = NSRange(location: max(0, selection.location - 1), length: 0)
        case "moveRight": editor.selectedRange = NSRange(location: min(length, selection.location + 1), length: 0)
        case "moveToEndOfDocument": editor.selectedRange = NSRange(location: length, length: 0)
        case "moveToStartOfDocument": editor.selectedRange = NSRange(location: 0, length: 0)
        default: break
        }
    }

    public var macroIsAtEndOfDocument: Bool {
        guard let editor = currentEditor else { return true }
        return editor.selectedRange.location >= (editor.text as NSString).length
    }

    // MARK: - Run

    @objc public func runCommandAction(_ sender: Any?) {
        runPanel().present()
    }

    func runPanel() -> RunPanelController {
        if let existing = installedRunPanel { return existing }
        let panel = RunPanelController()
        panel.onRun = { [weak self] command, capturesOutput, savesFirst in
            guard let self else { return }
            if savesFirst { self.saveDocumentAction(nil) }
            self.execute(command: command, capturingOutput: capturesOutput)
        }
        panel.onSave = { [weak self] command in
            try? self?.runCommandStore?.add(RunCommand(name: command, command: command))
        }
        installedRunPanel = panel
        return panel
    }

    /// Runs a command through the user's shell.
    ///
    /// Output is captured into the Run Output panel when asked for, so a
    /// command that prints something is not a command that appears to do
    /// nothing.
    func execute(command: String, capturingOutput: Bool = false) {
        guard documents.indices.contains(activeIndex) else { return }
        let document = documents[activeIndex]
        let caret = currentEditor?.caretPosition() ?? (line: 1, column: 1)
        let context = RunContext.forDocument(
            path: document.fileURL?.path, line: caret.line, column: caret.column
        )

        let unknown = RunCommandExpander.unknownVariables(in: command, context: context)
        if !unknown.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Unknown variable\(unknown.count == 1 ? "" : "s")"
            alert.informativeText = unknown.map { "$(\($0))" }.joined(separator: ", ")
                + " will be passed through literally."
            presentSheet(alert) { _ in }
        }

        let expanded = RunCommandExpander.expand(command, with: context)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", expanded]
        process.currentDirectoryURL = document.fileURL?.deletingLastPathComponent()

        var pipe: Pipe?
        if capturingOutput, let panel = runOutputPanel {
            dockHost?.show("runOutput")
            panel.begin(command: expanded)
            let output = Pipe()
            pipe = output
            process.standardOutput = output
            process.standardError = output
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { panel.append(text) }
                }
            }
            process.terminationHandler = { finished in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        output.fileHandleForReading.readabilityHandler = nil
                        panel.finish(status: finished.terminationStatus)
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            pipe?.fileHandleForReading.readabilityHandler = nil
            let alert = NSAlert()
            alert.messageText = "Could not run command"
            alert.informativeText = error.localizedDescription
            presentSheet(alert) { _ in }
        }
    }
}
