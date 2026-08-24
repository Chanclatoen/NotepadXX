import XCTest
@testable import NotepadXXCore

/// A text editor lives or dies on index arithmetic. Swift's String counts
/// characters, NSString counts UTF-16 units, and an emoji is two of the latter
/// — mixing them silently corrupts positions. These probe the seams.
final class UnicodeAuditTests: XCTestCase {
    // A line whose Character count and UTF-16 count differ at every stage.
    private let emoji = "let x = \"😀\" // 🇳🇱 café"

    func testColumnSelectionSurvivesAstralCharacters() {
        let text = "\(emoji)\nsecond line here\n"
        // Whatever it returns, it must not crash and must stay inside the text.
        let ranges = ColumnSelection.ranges(in: text,
                                            from: TextPosition(line: 0, column: 0),
                                            to: TextPosition(line: 1, column: 5))
        let length = (text as NSString).length
        for range in ranges {
            XCTAssertGreaterThanOrEqual(range.location, 0)
            XCTAssertLessThanOrEqual(NSMaxRange(range), length,
                                     "a column range runs past the end of the text")
        }
    }

    func testOccurrencesReturnsRangesValidForNSString() {
        let text = "😀 needle 🇳🇱 needle café needle"
        let ranges = Occurrences.all(of: "needle", in: text)
        XCTAssertEqual(ranges.count, 3)

        let content = text as NSString
        for range in ranges {
            XCTAssertLessThanOrEqual(NSMaxRange(range), content.length)
            XCTAssertEqual(content.substring(with: range), "needle",
                           "the range does not land on the word it found")
        }
    }

    func testSearchEngineRangesLandOnTheMatch() throws {
        let text = "🇳🇱 alpha 😀 alpha"
        let engine = SearchEngine(pattern: "alpha", options: SearchOptions())
        let matches = try engine.matches(in: text)
        XCTAssertEqual(matches.count, 2)

        let content = text as NSString
        for match in matches {
            XCTAssertEqual(content.substring(with: match.range), "alpha")
        }
    }

    /// Line and column reported for a caret must round-trip back to it.
    func testFindInFilesLineNumbersAreCorrectAcrossEmoji() throws {
        let text = "😀 first\n🇳🇱 second needle\nthird\n"
        let url = URL(fileURLWithPath: "/tmp/emoji.txt")
        let hits = try FindInFiles(engine: SearchEngine(pattern: "needle", options: SearchOptions()))
            .search(text: text, url: url)

        XCTAssertEqual(hits.count, 1)
        let hit = try XCTUnwrap(hits.first)
        XCTAssertEqual(hit.lineNumber, 2, "the hit is on the second line")

        // The in-line range must actually select the match within that line.
        let line = hit.lineText as NSString
        XCTAssertLessThanOrEqual(NSMaxRange(hit.rangeInLine), line.length,
                                 "rangeInLine runs past the line: \(hit.rangeInLine) in '\(hit.lineText)'")
        XCTAssertEqual(line.substring(with: hit.rangeInLine), "needle",
                       "the highlight lands on the wrong characters")
    }

    /// Auto-close inspects the characters around the caret.
    func testAutoCloseHandlesAstralNeighbours() {
        let text = "😀("
        let caret = (text as NSString).length
        // Must not crash on a caret whose preceding unit is half a surrogate pair.
        _ = AutoClose.action(for: "(", in: text, caret: caret)

        let quote = "café'"
        _ = AutoClose.action(for: "'", in: quote, caret: (quote as NSString).length)
    }

    /// Line splitting yields the content lines; a trailing newline terminates
    /// the last one rather than starting an empty extra. LineCountConsistency
    /// tests check this agrees with what the gutter and status bar report.
    func testLineSplittingCountsLinesNotCharacters() {
        let (lines, _) = LineOperations.split("😀\n🇳🇱\ncafé\n")
        XCTAssertEqual(lines.count, 3, "got: \(lines)")
        XCTAssertEqual(lines[0], "😀")
        XCTAssertEqual(lines[1], "🇳🇱")
    }
}
