import XCTest
@testable import NotepadXXCore

final class ChangeHistoryTests: XCTestCase {
    func testEditingMarksALineModified() {
        var history = ChangeHistory()
        history.recordEdit(atLine: 3)
        XCTAssertEqual(history.state(of: 3), .modified)
        XCTAssertEqual(history.state(of: 4), .unchanged)
    }

    /// The two tiers are the point of the margin: unsaved versus touched.
    func testSavingPromotesModifiedToSaved() {
        var history = ChangeHistory()
        history.recordEdit(atLine: 1)
        history.didSave()
        XCTAssertEqual(history.state(of: 1), .saved)
        XCTAssertTrue(history.modifiedLines.isEmpty)
    }

    func testEditingASavedLineMakesItModifiedAgain() {
        var history = ChangeHistory()
        history.recordEdit(atLine: 2)
        history.didSave()
        history.recordEdit(atLine: 2)
        XCTAssertEqual(history.state(of: 2), .modified)
        XCTAssertFalse(history.savedLines.contains(2), "a line is in exactly one tier")
    }

    func testRangeEdits() {
        var history = ChangeHistory()
        history.recordEdit(inLines: 2...4)
        XCTAssertEqual(history.modifiedLines, [2, 3, 4])
    }

    func testResetClearsBothTiers() {
        var history = ChangeHistory()
        history.recordEdit(atLine: 1)
        history.didSave()
        history.recordEdit(atLine: 5)
        history.reset()
        XCTAssertTrue(history.isEmpty)
    }

    /// Inserting lines above a mark must carry it, or the margin points at
    /// unrelated lines after an edit.
    func testShiftMovesMarksBelowAnEdit() {
        var history = ChangeHistory()
        history.recordEdit(atLine: 1)
        history.recordEdit(atLine: 6)
        history.didSave()
        history.recordEdit(atLine: 8)

        history.shift(fromLine: 5, by: 2)
        XCTAssertTrue(history.savedLines.contains(1), "marks above the edit stay put")
        XCTAssertTrue(history.savedLines.contains(8), "6 moved to 8")
        XCTAssertTrue(history.modifiedLines.contains(10), "8 moved to 10")
    }

    func testShiftDropsMarksDeletedOutOfExistence() {
        var history = ChangeHistory()
        history.recordEdit(inLines: 0...2)
        history.shift(fromLine: 0, by: -2)
        XCTAssertEqual(history.modifiedLines, [0])
    }

    func testNavigationWraps() {
        var history = ChangeHistory()
        history.recordEdit(atLine: 2)
        history.recordEdit(atLine: 7)
        XCTAssertEqual(history.nextChange(after: 2), 7)
        XCTAssertEqual(history.nextChange(after: 7), 2, "wraps to the first")
        XCTAssertEqual(history.previousChange(before: 7), 2)
        XCTAssertEqual(history.previousChange(before: 2), 7, "wraps to the last")
    }

    func testNavigationOnAnUnchangedDocumentIsNil() {
        let history = ChangeHistory()
        XCTAssertNil(history.nextChange(after: 0))
        XCTAssertNil(history.previousChange(before: 0))
    }
}

final class URLDetectionTests: XCTestCase {
    func testFindsHTTPLinks() {
        let text = "see https://example.com/page for more"
        let links = URLDetection.links(in: text)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url.absoluteString, "https://example.com/page")
    }

    func testFindsSeveralLinksOnOneLine() {
        let links = URLDetection.links(in: "http://a.example http://b.example")
        XCTAssertEqual(links.count, 2)
    }

    func testPlainTextHasNoLinks() {
        XCTAssertTrue(URLDetection.links(in: "just some words here").isEmpty)
    }

    func testLinkAtLocation() {
        let text = "prefix https://example.com suffix"
        let inside = (text as NSString).range(of: "https://example.com").location + 3
        XCTAssertNotNil(URLDetection.link(at: inside, in: text))
        XCTAssertNil(URLDetection.link(at: 0, in: text), "the caret is not on a link")
    }

    func testLinkLookupIsSafeAtDocumentBounds() {
        XCTAssertNil(URLDetection.link(at: 0, in: ""))
        XCTAssertNil(URLDetection.link(at: 999, in: "short"))
    }

    /// A click only needs the surrounding line, not the whole document.
    func testLookupOnALargeDocumentIsFast() {
        let text = String(repeating: "no links on this line at all\n", count: 100_000)
            + "https://example.com\n"
        let target = (text as NSString).range(of: "https://example.com").location + 2
        let start = Date()
        XCTAssertNotNil(URLDetection.link(at: target, in: text))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
