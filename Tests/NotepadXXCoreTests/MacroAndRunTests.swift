import XCTest
@testable import NotepadXXCore

final class RunCommandTests: XCTestCase {
    private let context = RunContext.forDocument(
        path: "/Users/me/proj/main.swift", currentWord: "widget", line: 12, column: 5
    )

    func testExpandsPathVariables() {
        // Values arrive shell-quoted: the expansion is handed to /bin/sh, and
        // an unquoted path is a command-injection hole (ShellInjectionTests).
        XCTAssertEqual(RunCommandExpander.expand("$(FULL_CURRENT_PATH)", with: context),
                       "'/Users/me/proj/main.swift'")
        XCTAssertEqual(RunCommandExpander.expand("$(CURRENT_DIRECTORY)", with: context), "'/Users/me/proj'")
        XCTAssertEqual(RunCommandExpander.expand("$(FILE_NAME)", with: context), "'main.swift'")
        XCTAssertEqual(RunCommandExpander.expand("$(NAME_PART)", with: context), "'main'")
        XCTAssertEqual(RunCommandExpander.expand("$(EXT_PART)", with: context), "'swift'")
    }

    func testExpandsCaretVariables() {
        XCTAssertEqual(RunCommandExpander.expand("$(CURRENT_WORD)", with: context), "'widget'")
        XCTAssertEqual(RunCommandExpander.expand("$(CURRENT_LINE)", with: context), "'12'")
        XCTAssertEqual(RunCommandExpander.expand("$(CURRENT_COLUMN)", with: context), "'5'")
    }

    func testExpandsSeveralVariablesInOneCommand() {
        let expanded = RunCommandExpander.expand("swiftc $(FILE_NAME) -o $(NAME_PART)", with: context)
        XCTAssertEqual(expanded, "swiftc 'main.swift' -o 'main'")
    }

    /// A typo'd variable must stay visible rather than silently vanishing.
    func testUnknownVariablesAreLeftIntactAndReported() {
        let command = "run $(NOT_A_THING) $(FILE_NAME)"
        XCTAssertEqual(RunCommandExpander.expand(command, with: context), "run $(NOT_A_THING) 'main.swift'")
        XCTAssertEqual(RunCommandExpander.unknownVariables(in: command, context: context), ["NOT_A_THING"])
    }

    func testUntitledDocumentYieldsEmptyPaths() {
        let empty = RunContext.forDocument(path: nil, currentWord: "w")
        // An empty value still quotes, so the shell sees an empty argument
        // rather than the argument disappearing and shifting the ones after it.
        XCTAssertEqual(RunCommandExpander.expand("$(FULL_CURRENT_PATH)", with: empty), "''")
        XCTAssertEqual(RunCommandExpander.expand("$(CURRENT_WORD)", with: empty), "'w'")
    }

    func testStorePersistsCommands() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-run-\(UUID().uuidString)", isDirectory: true)
        let store = try RunCommandStore(directory: dir)
        let command = RunCommand(name: "Build", command: "swiftc $(FILE_NAME)")
        try store.add(command)

        let reopened = try RunCommandStore(directory: dir)
        XCTAssertEqual(reopened.commands.map(\.name), ["Build"])

        try reopened.remove(id: command.id)
        XCTAssertTrue(try RunCommandStore(directory: dir).commands.isEmpty)
    }
}

@MainActor
final class MacroTests: XCTestCase {
    @MainActor
    private final class StubTarget: MacroPlaybackTarget {
        var inserted: [String] = []
        var commands: [String] = []
        var navigations: [String] = []
        var remainingBeforeEnd: Int
        init(remainingBeforeEnd: Int = 0) { self.remainingBeforeEnd = remainingBeforeEnd }

        func macroInsertText(_ text: String) {
            inserted.append(text)
            if remainingBeforeEnd > 0 { remainingBeforeEnd -= 1 }
        }
        func macroRunCommand(_ selectorName: String) { commands.append(selectorName) }
        func macroNavigate(_ movement: String) { navigations.append(movement) }
        var macroIsAtEndOfDocument: Bool { remainingBeforeEnd == 0 }
    }

    func testRecordingCapturesSteps() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.record(.command("selectAll:"))
        recorder.record(.navigation("moveLeft"))
        let steps = recorder.stop()
        XCTAssertEqual(steps, [.command("selectAll:"), .navigation("moveLeft")])
        XCTAssertFalse(recorder.isRecording)
    }

    func testNothingIsRecordedBeforeStart() {
        let recorder = MacroRecorder()
        recorder.record(.command("x"))
        XCTAssertTrue(recorder.steps.isEmpty)
    }

    /// Typing a word should produce one step, not one per keystroke.
    func testConsecutiveTypingIsCoalesced() {
        let recorder = MacroRecorder()
        recorder.start()
        for character in "hello" { recorder.record(.insertText(String(character))) }
        XCTAssertEqual(recorder.stop(), [.insertText("hello")])
    }

    func testTypingIsNotCoalescedAcrossACommand() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.record(.insertText("ab"))
        recorder.record(.command("cut:"))
        recorder.record(.insertText("cd"))
        XCTAssertEqual(recorder.stop(), [.insertText("ab"), .command("cut:"), .insertText("cd")])
    }

    func testStartingAgainDiscardsPreviousRecording() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.record(.insertText("old"))
        recorder.start()
        recorder.record(.insertText("new"))
        XCTAssertEqual(recorder.stop(), [.insertText("new")])
    }

    func testPlaybackRunsEveryStep() {
        let target = StubTarget()
        let macro = Macro(name: "m", steps: [.insertText("x"), .command("c"), .navigation("n")])
        MacroPlayer.play(macro, on: target)
        XCTAssertEqual(target.inserted, ["x"])
        XCTAssertEqual(target.commands, ["c"])
        XCTAssertEqual(target.navigations, ["n"])
    }

    func testPlaybackRepeatsRequestedNumberOfTimes() {
        let target = StubTarget()
        MacroPlayer.play(Macro(name: "m", steps: [.insertText("x")]), on: target, times: 3)
        XCTAssertEqual(target.inserted.count, 3)
    }

    func testZeroOrNegativeRepeatsDoNothing() {
        let target = StubTarget()
        MacroPlayer.play(Macro(name: "m", steps: [.insertText("x")]), on: target, times: 0)
        XCTAssertTrue(target.inserted.isEmpty)
    }

    func testPlayUntilEndOfDocument() {
        let target = StubTarget(remainingBeforeEnd: 4)
        MacroPlayer.playUntilEndOfDocument(Macro(name: "m", steps: [.insertText("x")]), on: target)
        XCTAssertEqual(target.inserted.count, 4)
    }

    /// A macro that never advances must not hang the app.
    func testPlayUntilEndStopsAtSafetyLimit() {
        let target = StubTarget(remainingBeforeEnd: 1)
        target.remainingBeforeEnd = 1
        let neverAdvances = Macro(name: "m", steps: [.command("noop")])
        MacroPlayer.playUntilEndOfDocument(neverAdvances, on: target, safetyLimit: 10)
        XCTAssertEqual(target.commands.count, 10, "the safety limit stops a non-advancing macro")
    }

    func testMacroRoundTripsThroughDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-macro-\(UUID().uuidString)", isDirectory: true)
        let store = try MacroStore(directory: dir)
        let macro = Macro(name: "Wrap", steps: [.insertText("<b>"), .command("moveToEndOfLine:")])
        try store.add(macro)

        let reopened = try MacroStore(directory: dir)
        XCTAssertEqual(reopened.macros.first?.name, "Wrap")
        XCTAssertEqual(reopened.macros.first?.steps, macro.steps, "steps survive encoding")
    }
}
