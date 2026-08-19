import XCTest
@testable import NotepadXXCore

/// Auto-closing is only useful if it knows when to stay out of the way.
final class AutoCloseTests: XCTestCase {
    private func action(typing typed: Character, into text: String) -> AutoClose.Action {
        // The caret sits after the typed character, as it does in the editor.
        AutoClose.action(for: typed, in: text, caret: (text as NSString).range(of: "|").location)
    }

    /// `|` marks the caret in these fixtures.
    private func check(_ typed: Character, _ fixture: String,
                       is expected: AutoClose.Action, file: StaticString = #filePath, line: UInt = #line) {
        let caret = (fixture as NSString).range(of: "|").location
        let text = fixture.replacingOccurrences(of: "|", with: "")
        XCTAssertEqual(AutoClose.action(for: typed, in: text, caret: caret),
                       expected, fixture, file: file, line: line)
    }

    func testBracketsCloseAtTheEndOfALine() {
        check("(", "foo(|", is: .close(")"))
        check("[", "list[|", is: .close("]"))
        check("{", "if x {|", is: .close("}"))
    }

    /// Typing the closer when it is already there steps over it.
    func testTypingTheCloserSkipsOverIt() {
        check(")", "foo()|)", is: .skip)
        check("}", "{}|}", is: .skip)
    }

    /// Closing before a word swallows what the user is about to wrap.
    func testItDoesNotCloseBeforeAWord() {
        check("(", "call(|argument", is: .none)
        check("[", "a[|index", is: .none)
    }

    /// An apostrophe is not an opening quote.
    func testAnApostropheInsideAWordIsLeftAlone() {
        check("'", "don'|t", is: .none)
        check("'", "isn'|", is: .none)
    }

    func testAQuoteOpensAPairAtTheStartOfAValue() {
        check("\"", "name = \"|", is: .close("\""))
    }

    /// The second quote of a pair closes it rather than opening another.
    func testTheClosingQuoteDoesNotOpenANewPair() {
        check("\"", "name = \"value\"|", is: .none)
    }

    // MARK: Tags

    func testAnOpeningTagIsClosed() {
        XCTAssertEqual(AutoClose.closingTag(after: 5, in: "<div>"), "</div>")
        XCTAssertEqual(AutoClose.closingTag(after: 24, in: "<section class=\"intro\">x"), nil)
        XCTAssertEqual(AutoClose.closingTag(after: 23, in: "<section class=\"intro\">"), "</section>")
    }

    func testClosingAndSelfClosingTagsAreLeftAlone() {
        XCTAssertNil(AutoClose.closingTag(after: 6, in: "</div>"))
        XCTAssertNil(AutoClose.closingTag(after: 6, in: "<div/>"))
        XCTAssertNil(AutoClose.closingTag(after: 15, in: "<!DOCTYPE html>"))
    }

    /// Elements that never take a closing tag must not get one.
    func testVoidElementsAreNotClosed() {
        XCTAssertNil(AutoClose.closingTag(after: 4, in: "<br>"))
        XCTAssertNil(AutoClose.closingTag(after: 15, in: "<img src=\"a.p\">"))
    }
}
