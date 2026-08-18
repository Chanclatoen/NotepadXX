import Foundation

public struct CompletionItem: Equatable, Sendable {
    public enum Kind: String, Sendable { case word, keyword, function, path }
    public let text: String
    public let kind: Kind
    /// Shown beside the name, e.g. a function signature for a call tip.
    public let detail: String?

    public init(text: String, kind: Kind, detail: String? = nil) {
        self.text = text
        self.kind = kind
        self.detail = detail
    }
}

/// Word, keyword, function and path completion, matching the four sources
/// Notepad++ offers in its Auto-Completion preferences.
public enum AutoCompletion {

    /// The identifier immediately before `location`, which is what gets completed.
    public static func currentPrefix(in text: String, at location: Int) -> String {
        let content = text as NSString
        guard location > 0, location <= content.length else { return "" }
        var start = location
        while start > 0 {
            let character = content.substring(with: NSRange(location: start - 1, length: 1))
            guard let scalar = character.unicodeScalars.first,
                  CharacterSet.alphanumerics.contains(scalar) || character == "_" else { break }
            start -= 1
        }
        return content.substring(with: NSRange(location: start, length: location - start))
    }

    /// Every distinct word in the buffer, for word completion. The word being
    /// typed is excluded so it does not suggest itself.
    public static func words(in text: String, minimumLength: Int = 3) -> Set<String> {
        var result: Set<String> = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                if current.count >= minimumLength { result.insert(current) }
                current = ""
            }
        }
        if current.count >= minimumLength { result.insert(current) }
        return result
    }

    /// Suggestions for the prefix at `location`.
    ///
    /// Ordering is deliberate: keywords first (they are the smaller, more
    /// certain set), then buffer words. Matching is case-insensitive but exact
    /// case is preferred, so typing `wid` ranks `widget` above `Widget`.
    public static func suggestions(
        in text: String, at location: Int, language: LanguageDefinition?,
        includeWords: Bool = true, includeKeywords: Bool = true, maximum: Int = 50
    ) -> [CompletionItem] {
        let prefix = currentPrefix(in: text, at: location)
        guard !prefix.isEmpty else { return [] }
        let lowered = prefix.lowercased()

        var keywords: [String] = []
        if includeKeywords, let language {
            let all = language.keywords1.union(language.keywords2)
                .union(language.keywords3).union(language.keywords4)
            keywords = all.filter { $0.lowercased().hasPrefix(lowered) && $0 != prefix }
        }

        var bufferWords: [String] = []
        if includeWords {
            bufferWords = words(in: text)
                .filter { $0.lowercased().hasPrefix(lowered) && $0 != prefix }
                .filter { word in !keywords.contains(word) }
        }

        func rank(_ candidates: [String]) -> [String] {
            candidates.sorted { a, b in
                let aExact = a.hasPrefix(prefix), bExact = b.hasPrefix(prefix)
                if aExact != bExact { return aExact }
                if a.count != b.count { return a.count < b.count }
                return a < b
            }
        }

        let items = rank(keywords).map { CompletionItem(text: $0, kind: .keyword) }
            + rank(bufferWords).map { CompletionItem(text: $0, kind: .word) }
        return Array(items.prefix(maximum))
    }

    /// Path completion for the fragment before `location`.
    /// Triggered by a `/` or `~` in the token, as Notepad++ does.
    public static func pathSuggestions(in text: String, at location: Int, maximum: Int = 50) -> [CompletionItem] {
        let content = text as NSString
        guard location > 0, location <= content.length else { return [] }
        var start = location
        while start > 0 {
            let character = content.substring(with: NSRange(location: start - 1, length: 1))
            if character == " " || character == "\t" || character == "\n" || character == "\"" { break }
            start -= 1
        }
        var fragment = content.substring(with: NSRange(location: start, length: location - start))
        guard fragment.contains("/") || fragment.hasPrefix("~") else { return [] }
        if fragment.hasPrefix("~") {
            fragment = NSString(string: fragment).expandingTildeInPath
        }

        let url = URL(fileURLWithPath: fragment)
        let directory = fragment.hasSuffix("/") ? url : url.deletingLastPathComponent()
        let partial = fragment.hasSuffix("/") ? "" : url.lastPathComponent

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { partial.isEmpty || $0.lastPathComponent.lowercased().hasPrefix(partial.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(maximum)
            .map { candidate in
                let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return CompletionItem(
                    text: candidate.lastPathComponent + (isDirectory ? "/" : ""),
                    kind: .path,
                    detail: candidate.deletingLastPathComponent().path
                )
            }
    }

    /// Call tips: function signatures matching the name before an open paren.
    public static func callTip(
        for functionName: String, in text: String, languageName: String?
    ) -> String? {
        let symbols = FunctionListExtractor.symbols(in: text, languageName: languageName)
        guard symbols.contains(where: { $0.name == functionName }) else { return nil }
        let (lines, _) = LineOperations.split(text)
        // The declaration line is the tip, trimmed of leading indentation.
        for line in lines where line.contains(functionName) && line.contains("(") {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
