import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Audit: every Edit and Search command, driven through the controller and
/// asserted against the resulting document text.
@MainActor
final class AuditEditTests: XCTestCase {
    private func make(_ text: String) -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        return controller
    }
    private func text(_ c: MainWindowController) -> String { c.activeDocument?.text ?? "" }
    private func caret(_ c: MainWindowController, _ location: Int) {
        c.currentEditor?.selectedRange = NSRange(location: location, length: 0)
    }
    private func select(_ c: MainWindowController, _ range: NSRange) {
        c.currentEditor?.selectedRange = range
    }

    // MARK: - Line operations

    func testDuplicateRemoveMoveJoin() {
        var c = make("a\nb\nc\n"); caret(c, 2); c.duplicateLinesAction(nil)
        XCTAssertEqual(text(c), "a\nb\nb\nc\n", "duplicate")

        c = make("a\nb\nc\n"); caret(c, 2); c.removeLinesAction(nil)
        XCTAssertEqual(text(c), "a\nc\n", "remove")

        c = make("a\nb\nc\n"); caret(c, 0); c.moveLinesDownAction(nil)
        XCTAssertEqual(text(c), "b\na\nc\n", "move down")

        c = make("a\nb\nc\n"); caret(c, 2); c.moveLinesUpAction(nil)
        XCTAssertEqual(text(c), "b\na\nc\n", "move up")

        c = make("a\nb\nc\n"); select(c, NSRange(location: 0, length: 3)); c.joinLinesAction(nil)
        XCTAssertTrue(text(c).hasPrefix("a b"), "join produced \(text(c))")
    }

    func testSortVariants() {
        var c = make("b\na\nc\n"); c.sortLinesAscendingAction(nil)
        XCTAssertEqual(text(c), "a\nb\nc\n", "ascending")

        c = make("a\nb\nc\n"); c.sortLinesDescendingAction(nil)
        XCTAssertEqual(text(c), "c\nb\na\n", "descending")

        c = make("10\n9\n100\n"); c.sortLinesIntegerAction(nil)
        XCTAssertEqual(text(c), "9\n10\n100\n", "numeric sort, not lexical")

        c = make("a\nb\nc\n"); c.reverseLineOrderAction(nil)
        XCTAssertEqual(text(c), "c\nb\na\n", "reverse")

        c = make("b\na\nb\n"); c.removeAllDuplicatesAction(nil)
        XCTAssertEqual(text(c), "b\na\n", "dedupe keeps first occurrence")
    }

    func testCaseConversions() {
        let cases: [(String, (MainWindowController) -> Void, String)] = [
            ("hello world", { $0.convertUpperCaseAction(nil) }, "HELLO WORLD"),
            ("HELLO", { $0.convertLowerCaseAction(nil) }, "hello"),
            ("hello world", { $0.convertProperCaseAction(nil) }, "Hello World"),
            ("hello world", { $0.convertSentenceCaseAction(nil) }, "Hello world"),
            ("Hello", { $0.convertInvertCaseAction(nil) }, "hELLO"),
        ]
        for (input, action, expected) in cases {
            let c = make(input)
            select(c, NSRange(location: 0, length: (input as NSString).length))
            action(c)
            XCTAssertEqual(text(c), expected, "converting \"\(input)\"")
        }
    }

    func testBlankOperations() {
        var c = make("a  \nb\t\n"); c.trimTrailingSpaceAction(nil)
        XCTAssertEqual(text(c), "a\nb\n", "trim trailing")

        c = make("  a\n  b\n"); c.trimLeadingSpaceAction(nil)
        XCTAssertEqual(text(c), "a\nb\n", "trim leading")

        c = make("a\n\n\nb\n"); c.removeEmptyLinesAction(nil)
        XCTAssertEqual(text(c), "a\nb\n", "remove empty lines")
    }

    func testTabSpaceConversion() {
        var c = make("\tx\n"); c.tabWidth = 4; c.tabsToSpacesAction(nil)
        XCTAssertEqual(text(c), "    x\n", "tabs to spaces")

        c = make("    x\n"); c.tabWidth = 4; c.spacesToTabsAction(nil)
        XCTAssertEqual(text(c), "\tx\n", "spaces to tabs")
    }

    func testInsertDateTimeAddsSomething() {
        let c = make("")
        c.insertDateTimeAction(nil)
        XCTAssertFalse(text(c).isEmpty, "a timestamp was inserted")
    }

    func testCommandsMarkTheDocumentDirty() {
        let c = make("b\na\n")
        XCTAssertFalse(c.activeDocument?.isDirty ?? true)
        c.sortLinesAscendingAction(nil)
        XCTAssertTrue(c.activeDocument?.isDirty ?? false)
    }

    /// A command must leave the view and the document agreeing, or the next
    /// save writes the wrong thing.
    func testViewAndDocumentAgreeAfterEveryCommand() {
        let commands: [(String, (MainWindowController) -> Void)] = [
            ("sort", { $0.sortLinesAscendingAction(nil) }),
            ("dedupe", { $0.removeAllDuplicatesAction(nil) }),
            ("trim", { $0.trimTrailingSpaceAction(nil) }),
            ("upper", { $0.convertUpperCaseAction(nil) }),
            ("duplicate", { $0.duplicateLinesAction(nil) }),
            ("removeEmpty", { $0.removeEmptyLinesAction(nil) }),
        ]
        for (name, action) in commands {
            let c = make("b  \n\na\nb\n")
            action(c)
            XCTAssertEqual(c.currentEditor?.text, c.activeDocument?.text,
                           "\(name) left the view and document out of sync")
        }
    }
}

@MainActor
final class AuditSearchTests: XCTestCase {
    private func make(_ text: String) -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        return controller
    }
    private func request(_ pattern: String, _ replacement: String = "",
                         _ options: SearchOptions = SearchOptions(),
                         inSelection: Bool = false) -> FindPanelController.Request {
        .init(pattern: pattern, replacement: replacement, options: options, inSelection: inSelection)
    }

    func testSearchModes() {
        // Normal treats the pattern literally.
        var c = make("a.c abc")
        c.performFind(request("a.c"))
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 0, "normal mode is literal")

        // Regex treats it as a pattern.
        c = make("xbc abc")
        c.performFind(request("a.c", "", SearchOptions(mode: .regex)))
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 4)

        // Extended understands escapes.
        c = make("a\tb")
        c.performFind(request("\\t", "", SearchOptions(mode: .extended)))
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 1, "\\t matched a real tab")
    }

    func testMatchCaseAndWholeWord() {
        var c = make("Alpha alpha")
        c.performFind(request("alpha", "", SearchOptions(matchCase: true)))
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 6, "case-sensitive skipped Alpha")

        c = make("alphabet alpha")
        c.performFind(request("alpha", "", SearchOptions(wholeWord: true)))
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 9, "whole word skipped alphabet")
    }

    func testWrapAroundAndBackward() {
        let c = make("x x x")
        c.currentEditor?.selectedRange = NSRange(location: 5, length: 0)
        c.performFind(request("x", "", SearchOptions(wrapAround: true)))
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 0, "search wrapped to the top")

        let back = make("x x x")
        back.currentEditor?.selectedRange = NSRange(location: 4, length: 0)
        back.performFind(request("x", "", SearchOptions(backward: true)))
        XCTAssertEqual(back.currentEditor?.selectedRange.location, 2, "searched backwards")
    }

    func testReplaceAllAndInSelection() {
        var c = make("a a a")
        c.performReplaceAll(request("a", "b"))
        XCTAssertEqual(c.activeDocument?.text, "b b b")

        c = make("a a a")
        c.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        c.performReplaceAll(request("a", "b", SearchOptions(), inSelection: true))
        XCTAssertEqual(c.activeDocument?.text, "b b a", "only the selection was replaced")
    }

    func testRegexCaptureGroupsInReplacement() {
        let c = make("john smith")
        c.performReplaceAll(request("(\\w+) (\\w+)", "$2, $1", SearchOptions(mode: .regex)))
        XCTAssertEqual(c.activeDocument?.text, "smith, john")
    }

    func testInvalidRegexLeavesTheDocumentAlone() {
        let c = make("abc")
        c.performReplaceAll(request("(unclosed", "x", SearchOptions(mode: .regex)))
        XCTAssertEqual(c.activeDocument?.text, "abc")
    }

    func testCountDoesNotModify() {
        let c = make("a a a")
        let before = c.activeDocument?.text
        c.performFind(request("a"))
        XCTAssertEqual(c.activeDocument?.text, before, "finding never edits")
    }

    /// Find in Files must search the edited buffer, not the stale file.
    func testFindInFilesSeesUnsavedBuffers() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-fif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("f.txt")
        try Data("on disk".utf8).write(to: url)

        let engine = SearchEngine(pattern: "needle", options: SearchOptions())
        let results = try FindInFiles(engine: engine).search(
            directory: dir, openBuffers: [url.path: "unsaved needle"]
        )
        XCTAssertEqual(results.count, 1, "the open buffer was searched, not the stale file")
    }
}
