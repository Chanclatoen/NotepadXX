import Foundation

/// Incremental syntax highlighting over a document.
///
/// Highlighting a 100MB log by lexing the whole buffer on every keystroke would
/// undo the performance work in the text engine. Instead this keeps the lexer
/// state (currently block-comment depth) at the start of every line, so any
/// visible range can be lexed on its own by seeding from that line's cached
/// state. An edit invalidates only from its line onward, and re-lexing stops
/// early once the recomputed state matches the cache again — so a keystroke
/// inside a function costs a line or two, not a document.
public final class SyntaxHighlighter {
    public private(set) var language: LanguageDefinition
    private var lexer: Lexer
    /// State entering each line. `lineStates[i]` is valid iff `i < validPrefix`.
    private var lineStates: [Lexer.State] = [.initial]
    private var validPrefix: Int = 1
    private var lineStarts: [Int] = [0]
    private var text: String = ""

    public init(language: LanguageDefinition) {
        self.language = language
        self.lexer = Lexer(language: language)
    }

    public func setLanguage(_ language: LanguageDefinition) {
        self.language = language
        self.lexer = Lexer(language: language)
        invalidate(fromLine: 0)
    }

    /// Replaces the document. Line offsets are recomputed; states are dropped.
    public func setText(_ newText: String) {
        text = newText
        lineStarts = Self.computeLineStarts(newText)
        lineStates = [.initial]
        validPrefix = 1
    }

    public var lineCount: Int { lineStarts.count }

    /// Discards cached state at and after `line`.
    public func invalidate(fromLine line: Int) {
        validPrefix = min(validPrefix, max(1, line + 1))
    }

    /// Call after an edit so line offsets and states stay correct.
    public func textDidChange(_ newText: String, editedLine: Int) {
        text = newText
        lineStarts = Self.computeLineStarts(newText)
        if lineStates.count > lineStarts.count {
            lineStates.removeSubrange(lineStarts.count...)
        }
        invalidate(fromLine: editedLine)
    }

    /// Tokens for lines `range`, in whole-document offsets.
    public func tokens(forLines range: ClosedRange<Int>) -> [Token] {
        guard !lineStarts.isEmpty else { return [] }
        let first = max(0, range.lowerBound)
        let last = min(lineStarts.count - 1, range.upperBound)
        guard first <= last else { return [] }

        let state = state(atLine: first)
        let start = lineStarts[first]
        let end = last + 1 < lineStarts.count ? lineStarts[last + 1] : (text as NSString).length
        guard end > start else { return [] }

        let content = text as NSString
        let chunk = content.substring(with: NSRange(location: start, length: end - start))
        let result = lexer.tokenize(chunk, startingIn: state)
        // Shift chunk-local ranges into document coordinates.
        return result.tokens.map {
            Token(type: $0.type, range: NSRange(location: $0.range.location + start, length: $0.range.length))
        }
    }

    /// Cached lexer state entering `line`, computing forward from the last known
    /// good line if necessary.
    public func state(atLine line: Int) -> Lexer.State {
        guard line > 0 else { return .initial }
        if line < validPrefix, line < lineStates.count { return lineStates[line] }

        let content = text as NSString
        var current = lineStates.indices.contains(validPrefix - 1) ? lineStates[validPrefix - 1] : .initial
        var index = validPrefix - 1

        while index < line && index < lineStarts.count {
            let start = lineStarts[index]
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : content.length
            guard end >= start else { break }
            let chunk = content.substring(with: NSRange(location: start, length: end - start))
            current = lexer.tokenize(chunk, startingIn: current).endState
            index += 1
            if lineStates.count > index {
                lineStates[index] = current
            } else {
                lineStates.append(current)
            }
        }
        validPrefix = max(validPrefix, min(line + 1, lineStates.count))
        return lineStates.indices.contains(line) ? lineStates[line] : current
    }

    /// The 0-based line containing `offset`.
    public func line(containing offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1, answer = 0
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset { answer = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return answer
    }

    public func lineRange(forCharacterRange range: NSRange) -> ClosedRange<Int> {
        let first = line(containing: range.location)
        let last = line(containing: max(range.location, NSMaxRange(range) - 1))
        return first...max(first, last)
    }

    static func computeLineStarts(_ text: String) -> [Int] {
        let content = text as NSString
        var starts: [Int] = [0]
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: content.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosing, _ in
            let next = NSMaxRange(enclosing)
            if next < content.length { starts.append(next) }
        }
        return starts
    }
}
