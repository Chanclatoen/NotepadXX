import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore
@testable import NotepadXXEditor

@MainActor
final class MultiCaretTests: XCTestCase {
    private func make(_ text: String) -> (MainWindowController, EditorViewController) {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        return (controller, controller.currentEditor!)
    }

    func testAddingCarets() {
        let (_, editor) = make("abc def ghi")
        editor.selectedRange = NSRange(location: 0, length: 0)
        editor.addCaret(at: 4)
        editor.addCaret(at: 8)
        XCTAssertEqual(editor.selectedRanges.count, 3)
        XCTAssertEqual(editor.selectedRanges.map(\.location), [0, 4, 8])
    }

    func testDuplicateCaretIsIgnored() {
        let (_, editor) = make("abc")
        editor.selectedRange = NSRange(location: 1, length: 0)
        editor.addCaret(at: 1)
        XCTAssertEqual(editor.selectedRanges.count, 1, "a second caret in one place is refused")
    }

    /// First press selects the word; the next adds a caret on the following one.
    func testSelectNextOccurrenceGrowsTheSelection() {
        let (controller, editor) = make("widget a widget b widget")
        editor.selectedRange = NSRange(location: 2, length: 0)

        controller.selectNextOccurrenceAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, 1)
        XCTAssertEqual(editor.selectedRanges.first?.length, 6, "the word under the caret")

        controller.selectNextOccurrenceAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, 2)
        controller.selectNextOccurrenceAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, 3)
    }

    func testSelectAllOccurrencesPutsACaretOnEach() {
        let (controller, editor) = make("cat dog cat bird cat")
        editor.selectedRange = NSRange(location: 1, length: 0)
        controller.selectAllOccurrencesAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, 3)
    }

    func testSelectAllOccurrencesIsWholeWordFromACaret() {
        let (controller, editor) = make("cat concat cat")
        editor.selectedRange = NSRange(location: 0, length: 0)
        controller.selectAllOccurrencesAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, 2, "concat is not a whole-word match")
    }

    func testUndoLastCaret() {
        let (controller, editor) = make("a a a")
        editor.selectedRange = NSRange(location: 0, length: 1)
        controller.selectNextOccurrenceAction(nil)
        controller.selectNextOccurrenceAction(nil)
        let before = editor.selectedRanges.count

        controller.removeLastCaretAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, before - 1)
    }

    func testCollapseReturnsToOneCaret() {
        let (controller, editor) = make("x x x")
        editor.selectedRanges = [NSRange(location: 0, length: 1),
                                 NSRange(location: 2, length: 1)]
        controller.collapseCaretsAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, 1)
        XCTAssertEqual(editor.selectedRanges.first?.location, 0, "kept the first")
    }

    func testSplitSelectionIntoLines() {
        let (controller, editor) = make("one\ntwo\nthree\n")
        editor.selectedRange = NSRange(location: 0, length: 13)
        controller.splitSelectionIntoLinesAction(nil)
        XCTAssertEqual(editor.selectedRanges.count, 3, "a caret per touched line")
        XCTAssertTrue(editor.selectedRanges.allSatisfy { $0.length == 0 })
    }

    /// The point of multi-caret: one keystroke edits every caret.
    func testTypingWithSeveralCaretsEditsEveryOne() {
        let (_, editor) = make("aaa\nbbb\nccc\n")
        editor.selectedRanges = [NSRange(location: 0, length: 0),
                                 NSRange(location: 4, length: 0),
                                 NSRange(location: 8, length: 0)]
        editor.textView.insertText(">", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(editor.text, ">aaa\n>bbb\n>ccc\n")
    }

    func testReplacingSeveralSelectionsAtOnce() {
        let (controller, editor) = make("cat cat cat")
        editor.selectedRange = NSRange(location: 0, length: 0)
        controller.selectAllOccurrencesAction(nil)
        editor.textView.insertText("dog", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(editor.text, "dog dog dog")
    }

    func testNoWordUnderCaretIsHandled() {
        let (_, editor) = make("   ")
        editor.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertFalse(editor.selectNextOccurrence(), "nothing to select, reported honestly")
    }
}

@MainActor
final class MultiCaretStatusTests: XCTestCase {
    private func labels(in view: NSView) -> String {
        var found = view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        for sub in view.subviews { found += labels(in: sub).isEmpty ? [] : [labels(in: sub)] }
        return found.joined(separator: " | ")
    }

    /// With several carets a single Ln/Col is meaningless, and the totals must
    /// span every selection or the bar under-reports what a keystroke affects.
    func testStatusBarReportsCaretCountAndTotalSelection() {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "cat cat cat")], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 1100, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()

        controller.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        controller.selectAllOccurrencesAction(nil)

        let text = labels(in: controller.statusBar)
        XCTAssertTrue(text.contains("3 carets"), "caret count shown, got: \(text)")
        // The design writes the status bar without colons: "Sel 9 | 3".
        XCTAssertTrue(text.contains("Sel 9"), "all three selections counted, got: \(text)")
    }

    func testSingleCaretStillShowsLineAndColumn() {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "abc")], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 1100, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        controller.currentEditor?.selectedRange = NSRange(location: 1, length: 0)
        controller.refreshUI()

        let text = labels(in: controller.statusBar)
        XCTAssertTrue(text.contains("Ln 1"), "got: \(text)")
        XCTAssertFalse(text.contains("carets"))
    }
}
