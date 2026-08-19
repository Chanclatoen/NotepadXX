import XCTest
@testable import NotepadXXCore

final class AutoIndentTests: XCTestCase {
    private let swift = BuiltInLanguages.swift
    private let python = BuiltInLanguages.python

    func testCopiesTheCurrentLineIndent() {
        let text = "    let x = 1\n"
        let indent = AutoIndent.indent(forNewLineAt: (text as NSString).length,
                                       in: text, language: swift, tabWidth: 4, useSpaces: true)
        XCTAssertEqual(indent, "    ")
    }

    func testAddsALevelAfterAnOpeningBrace() {
        let text = "func a() {\n"
        let indent = AutoIndent.indent(forNewLineAt: (text as NSString).length,
                                       in: text, language: swift, tabWidth: 4, useSpaces: true)
        XCTAssertEqual(indent, "    ", "indented one level inside the block")
    }

    func testNestedBraceAddsToTheExistingIndent() {
        let text = "    if x {\n"
        let indent = AutoIndent.indent(forNewLineAt: (text as NSString).length,
                                       in: text, language: swift, tabWidth: 4, useSpaces: true)
        XCTAssertEqual(indent, "        ", "existing indent plus one level")
    }

    func testTabsAreKeptAsTabs() {
        let text = "\tlet x = 1\n"
        let indent = AutoIndent.indent(forNewLineAt: (text as NSString).length,
                                       in: text, language: swift, tabWidth: 4, useSpaces: false)
        XCTAssertEqual(indent, "\t", "a tab-indented file stays tab-indented")
    }

    func testPythonColonOpensABlock() {
        let text = "def a():\n"
        let indent = AutoIndent.indent(forNewLineAt: (text as NSString).length,
                                       in: text, language: python, tabWidth: 4, useSpaces: true)
        XCTAssertEqual(indent, "    ")
    }

    func testNoIndentOnAnUnindentedPlainLine() {
        let text = "let x = 1\n"
        XCTAssertEqual(AutoIndent.indent(forNewLineAt: (text as NSString).length,
                                         in: text, language: swift, tabWidth: 4, useSpaces: true), "")
    }

    func testNoLanguageJustCopiesTheIndent() {
        let text = "      some text\n"
        let indent = AutoIndent.indent(forNewLineAt: (text as NSString).length,
                                       in: text, language: nil, tabWidth: 4, useSpaces: true)
        XCTAssertEqual(indent, "      ", "without a language we still keep alignment")
    }

    /// "endif" ends with "if" but must not be treated as opening a block.
    func testWordMarkersMatchWholeWordsOnly() {
        let shell = BuiltInLanguages.shell
        XCTAssertTrue(AutoIndent.opensBlock("if x; then", language: shell))
        XCTAssertFalse(AutoIndent.opensBlock("fi", language: shell))
    }

    func testDedentRemovesOneLevel() {
        XCTAssertEqual(AutoIndent.dedented("        ", tabWidth: 4), "    ")
        XCTAssertEqual(AutoIndent.dedented("\t\t", tabWidth: 4), "\t")
        XCTAssertEqual(AutoIndent.dedented("", tabWidth: 4), "", "nothing to remove is safe")
    }

    func testStartOfDocumentIsSafe() {
        XCTAssertEqual(AutoIndent.indent(forNewLineAt: 0, in: "", language: swift,
                                         tabWidth: 4, useSpaces: true), "")
    }
}

final class PasteSpecialTests: XCTestCase {
    func testStripsTagsFromHTML() {
        XCTAssertEqual(PasteSpecial.plainText(from: "<p>hello <b>world</b></p>"), "hello world")
    }

    func testDecodesCommonEntities() {
        XCTAssertEqual(PasteSpecial.plainText(from: "a &lt;b&gt; &amp; c&nbsp;d"), "a <b> & c d")
    }

    /// Ampersand must be escaped first, or the other escapes get mangled.
    func testEscapingDoesNotDoubleEncode() {
        XCTAssertEqual(PasteSpecial.escapeHTML("a & b < c"), "a &amp; b &lt; c")
    }

    func testHTMLWrapsInPre() {
        XCTAssertEqual(PasteSpecial.html(from: "x < y"), "<pre>x &lt; y</pre>")
    }

    func testRoundTripThroughHTMLAndBack() {
        let original = "if (a < b) { print(\"hi\"); }"
        let restored = PasteSpecial.plainText(from: PasteSpecial.html(from: original))
        XCTAssertEqual(restored, original)
    }
}
