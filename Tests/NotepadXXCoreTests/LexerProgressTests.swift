import XCTest
@testable import NotepadXXCore

/// The lexer runs on the main thread, so a pass that consumes nothing freezes
/// the app. These tests pin that class of bug (T10652: any `@` hung the app).
final class LexerProgressTests: XCTestCase {
    private func tokens(_ text: String, _ language: LanguageDefinition) -> [(TokenType, String)] {
        let content = Array(text)
        return Lexer(language: language).tokenize(text).tokens.map {
            ($0.type, String(content[$0.range.location..<($0.range.location + $0.range.length)]))
        }
    }

    /// Runs `body` off the main thread so a regression fails instead of hanging the suite.
    private func finishes(within seconds: Double, _ body: @escaping () -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        let work = UncheckedWork(body)
        DispatchQueue.global().async { work.run(); done.signal() }
        return done.wait(timeout: .now() + seconds) == .success
    }

    private func assertTokenizes(_ text: String, _ language: LanguageDefinition,
                                 file: StaticString = #filePath, line: UInt = #line) -> [(TokenType, String)] {
        var result: [(TokenType, String)] = []
        let ok = finishes(within: 5) { _ = Lexer(language: language).tokenize(text) }
        XCTAssertTrue(ok, "\(language.name) hung on \(text.debugDescription)", file: file, line: line)
        if ok { result = tokens(text, language) }
        return result
    }

    // MARK: regression: "@" per language

    func testPythonDecorator() {
        let r = assertTokenizes("@dataclass\nclass A:\n    @property\n    def x(self): return 1\n", BuiltInLanguages.python)
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@dataclass") })
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@property") })
        XCTAssertTrue(r.contains { $0.1 == "class" && $0.0 == .keyword1 })
    }

    func testJavaAnnotation() {
        let r = assertTokenizes("@Override\npublic void run() {}\n@SuppressWarnings(\"x\")\n", BuiltInLanguages.java)
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@Override") })
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@SuppressWarnings") })
        XCTAssertTrue(r.contains { $0 == (.string, "\"x\"") })
    }

    func testCSSAtRule() {
        let r = assertTokenizes("@media (max-width: 600px) { a { color: red } }\n@import url(x.css);", BuiltInLanguages.css)
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@media") })
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@import") })
    }

    func testSwiftAttribute() {
        let r = assertTokenizes("@MainActor final class A {\n  @Published var x = 1\n}\n", BuiltInLanguages.swift)
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@MainActor") })
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@Published") })
        XCTAssertTrue(r.contains { $0.1 == "class" })
    }

    func testKotlinAnnotation() {
        let r = assertTokenizes("@Composable\nfun A() {}\n", language("Kotlin"))
        XCTAssertTrue(r.contains { $0 == (.preprocessor, "@Composable") })
    }

    func testJavaScriptAndTypeScriptDecorators() {
        for lang in [BuiltInLanguages.javascript, BuiltInLanguages.typescript] {
            let r = assertTokenizes("@Component({selector: 'a'})\nclass A { @Input() x = 1 }\n", lang)
            XCTAssertTrue(r.contains { $0 == (.preprocessor, "@Component") }, lang.name)
            XCTAssertTrue(r.contains { $0 == (.preprocessor, "@Input") }, lang.name)
        }
    }

    func testShellAndMarkdown() {
        let sh = assertTokenizes("echo \"${arr[@]}\" \"$@\"\nfor a in \"$@\"; do echo $a; done\n", BuiltInLanguages.shell)
        XCTAssertTrue(sh.contains { $0.1 == "echo" || $0.1 == "for" })
        let md = assertTokenizes("mail me@example.com or @jaber, see @ here\n", BuiltInLanguages.markdown)
        XCTAssertFalse(md.contains { $0.1 == "@example" }, "an @ glued to an identifier is not a decorator")
        XCTAssertTrue(md.contains { $0 == (.preprocessor, "@jaber") })
    }

    func testObjectiveCKeywordWithAtSign() {
        let r = assertTokenizes("@interface Foo : NSObject\n@end\n", language("Objective-C"))
        XCTAssertTrue(r.contains { $0 == (.keyword1, "@interface") })
        XCTAssertTrue(r.contains { $0 == (.keyword1, "@end") })
    }

    func testLoneAtSignsAndEdges() {
        for lang in BuiltInLanguages.all {
            for text in ["@", "@@", "@\n@", " @ ", "@1", "@_", "a@", "@@@@@@", "@\u{301}"] {
                _ = assertTokenizes(text, lang)
            }
        }
    }

    /// Non-ASCII digits ("²", "½") are `isNumber` but not number characters:
    /// the number branch had the same zero-length shape as the `@` bug.
    func testUnicodeNumbersMakeProgress() {
        for text in ["x²", "½", ".½", "a ² b", "٣٤", "①②"] {
            _ = assertTokenizes(text, BuiltInLanguages.c)
        }
    }

    /// Zero-length regex matches must advance too (find-all, count, replace-all).
    func testZeroLengthRegexMatchesTerminate() throws {
        let text = "alpha beta\n\ngamma  @x\n"
        let patterns = ["^", "$", "(?=a)", "\\b", "x*", "(?<=a)"]
        let ok = finishes(within: 10) {
            for pattern in patterns {
                let engine = SearchEngine(pattern: pattern, options: SearchOptions(mode: .regex))
                _ = try? engine.count(in: text)
                _ = try? engine.replaceAll(in: text, with: "-")
            }
        }
        XCTAssertTrue(ok)
    }

    private func language(_ name: String) -> LanguageDefinition {
        guard let l = BuiltInLanguages.all.first(where: { $0.name == name }) else {
            XCTFail("no language \(name)"); return BuiltInLanguages.c
        }
        return l
    }

    // MARK: fuzz

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    private static let unicode: [String] = [
        "é", "ü", "ß", "漢", "字", "😀", "👨‍👩‍👧", "\u{301}", "\u{200D}", "\u{FEFF}", "\u{0}",
        "²", "½", "①", "٣", "\r\n", "\r", "\u{2028}", "\u{A0}", "@", "$", "_",
    ]

    func testFuzzEveryBundledLanguage() {
        let ascii = (0x09...0x7E).compactMap { Unicode.Scalar($0).map(String.init) }
        let cases = 10_000
        for language in BuiltInLanguages.all {
            // Language-specific pieces make adversarial combinations likely.
            var pieces = ascii + Self.unicode
            pieces += language.lineCommentTokens
            pieces += language.stringDelimiters
            pieces += language.preprocessorPrefixes
            pieces += [language.blockCommentOpen, language.blockCommentClose].compactMap { $0 }
            pieces += Array(language.keywords1.prefix(8)) + Array(language.keywords2.prefix(8))
            if let e = language.escapeCharacter { pieces.append(String(e)) }

            let name = language.name
            let seed: UInt64 = 0xC0FFEE
            let lexer = Lexer(language: language)
            let worst = LockedBox<Double>(0)
            let ok = finishes(within: 120) {
                var rng = SplitMix64(state: seed)
                for _ in 0..<cases {
                    let length = rng.below(60)
                    var text = ""
                    for _ in 0..<length { text += pieces[rng.below(pieces.count)] }
                    let started = DispatchTime.now().uptimeNanoseconds
                    let start = Array(text).count
                    let (toks, _) = lexer.tokenize(text, startingIn: Lexer.State(blockCommentDepth: rng.below(3)))
                    let seconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
                    worst.update { $0 = max($0, seconds) }
                    for t in toks where t.range.length <= 0 || t.range.location < 0 || t.range.location + t.range.length > start {
                        XCTFail("\(name): bad token range \(t.range) for \(text.debugDescription)")
                        return
                    }
                }
            }
            XCTAssertTrue(ok, "\(name): fuzz run hung or exceeded 120 s")
            XCTAssertLessThan(worst.value, 1.0, "\(name): a single case took too long")
            if !ok { return }
        }
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func update(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}

private final class UncheckedWork: @unchecked Sendable {
    private let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    func run() { body() }
}
