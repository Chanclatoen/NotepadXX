import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class SearchNavigationTests: XCTestCase {
    private func make(_ text: String) -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: text)], activeIndex: 0)
        let window = controller.window!
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    /// Find Next with nothing typed should reuse the selection, which is how
    /// you search for the word you just highlighted.
    func testFindNextUsesTheSelection() {
        let c = make("cat dog cat")
        c.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        c.findNextAction(nil)
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 8, "jumped to the next cat")
    }

    func testFindNextFallsBackToHistory() {
        let c = make("alpha beta alpha")
        c.performFind(.init(pattern: "beta", replacement: "",
                            options: SearchOptions(), inSelection: false))
        c.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        c.findNextAction(nil)
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 6, "reused the last search")
    }

    func testFindPreviousSearchesBackwards() {
        let c = make("x y x y x")
        c.performFind(.init(pattern: "x", replacement: "",
                            options: SearchOptions(), inSelection: false))
        c.currentEditor?.selectedRange = NSRange(location: 8, length: 0)
        c.findPreviousAction(nil)
        XCTAssertLessThan(c.currentEditor?.selectedRange.location ?? 99, 8)
    }

    func testSelectAndFindNextTakesTheWordUnderTheCaret() {
        let c = make("widget a widget")
        c.currentEditor?.selectedRange = NSRange(location: 2, length: 0)
        c.selectAndFindNextAction(nil)
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 9, "found the second widget")
    }

    func testSearchIsRecordedInHistory() {
        let c = make("needle")
        c.performFind(.init(pattern: "needle", replacement: "thread",
                            options: SearchOptions(), inSelection: false))
        XCTAssertEqual(c.searchHistory?.entries(for: .pattern).first, "needle")
        XCTAssertEqual(c.searchHistory?.entries(for: .replacement).first, "thread")
    }

    func testMarkAllMarksEveryOccurrence() {
        let c = make("cat dog cat bird cat")
        c.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        c.markAllAction(nil)

        guard let id = c.activeDocument?.id else { return XCTFail("no document") }
        XCTAssertEqual(c.markedRanges[id]?.ranges(for: MarkStyle(index: 0)).count, 3)
    }

    func testMarkStylesAreIndependentAndClearable() {
        let c = make("cat dog cat")
        c.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        c.markAllAction(nil)

        c.activeMarkStyle = 1
        c.currentEditor?.selectedRange = NSRange(location: 4, length: 3)
        c.markAllAction(nil)

        guard let id = c.activeDocument?.id else { return XCTFail("no document") }
        XCTAssertEqual(c.markedRanges[id]?.ranges(for: MarkStyle(index: 0)).count, 2)
        XCTAssertEqual(c.markedRanges[id]?.ranges(for: MarkStyle(index: 1)).count, 1)

        c.clearMarksAction(nil)
        XCTAssertTrue(c.markedRanges[id]?.isEmpty ?? false)
    }

    func testCopyMarkedTextPutsMarksOnThePasteboard() {
        let c = make("cat dog cat")
        c.currentEditor?.selectedRange = NSRange(location: 0, length: 3)
        c.markAllAction(nil)
        c.copyMarkedTextAction(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "cat\ncat")
    }

    /// Escape must put the caret back where the search started.
    func testIncrementalSearchRestoresTheOriginOnCancel() {
        let c = make("alpha beta gamma")
        c.currentEditor?.selectedRange = NSRange(location: 12, length: 0)
        c.incrementalSearchAction(nil)
        XCTAssertEqual(c.incrementalOrigin, 12)

        c.currentEditor?.selectedRange = NSRange(location: 0, length: 5)
        c.incrementalBar?.onCancel?()
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 12, "returned to where we started")
    }

    func testIncrementalSearchMovesAsYouType() {
        let c = make("alpha beta gamma")
        c.currentEditor?.selectedRange = NSRange(location: 0, length: 0)
        c.incrementalSearchAction(nil)
        c.incrementalBar?.onQueryChanged?("gamma")
        XCTAssertEqual(c.currentEditor?.selectedRange.location, 11)
    }
}
