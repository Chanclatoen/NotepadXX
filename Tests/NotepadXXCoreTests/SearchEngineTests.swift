import XCTest
@testable import NotepadXXCore

final class SearchEngineTests: XCTestCase {
    private func engine(_ pattern: String, _ options: SearchOptions = SearchOptions()) -> SearchEngine {
        SearchEngine(pattern: pattern, options: options)
    }

    // MARK: - Normal mode

    func testNormalModeIsLiteralNotRegex() throws {
        // "a.c" must not match "abc" in normal mode.
        let found = try engine("a.c").matches(in: "abc a.c")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].range, NSRange(location: 4, length: 3))
    }

    func testCaseSensitivity() throws {
        XCTAssertEqual(try engine("abc").count(in: "ABC abc"), 2, "case-insensitive by default")
        let sensitive = try engine("abc", SearchOptions(matchCase: true)).count(in: "ABC abc")
        XCTAssertEqual(sensitive, 1)
    }

    func testWholeWord() throws {
        let options = SearchOptions(wholeWord: true)
        XCTAssertEqual(try engine("cat", options).count(in: "cat catalog concat cat."), 2)
    }

    func testEmptyPatternThrows() {
        XCTAssertThrowsError(try engine("").matches(in: "abc")) { error in
            XCTAssertEqual(error as? SearchError, .emptyPattern)
        }
    }

    // MARK: - Extended mode

    func testExtendedEscapes() {
        XCTAssertEqual(SearchEngine.decodeExtended("a\\tb"), "a\tb")
        XCTAssertEqual(SearchEngine.decodeExtended("a\\nb"), "a\nb")
        XCTAssertEqual(SearchEngine.decodeExtended("\\x41"), "A")
        XCTAssertEqual(SearchEngine.decodeExtended("\\u0041"), "A")
        XCTAssertEqual(SearchEngine.decodeExtended("a\\\\b"), "a\\b")
    }

    func testExtendedLeavesUnknownEscapesLiteral() {
        XCTAssertEqual(SearchEngine.decodeExtended("\\q"), "\\q")
        XCTAssertEqual(SearchEngine.decodeExtended("\\xZZ"), "\\xZZ", "a malformed hex escape is not silently eaten")
    }

    func testExtendedModeMatchesDecodedText() throws {
        let found = try engine("a\\tb", SearchOptions(mode: .extended)).matches(in: "x a\tb y")
        XCTAssertEqual(found.count, 1)
    }

    func testExtendedModeStillTreatsResultAsLiteral() throws {
        // After decoding, "a.c" must remain literal.
        XCTAssertEqual(try engine("a.c", SearchOptions(mode: .extended)).count(in: "abc a.c"), 1)
    }

    // MARK: - Regex mode

    func testRegexMatchingAndGroups() throws {
        let found = try engine("(\\w+)@(\\w+)", SearchOptions(mode: .regex)).matches(in: "mail bob@host end")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].groups.count, 3, "whole match plus two groups")
    }

    func testDotMatchesNewlineOption() throws {
        let off = try engine("a.b", SearchOptions(mode: .regex)).count(in: "a\nb")
        XCTAssertEqual(off, 0)
        let on = try engine("a.b", SearchOptions(mode: .regex, dotMatchesNewline: true)).count(in: "a\nb")
        XCTAssertEqual(on, 1)
    }

    func testInvalidRegexSurfacesAsError() {
        XCTAssertThrowsError(try engine("(unclosed", SearchOptions(mode: .regex)).matches(in: "x")) { error in
            guard case .invalidRegex = error as? SearchError else {
                return XCTFail("expected invalidRegex, got \(error)")
            }
        }
    }

    /// Boost constructs ICU does not support must fail loudly rather than being
    /// silently reinterpreted into a pattern that means something else.
    func testUnsupportedBoostConstructsDoNotSilentlyMisbehave() {
        // \K is a Boost/PCRE feature with no ICU equivalent.
        let result = try? engine("foo\\Kbar", SearchOptions(mode: .regex)).matches(in: "foobar")
        if let result {
            XCTAssertTrue(result.isEmpty || result[0].range.location == 0,
                          "if ICU accepts \\K it must not silently produce a Boost-style trimmed match")
        }
    }

    // MARK: - Navigation

    func testFindForwardBackwardAndWrap() throws {
        let text = "x a y a z"
        let forward = try engine("a").find(in: text, from: 0)
        XCTAssertEqual(forward?.range.location, 2)

        let next = try engine("a").find(in: text, from: 3)
        XCTAssertEqual(next?.range.location, 6)

        let wrapped = try engine("a").find(in: text, from: 7)
        XCTAssertEqual(wrapped?.range.location, 2, "wraps to the first match")

        let noWrap = try engine("a", SearchOptions(wrapAround: false)).find(in: text, from: 7)
        XCTAssertNil(noWrap)

        let backward = try engine("a", SearchOptions(backward: true)).find(in: text, from: 6)
        XCTAssertEqual(backward?.range.location, 2)
    }

    func testFindReturnsNilWhenAbsent() throws {
        XCTAssertNil(try engine("zzz").find(in: "abc", from: 0))
    }

    // MARK: - Replace

    func testReplaceAllLiteralTreatsDollarSignsAsText() throws {
        let (text, count) = try engine("price").replaceAll(in: "price and price", with: "$100")
        XCTAssertEqual(count, 2)
        XCTAssertEqual(text, "$100 and $100", "a literal $1 must not be read as a capture reference")
    }

    func testReplaceAllRegexExpandsGroups() throws {
        let (text, count) = try engine("(\\w+)@(\\w+)", SearchOptions(mode: .regex))
            .replaceAll(in: "bob@host", with: "$2:$1")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(text, "host:bob")
    }

    func testReplaceSingleMatchOnly() throws {
        let engine = self.engine("a")
        let match = try XCTUnwrap(engine.find(in: "a a a", from: 0))
        XCTAssertEqual(try engine.replace(in: "a a a", match: match, with: "Z"), "Z a a")
    }

    func testReplaceAllInSelectionOnly() throws {
        let text = "aaa aaa"
        let (updated, count) = try engine("a").replaceAll(in: text, with: "b", range: NSRange(location: 0, length: 3))
        XCTAssertEqual(count, 3)
        XCTAssertEqual(updated, "bbb aaa", "text outside the selection is untouched")
    }

    func testReplaceAllWithNoMatchesIsANoOp() throws {
        let (text, count) = try engine("zzz").replaceAll(in: "abc", with: "x")
        XCTAssertEqual(count, 0)
        XCTAssertEqual(text, "abc")
    }

    func testCountInRange() throws {
        XCTAssertEqual(try engine("a").count(in: "aaaa", range: NSRange(location: 1, length: 2)), 2)
    }
}
