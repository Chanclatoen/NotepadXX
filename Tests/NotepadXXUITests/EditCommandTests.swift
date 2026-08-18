import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Drives Edit-menu commands through the window controller so the wiring —
/// selection handling, editor round-trip, dirty flags — is covered, not just
/// the pure string functions underneath.
@MainActor
final class EditCommandTests: XCTestCase {
    private func makeController(_ text: String) -> (MainWindowController, TextDocument) {
        let controller = MainWindowController()
        let document = TextDocument(text: text)
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window          // force the editor to be installed
        return (controller, document)
    }

    func testDuplicateCurrentLineActsOnTheCaretLine() {
        let (controller, document) = makeController("a\nb\nc\n")
        controller.currentEditor?.selectedRange = NSRange(location: 2, length: 0)   // line "b"
        controller.duplicateLinesAction(nil)
        XCTAssertEqual(document.text, "a\nb\nb\nc\n")
    }

    func testRemoveCurrentLine() {
        let (controller, document) = makeController("a\nb\nc\n")
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        controller.removeLinesAction(nil)
        XCTAssertEqual(document.text, "b\nc\n")
    }

    func testMoveLineDownThenUpIsIdentity() {
        let (controller, document) = makeController("a\nb\nc\n")
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        controller.moveLinesDownAction(nil)
        XCTAssertEqual(document.text, "b\na\nc\n")
        controller.currentEditor?.selectedRange = NSRange(location: 2, length: 0)
        controller.moveLinesUpAction(nil)
        XCTAssertEqual(document.text, "a\nb\nc\n")
    }

    func testMultiLineSelectionAffectsEveryTouchedLine() {
        let (controller, document) = makeController("a\nb\nc\n")
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        controller.duplicateLinesAction(nil)
        XCTAssertEqual(document.text, "a\nb\na\nb\nc\n")
    }

    func testCaseConversionUsesSelectionWhenPresent() {
        let (controller, document) = makeController("hello world")
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 5)
        controller.convertUpperCaseAction(nil)
        XCTAssertEqual(document.text, "HELLO world", "only the selection is converted")
    }

    func testCaseConversionFallsBackToWholeDocument() {
        let (controller, document) = makeController("hello world")
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        controller.convertUpperCaseAction(nil)
        XCTAssertEqual(document.text, "HELLO WORLD")
    }

    func testSortAndDedupe() {
        let (controller, document) = makeController("b\na\nb\n")
        controller.sortLinesAscendingAction(nil)
        XCTAssertEqual(document.text, "a\nb\nb\n")
        controller.removeAllDuplicatesAction(nil)
        XCTAssertEqual(document.text, "a\nb\n")
    }

    func testBlankOperations() {
        let (controller, document) = makeController("a  \n\nb\t\n")
        controller.trimTrailingSpaceAction(nil)
        XCTAssertEqual(document.text, "a\n\nb\n")
        controller.removeEmptyLinesAction(nil)
        XCTAssertEqual(document.text, "a\nb\n")
    }

    func testTabConversionUsesConfiguredWidth() {
        let (controller, document) = makeController("\tx\n")
        controller.tabWidth = 2
        controller.tabsToSpacesAction(nil)
        XCTAssertEqual(document.text, "  x\n")
    }

    func testEOLConversionMarksDirtyWithoutChangingText() {
        let (controller, document) = makeController("a\nb\n")
        XCTAssertFalse(document.isDirty)
        controller.convertToWindowsEOLAction(nil)
        XCTAssertEqual(document.lineEnding, .crlf)
        XCTAssertEqual(document.text, "a\nb\n", "in-memory text stays LF-normalised")
        XCTAssertTrue(document.isDirty)
    }

    func testConvertEncodingMarksDirty() {
        let (controller, document) = makeController("x")
        controller.convertToUTF8BOMAction(nil)
        XCTAssertEqual(document.encoding, .utf8BOM)
        XCTAssertTrue(document.isDirty)
    }

    func testEditingThroughCommandsMarksDocumentDirty() {
        let (controller, document) = makeController("b\na\n")
        XCTAssertFalse(document.isDirty)
        controller.sortLinesAscendingAction(nil)
        XCTAssertTrue(document.isDirty, "a command that changes text must mark the tab dirty")
    }
}

/// Find/replace driven through the controller and its panel.
@MainActor
final class SearchCommandTests: XCTestCase {
    private func makeController(_ text: String) -> (MainWindowController, TextDocument) {
        let controller = MainWindowController()
        let document = TextDocument(text: text)
        controller.adopt(documents: [document], activeIndex: 0)
        _ = controller.window
        return (controller, document)
    }

    private func request(_ pattern: String, replacement: String = "",
                         options: SearchOptions = SearchOptions(),
                         inSelection: Bool = false) -> FindPanelController.Request {
        FindPanelController.Request(pattern: pattern, replacement: replacement,
                                    options: options, inSelection: inSelection)
    }

    func testFindSelectsTheMatch() {
        let (controller, _) = makeController("one needle two")
        controller.performFind(request("needle"))
        XCTAssertEqual(controller.currentEditor?.selectedRange, NSRange(location: 4, length: 6))
    }

    func testFindAdvancesThroughMatches() {
        let (controller, _) = makeController("a a a")
        controller.performFind(request("a"))
        XCTAssertEqual(controller.currentEditor?.selectedRange.location, 0)
        controller.performFind(request("a"))
        XCTAssertEqual(controller.currentEditor?.selectedRange.location, 2)
        controller.performFind(request("a"))
        XCTAssertEqual(controller.currentEditor?.selectedRange.location, 4)
    }

    func testReplaceAllUpdatesDocument() {
        let (controller, document) = makeController("cat cat cat")
        controller.performReplaceAll(request("cat", replacement: "dog"))
        XCTAssertEqual(document.text, "dog dog dog")
        XCTAssertTrue(document.isDirty)
    }

    func testReplaceAllRegexWithGroups() {
        let (controller, document) = makeController("bob@host")
        controller.performReplaceAll(
            request("(\\w+)@(\\w+)", replacement: "$2:$1", options: SearchOptions(mode: .regex))
        )
        XCTAssertEqual(document.text, "host:bob")
    }

    func testReplaceAllInSelectionLeavesTheRestAlone() {
        let (controller, document) = makeController("aaa aaa")
        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        controller.performReplaceAll(request("a", replacement: "b", inSelection: true))
        XCTAssertEqual(document.text, "bbb aaa")
    }

    func testInvalidRegexDoesNotModifyTheDocument() {
        let (controller, document) = makeController("abc")
        controller.performReplaceAll(
            request("(unclosed", replacement: "x", options: SearchOptions(mode: .regex))
        )
        XCTAssertEqual(document.text, "abc", "a bad pattern must be reported, not applied")
    }

    func testGoToLineMovesTheCaret() {
        let (controller, _) = makeController("one\ntwo\nthree\n")
        controller.currentEditor?.goToLine(3)
        XCTAssertEqual(controller.currentEditor?.caretPosition().line, 3)
    }
}
