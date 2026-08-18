import XCTest
@testable import NotepadXXCore

final class CaseConversionTests: XCTestCase {
    func testBasicCases() {
        XCTAssertEqual(CaseConversion.upper.apply(to: "hello World"), "HELLO WORLD")
        XCTAssertEqual(CaseConversion.lower.apply(to: "Hello World"), "hello world")
        XCTAssertEqual(CaseConversion.invert.apply(to: "Hello World"), "hELLO wORLD")
    }

    func testProperCaseLowercasesRemainder() {
        XCTAssertEqual(CaseConversion.proper.apply(to: "hello wORLD"), "Hello World")
    }

    func testProperCaseBlendPreservesInnerCapitals() {
        XCTAssertEqual(CaseConversion.properBlend.apply(to: "mcDonald ate"), "McDonald Ate")
    }

    func testSentenceCase() {
        XCTAssertEqual(
            CaseConversion.sentence.apply(to: "hello there. how are you? fine!"),
            "Hello there. How are you? Fine!"
        )
    }

    func testInvertIsItsOwnInverse() {
        let original = "MiXeD cAsE 123"
        let once = CaseConversion.invert.apply(to: original)
        XCTAssertEqual(CaseConversion.invert.apply(to: once), original)
    }

    func testRandomCaseIsDeterministicWithInjectedSource() {
        var flag = true
        let result = CaseConversion.random.apply(to: "abcd") { defer { flag.toggle() }; return flag }
        XCTAssertEqual(result, "AbCd")
    }

    func testNonLettersUntouched() {
        XCTAssertEqual(CaseConversion.upper.apply(to: "a1!ü"), "A1!Ü")
    }
}

final class LineOperationsTests: XCTestCase {
    func testSplitJoinRoundTripPreservesTrailingNewline() {
        for sample in ["a\nb\nc", "a\nb\nc\n", "", "\n"] {
            let (lines, trailing) = LineOperations.split(sample)
            XCTAssertEqual(LineOperations.join(lines, hadTrailingNewline: trailing), sample, "round trip of \(sample.debugDescription)")
        }
    }

    func testDuplicateAndRemove() {
        XCTAssertEqual(LineOperations.duplicate("a\nb\nc\n", range: 1...1), "a\nb\nb\nc\n")
        XCTAssertEqual(LineOperations.remove("a\nb\nc\n", range: 1...1), "a\nc\n")
        XCTAssertEqual(LineOperations.duplicate("a\nb\nc\n", range: 0...1), "a\nb\na\nb\nc\n")
    }

    func testMoveUpDownAndBoundaries() {
        XCTAssertEqual(LineOperations.moveUp("a\nb\nc\n", range: 1...1), "b\na\nc\n")
        XCTAssertEqual(LineOperations.moveDown("a\nb\nc\n", range: 1...1), "a\nc\nb\n")
        XCTAssertEqual(LineOperations.moveUp("a\nb\n", range: 0...0), "a\nb\n", "moving the first line up is a no-op")
        XCTAssertEqual(LineOperations.moveDown("a\nb\n", range: 1...1), "a\nb\n", "moving the last line down is a no-op")
    }

    func testOutOfRangeIndicesAreClamped() {
        XCTAssertEqual(LineOperations.remove("a\nb\n", range: 5...9), "a\nb\n")
        XCTAssertEqual(LineOperations.duplicate("a\nb\n", range: 0...99), "a\nb\na\nb\n")
    }

    func testJoinLines() {
        XCTAssertEqual(LineOperations.joinLines("a\nb\nc\n", range: 0...1), "ab\nc\n")
    }

    func testDuplicateRemoval() {
        XCTAssertEqual(LineOperations.removeConsecutiveDuplicates("a\na\nb\na\n"), "a\nb\na\n")
        XCTAssertEqual(LineOperations.removeAllDuplicates("a\na\nb\na\n"), "a\nb\n")
    }

    func testSortLexicographic() {
        XCTAssertEqual(LineOperations.sort("b\nA\na\n", mode: .lexicographic(caseSensitive: false)), "A\na\nb\n")
        XCTAssertEqual(LineOperations.sort("b\na\n", mode: .lexicographic(caseSensitive: true), ascending: false), "b\na\n")
    }

    func testSortNumericBeatsLexicographic() {
        // Lexicographically "10" < "9"; numerically it must not be.
        XCTAssertEqual(LineOperations.sort("10\n9\n2\n", mode: .integer), "2\n9\n10\n")
        XCTAssertEqual(LineOperations.sort("1.5\n1.25\n", mode: .decimal), "1.25\n1.5\n")
    }

    func testSortNegativeNumbers() {
        XCTAssertEqual(LineOperations.sort("3\n-5\n0\n", mode: .integer), "-5\n0\n3\n")
    }

    func testSortByLengthAndReverseAndShuffle() {
        XCTAssertEqual(LineOperations.sort("ccc\na\nbb\n", mode: .byLength), "a\nbb\nccc\n")
        XCTAssertEqual(LineOperations.sort("a\nb\nc\n", mode: .reverseOrder), "c\nb\na\n")
        XCTAssertEqual(LineOperations.sort("a\nb\n", mode: .randomize, shuffle: { $0.reversed() }), "b\na\n")
    }

    func testTrimOperations() {
        XCTAssertEqual(LineOperations.trimTrailingWhitespace("a  \nb\t\n"), "a\nb\n")
        XCTAssertEqual(LineOperations.trimLeadingWhitespace("  a\n\tb\n"), "a\nb\n")
        XCTAssertEqual(LineOperations.trimBothEnds("  a  \n"), "a\n")
    }

    func testRemoveEmptyLines() {
        XCTAssertEqual(LineOperations.removeEmptyLines("a\n\nb\n", keepingWhitespaceOnly: true), "a\nb\n")
        XCTAssertEqual(LineOperations.removeEmptyLines("a\n   \nb\n", keepingWhitespaceOnly: true), "a\n   \nb\n",
                       "whitespace-only lines are kept in this mode")
        XCTAssertEqual(LineOperations.removeEmptyLines("a\n   \nb\n", keepingWhitespaceOnly: false), "a\nb\n")
    }

    func testTabsToSpacesRespectsTabStops() {
        // A tab at column 1 advances to the next multiple of 4, not by 4.
        XCTAssertEqual(LineOperations.tabsToSpaces("a\tb\n", width: 4), "a   b\n")
        XCTAssertEqual(LineOperations.tabsToSpaces("\tx\n", width: 4), "    x\n")
        XCTAssertEqual(LineOperations.tabsToSpaces("abcd\te\n", width: 4), "abcd    e\n")
    }

    func testLeadingSpacesToTabsOnlyTouchesIndent() {
        XCTAssertEqual(LineOperations.leadingSpacesToTabs("        x  y\n", width: 4), "\t\tx  y\n")
        XCTAssertEqual(LineOperations.leadingSpacesToTabs("      x\n", width: 4), "\t  x\n",
                       "remainder stays as spaces")
    }

    func testTabSpaceRoundTrip() {
        let original = "\t\tcode\n"
        let expanded = LineOperations.tabsToSpaces(original, width: 4)
        XCTAssertEqual(LineOperations.leadingSpacesToTabs(expanded, width: 4), original)
    }
}
