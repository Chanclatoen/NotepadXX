import XCTest
@testable import NotepadXXCore

/// `state(atLine:)` skips lines that contain no block-comment delimiter, on the
/// reasoning that such a line cannot change the depth carried into the next
/// one. That is a claim about the lexer, so it is checked against the lexer
/// rather than assumed.
final class HighlighterStateEquivalenceTests: XCTestCase {
    /// The state the highlighter reports must equal the state reached by
    /// tokenising every line from the top, with nothing skipped.
    private func assertStatesMatchFullLexing(_ text: String,
                                             language: LanguageDefinition,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) {
        let highlighter = SyntaxHighlighter(language: language)
        highlighter.setText(text)
        let lexer = Lexer(language: language)
        let content = text as NSString

        // The reference: lex every line in order, carrying the state forward.
        var starts: [Int] = [0]
        content.enumerateSubstrings(in: NSRange(location: 0, length: content.length),
                                    options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            let next = NSMaxRange(enclosing)
            if next < content.length { starts.append(next) }
        }

        var expected = Lexer.State.initial
        for index in starts.indices {
            XCTAssertEqual(highlighter.state(atLine: index), expected,
                           "state entering line \(index) disagrees with full lexing",
                           file: file, line: line)
            let start = starts[index]
            let end = index + 1 < starts.count ? starts[index + 1] : content.length
            let chunk = content.substring(with: NSRange(location: start, length: end - start))
            expected = lexer.tokenize(chunk, startingIn: expected).endState
        }
    }

    private var c: LanguageDefinition {
        LanguageRegistry.shared.all.first { $0.blockCommentOpen == "/*" } ?? LanguageRegistry.shared.all[0]
    }

    func testPlainLinesBetweenCommentsDoNotDisturbTheState() {
        assertStatesMatchFullLexing("""
        int a = 1;
        /* opened here
        still inside
        and here
        */ int b = 2;
        int c = 3;
        """, language: c)
    }

    /// A delimiter inside a string literal must not be treated as opening a
    /// comment — the line contains one, so it has to be lexed properly.
    func testADelimiterInsideAStringIsNotAComment() {
        assertStatesMatchFullLexing("""
        const char *s = "/*";
        int after = 1;
        const char *t = "*/";
        int last = 2;
        """, language: c)
    }

    func testAnUnterminatedCommentCarriesToTheEnd() {
        assertStatesMatchFullLexing("""
        int a = 1;
        /* never closed
        line
        line
        line
        """, language: c)
    }

    func testBothDelimitersOnOneLine() {
        assertStatesMatchFullLexing("""
        int a = 1; /* here */ int b = 2;
        int c = 3;
        /* and */ /* twice */
        int d = 4;
        """, language: c)
    }

    /// Languages with no block comment at all take the fast path that returns
    /// the initial state; it has to be the right answer, not just a quick one.
    func testALanguageWithoutBlockCommentsIsAlwaysInitial() {
        guard let plain = LanguageRegistry.shared.all.first(where: { $0.blockCommentOpen == nil })
        else { return XCTFail("no language without block comments to test") }
        assertStatesMatchFullLexing("""
        one /* not a comment here */
        two */
        three
        """, language: plain)
    }
}
