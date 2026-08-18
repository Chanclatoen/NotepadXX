import XCTest
@testable import NotepadXXCore

final class FoldingEngineTests: XCTestCase {
    func testBraceFolding() {
        let text = "func a() {\n  body\n}\nafter\n"
        let folds = FoldingEngine.folds(in: text, language: BuiltInLanguages.swift)
        XCTAssertEqual(folds.count, 1)
        XCTAssertEqual(folds[0].start, 0)
        XCTAssertEqual(folds[0].end, 2)
    }

    func testNestedBracesProduceNestedFolds() {
        let text = "a {\n  b {\n    c\n  }\n}\n"
        let folds = FoldingEngine.folds(in: text, language: BuiltInLanguages.swift)
        XCTAssertEqual(folds.count, 2)
        let outer = folds.first { $0.start == 0 }
        let inner = folds.first { $0.start == 1 }
        XCTAssertEqual(outer?.end, 4)
        XCTAssertEqual(inner?.end, 3)
        XCTAssertGreaterThan(inner?.level ?? 0, outer?.level ?? 0)
    }

    func testSingleLineBlockDoesNotFold() {
        let folds = FoldingEngine.folds(in: "func a() { body }\n", language: BuiltInLanguages.swift)
        XCTAssertTrue(folds.isEmpty, "a block that opens and closes on one line is not foldable")
    }

    /// A brace inside a string or comment must not open a phantom fold.
    func testBracesInStringsAndCommentsAreIgnored() {
        let text = "let s = \"{ not a block\"\nlet t = 1 // }\nreal {\n  x\n}\n"
        let folds = FoldingEngine.folds(in: text, language: BuiltInLanguages.swift)
        XCTAssertEqual(folds.count, 1, "only the real brace pair folds")
        XCTAssertEqual(folds[0].start, 2)
    }

    func testUnbalancedBracesDoNotCrash() {
        XCTAssertNoThrow(FoldingEngine.folds(in: "{\n{\n{\n", language: BuiltInLanguages.swift))
        XCTAssertNoThrow(FoldingEngine.folds(in: "}\n}\n", language: BuiltInLanguages.swift))
    }

    func testIndentationFoldingForPython() {
        let text = "def a():\n    x = 1\n    y = 2\ndef b():\n    z = 3\n"
        let folds = FoldingEngine.folds(in: text, language: BuiltInLanguages.python)
        XCTAssertTrue(folds.contains { $0.start == 0 && $0.end == 2 })
        XCTAssertTrue(folds.contains { $0.start == 3 && $0.end == 4 })
    }

    func testBlankLinesStayInsideAnIndentedBlock() {
        let text = "def a():\n    x = 1\n\n    y = 2\nafter\n"
        let folds = FoldingEngine.indentationFolds(in: text)
        let block = folds.first { $0.start == 0 }
        XCTAssertEqual(block?.end, 3, "a blank line does not terminate the block")
    }

    func testIndentWidthCountsTabsToTabStops() {
        XCTAssertEqual(FoldingEngine.indentWidth(of: "\tx", tabWidth: 4), 4)
        XCTAssertEqual(FoldingEngine.indentWidth(of: "  \tx", tabWidth: 4), 4, "tab advances to the stop")
        XCTAssertEqual(FoldingEngine.indentWidth(of: "      x", tabWidth: 4), 6)
    }

    func testInnermostFoldContainingLine() {
        let folds = [
            FoldRange(start: 0, end: 10, level: 0),
            FoldRange(start: 2, end: 5, level: 1),
        ]
        XCTAssertEqual(FoldingEngine.innermostFold(containing: 3, in: folds)?.start, 2)
        XCTAssertEqual(FoldingEngine.innermostFold(containing: 8, in: folds)?.start, 0)
        XCTAssertNil(FoldingEngine.innermostFold(containing: 99, in: folds))
    }

    func testEmptyDocument() {
        XCTAssertTrue(FoldingEngine.folds(in: "", language: BuiltInLanguages.swift).isEmpty)
    }
}

final class FunctionListTests: XCTestCase {
    func testSwiftFunctionsAndTypes() {
        let text = """
        import Foundation

        struct Widget {
            func render() {}
            private func hidden() {}
        }

        extension Widget {}
        """
        let symbols = FunctionListExtractor.symbols(in: text, languageName: "Swift")
        let names = symbols.map(\.name)
        XCTAssertTrue(names.contains("Widget"))
        XCTAssertTrue(names.contains("render"))
        XCTAssertTrue(names.contains("hidden"), "access modifiers do not hide a symbol")
    }

    func testPythonDefsAndClasses() {
        let text = "class A:\n    def method(self):\n        pass\n\nasync def top():\n    pass\n"
        let symbols = FunctionListExtractor.symbols(in: text, languageName: "Python")
        XCTAssertEqual(symbols.map(\.name), ["A", "method", "top"])
    }

    func testSymbolsCarryLineAndOffset() {
        let text = "x = 1\ndef target():\n    pass\n"
        let symbols = FunctionListExtractor.symbols(in: text, languageName: "Python")
        let target = try? XCTUnwrap(symbols.first)
        XCTAssertEqual(target?.line, 1)
        // Offset must point at the name within the document.
        let content = text as NSString
        if let offset = target?.offset {
            XCTAssertEqual(content.substring(with: NSRange(location: offset, length: 6)), "target")
        }
    }

    func testSymbolsAreInDocumentOrder() {
        let text = "def b():\n    pass\ndef a():\n    pass\n"
        let symbols = FunctionListExtractor.symbols(in: text, languageName: "Python")
        XCTAssertEqual(symbols.map(\.name), ["b", "a"], "document order, not alphabetical")
    }

    func testGoMethodsWithReceivers() {
        let text = "func (w *Widget) Render() {}\nfunc Plain() {}\n"
        let symbols = FunctionListExtractor.symbols(in: text, languageName: "Go")
        XCTAssertEqual(symbols.map(\.name), ["Render", "Plain"])
    }

    func testMarkdownHeadings() {
        let symbols = FunctionListExtractor.symbols(in: "# One\ntext\n### Three\n", languageName: "Markdown")
        XCTAssertEqual(symbols.map(\.name), ["One", "Three"])
    }

    func testUnknownLanguageYieldsNoSymbols() {
        XCTAssertTrue(FunctionListExtractor.symbols(in: "anything", languageName: "Brainfuck").isEmpty)
        XCTAssertTrue(FunctionListExtractor.symbols(in: "anything", languageName: nil).isEmpty)
    }

    func testOneSymbolPerLine() {
        // A line matching several rules must not produce duplicates.
        let symbols = FunctionListExtractor.symbols(in: "class A:\n", languageName: "Python")
        XCTAssertEqual(symbols.count, 1)
    }
}
