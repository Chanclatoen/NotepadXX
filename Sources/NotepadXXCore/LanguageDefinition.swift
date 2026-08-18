import Foundation

/// Token classes a lexer can emit. These mirror Notepad++'s styler categories so
/// a Style Configurator can map them one-to-one.
public enum TokenType: String, CaseIterable, Sendable, Codable {
    case plain
    case comment
    case commentLine
    case string
    case character
    case number
    case keyword1        // language keywords
    case keyword2        // types / built-ins
    case keyword3        // library functions
    case keyword4        // user-defined
    case preprocessor
    case operatorToken
    case delimiter
}

public struct Token: Equatable, Sendable {
    public let type: TokenType
    public let range: NSRange
    public init(type: TokenType, range: NSRange) {
        self.type = type
        self.range = range
    }
}

/// A keyword/delimiter language description.
///
/// This is the same shape Notepad++ uses for both its built-in lexers and its
/// User Defined Languages, which is why one engine can serve both: a UDL is
/// simply a definition the user authored instead of one we shipped.
public struct LanguageDefinition: Sendable, Codable, Equatable {
    public var name: String
    public var fileExtensions: [String]
    /// Matched against a `#!` first line, e.g. "python", "bash".
    public var shebangs: [String]

    public var lineCommentTokens: [String]
    /// Paired block comment delimiters, e.g. ("/*", "*/").
    public var blockCommentOpen: String?
    public var blockCommentClose: String?
    public var blockCommentsNest: Bool

    /// Quote characters that start a string, e.g. ["\"", "'"].
    public var stringDelimiters: [String]
    /// Stored as a string so the definition stays Codable for UDL import/export.
    public var escapeCharacterString: String?
    /// Whether a string may span lines (heredocs aside, most languages say no).
    public var stringsSpanLines: Bool

    public var preprocessorPrefixes: [String]
    public var operatorCharacterString: String
    public var isCaseSensitive: Bool

    /// Up to four keyword groups, matching Notepad++'s keyword lists.
    public var keywords1: Set<String>
    public var keywords2: Set<String>
    public var keywords3: Set<String>
    public var keywords4: Set<String>

    /// Fold markers, e.g. ("{", "}") — used by the folding pass.
    public var foldOpen: [String]
    public var foldClose: [String]

    public init(
        name: String,
        fileExtensions: [String] = [],
        shebangs: [String] = [],
        lineCommentTokens: [String] = [],
        blockCommentOpen: String? = nil,
        blockCommentClose: String? = nil,
        blockCommentsNest: Bool = false,
        stringDelimiters: [String] = ["\""],
        escapeCharacter: Character? = "\\",
        stringsSpanLines: Bool = false,
        preprocessorPrefixes: [String] = [],
        operatorCharacters: String = "+-*/%=<>!&|^~?:;,.()[]{}",
        isCaseSensitive: Bool = true,
        keywords1: Set<String> = [],
        keywords2: Set<String> = [],
        keywords3: Set<String> = [],
        keywords4: Set<String> = [],
        foldOpen: [String] = ["{"],
        foldClose: [String] = ["}"]
    ) {
        self.name = name
        self.fileExtensions = fileExtensions
        self.shebangs = shebangs
        self.lineCommentTokens = lineCommentTokens
        self.blockCommentOpen = blockCommentOpen
        self.blockCommentClose = blockCommentClose
        self.blockCommentsNest = blockCommentsNest
        self.stringDelimiters = stringDelimiters
        self.escapeCharacterString = escapeCharacter.map(String.init)
        self.stringsSpanLines = stringsSpanLines
        self.preprocessorPrefixes = preprocessorPrefixes
        self.operatorCharacterString = operatorCharacters
        self.isCaseSensitive = isCaseSensitive
        self.keywords1 = keywords1
        self.keywords2 = keywords2
        self.keywords3 = keywords3
        self.keywords4 = keywords4
        self.foldOpen = foldOpen
        self.foldClose = foldClose
    }

    public var escapeCharacter: Character? { escapeCharacterString?.first }
    public var operatorCharacters: Set<Character> { Set(operatorCharacterString) }

    /// Which keyword group a word belongs to, respecting case sensitivity.
    public func keywordGroup(for word: String) -> TokenType? {
        let probe = isCaseSensitive ? word : word.lowercased()
        func contains(_ set: Set<String>) -> Bool {
            isCaseSensitive ? set.contains(probe) : set.contains(where: { $0.lowercased() == probe })
        }
        if contains(keywords1) { return .keyword1 }
        if contains(keywords2) { return .keyword2 }
        if contains(keywords3) { return .keyword3 }
        if contains(keywords4) { return .keyword4 }
        return nil
    }
}
