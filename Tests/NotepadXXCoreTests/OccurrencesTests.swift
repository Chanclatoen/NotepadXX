import XCTest
@testable import NotepadXXCore

final class OccurrencesTests: XCTestCase {
    func testWordUnderCaret() {
        let text = "let widget = 1"
        XCTAssertEqual(Occurrences.word(at: 5, in: text)?.text, "widget")
        XCTAssertEqual(Occurrences.word(at: 4, in: text)?.text, "widget", "start of the word")
    }

    /// A caret sitting just past a word still counts as being on it, which is
    /// where it lands after you finish typing one.
    func testCaretJustPastAWordStillMatchesIt() {
        XCTAssertEqual(Occurrences.word(at: 10, in: "let widget = 1")?.text, "widget")
    }

    /// Whitespace on both sides means there is genuinely no word to take.
    /// A caret directly after a word still matches it — see the test above.
    func testCaretSurroundedByWhitespaceHasNoWord() {
        XCTAssertNil(Occurrences.word(at: 2, in: "a   b"))
        XCTAssertNil(Occurrences.word(at: 0, in: "   "))
    }

    func testUnderscoresAndDigitsAreWordCharacters() {
        XCTAssertEqual(Occurrences.word(at: 2, in: "my_var2 = 1")?.text, "my_var2")
    }

    func testFindsAllOccurrences() {
        XCTAssertEqual(Occurrences.all(of: "ab", in: "ab cab ab").count, 3)
    }

    func testWholeWordExcludesSubstrings() {
        let matches = Occurrences.all(of: "cat", in: "cat concat cats cat", wholeWord: true)
        XCTAssertEqual(matches.count, 2, "concat and cats are not whole-word matches")
    }

    func testNextWrapsAround() {
        let text = "x y x y x"
        XCTAssertEqual(Occurrences.next(of: "x", in: text, after: 0)?.location, 4)
        XCTAssertEqual(Occurrences.next(of: "x", in: text, after: 8)?.location, 0, "wrapped")
    }

    func testPreviousWrapsAround() {
        let text = "x y x"
        XCTAssertEqual(Occurrences.previous(of: "x", in: text, before: 4)?.location, 0)
        XCTAssertEqual(Occurrences.previous(of: "x", in: text, before: 0)?.location, 4, "wrapped")
    }

    func testEmptyNeedleFindsNothing() {
        XCTAssertTrue(Occurrences.all(of: "", in: "anything").isEmpty)
        XCTAssertNil(Occurrences.next(of: "", in: "anything", after: 0))
    }

    /// Two carets in one place would double every keystroke.
    func testNormalizedMergesOverlappingRanges() {
        let merged = Occurrences.normalized([
            NSRange(location: 0, length: 5),
            NSRange(location: 3, length: 5),
            NSRange(location: 20, length: 2),
        ])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first, NSRange(location: 0, length: 8), "overlap became a union")
    }

    func testNormalizedRemovesDuplicateCarets() {
        let merged = Occurrences.normalized([
            NSRange(location: 4, length: 0),
            NSRange(location: 4, length: 0),
        ])
        XCTAssertEqual(merged.count, 1)
    }

    func testNormalizedKeepsDocumentOrder() {
        let merged = Occurrences.normalized([
            NSRange(location: 30, length: 1),
            NSRange(location: 10, length: 1),
        ])
        XCTAssertEqual(merged.map(\.location), [10, 30])
    }
}
