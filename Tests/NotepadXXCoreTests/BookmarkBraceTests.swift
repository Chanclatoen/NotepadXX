import XCTest
@testable import NotepadXXCore

final class BookmarksTests: XCTestCase {
    func testToggleAddsAndRemoves() {
        var bookmarks = Bookmarks()
        bookmarks.toggle(3)
        XCTAssertTrue(bookmarks.contains(3))
        bookmarks.toggle(3)
        XCTAssertFalse(bookmarks.contains(3))
    }

    func testNextAndPreviousWrapAround() {
        let bookmarks = Bookmarks(lines: [2, 5, 9])
        XCTAssertEqual(bookmarks.next(after: 2), 5)
        XCTAssertEqual(bookmarks.next(after: 9), 2, "wraps to the first")
        XCTAssertEqual(bookmarks.previous(before: 5), 2)
        XCTAssertEqual(bookmarks.previous(before: 2), 9, "wraps to the last")
    }

    func testNavigationOnEmptySetIsNil() {
        let bookmarks = Bookmarks()
        XCTAssertNil(bookmarks.next(after: 0))
        XCTAssertNil(bookmarks.previous(before: 0))
    }

    func testInvert() {
        var bookmarks = Bookmarks(lines: [1])
        bookmarks.invert(totalLines: 4)
        XCTAssertEqual(bookmarks.lines, [0, 2, 3])
    }

    /// Inserting lines above a bookmark must carry it along, or bookmarks drift
    /// onto unrelated lines after an edit.
    func testShiftMovesBookmarksBelowAnEdit() {
        var bookmarks = Bookmarks(lines: [1, 5])
        bookmarks.shift(fromLine: 3, by: 2)
        XCTAssertEqual(bookmarks.lines, [1, 7], "only bookmarks at or below the edit move")
    }

    func testShiftDropsBookmarksPushedAboveZero() {
        var bookmarks = Bookmarks(lines: [0, 1, 5])
        bookmarks.shift(fromLine: 0, by: -2)
        XCTAssertEqual(bookmarks.lines, [3], "lines deleted out of existence are dropped")
    }

    func testMarkedTextInDocumentOrder() {
        let bookmarks = Bookmarks(lines: [2, 0])
        XCTAssertEqual(bookmarks.markedText(in: "a\nb\nc\n"), "a\nc")
    }

    func testRemovingMarkedLines() {
        let bookmarks = Bookmarks(lines: [1])
        XCTAssertEqual(bookmarks.removingMarkedLines(from: "a\nb\nc\n"), "a\nc\n")
    }
}

final class BraceMatchingTests: XCTestCase {
    func testMatchesForward() {
        XCTAssertEqual(BraceMatching.match(in: "(abc)", at: 0), 4)
        XCTAssertEqual(BraceMatching.match(in: "[a]", at: 0), 2)
        XCTAssertEqual(BraceMatching.match(in: "{}", at: 0), 1)
    }

    func testMatchesBackward() {
        XCTAssertEqual(BraceMatching.match(in: "(abc)", at: 4), 0)
    }

    func testNestedBrackets() {
        //          0123456789
        let text = "( a ( b ) )"
        XCTAssertEqual(BraceMatching.match(in: text, at: 0), 10, "outer matches outer")
        XCTAssertEqual(BraceMatching.match(in: text, at: 4), 8, "inner matches inner")
    }

    func testUnbalancedReturnsNil() {
        XCTAssertNil(BraceMatching.match(in: "(abc", at: 0))
        XCTAssertNil(BraceMatching.match(in: "abc)", at: 3))
    }

    func testCaretNotOnABracketReturnsNil() {
        XCTAssertNil(BraceMatching.match(in: "(abc)", at: 2))
    }

    /// A brace inside a string or comment must not match a real one.
    func testBracketsInStringsAndCommentsAreIgnored() {
        let text = "if (x) { let s = \"}\" }"
        // The brace at index 7 should match the final one at 21, not the one
        // inside the string literal.
        XCTAssertEqual(BraceMatching.match(in: text, at: 7, language: BuiltInLanguages.swift), 21)
    }

    func testBracketInsideACommentIsNotAStartingPoint() {
        let text = "// (\nlet x = 1\n"
        XCTAssertNil(BraceMatching.match(in: text, at: 3, language: BuiltInLanguages.swift),
                     "a bracket inside a comment has no partner")
    }

    func testEnclosingRangeCoversBothBrackets() {
        let range = BraceMatching.enclosingRange(in: "(ab)", at: 0)
        XCTAssertEqual(range, NSRange(location: 0, length: 4))
    }

    func testOutOfBoundsIsSafe() {
        XCTAssertNil(BraceMatching.match(in: "()", at: 99))
        XCTAssertNil(BraceMatching.match(in: "", at: 0))
    }
}
