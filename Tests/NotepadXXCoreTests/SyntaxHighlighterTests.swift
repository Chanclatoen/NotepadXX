import XCTest
@testable import NotepadXXCore

final class SyntaxHighlighterTests: XCTestCase {
    private func highlighter(_ text: String, _ language: LanguageDefinition = BuiltInLanguages.c) -> SyntaxHighlighter {
        let highlighter = SyntaxHighlighter(language: language)
        highlighter.setText(text)
        return highlighter
    }

    func testLineCountAndOffsets() {
        let subject = highlighter("a\nb\nc")
        XCTAssertEqual(subject.lineCount, 3)
        XCTAssertEqual(subject.line(containing: 0), 0)
        XCTAssertEqual(subject.line(containing: 2), 1)
        XCTAssertEqual(subject.line(containing: 4), 2)
    }

    func testTokensAreInDocumentCoordinates() {
        let text = "x = 1;\nint y = 2;\n"
        let subject = highlighter(text)
        let tokens = subject.tokens(forLines: 1...1)
        let content = text as NSString
        guard let keyword = tokens.first(where: { $0.type == .keyword2 }) else {
            return XCTFail("expected the int keyword on line 1")
        }
        XCTAssertEqual(content.substring(with: keyword.range), "int")
        XCTAssertGreaterThanOrEqual(keyword.range.location, 7,
                                    "offsets must be document-wide, not chunk-relative")
    }

    /// The point of the state cache: a line inside an open block comment must be
    /// highlighted as comment even when lexed in isolation.
    func testLineInsideBlockCommentIsCommentWhenLexedAlone() {
        let text = "/* open\nstill inside\nint after */\n"
        let subject = highlighter(text)
        let tokens = subject.tokens(forLines: 1...1)
        XCTAssertTrue(tokens.contains { $0.type == .comment },
                      "seeded state carries the open comment into the isolated line")
        XCTAssertFalse(tokens.contains { $0.type == .keyword2 })
    }

    func testStateAtLineTracksCommentDepth() {
        let subject = highlighter("/* open\nmid\n*/ closed\nint x\n")
        XCTAssertEqual(subject.state(atLine: 0).blockCommentDepth, 0)
        XCTAssertEqual(subject.state(atLine: 1).blockCommentDepth, 1)
        XCTAssertEqual(subject.state(atLine: 3).blockCommentDepth, 0, "comment closed on line 2")
    }

    func testKeywordAfterClosedCommentIsHighlighted() {
        let text = "/* c */\nint x;\n"
        let subject = highlighter(text)
        XCTAssertTrue(subject.tokens(forLines: 1...1).contains { $0.type == .keyword2 })
    }

    func testInvalidationRecomputesAfterEdit() {
        let subject = highlighter("int a;\nint b;\n")
        XCTAssertTrue(subject.tokens(forLines: 1...1).contains { $0.type == .keyword2 })

        // Introduce an unterminated comment on line 0; line 1 becomes comment.
        let updated = "/* oops\nint b;\n"
        subject.textDidChange(updated, editedLine: 0)
        let tokens = subject.tokens(forLines: 1...1)
        XCTAssertTrue(tokens.contains { $0.type == .comment })
        XCTAssertFalse(tokens.contains { $0.type == .keyword2 },
                       "stale cached state must not survive the edit")
    }

    func testSwitchingLanguageRelexes() {
        let subject = highlighter("select 1", BuiltInLanguages.c)
        XCTAssertFalse(subject.tokens(forLines: 0...0).contains { $0.type == .keyword1 })
        subject.setLanguage(BuiltInLanguages.sql)
        XCTAssertTrue(subject.tokens(forLines: 0...0).contains { $0.type == .keyword1 })
    }

    func testLineRangeForCharacterRange() {
        let subject = highlighter("aaa\nbbb\nccc\n")
        XCTAssertEqual(subject.lineRange(forCharacterRange: NSRange(location: 0, length: 9)), 0...2)
        XCTAssertEqual(subject.lineRange(forCharacterRange: NSRange(location: 4, length: 1)), 1...1)
    }

    func testOutOfRangeLinesAreSafe() {
        let subject = highlighter("a\n")
        XCTAssertTrue(subject.tokens(forLines: 50...60).isEmpty)
        XCTAssertNoThrow(subject.state(atLine: 999))
    }

    func testEmptyDocument() {
        let subject = highlighter("")
        XCTAssertEqual(subject.lineCount, 1)
        XCTAssertTrue(subject.tokens(forLines: 0...0).isEmpty)
    }

    /// Highlighting a viewport in a large document must not cost a full re-lex.
    func testViewportHighlightingIsFastOnALargeDocument() {
        let text = String(repeating: "int value = 1; // note\n", count: 200_000)
        let subject = highlighter(text)

        // Warm the state cache to the viewport once...
        let warm = Date()
        _ = subject.tokens(forLines: 150_000...150_050)
        let warmCost = Date().timeIntervalSince(warm)

        // ...then a nearby viewport must be nearly free, because state is cached.
        let cached = Date()
        _ = subject.tokens(forLines: 150_060...150_110)
        let cachedCost = Date().timeIntervalSince(cached)

        XCTAssertLessThan(cachedCost, 0.05,
                          "a cached viewport should be sub-50ms (warm pass took \(warmCost)s)")
    }
}
