import Foundation

/// A keyword/delimiter lexer driven entirely by `LanguageDefinition`.
///
/// One engine serves both the built-in languages and User Defined Languages,
/// exactly as Notepad++ does. It is a single linear scan, so cost is O(n) in the
/// text length — important because highlighting runs on every edit.
public struct Lexer {
    public let language: LanguageDefinition

    public init(language: LanguageDefinition) {
        self.language = language
    }

    /// State carried across a line boundary, so a range can be re-lexed without
    /// rescanning the whole document.
    public struct State: Equatable, Sendable {
        public var blockCommentDepth: Int
        public init(blockCommentDepth: Int = 0) {
            self.blockCommentDepth = blockCommentDepth
        }
        public static let initial = State()
    }

    /// Tokenises `text`. Only non-plain runs are emitted, so a mostly-plain
    /// document produces few tokens.
    public func tokenize(_ text: String, startingIn state: State = .initial) -> (tokens: [Token], endState: State) {
        let scalars = Array(text)
        var tokens: [Token] = []
        var state = state
        var index = 0

        func emit(_ type: TokenType, _ start: Int, _ end: Int) {
            guard end > start else { return }
            tokens.append(Token(type: type, range: NSRange(location: start, length: end - start)))
        }

        func matches(_ token: String, at position: Int) -> Bool {
            guard !token.isEmpty, position + token.count <= scalars.count else { return false }
            return String(scalars[position..<(position + token.count)]) == token
        }

        while index < scalars.count {
            // Continue an open block comment first — it swallows everything else.
            if state.blockCommentDepth > 0, let close = language.blockCommentClose {
                let start = index
                while index < scalars.count {
                    if let open = language.blockCommentOpen, language.blockCommentsNest, matches(open, at: index) {
                        state.blockCommentDepth += 1
                        index += open.count
                        continue
                    }
                    if matches(close, at: index) {
                        index += close.count
                        state.blockCommentDepth -= 1
                        if state.blockCommentDepth == 0 { break }
                        continue
                    }
                    index += 1
                }
                emit(.comment, start, index)
                continue
            }

            let character = scalars[index]

            // Line comment: runs to end of line.
            if let token = language.lineCommentTokens.first(where: { matches($0, at: index) }) {
                let start = index
                index += token.count
                while index < scalars.count && scalars[index] != "\n" { index += 1 }
                emit(.commentLine, start, index)
                continue
            }

            // Block comment open.
            if let open = language.blockCommentOpen, matches(open, at: index) {
                state.blockCommentDepth = 1
                index += open.count
                continue
            }

            // Preprocessor directive, only when it is the first thing on the line.
            if let prefix = language.preprocessorPrefixes.first(where: { matches($0, at: index) }),
               isAtLineStart(scalars, index) {
                let start = index
                index += prefix.count
                while index < scalars.count && scalars[index] != "\n" { index += 1 }
                emit(.preprocessor, start, index)
                continue
            }

            // String / character literal.
            if let quote = language.stringDelimiters.first(where: { matches($0, at: index) }) {
                let start = index
                index += quote.count
                var terminated = false
                while index < scalars.count {
                    if let escape = language.escapeCharacter, scalars[index] == escape {
                        index += 2
                        continue
                    }
                    if scalars[index] == "\n" && !language.stringsSpanLines { break }
                    if matches(quote, at: index) {
                        index += quote.count
                        terminated = true
                        break
                    }
                    index += 1
                }
                _ = terminated
                emit(quote == "'" ? .character : .string, start, min(index, scalars.count))
                continue
            }

            // Number: digits, or a leading dot followed by a digit.
            if character.isNumber || (character == "." && index + 1 < scalars.count && scalars[index + 1].isNumber) {
                // A digit directly after an identifier character belongs to that
                // identifier (e.g. "utf8"), not to a number.
                if index > 0 && isIdentifierCharacter(scalars[index - 1]) {
                    index += 1
                    continue
                }
                let start = index
                while index < scalars.count && isNumberCharacter(scalars[index]) { index += 1 }
                emit(.number, start, index)
                continue
            }

            // Word: keyword or identifier.
            if isIdentifierStart(character) {
                let start = index
                while index < scalars.count && isIdentifierCharacter(scalars[index]) { index += 1 }
                let word = String(scalars[start..<index])
                if let group = language.keywordGroup(for: word) { emit(group, start, index) }
                continue
            }

            // Operator.
            if language.operatorCharacters.contains(character) {
                emit(.operatorToken, index, index + 1)
                index += 1
                continue
            }

            index += 1
        }

        return (tokens, state)
    }

    private func isAtLineStart(_ scalars: [Character], _ index: Int) -> Bool {
        var probe = index - 1
        while probe >= 0 {
            let character = scalars[probe]
            if character == "\n" { return true }
            if character != " " && character != "\t" { return false }
            probe -= 1
        }
        return true
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$" || character == "@"
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private func isNumberCharacter(_ character: Character) -> Bool {
        character.isHexDigit || character == "." || character == "x" || character == "X"
            || character == "b" || character == "o" || character == "_"
    }
}
