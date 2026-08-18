import Foundation

/// A collapsible region, expressed in 0-based lines. `end` is the last line
/// belonging to the fold.
public struct FoldRange: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let level: Int
    public init(start: Int, end: Int, level: Int) {
        self.start = start
        self.end = end
        self.level = level
    }
    public var lineCount: Int { end - start + 1 }
}

/// Computes fold regions for a document.
///
/// Two strategies, chosen by the language: brace/keyword matching for languages
/// that delimit blocks (C, Swift, JSON), and indentation for languages that do
/// not (Python, YAML). Notepad++ does the same split, and getting it wrong is
/// very visible — folding a Python file by braces would produce nothing.
public enum FoldingEngine {

    public static func folds(in text: String, language: LanguageDefinition) -> [FoldRange] {
        // A language with no fold markers folds by indentation.
        if language.foldOpen.isEmpty || language.foldClose.isEmpty {
            return indentationFolds(in: text)
        }
        return delimiterFolds(in: text, language: language)
    }

    /// Brace-style folding. Comments and strings are skipped by lexing first, so
    /// a brace inside a string literal does not open a phantom fold.
    public static func delimiterFolds(in text: String, language: LanguageDefinition) -> [FoldRange] {
        let (lines, _) = LineOperations.split(text)
        let lexer = Lexer(language: language)
        var state = Lexer.State.initial
        var stack: [(line: Int, level: Int)] = []
        var folds: [FoldRange] = []

        for (index, line) in lines.enumerated() {
            let result = lexer.tokenize(line, startingIn: state)
            let masked = maskTokens(line, tokens: result.tokens)
            state = result.endState

            for open in language.foldOpen where masked.contains(open) {
                for _ in 0..<masked.components(separatedBy: open).count - 1 {
                    stack.append((index, stack.count))
                }
            }
            for close in language.foldClose where masked.contains(close) {
                for _ in 0..<masked.components(separatedBy: close).count - 1 {
                    guard let opened = stack.popLast() else { continue }
                    // A fold must span more than one line to be worth showing.
                    if index > opened.line {
                        folds.append(FoldRange(start: opened.line, end: index, level: opened.level))
                    }
                }
            }
        }
        return folds.sorted { $0.start < $1.start }
    }

    /// Indentation folding: a line owns every following line indented further.
    public static func indentationFolds(in text: String) -> [FoldRange] {
        let (lines, _) = LineOperations.split(text)
        let indents = lines.map { line -> Int? in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : indentWidth(of: line)
        }

        var folds: [FoldRange] = []
        for (index, indent) in indents.enumerated() {
            guard let indent else { continue }
            var last = index
            var probe = index + 1
            while probe < indents.count {
                guard let next = indents[probe] else { probe += 1; continue }  // blank lines belong to the block
                if next > indent { last = probe; probe += 1 } else { break }
            }
            if last > index {
                folds.append(FoldRange(start: index, end: last, level: indent))
            }
        }
        return folds
    }

    /// Replaces comment and string content with spaces so delimiter scanning
    /// only sees real code.
    private static func maskTokens(_ line: String, tokens: [Token]) -> String {
        guard !tokens.isEmpty else { return line }
        let content = line as NSString
        let masked = NSMutableString(string: line)
        for token in tokens where token.type == .comment || token.type == .commentLine
            || token.type == .string || token.type == .character {
            let range = NSIntersectionRange(token.range, NSRange(location: 0, length: content.length))
            guard range.length > 0 else { continue }
            masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return masked as String
    }

    static func indentWidth(of line: String, tabWidth: Int = 4) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 }
            else if character == "\t" { width += tabWidth - (width % tabWidth) }
            else { break }
        }
        return width
    }

    /// The innermost fold containing `line`, for "fold current level".
    public static func innermostFold(containing line: Int, in folds: [FoldRange]) -> FoldRange? {
        folds.filter { $0.start <= line && line <= $0.end }
             .min { $0.lineCount < $1.lineCount }
    }
}
