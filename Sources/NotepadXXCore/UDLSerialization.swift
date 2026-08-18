import Foundation

/// Reads and writes Notepad++ User Defined Language XML.
///
/// The format is deliberately the real one rather than something of our own, so
/// the existing community UDL collection loads without conversion. Notepad++
/// stores keyword groups as whitespace-separated lists inside `<Keywords>`
/// elements named Keywords1..8, and comment/delimiter tokens inside a
/// `Comments` keyword list using `00`-prefixed markers.
public enum UDLSerialization {

    public enum UDLError: Error, Equatable {
        case malformed(String)
        case noLanguageFound
    }

    // MARK: - Import

    public static func importLanguages(from xml: String) throws -> [LanguageDefinition] {
        let parser = UDLParser()
        guard let languages = parser.parse(xml) else {
            throw UDLError.malformed("could not parse UDL XML")
        }
        guard !languages.isEmpty else { throw UDLError.noLanguageFound }
        return languages
    }

    public static func importLanguages(from url: URL) throws -> [LanguageDefinition] {
        let xml = try String(contentsOf: url, encoding: .utf8)
        return try importLanguages(from: xml)
    }

    // MARK: - Export

    public static func exportXML(for languages: [LanguageDefinition]) -> String {
        var output = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n"
        for language in languages {
            output += "    <UserLang name=\"\(escape(language.name))\""
            output += " ext=\"\(escape(language.fileExtensions.joined(separator: " ")))\""
            output += " udlVersion=\"2.1\">\n"
            output += "        <Settings>\n"
            output += "            <Global caseIgnored=\"\(language.isCaseSensitive ? "no" : "yes")\" />\n"
            output += "        </Settings>\n"
            output += "        <KeywordLists>\n"
            output += keywordList("Comments", commentTokens(for: language))
            output += keywordList("Keywords1", language.keywords1.sorted().joined(separator: " "))
            output += keywordList("Keywords2", language.keywords2.sorted().joined(separator: " "))
            output += keywordList("Keywords3", language.keywords3.sorted().joined(separator: " "))
            output += keywordList("Keywords4", language.keywords4.sorted().joined(separator: " "))
            output += keywordList("Operators1", language.operatorCharacterString.map(String.init).joined(separator: " "))
            output += keywordList("Delimiters", delimiterSpec(for: language))
            output += "        </KeywordLists>\n"
            output += "    </UserLang>\n"
        }
        output += "</NotepadPlus>\n"
        return output
    }

    /// Notepad++ encodes comment tokens with positional markers: `00` opens a
    /// block comment, `01` closes it, `02` starts a line comment.
    static func commentTokens(for language: LanguageDefinition) -> String {
        var parts: [String] = []
        if let open = language.blockCommentOpen { parts.append("00\(open)") }
        if let close = language.blockCommentClose { parts.append("01\(close)") }
        for token in language.lineCommentTokens { parts.append("02\(token)") }
        return parts.joined(separator: " ")
    }

    static func delimiterSpec(for language: LanguageDefinition) -> String {
        language.stringDelimiters.enumerated().map { index, quote in
            "0\(index)\(quote)"
        }.joined(separator: " ")
    }

    private static func keywordList(_ name: String, _ content: String) -> String {
        "            <Keywords name=\"\(name)\">\(escape(content))</Keywords>\n"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// XMLParser-based reader for the UserLang format.
final class UDLParser: NSObject, XMLParserDelegate {
    private var languages: [LanguageDefinition] = []
    private var current: LanguageDefinition?
    private var currentKeywordName: String?
    private var buffer = ""

    func parse(_ xml: String) -> [LanguageDefinition]? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return languages
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "UserLang":
            let name = attributeDict["name"] ?? "Untitled"
            let extensions = (attributeDict["ext"] ?? "")
                .split(whereSeparator: { $0 == " " || $0 == ";" })
                .map { $0.lowercased() }
            current = LanguageDefinition(name: name, fileExtensions: extensions)
        case "Global":
            // caseIgnored="yes" means the language is case-insensitive.
            current?.isCaseSensitive = (attributeDict["caseIgnored"] ?? "no") != "yes"
        case "Keywords":
            currentKeywordName = attributeDict["name"]
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "Keywords":
            applyKeywords(name: currentKeywordName, content: buffer)
            currentKeywordName = nil
            buffer = ""
        case "UserLang":
            if let current { languages.append(current) }
            current = nil
        default:
            break
        }
    }

    private func applyKeywords(name: String?, content: String) {
        guard var language = current, let name else { return }
        let tokens = content.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.isEmpty }

        switch name {
        case "Keywords1": language.keywords1 = Set(tokens)
        case "Keywords2": language.keywords2 = Set(tokens)
        case "Keywords3": language.keywords3 = Set(tokens)
        case "Keywords4": language.keywords4 = Set(tokens)
        case "Comments":
            // Positional markers: 00 opens a block, 01 closes it, 02 starts a line.
            for token in tokens {
                guard token.count > 2 else { continue }
                let marker = String(token.prefix(2))
                let value = String(token.dropFirst(2))
                switch marker {
                case "00": language.blockCommentOpen = value
                case "01": language.blockCommentClose = value
                case "02": language.lineCommentTokens.append(value)
                default: break
                }
            }
        case "Operators1":
            let characters = tokens.joined()
            if !characters.isEmpty { language.operatorCharacterString = characters }
        default:
            break
        }
        current = language
    }
}
