import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

@MainActor
final class UDLEditorTests: XCTestCase {
    func testEditingAnExistingLanguageRoundTrips() {
        let original = LanguageDefinition(
            name: "MyLang", fileExtensions: ["ml1"],
            lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
            stringDelimiters: ["\""], isCaseSensitive: false,
            keywords1: ["alpha", "beta"], keywords2: ["Gamma"],
            foldOpen: ["{"], foldClose: ["}"]
        )
        let editor = UDLEditorWindowController(editing: original) { _ in }
        _ = editor.window

        let read = editor.currentDefinition()
        XCTAssertEqual(read.name, "MyLang")
        XCTAssertEqual(read.fileExtensions, ["ml1"])
        XCTAssertEqual(read.lineCommentTokens, ["//"])
        XCTAssertEqual(read.blockCommentOpen, "/*")
        XCTAssertEqual(read.keywords1, ["alpha", "beta"])
        XCTAssertEqual(read.keywords2, ["Gamma"])
        XCTAssertFalse(read.isCaseSensitive)
        XCTAssertEqual(read.foldOpen, ["{"])
    }

    func testAnEmptyNameIsRefused() {
        let editor = UDLEditorWindowController(
            editing: LanguageDefinition(name: "  ", fileExtensions: [])
        ) { _ in }
        _ = editor.window
        XCTAssertNotNil(editor.validationError())
    }

    func testANewLanguageStartsBlankButUsable() {
        let editor = UDLEditorWindowController { _ in }
        _ = editor.window
        let definition = editor.currentDefinition()
        XCTAssertEqual(definition.name, "New Language")
        // A blank definition must still lex without crashing.
        XCTAssertNoThrow(Lexer(language: definition).tokenize("anything at all"))
    }

    /// The definition the GUI produces must actually drive the lexer — the
    /// point of the editor is a working language, not a saved form.
    func testTheEditedDefinitionLexes() {
        let original = LanguageDefinition(
            name: "Toy", fileExtensions: ["toy"],
            lineCommentTokens: ["#"], stringDelimiters: ["\""],
            keywords1: ["begin", "end"]
        )
        let editor = UDLEditorWindowController(editing: original) { _ in }
        _ = editor.window

        let text = "begin \"s\" # note"
        let tokens = Lexer(language: editor.currentDefinition()).tokenize(text).tokens
        let content = text as NSString
        XCTAssertTrue(tokens.contains { $0.type == .keyword1 && content.substring(with: $0.range) == "begin" })
        XCTAssertTrue(tokens.contains { $0.type == .string })
        XCTAssertTrue(tokens.contains { $0.type == .commentLine })
    }

    func testSaveHandsBackTheEditedLanguage() {
        var saved: LanguageDefinition?
        let editor = UDLEditorWindowController(
            editing: LanguageDefinition(name: "Keeper", fileExtensions: ["kp"])
        ) { saved = $0 }
        _ = editor.window

        XCTAssertNil(editor.validationError())
        XCTAssertTrue(editor.save())
        XCTAssertEqual(saved?.name, "Keeper")
        XCTAssertEqual(saved?.fileExtensions, ["kp"])
    }

    /// Shadowing a shipped language would leave no way back to the built-in.
    func testCannotShadowABuiltInLanguage() {
        var saved: LanguageDefinition?
        let editor = UDLEditorWindowController(
            editing: LanguageDefinition(name: "Swift", fileExtensions: ["nope"])
        ) { saved = $0 }
        _ = editor.window
        XCTAssertNotNil(editor.validationError(), "a built-in name is refused")
        XCTAssertFalse(editor.save())
        XCTAssertNil(saved, "nothing is handed back when validation fails")
    }

    func testUserLanguagesPersistAsNotepadPlusPlusXML() throws {
        let language = LanguageDefinition(
            name: "Portable", fileExtensions: ["po1"],
            lineCommentTokens: ["//"], keywords1: ["one", "two"]
        )
        let xml = UDLSerialization.exportXML(for: [language])
        let restored = try XCTUnwrap(try UDLSerialization.importLanguages(from: xml).first)
        XCTAssertEqual(restored.name, "Portable")
        XCTAssertEqual(restored.keywords1, ["one", "two"])
        XCTAssertTrue(xml.contains("<UserLang"), "the on-disk format is Notepad++'s, not our own")
    }
}
