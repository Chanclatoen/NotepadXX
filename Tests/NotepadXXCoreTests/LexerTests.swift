import XCTest
@testable import NotepadXXCore

final class LexerTests: XCTestCase {
    private func tokens(_ text: String, _ language: LanguageDefinition) -> [(TokenType, String)] {
        let content = text as NSString
        return Lexer(language: language).tokenize(text).tokens.map {
            ($0.type, content.substring(with: $0.range))
        }
    }

    func testKeywordsTypesAndNumbers() {
        let result = tokens("int x = 42;", BuiltInLanguages.c)
        XCTAssertTrue(result.contains { $0 == (.keyword2, "int") })
        XCTAssertTrue(result.contains { $0 == (.number, "42") })
        XCTAssertFalse(result.contains { $0.1 == "x" }, "identifiers are not tokenised")
    }

    func testLineComment() {
        let result = tokens("code // trailing comment\nmore", BuiltInLanguages.c)
        XCTAssertTrue(result.contains { $0 == (.commentLine, "// trailing comment") })
    }

    func testBlockComment() {
        let result = tokens("a /* hidden */ b", BuiltInLanguages.c)
        XCTAssertTrue(result.contains { $0.0 == .comment && $0.1.contains("hidden") })
    }

    /// A keyword inside a comment or string must not be highlighted as a keyword.
    func testKeywordsInsideCommentsAndStringsAreNotKeywords() {
        let commented = tokens("// int here", BuiltInLanguages.c)
        XCTAssertFalse(commented.contains { $0.0 == .keyword2 })

        let stringed = tokens("\"int here\"", BuiltInLanguages.c)
        XCTAssertFalse(stringed.contains { $0.0 == .keyword2 })
        XCTAssertTrue(stringed.contains { $0.0 == .string })
    }

    func testEscapedQuoteDoesNotEndTheString() {
        let result = tokens("\"a\\\"b\" int", BuiltInLanguages.c)
        XCTAssertTrue(result.contains { $0.0 == .string && $0.1.contains("\\\"") },
                      "the escaped quote stays inside the string")
        XCTAssertTrue(result.contains { $0 == (.keyword2, "int") },
                      "the string ends where it should, so the keyword after it is seen")
    }

    func testUnterminatedStringStopsAtEndOfLine() {
        let result = tokens("\"oops\nint x", BuiltInLanguages.c)
        XCTAssertTrue(result.contains { $0 == (.keyword2, "int") },
                      "a runaway string must not swallow the rest of the file")
    }

    func testNestedBlockCommentsWhereSupported() {
        // Swift nests; C does not.
        let swiftResult = Lexer(language: BuiltInLanguages.swift)
            .tokenize("/* outer /* inner */ still comment */ let")
        let content = "/* outer /* inner */ still comment */ let" as NSString
        let hasLet = swiftResult.tokens.contains {
            $0.type == .keyword1 && content.substring(with: $0.range) == "let"
        }
        XCTAssertTrue(hasLet, "nested comment closes only at the outer terminator")

        let cResult = tokens("/* outer /* inner */ int", BuiltInLanguages.c)
        XCTAssertTrue(cResult.contains { $0 == (.keyword2, "int") },
                      "C comments do not nest, so the first */ ends it")
    }

    func testBlockCommentStateCarriesAcrossChunks() {
        let lexer = Lexer(language: BuiltInLanguages.c)
        let first = lexer.tokenize("/* start")
        XCTAssertEqual(first.endState.blockCommentDepth, 1, "comment is still open")
        let second = lexer.tokenize("still comment */ int", startingIn: first.endState)
        XCTAssertEqual(second.endState.blockCommentDepth, 0)
        let content = "still comment */ int" as NSString
        XCTAssertTrue(second.tokens.contains {
            $0.type == .keyword2 && content.substring(with: $0.range) == "int"
        })
    }

    func testPreprocessorOnlyAtLineStart() {
        let atStart = tokens("#include <stdio.h>", BuiltInLanguages.c)
        XCTAssertTrue(atStart.contains { $0.0 == .preprocessor })

        let midLine = tokens("a # b", BuiltInLanguages.c)
        XCTAssertFalse(midLine.contains { $0.0 == .preprocessor },
                       "a hash mid-line is not a directive")
    }

    func testCaseInsensitiveLanguages() {
        let upper = tokens("SELECT * FROM t", BuiltInLanguages.sql)
        XCTAssertTrue(upper.contains { $0.0 == .keyword1 && $0.1 == "SELECT" })
        let lower = tokens("select * from t", BuiltInLanguages.sql)
        XCTAssertTrue(lower.contains { $0.0 == .keyword1 && $0.1 == "select" })
    }

    func testCaseSensitiveLanguagesRejectWrongCase() {
        let result = tokens("INT x", BuiltInLanguages.c)
        XCTAssertFalse(result.contains { $0.0 == .keyword2 }, "C is case sensitive")
    }

    func testDigitsInsideIdentifiersAreNotNumbers() {
        let result = tokens("var utf8 = 1", BuiltInLanguages.javascript)
        XCTAssertFalse(result.contains { $0.0 == .number && $0.1 == "8" },
                       "the 8 in utf8 belongs to the identifier")
        XCTAssertTrue(result.contains { $0.0 == .number && $0.1 == "1" })
    }

    func testPythonHashComment() {
        let result = tokens("x = 1  # note\ny = 2", BuiltInLanguages.python)
        XCTAssertTrue(result.contains { $0.0 == .commentLine && $0.1 == "# note" })
    }

    func testEmptyAndPlainInputProduceNoCrash() {
        XCTAssertTrue(tokens("", BuiltInLanguages.c).isEmpty)
        XCTAssertTrue(tokens("just words here", BuiltInLanguages.c).allSatisfy { $0.0 != .keyword1 })
    }

    func testLexingIsLinearOnLargeInput() {
        // Guards against an accidental quadratic scan; highlighting runs per edit.
        let text = String(repeating: "int value = 123; // comment\n", count: 20_000)
        let start = Date()
        _ = Lexer(language: BuiltInLanguages.c).tokenize(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5.0, "lexing 20k lines should be quick")
    }
}

final class LanguageRegistryTests: XCTestCase {
    private let registry = LanguageRegistry()

    func testDetectByExtension() {
        XCTAssertEqual(registry.detect(fileName: "main.swift")?.name, "Swift")
        XCTAssertEqual(registry.detect(fileName: "a.py")?.name, "Python")
        XCTAssertEqual(registry.detect(fileName: "Style.CSS")?.name, "CSS", "extension match is case-insensitive")
    }

    func testDetectByShebangWhenExtensionIsUnknown() {
        XCTAssertEqual(registry.detect(fileName: "script", firstLine: "#!/usr/bin/env python3")?.name, "Python")
        XCTAssertEqual(registry.detect(fileName: "run", firstLine: "#!/bin/bash")?.name, "Shell")
    }

    func testExtensionWinsOverShebang() {
        // A shebang inside a .md file is incidental.
        XCTAssertEqual(registry.detect(fileName: "notes.md", firstLine: "#!/bin/bash")?.name, "Markdown")
    }

    func testUnknownFileYieldsNil() {
        XCTAssertNil(registry.detect(fileName: "data.unknownext", firstLine: "plain text"))
    }

    func testRegisterAndOverrideUserDefinedLanguage() {
        let registry = LanguageRegistry()
        let custom = LanguageDefinition(name: "MyLang", fileExtensions: ["mylang"], keywords1: ["foo"])
        registry.register(custom)
        XCTAssertEqual(registry.detect(fileName: "a.mylang")?.name, "MyLang")

        var updated = custom
        updated.keywords1 = ["bar"]
        registry.register(updated)
        XCTAssertEqual(registry.language(named: "MyLang")?.keywords1, ["bar"], "re-registering replaces")
        XCTAssertEqual(registry.all.filter { $0.name == "MyLang" }.count, 1, "no duplicate entry")

        registry.remove(named: "MyLang")
        XCTAssertNil(registry.language(named: "MyLang"))
    }

    func testBuiltInsAreSortedAndNonEmpty() {
        XCTAssertGreaterThan(registry.all.count, 20)
        let names = registry.all.map { $0.name.lowercased() }
        XCTAssertEqual(names, names.sorted())
    }
}

final class ExtendedLanguageTests: XCTestCase {
    private let registry = LanguageRegistry()

    private func tokens(_ text: String, _ language: LanguageDefinition) -> [(TokenType, String)] {
        let content = text as NSString
        return Lexer(language: language).tokenize(text).tokens.map {
            ($0.type, content.substring(with: $0.range))
        }
    }

    func testShippedLanguageCount() {
        XCTAssertGreaterThanOrEqual(registry.all.count, 70,
                                    "the shipped set should cover most of Notepad++'s lexers")
    }

    func testNoDuplicateLanguageNames() {
        let names = registry.all.map { $0.name.lowercased() }
        XCTAssertEqual(Set(names).count, names.count, "language names must be unique")
    }

    /// A file extension claimed by two languages would make detection depend on
    /// declaration order.
    func testNoDuplicateFileExtensions() {
        var seen: [String: String] = [:]
        var clashes: [String] = []
        for language in registry.all {
            for ext in language.fileExtensions {
                if let owner = seen[ext] { clashes.append("\(ext): \(owner) vs \(language.name)") }
                seen[ext] = language.name
            }
        }
        XCTAssertTrue(clashes.isEmpty, "extensions claimed twice: \(clashes)")
    }

    func testEveryLanguageHasANameAndLexes() {
        for language in registry.all {
            XCTAssertFalse(language.name.isEmpty)
            // Every definition must survive lexing a representative snippet.
            XCTAssertNoThrow(Lexer(language: language).tokenize("a = 1 // x\n\"s\"\n"))
        }
    }

    func testPowerShellIsCaseInsensitive() {
        XCTAssertTrue(tokens("FUNCTION Test {}", BuiltInLanguages.powershell)
            .contains { $0.0 == .keyword1 })
    }

    func testHaskellNestsBlockComments() {
        let result = tokens("{- outer {- inner -} still -} data", BuiltInLanguages.haskell)
        XCTAssertTrue(result.contains { $0 == (.keyword1, "data") },
                      "nested comment closes at the outer terminator")
    }

    func testMakefileAndDockerfileMatchByWholeName() {
        XCTAssertEqual(registry.detect(fileName: "Makefile")?.name, "Makefile")
        XCTAssertEqual(registry.detect(fileName: "Dockerfile")?.name, "Dockerfile")
    }

    func testLogLevelsAreDistinctKeywordGroups() {
        let result = tokens("ERROR WARN INFO", BuiltInLanguages.log)
        XCTAssertTrue(result.contains { $0 == (.keyword1, "ERROR") })
        XCTAssertTrue(result.contains { $0 == (.keyword2, "WARN") })
        XCTAssertTrue(result.contains { $0 == (.keyword3, "INFO") })
    }

    func testAssemblyCommentsAndRegisters() {
        let result = tokens("mov eax, 1 ; load", BuiltInLanguages.assembly)
        XCTAssertTrue(result.contains { $0 == (.keyword1, "mov") })
        XCTAssertTrue(result.contains { $0 == (.keyword2, "eax") })
        XCTAssertTrue(result.contains { $0.0 == .commentLine })
    }
}
