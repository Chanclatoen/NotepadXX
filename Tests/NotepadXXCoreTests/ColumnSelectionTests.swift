import XCTest
@testable import NotepadXXCore

final class ColumnSelectionTests: XCTestCase {
    private let sample = "abcdef\nghijkl\nmnopqr\n"

    func testPositionAndOffsetRoundTrip() {
        for offset in [0, 3, 6, 7, 10, 14] {
            let position = ColumnSelection.position(ofOffset: offset, in: sample)
            XCTAssertEqual(ColumnSelection.offset(of: position, in: sample), offset,
                           "round trip for offset \(offset)")
        }
    }

    func testPositionKnowsLineAndColumn() {
        XCTAssertEqual(ColumnSelection.position(ofOffset: 0, in: sample), TextPosition(line: 0, column: 0))
        XCTAssertEqual(ColumnSelection.position(ofOffset: 8, in: sample), TextPosition(line: 1, column: 1))
    }

    func testRectangleProducesOneRangePerLine() {
        let ranges = ColumnSelection.ranges(
            in: sample,
            from: TextPosition(line: 0, column: 1),
            to: TextPosition(line: 2, column: 4)
        )
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[0], NSRange(location: 1, length: 3))    // "bcd"
        XCTAssertEqual(ranges[1], NSRange(location: 8, length: 3))    // "hij"
        XCTAssertEqual(ranges[2], NSRange(location: 15, length: 3))   // "nop"
    }

    func testCornerOrderDoesNotMatter() {
        let forward = ColumnSelection.ranges(in: sample,
            from: TextPosition(line: 0, column: 1), to: TextPosition(line: 2, column: 4))
        let reversed = ColumnSelection.ranges(in: sample,
            from: TextPosition(line: 2, column: 4), to: TextPosition(line: 0, column: 1))
        XCTAssertEqual(forward, reversed, "dragging up-left must equal dragging down-right")
    }

    func testRaggedLinesYieldEmptyRangesRatherThanBeingDropped() {
        // Middle line is shorter than the selected column span.
        let text = "abcdef\ngh\nmnopqr\n"
        let ranges = ColumnSelection.ranges(in: text,
            from: TextPosition(line: 0, column: 3), to: TextPosition(line: 2, column: 5))
        XCTAssertEqual(ranges.count, 3, "every spanned line contributes a range")
        XCTAssertEqual(ranges[1].length, 0, "the short line collapses to an insertion point")
        XCTAssertEqual(ranges[1].location, 9, "clamped to the end of the short line")
    }

    func testSingleLineRectangleIsAPlainRange() {
        let ranges = ColumnSelection.ranges(in: sample,
            from: TextPosition(line: 1, column: 1), to: TextPosition(line: 1, column: 4))
        XCTAssertEqual(ranges, [NSRange(location: 8, length: 3)])
    }

    func testZeroWidthRectangleGivesCaretsOnEveryLine() {
        let ranges = ColumnSelection.ranges(in: sample,
            from: TextPosition(line: 0, column: 2), to: TextPosition(line: 2, column: 2))
        XCTAssertEqual(ranges.count, 3)
        XCTAssertTrue(ranges.allSatisfy { $0.length == 0 }, "a zero-width column is multi-caret")
    }

    func testOutOfRangeLinesAreClamped() {
        let ranges = ColumnSelection.ranges(in: sample,
            from: TextPosition(line: 0, column: 0), to: TextPosition(line: 99, column: 2))
        XCTAssertLessThanOrEqual(ranges.count, 4)
    }
}

final class ColumnEditorTests: XCTestCase {
    func testInsertTextOnEveryLineOfTheBlock() {
        let result = ColumnSelection.insertText("> ", in: "aaa\nbbb\nccc\n", lines: 0...2, column: 0)
        XCTAssertEqual(result, "> aaa\n> bbb\n> ccc\n")
    }

    func testInsertTextAtAnInnerColumn() {
        let result = ColumnSelection.insertText("-", in: "abc\ndef\n", lines: 0...1, column: 1)
        XCTAssertEqual(result, "a-bc\nd-ef\n")
    }

    func testShortLinesArePaddedSoTheBlockStaysAligned() {
        let result = ColumnSelection.insertText("X", in: "abcdef\nab\n", lines: 0...1, column: 4)
        XCTAssertEqual(result, "abcdXef\nab  X\n", "the short line is space-padded out to the column")
    }

    func testOnlyTheSelectedLinesAreTouched() {
        let result = ColumnSelection.insertText("#", in: "a\nb\nc\n", lines: 1...1, column: 0)
        XCTAssertEqual(result, "a\n#b\nc\n")
    }

    func testInsertIncrementingNumbers() {
        let result = ColumnSelection.insertNumbers(
            in: "a\nb\nc\n", lines: 0...2, column: 0, initial: 1, increment: 1
        )
        XCTAssertEqual(result, "1a\n2b\n3c\n")
    }

    func testNumberIncrementOtherThanOne() {
        let result = ColumnSelection.insertNumbers(
            in: "a\nb\nc\n", lines: 0...2, column: 0, initial: 10, increment: 5
        )
        XCTAssertEqual(result, "10a\n15b\n20c\n")
    }

    func testLeadingZerosPadToTheWidestValue() {
        let result = ColumnSelection.insertNumbers(
            in: "a\nb\nc\n", lines: 0...2, column: 0,
            initial: 8, increment: 1, leadingZeros: true
        )
        XCTAssertEqual(result, "08a\n09b\n10c\n")
    }

    func testRepeatCountHoldsEachNumberForSeveralLines() {
        let result = ColumnSelection.insertNumbers(
            in: "a\nb\nc\nd\n", lines: 0...3, column: 0,
            initial: 1, increment: 1, repeatCount: 2
        )
        XCTAssertEqual(result, "1a\n1b\n2c\n2d\n")
    }

    func testHexadecimalAndBinaryFormats() {
        XCTAssertEqual(
            ColumnSelection.insertNumbers(in: "a\nb\n", lines: 0...1, column: 0,
                                          initial: 14, increment: 1, format: .hexadecimal),
            "ea\nfb\n"
        )
        XCTAssertEqual(
            ColumnSelection.insertNumbers(in: "a\nb\n", lines: 0...1, column: 0,
                                          initial: 2, increment: 1, format: .binary),
            "10a\n11b\n"
        )
    }
}
