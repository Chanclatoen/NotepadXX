import XCTest
@testable import NotepadXXCore

final class AutoCompletionTests: XCTestCase {
    func testCurrentPrefixStopsAtNonIdentifierCharacters() {
        XCTAssertEqual(AutoCompletion.currentPrefix(in: "let wid", at: 7), "wid")
        XCTAssertEqual(AutoCompletion.currentPrefix(in: "a.b", at: 3), "b", "the dot terminates the prefix")
        XCTAssertEqual(AutoCompletion.currentPrefix(in: "foo_bar", at: 7), "foo_bar", "underscores are part of it")
        XCTAssertEqual(AutoCompletion.currentPrefix(in: "x ", at: 2), "", "no prefix after a space")
    }

    func testWordsRespectMinimumLength() {
        let words = AutoCompletion.words(in: "an apple a day", minimumLength: 3)
        XCTAssertTrue(words.contains("apple"))
        XCTAssertTrue(words.contains("day"))
        XCTAssertFalse(words.contains("an"), "words shorter than the minimum are skipped")
    }

    func testKeywordsRankBeforeBufferWords() {
        let text = "func fun fundamental\nf"
        let items = AutoCompletion.suggestions(
            in: text, at: (text as NSString).length, language: BuiltInLanguages.swift
        )
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(items.first?.kind, .keyword, "language keywords are the more certain set")
    }

    func testSuggestionsExcludeTheWordBeingTyped() {
        let text = "widget wid"
        let items = AutoCompletion.suggestions(in: text, at: (text as NSString).length, language: nil)
        XCTAssertTrue(items.contains { $0.text == "widget" })
        XCTAssertFalse(items.contains { $0.text == "wid" }, "the prefix must not suggest itself")
    }

    func testExactCaseIsPreferredOverCaseInsensitiveMatch() {
        let text = "Widget widget wid"
        let items = AutoCompletion.suggestions(in: text, at: (text as NSString).length, language: nil)
        XCTAssertEqual(items.first?.text, "widget", "exact-case prefix ranks first")
    }

    func testShorterCandidatesRankFirst() {
        let text = "test testing testingLonger tes"
        let items = AutoCompletion.suggestions(in: text, at: (text as NSString).length, language: nil)
        XCTAssertEqual(items.first?.text, "test")
    }

    func testEmptyPrefixYieldsNothing() {
        XCTAssertTrue(AutoCompletion.suggestions(in: "hello ", at: 6, language: nil).isEmpty)
    }

    func testSourcesCanBeDisabledIndependently() {
        let text = "widget wid"
        let keywordsOnly = AutoCompletion.suggestions(
            in: text, at: (text as NSString).length,
            language: BuiltInLanguages.swift, includeWords: false
        )
        XCTAssertFalse(keywordsOnly.contains { $0.text == "widget" })
    }

    func testMaximumIsRespected() {
        let text = (0..<200).map { "word\($0)" }.joined(separator: " ") + " word"
        let items = AutoCompletion.suggestions(in: text, at: (text as NSString).length,
                                               language: nil, maximum: 10)
        XCTAssertEqual(items.count, 10)
    }

    func testPathCompletionOnlyTriggersOnPathLikeTokens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("npxx-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("alpha.txt"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("beta"),
                                                withIntermediateDirectories: true)

        let fragment = dir.path + "/"
        let items = AutoCompletion.pathSuggestions(in: fragment, at: (fragment as NSString).length)
        let names = items.map(\.text)
        XCTAssertTrue(names.contains("alpha.txt"))
        XCTAssertTrue(names.contains("beta/"), "directories are marked with a trailing slash")

        XCTAssertTrue(AutoCompletion.pathSuggestions(in: "plainword", at: 9).isEmpty,
                      "a token with no slash is not a path")
    }

    func testCallTipReturnsTheDeclarationLine() {
        let text = "func render(width: Int) -> String {\n    return \"\"\n}\n"
        let tip = AutoCompletion.callTip(for: "render", in: text, languageName: "Swift")
        XCTAssertEqual(tip, "func render(width: Int) -> String {")
    }

    func testCallTipForUnknownFunctionIsNil() {
        XCTAssertNil(AutoCompletion.callTip(for: "missing", in: "func a() {}", languageName: "Swift"))
    }
}

final class UDLSerializationTests: XCTestCase {
    private let sample = """
    <?xml version="1.0" encoding="UTF-8" ?>
    <NotepadPlus>
        <UserLang name="MyLang" ext="ml mylang" udlVersion="2.1">
            <Settings>
                <Global caseIgnored="yes" />
            </Settings>
            <KeywordLists>
                <Keywords name="Comments">00/* 01*/ 02//</Keywords>
                <Keywords name="Keywords1">alpha beta gamma</Keywords>
                <Keywords name="Keywords2">TypeOne TypeTwo</Keywords>
            </KeywordLists>
        </UserLang>
    </NotepadPlus>
    """

    func testImportsNameExtensionsAndKeywords() throws {
        let languages = try UDLSerialization.importLanguages(from: sample)
        XCTAssertEqual(languages.count, 1)
        let language = try XCTUnwrap(languages.first)
        XCTAssertEqual(language.name, "MyLang")
        XCTAssertEqual(language.fileExtensions, ["ml", "mylang"])
        XCTAssertEqual(language.keywords1, ["alpha", "beta", "gamma"])
        XCTAssertEqual(language.keywords2, ["TypeOne", "TypeTwo"])
    }

    /// The positional comment markers are the fiddly part of the real format.
    func testImportsPositionalCommentMarkers() throws {
        let language = try XCTUnwrap(try UDLSerialization.importLanguages(from: sample).first)
        XCTAssertEqual(language.blockCommentOpen, "/*")
        XCTAssertEqual(language.blockCommentClose, "*/")
        XCTAssertEqual(language.lineCommentTokens, ["//"])
    }

    func testCaseIgnoredMapsToCaseInsensitive() throws {
        let language = try XCTUnwrap(try UDLSerialization.importLanguages(from: sample).first)
        XCTAssertFalse(language.isCaseSensitive, "caseIgnored=yes means case-insensitive")
    }

    func testAnImportedUDLActuallyLexes() throws {
        let language = try XCTUnwrap(try UDLSerialization.importLanguages(from: sample).first)
        let text = "alpha /* c */ ALPHA"
        let tokens = Lexer(language: language).tokenize(text).tokens
        let content = text as NSString
        XCTAssertTrue(tokens.contains { $0.type == .keyword1 && content.substring(with: $0.range) == "alpha" })
        XCTAssertTrue(tokens.contains { $0.type == .keyword1 && content.substring(with: $0.range) == "ALPHA" },
                      "case-insensitive language matches either case")
        XCTAssertTrue(tokens.contains { $0.type == .comment })
    }

    func testRoundTripThroughExportAndImport() throws {
        let original = LanguageDefinition(
            name: "RoundTrip", fileExtensions: ["rt"],
            lineCommentTokens: ["#"], blockCommentOpen: "<!--", blockCommentClose: "-->",
            isCaseSensitive: true, keywords1: ["one", "two"], keywords2: ["Three"]
        )
        let xml = UDLSerialization.exportXML(for: [original])
        let restored = try XCTUnwrap(try UDLSerialization.importLanguages(from: xml).first)

        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.fileExtensions, original.fileExtensions)
        XCTAssertEqual(restored.keywords1, original.keywords1)
        XCTAssertEqual(restored.keywords2, original.keywords2)
        XCTAssertEqual(restored.blockCommentOpen, original.blockCommentOpen)
        XCTAssertEqual(restored.blockCommentClose, original.blockCommentClose)
        XCTAssertEqual(restored.lineCommentTokens, original.lineCommentTokens)
        XCTAssertEqual(restored.isCaseSensitive, original.isCaseSensitive)
    }

    func testExportEscapesXMLSpecialCharacters() {
        let language = LanguageDefinition(name: "A&B<C>", fileExtensions: ["x"])
        let xml = UDLSerialization.exportXML(for: [language])
        XCTAssertTrue(xml.contains("A&amp;B&lt;C&gt;"))
        XCTAssertFalse(xml.contains("name=\"A&B<C>\""))
    }

    func testMalformedXMLThrows() {
        XCTAssertThrowsError(try UDLSerialization.importLanguages(from: "<NotepadPlus"))
    }

    func testXMLWithNoLanguagesThrows() {
        XCTAssertThrowsError(
            try UDLSerialization.importLanguages(from: "<?xml version=\"1.0\"?><NotepadPlus></NotepadPlus>")
        ) { error in
            XCTAssertEqual(error as? UDLSerialization.UDLError, .noLanguageFound)
        }
    }

    func testMultipleLanguagesInOneFile() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <NotepadPlus>
            <UserLang name="One" ext="a"><KeywordLists><Keywords name="Keywords1">x</Keywords></KeywordLists></UserLang>
            <UserLang name="Two" ext="b"><KeywordLists><Keywords name="Keywords1">y</Keywords></KeywordLists></UserLang>
        </NotepadPlus>
        """
        let languages = try UDLSerialization.importLanguages(from: xml)
        XCTAssertEqual(languages.map(\.name), ["One", "Two"])
    }
}
