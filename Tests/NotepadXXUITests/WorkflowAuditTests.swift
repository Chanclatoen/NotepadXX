import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Drives complete user workflows the way a person would, rather than testing
/// a model in isolation. Its job is to find commands that are wired up but do
/// not actually do anything useful.
@MainActor
final class WorkflowAuditTests: XCTestCase {
    private func controller(_ text: String = "") -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        _ = controller.window
        return controller
    }

    /// Typing is the single most basic thing an editor does.
    func testTypingReachesTheDocument() {
        let controller = self.controller()
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        editor.textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.text, "hello", "text typed into the view reaches the editor")
        XCTAssertEqual(controller.activeDocument?.text, "hello",
                       "and propagates to the document, so it would be saved")
    }

    func testTypingMarksTheTabDirty() {
        let controller = self.controller("start")
        controller.currentEditor?.textView.insertText("x", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertTrue(controller.activeDocument?.isDirty ?? false)
    }

    func testUndoAfterTyping() {
        let controller = self.controller("abc")
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        editor.textView.insertText("Z", replacementRange: NSRange(location: 3, length: 0))
        XCTAssertEqual(editor.text, "abcZ")
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.text, "abc", "undo restores the previous text")
    }

    func testFindSelectsAndReplaceRewrites() {
        let controller = self.controller("alpha beta alpha")
        controller.performFind(.init(pattern: "beta", replacement: "", options: SearchOptions(), inSelection: false))
        XCTAssertEqual(controller.currentEditor?.selectedRange.location, 6)

        controller.performReplaceAll(.init(pattern: "alpha", replacement: "gamma",
                                           options: SearchOptions(), inSelection: false))
        XCTAssertEqual(controller.activeDocument?.text, "gamma beta gamma")
    }

    /// Edit-menu commands must operate on the caret's line, then write back.
    func testLineOperationsRoundTripThroughTheEditor() {
        let controller = self.controller("one\ntwo\nthree\n")
        controller.currentEditor?.selectedRange = NSRange(location: 4, length: 0)
        controller.duplicateLinesAction(nil)
        XCTAssertEqual(controller.activeDocument?.text, "one\ntwo\ntwo\nthree\n")
        XCTAssertEqual(controller.currentEditor?.text, controller.activeDocument?.text,
                       "the view and the document agree after a command")
    }

    func testSortAndCaseConversionApply() {
        let controller = self.controller("b\na\nc\n")
        controller.sortLinesAscendingAction(nil)
        XCTAssertEqual(controller.activeDocument?.text, "a\nb\nc\n")

        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 1)
        controller.convertUpperCaseAction(nil)
        XCTAssertEqual(controller.activeDocument?.text, "A\nb\nc\n")
    }

    /// A macro must replay against the real editor, not a stub.
    func testMacroRecordAndPlaybackAffectsTheDocument() {
        let controller = self.controller("x")
        controller.currentEditor?.selectedRange = NSRange(location: 1, length: 0)
        controller.toggleMacroRecordingAction(nil)
        controller.macroInsertText("-recorded")
        controller.toggleMacroRecordingAction(nil)

        let before = controller.currentEditor?.text ?? ""
        controller.playbackMacroAction(nil)
        XCTAssertNotEqual(controller.currentEditor?.text, before, "playback changed the buffer")
    }

    func testSavingWritesTheEditorContentsNotTheStaleDocument() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("f.txt")
        try Data("original".utf8).write(to: url)

        let controller = MainWindowController()
        _ = controller.window
        XCTAssertTrue(controller.openOrFocus(url: url))

        controller.currentEditor?.textView.insertText(
            " edited", replacementRange: NSRange(location: 8, length: 0)
        )
        controller.saveDocumentAction(nil)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "original edited",
                       "what was typed is what lands on disk")
    }

    /// Switching tabs must show the other document, not keep the first one.
    func testSwitchingTabsSwapsTheVisibleText() {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "first"), TextDocument(text: "second")],
                         activeIndex: 0)
        _ = controller.window
        XCTAssertEqual(controller.currentEditor?.text, "first")
        controller.selectTab(at: 1)
        XCTAssertEqual(controller.currentEditor?.text, "second")
    }

    func testGoToLineMovesTheCaretAndStatusFollows() {
        let controller = self.controller("a\nb\nc\nd\n")
        controller.currentEditor?.goToLine(3)
        XCTAssertEqual(controller.currentEditor?.caretPosition().line, 3)
    }

    /// Column mode: typing with several ranges selected edits every line.
    func testColumnSelectionEditsEveryLine() {
        let controller = self.controller("aaa\nbbb\nccc\n")
        guard let editor = controller.currentEditor else { return XCTFail("no editor") }
        let ranges = ColumnSelection.ranges(
            in: editor.text,
            from: TextPosition(line: 0, column: 0), to: TextPosition(line: 2, column: 0)
        )
        editor.textView.selectionManager.setSelectedRanges(ranges)
        editor.textView.insertText(">", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(editor.text, ">aaa\n>bbb\n>ccc\n",
                       "typing with a column selection prefixes every line")
    }

    func testEncodingAndEOLCommandsReachTheDocument() {
        let controller = self.controller("a\nb\n")
        controller.convertToWindowsEOLAction(nil)
        XCTAssertEqual(controller.activeDocument?.lineEnding, .crlf)
        controller.convertToUTF8BOMAction(nil)
        XCTAssertEqual(controller.activeDocument?.encoding, .utf8BOM)
    }

    func testLanguageChangeRepaintsAndUpdatesStatus() {
        let controller = self.controller("select 1")
        controller.applyLanguage(named: "SQL")
        XCTAssertEqual(controller.currentEditor?.language?.name, "SQL")
        XCTAssertEqual(controller.activeDocument?.languageName, "SQL")
    }
}
