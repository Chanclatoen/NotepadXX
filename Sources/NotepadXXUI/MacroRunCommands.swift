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
        let alert = NSAlert()
        alert.messageText = "Run macro"
        alert.informativeText = "How many times? Leave blank to run until end of file."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let macro = Macro(name: "current", steps: lastRecordedSteps)
        if let times = Int(field.stringValue), times > 0 {
            MacroPlayer.play(macro, on: self, times: times)
        } else {
            MacroPlayer.playUntilEndOfDocument(macro, on: self)
        }
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
        let alert = NSAlert()
        alert.messageText = "Run"
        alert.informativeText = "Variables: $(FULL_CURRENT_PATH), $(CURRENT_DIRECTORY), $(FILE_NAME), $(NAME_PART), $(EXT_PART), $(CURRENT_WORD), $(CURRENT_LINE), $(CURRENT_COLUMN)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response != .alertThirdButtonReturn, !field.stringValue.isEmpty else { return }

        if response == .alertSecondButtonReturn {
            try? runCommandStore?.add(RunCommand(name: field.stringValue, command: field.stringValue))
            return
        }
        execute(command: field.stringValue)
    }

    /// Runs a command through the user's shell and reports failures.
    func execute(command: String) {
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
            alert.runModal()
        }

        let expanded = RunCommandExpander.expand(command, with: context)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", expanded]
        process.currentDirectoryURL = document.fileURL?.deletingLastPathComponent()
        do {
            try process.run()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not run command"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
