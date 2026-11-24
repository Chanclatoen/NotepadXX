import XCTest
@testable import NotepadXXCore

final class LineCommandsTests: XCTestCase {

    // MARK: - Line comments

    func testCommentsEveryLineInTheRange() {
        XCTAssertEqual(LineOperations.toggleLineComment("a\nb\nc\n", range: 0...1, token: "//"),
                       "// a\n// b\nc\n")
    }

    func testTogglingTwiceRestoresTheText() {
        let original = "    if x {\n        y()\n    }\n"
        let once = LineOperations.toggleLineComment(original, range: 0...2, token: "#")
        XCTAssertEqual(once, "    # if x {\n    #     y()\n    # }\n", "token at the shallowest indent keeps the block aligned")
        XCTAssertEqual(LineOperations.toggleLineComment(once, range: 0...2, token: "#"), original)
    }

    func testUncommentsWithAndWithoutTheSpace() {
        XCTAssertEqual(LineOperations.toggleLineComment("//a\n//  b\n", range: 0...1, token: "//"), "a\n b\n")
    }

    func testMixedRangeGetsCommentedNotUncommented() {
        XCTAssertEqual(LineOperations.toggleLineComment("// a\nb\n", range: 0...1, token: "//"),
                       "// // a\n// b\n")
    }

    func testBlankLinesAreLeftAlone() {
        XCTAssertEqual(LineOperations.toggleLineComment("a\n\nb\n", range: 0...2, token: "#"), "# a\n\n# b\n")
        XCTAssertEqual(LineOperations.toggleLineComment("# a\n\n# b\n", range: 0...2, token: "#"), "a\n\nb\n")
    }

    func testAnEmptyDocumentTakesTheMarker() {
        XCTAssertEqual(LineOperations.toggleLineComment("", range: 0...0, token: "//"), "// ")
    }

    func testNoTrailingNewlineIsKept() {
        XCTAssertEqual(LineOperations.toggleLineComment("a\nb", range: 0...1, token: ";"), "; a\n; b")
    }

    func testRangePastTheEndIsClamped() {
        XCTAssertEqual(LineOperations.toggleLineComment("a\n", range: 0...9, token: "#"), "# a\n")
    }

    // MARK: - Block comments

    func testWrapsTheSelection() {
        let edit = LineOperations.toggleBlockComment("one two three", selection: NSRange(location: 4, length: 3),
                                                     open: "/*", close: "*/")
        XCTAssertEqual(edit.text, "one /* two */ three")
        XCTAssertEqual(edit.selection, NSRange(location: 4, length: 9))
    }

    func testUnwrapsAWrappedSelection() {
        let edit = LineOperations.toggleBlockComment("one /* two */ three", selection: NSRange(location: 4, length: 9),
                                                     open: "/*", close: "*/")
        XCTAssertEqual(edit.text, "one two three")
        XCTAssertEqual(edit.selection, NSRange(location: 4, length: 3))
    }

    func testWithoutASelectionItWrapsTheCurrentLine() {
        let edit = LineOperations.toggleBlockComment("a\n  b c\nd\n", selection: NSRange(location: 4, length: 0),
                                                     open: "<!--", close: "-->")
        XCTAssertEqual(edit.text, "a\n  <!-- b c -->\nd\n")
    }

    func testBlockToggleTwiceIsIdentity() {
        let original = "x = 1;\ny = 2;\n"
        let first = LineOperations.toggleBlockComment(original, selection: NSRange(location: 0, length: 13),
                                                      open: "/*", close: "*/")
        let second = LineOperations.toggleBlockComment(first.text, selection: first.selection, open: "/*", close: "*/")
        XCTAssertEqual(second.text, original)
    }

    // MARK: - Indent

    func testIndentUsesTheGivenUnit() {
        XCTAssertEqual(LineOperations.indent("a\n\nb\n", range: 0...2, unit: "\t"), "\ta\n\n\tb\n")
        XCTAssertEqual(LineOperations.indent("a\nb\n", range: 1...1, unit: "    "), "a\n    b\n")
    }

    func testIndentOfASingleEmptyLineStillIndents() {
        XCTAssertEqual(LineOperations.indent("", range: 0...0, unit: "\t"), "\t")
    }

    func testUnindentRemovesATabOrUpToOneWidthOfSpaces() {
        XCTAssertEqual(LineOperations.unindent("\ta\n      b\n  c\nd\n", range: 0...3, width: 4), "a\n  b\nc\nd\n")
    }

    func testIndentThenUnindentIsIdentity() {
        let text = "a\n  b\n"
        XCTAssertEqual(LineOperations.unindent(LineOperations.indent(text, range: 0...1, unit: "    "),
                                               range: 0...1, width: 4), text)
    }

    // MARK: - Split lines

    func testSplitsAtTheLastSpaceBeforeTheLimit() {
        XCTAssertEqual(LineOperations.splitLines("aaa bbb ccc ddd\n", range: 0...0, width: 8), "aaa bbb\nccc ddd\n")
    }

    func testAWordLongerThanTheLimitIsCutInside() {
        XCTAssertEqual(LineOperations.splitLines("abcdefghij\n", range: 0...0, width: 4), "abcd\nefgh\nij\n")
    }

    func testShortLinesAndOtherLinesAreUntouched() {
        XCTAssertEqual(LineOperations.splitLines("short\naaa bbb ccc\nlast\n", range: 0...0, width: 8),
                       "short\naaa bbb ccc\nlast\n")
        XCTAssertEqual(LineOperations.splitLines("aaa bbb ccc\nxxx yyy zzz\n", range: 1...1, width: 8),
                       "aaa bbb ccc\nxxx yyy\nzzz\n")
    }

    func testContinuationLinesKeepTheIndent() {
        XCTAssertEqual(LineOperations.splitLines("  aaa bbb ccc\n", range: 0...0, width: 9), "  aaa bbb\n  ccc\n")
    }

    func testSplitTerminatesOnPathologicalInput() {
        let result = LineOperations.splitLines(String(repeating: " ", count: 50) + "x\n", range: 0...0, width: 3)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(LineOperations.splitLines("abc\n", range: 0...0, width: 1), "a\nb\nc\n")
    }

    func testCharacterRangeCoversTheLinesWithoutTheTerminator() {
        XCTAssertEqual(LineOperations.characterRange(ofLines: 1...2, in: "ab\ncd\nef\ngh\n"),
                       NSRange(location: 3, length: 5))
    }
}
