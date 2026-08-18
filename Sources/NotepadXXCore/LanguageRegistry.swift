import Foundation

/// Built-in language definitions plus user-defined ones, and the logic that
/// picks a language for a document.
public final class LanguageRegistry: @unchecked Sendable {
    public static let shared = LanguageRegistry()

    private var languages: [LanguageDefinition]

    public init(languages: [LanguageDefinition]? = nil) {
        self.languages = languages ?? BuiltInLanguages.all
    }

    public var all: [LanguageDefinition] {
        languages.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    public func language(named name: String) -> LanguageDefinition? {
        languages.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Registers or replaces a definition — how a User Defined Language enters
    /// the system, on equal footing with the built-ins.
    public func register(_ language: LanguageDefinition) {
        if let index = languages.firstIndex(where: { $0.name.caseInsensitiveCompare(language.name) == .orderedSame }) {
            languages[index] = language
        } else {
            languages.append(language)
        }
    }

    public func remove(named name: String) {
        languages.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Picks a language by file extension, falling back to a `#!` line.
    /// Extension wins, because a shebang in a `.txt` file is usually incidental.
    public func detect(fileName: String?, firstLine: String? = nil) -> LanguageDefinition? {
        if let fileName {
            let ext = (fileName as NSString).pathExtension.lowercased()
            if !ext.isEmpty,
               let match = languages.first(where: { $0.fileExtensions.contains(ext) }) {
                return match
            }
            // Extension-less names like "Makefile" are matched whole.
            let base = (fileName as NSString).lastPathComponent.lowercased()
            if let match = languages.first(where: { $0.fileExtensions.contains(base) }) {
                return match
            }
        }
        guard let firstLine, firstLine.hasPrefix("#!") else { return nil }
        let lowered = firstLine.lowercased()
        return languages.first { definition in
            definition.shebangs.contains { lowered.contains($0) }
        }
    }
}

/// The shipped language set.
///
/// Notepad++ ships ~95 lexers. These are defined as data, so extending coverage
/// is adding entries here rather than writing code — and a user can author the
/// same shape through the UDL editor.
public enum BuiltInLanguages {
    public static let all: [LanguageDefinition] = [
        c, cpp, csharp, java, javascript, typescript, swift, python, ruby, php,
        go, rust, shell, sql, html, xml, css, json, yaml, markdown, ini, batch, lua, perl,
    ] + additional + remaining

    private static let cFamilyOperators = "+-*/%=<>!&|^~?:;,.()[]{}"

    public static let c = LanguageDefinition(
        name: "C", fileExtensions: ["c", "h"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"], preprocessorPrefixes: ["#"],
        operatorCharacters: cFamilyOperators,
        keywords1: ["auto", "break", "case", "const", "continue", "default", "do", "else", "enum",
                    "extern", "for", "goto", "if", "register", "return", "sizeof", "static",
                    "struct", "switch", "typedef", "union", "volatile", "while"],
        keywords2: ["char", "double", "float", "int", "long", "short", "signed", "unsigned", "void"]
    )

    public static let cpp = LanguageDefinition(
        name: "C++", fileExtensions: ["cpp", "cxx", "cc", "hpp", "hxx", "hh"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"], preprocessorPrefixes: ["#"],
        operatorCharacters: cFamilyOperators,
        keywords1: ["class", "namespace", "template", "typename", "public", "private", "protected",
                    "virtual", "override", "new", "delete", "try", "catch", "throw", "using",
                    "constexpr", "nullptr", "auto", "return", "if", "else", "for", "while", "switch",
                    "case", "break", "continue", "const", "static", "struct", "enum"],
        keywords2: ["bool", "char", "double", "float", "int", "long", "short", "signed",
                    "unsigned", "void", "wchar_t", "size_t"]
    )

    public static let csharp = LanguageDefinition(
        name: "C#", fileExtensions: ["cs"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"], preprocessorPrefixes: ["#"],
        keywords1: ["abstract", "as", "base", "break", "case", "catch", "class", "const", "continue",
                    "default", "delegate", "do", "else", "enum", "event", "finally", "for", "foreach",
                    "get", "if", "interface", "internal", "is", "lock", "namespace", "new", "null",
                    "override", "params", "private", "protected", "public", "readonly", "ref",
                    "return", "sealed", "set", "static", "struct", "switch", "this", "throw", "try",
                    "typeof", "using", "var", "virtual", "while", "yield"],
        keywords2: ["bool", "byte", "char", "decimal", "double", "float", "int", "long", "object",
                    "sbyte", "short", "string", "uint", "ulong", "ushort", "void"]
    )

    public static let java = LanguageDefinition(
        name: "Java", fileExtensions: ["java"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["abstract", "assert", "break", "case", "catch", "class", "continue", "default",
                    "do", "else", "enum", "extends", "final", "finally", "for", "if", "implements",
                    "import", "instanceof", "interface", "native", "new", "package", "private",
                    "protected", "public", "return", "static", "super", "switch", "synchronized",
                    "this", "throw", "throws", "transient", "try", "volatile", "while"],
        keywords2: ["boolean", "byte", "char", "double", "float", "int", "long", "short", "void", "String"]
    )

    public static let javascript = LanguageDefinition(
        name: "JavaScript", fileExtensions: ["js", "mjs", "cjs", "jsx"],
        shebangs: ["node"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'", "`"],
        keywords1: ["async", "await", "break", "case", "catch", "class", "const", "continue",
                    "debugger", "default", "delete", "do", "else", "export", "extends", "finally",
                    "for", "from", "function", "if", "import", "in", "instanceof", "let", "new",
                    "of", "return", "static", "super", "switch", "this", "throw", "try", "typeof",
                    "var", "void", "while", "with", "yield"],
        keywords2: ["true", "false", "null", "undefined", "NaN", "Infinity"],
        keywords3: ["console", "document", "window", "Object", "Array", "String", "Number",
                    "Promise", "JSON", "Math", "Map", "Set"]
    )

    public static let typescript = LanguageDefinition(
        name: "TypeScript", fileExtensions: ["ts", "tsx"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'", "`"],
        keywords1: ["abstract", "async", "await", "break", "case", "catch", "class", "const",
                    "continue", "declare", "default", "delete", "do", "else", "enum", "export",
                    "extends", "finally", "for", "from", "function", "if", "implements", "import",
                    "in", "instanceof", "interface", "let", "namespace", "new", "of", "private",
                    "protected", "public", "readonly", "return", "static", "super", "switch",
                    "this", "throw", "try", "type", "typeof", "var", "while", "yield"],
        keywords2: ["any", "boolean", "never", "number", "object", "string", "symbol", "unknown",
                    "void", "true", "false", "null", "undefined"]
    )

    public static let swift = LanguageDefinition(
        name: "Swift", fileExtensions: ["swift"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        blockCommentsNest: true,
        stringDelimiters: ["\""],
        keywords1: ["associatedtype", "await", "async", "break", "case", "catch", "class",
                    "continue", "default", "defer", "deinit", "do", "else", "enum", "extension",
                    "fallthrough", "fileprivate", "for", "func", "guard", "if", "import", "in",
                    "init", "inout", "internal", "let", "open", "operator", "private", "protocol",
                    "public", "repeat", "rethrows", "return", "self", "static", "struct", "subscript",
                    "super", "switch", "throw", "throws", "try", "typealias", "var", "where", "while"],
        keywords2: ["Any", "Bool", "Character", "Double", "Float", "Int", "String", "UInt",
                    "Array", "Dictionary", "Set", "Optional", "nil", "true", "false"]
    )

    public static let python = LanguageDefinition(
        name: "Python", fileExtensions: ["py", "pyw"], shebangs: ["python"],
        lineCommentTokens: ["#"],
        stringDelimiters: ["\"\"\"", "'''", "\"", "'"],
        keywords1: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def",
                    "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
                    "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
                    "return", "try", "while", "with", "yield"],
        keywords2: ["True", "False", "None", "self", "cls"],
        keywords3: ["print", "len", "range", "dict", "list", "set", "tuple", "int", "str", "float",
                    "bool", "open", "enumerate", "zip", "map", "filter", "sorted", "sum"],
        foldOpen: [":"], foldClose: []
    )

    public static let ruby = LanguageDefinition(
        name: "Ruby", fileExtensions: ["rb"], shebangs: ["ruby"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        keywords1: ["alias", "and", "begin", "break", "case", "class", "def", "do", "else", "elsif",
                    "end", "ensure", "for", "if", "in", "module", "next", "nil", "not", "or",
                    "redo", "rescue", "retry", "return", "self", "super", "then", "unless",
                    "until", "when", "while", "yield"],
        keywords2: ["true", "false", "nil"],
        foldOpen: ["def", "do", "class"], foldClose: ["end"]
    )

    public static let php = LanguageDefinition(
        name: "PHP", fileExtensions: ["php", "phtml"],
        lineCommentTokens: ["//", "#"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["abstract", "and", "array", "as", "break", "callable", "case", "catch", "class",
                    "clone", "const", "continue", "declare", "default", "do", "echo", "else",
                    "elseif", "empty", "endfor", "endforeach", "endif", "endswitch", "endwhile",
                    "extends", "final", "finally", "fn", "for", "foreach", "function", "global",
                    "if", "implements", "include", "instanceof", "interface", "isset", "list",
                    "namespace", "new", "or", "print", "private", "protected", "public", "require",
                    "return", "static", "switch", "throw", "trait", "try", "unset", "use", "var",
                    "while", "yield"],
        keywords2: ["bool", "float", "int", "string", "void", "null", "true", "false"]
    )

    public static let go = LanguageDefinition(
        name: "Go", fileExtensions: ["go"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "`", "'"],
        keywords1: ["break", "case", "chan", "const", "continue", "default", "defer", "else",
                    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
                    "package", "range", "return", "select", "struct", "switch", "type", "var"],
        keywords2: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64",
                    "int", "int8", "int16", "int32", "int64", "rune", "string", "uint",
                    "uintptr", "nil", "true", "false"]
    )

    public static let rust = LanguageDefinition(
        name: "Rust", fileExtensions: ["rs"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        blockCommentsNest: true, stringDelimiters: ["\"", "'"],
        keywords1: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
                    "enum", "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match",
                    "mod", "move", "mut", "pub", "ref", "return", "self", "static", "struct",
                    "super", "trait", "type", "unsafe", "use", "where", "while"],
        keywords2: ["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize",
                    "str", "u8", "u16", "u32", "u64", "u128", "usize", "String", "Vec",
                    "Option", "Result", "true", "false"]
    )

    public static let shell = LanguageDefinition(
        name: "Shell", fileExtensions: ["sh", "bash", "zsh"], shebangs: ["sh", "bash", "zsh"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        keywords1: ["if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until",
                    "do", "done", "function", "in", "select", "return", "break", "continue",
                    "local", "export", "readonly", "declare", "unset", "shift", "source"],
        keywords3: ["echo", "cd", "pwd", "ls", "grep", "sed", "awk", "cat", "printf", "read",
                    "test", "exit", "trap", "eval", "exec"],
        foldOpen: ["then", "do"], foldClose: ["fi", "done"]
    )

    public static let sql = LanguageDefinition(
        name: "SQL", fileExtensions: ["sql"],
        lineCommentTokens: ["--"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["'", "\""], isCaseSensitive: false,
        keywords1: ["select", "from", "where", "insert", "into", "values", "update", "set",
                    "delete", "create", "table", "alter", "drop", "index", "view", "join",
                    "inner", "left", "right", "outer", "on", "group", "by", "order", "having",
                    "union", "distinct", "as", "and", "or", "not", "null", "in", "between",
                    "like", "limit", "offset", "primary", "key", "foreign", "references"],
        keywords2: ["int", "integer", "varchar", "char", "text", "date", "datetime", "timestamp",
                    "boolean", "decimal", "numeric", "float", "double", "blob"]
    )

    public static let html = LanguageDefinition(
        name: "HTML", fileExtensions: ["html", "htm", "xhtml"],
        blockCommentOpen: "<!--", blockCommentClose: "-->",
        stringDelimiters: ["\"", "'"], escapeCharacter: nil,
        operatorCharacters: "<>/=", isCaseSensitive: false,
        keywords1: ["html", "head", "body", "div", "span", "a", "p", "img", "ul", "ol", "li",
                    "table", "tr", "td", "th", "form", "input", "button", "script", "style",
                    "link", "meta", "title", "header", "footer", "nav", "section", "article",
                    "h1", "h2", "h3", "h4", "h5", "h6", "br", "hr"],
        keywords2: ["class", "id", "href", "src", "alt", "type", "value", "name", "style",
                    "width", "height", "rel", "target"],
        foldOpen: ["<"], foldClose: [">"]
    )

    public static let xml = LanguageDefinition(
        name: "XML", fileExtensions: ["xml", "xsd", "xsl", "plist", "svg"],
        blockCommentOpen: "<!--", blockCommentClose: "-->",
        stringDelimiters: ["\"", "'"], escapeCharacter: nil,
        operatorCharacters: "<>/=?", isCaseSensitive: false,
        foldOpen: ["<"], foldClose: [">"]
    )

    public static let css = LanguageDefinition(
        name: "CSS", fileExtensions: ["css", "scss", "less"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["color", "background", "background-color", "margin", "padding", "border",
                    "font", "font-size", "font-family", "font-weight", "display", "position",
                    "top", "right", "bottom", "left", "width", "height", "float", "clear",
                    "overflow", "z-index", "opacity", "flex", "grid", "gap", "align-items",
                    "justify-content", "text-align", "line-height"],
        keywords2: ["absolute", "relative", "fixed", "sticky", "block", "inline", "inline-block",
                    "none", "auto", "hidden", "visible", "bold", "italic", "center", "solid"]
    )

    public static let json = LanguageDefinition(
        name: "JSON", fileExtensions: ["json", "jsonc"],
        lineCommentTokens: ["//"], stringDelimiters: ["\""],
        operatorCharacters: ":,{}[]",
        keywords1: ["true", "false", "null"],
        foldOpen: ["{", "["], foldClose: ["}", "]"]
    )

    public static let yaml = LanguageDefinition(
        name: "YAML", fileExtensions: ["yml", "yaml"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        operatorCharacters: ":-[]{},",
        keywords1: ["true", "false", "null", "yes", "no", "on", "off"],
        foldOpen: [], foldClose: []
    )

    public static let markdown = LanguageDefinition(
        name: "Markdown", fileExtensions: ["md", "markdown"],
        stringDelimiters: ["`"], escapeCharacter: "\\",
        operatorCharacters: "*_#>-[]()!",
        foldOpen: [], foldClose: []
    )

    public static let ini = LanguageDefinition(
        name: "INI", fileExtensions: ["ini", "cfg", "conf"],
        lineCommentTokens: [";", "#"], stringDelimiters: ["\"", "'"],
        operatorCharacters: "=[]",
        foldOpen: [], foldClose: []
    )

    public static let batch = LanguageDefinition(
        name: "Batch", fileExtensions: ["bat", "cmd"],
        lineCommentTokens: ["rem", "::"], stringDelimiters: ["\""],
        isCaseSensitive: false,
        keywords1: ["if", "else", "for", "in", "do", "goto", "call", "exit", "set", "echo",
                    "setlocal", "endlocal", "shift", "pause"],
        foldOpen: [], foldClose: []
    )

    public static let lua = LanguageDefinition(
        name: "Lua", fileExtensions: ["lua"], shebangs: ["lua"],
        lineCommentTokens: ["--"], blockCommentOpen: "--[[", blockCommentClose: "]]",
        stringDelimiters: ["\"", "'"],
        keywords1: ["and", "break", "do", "else", "elseif", "end", "false", "for", "function",
                    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
                    "true", "until", "while"],
        keywords3: ["print", "pairs", "ipairs", "require", "tostring", "tonumber", "type", "table",
                    "string", "math", "io", "os"],
        foldOpen: ["function", "then", "do"], foldClose: ["end"]
    )

    public static let perl = LanguageDefinition(
        name: "Perl", fileExtensions: ["pl", "pm"], shebangs: ["perl"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        keywords1: ["my", "our", "local", "sub", "if", "elsif", "else", "unless", "while", "until",
                    "for", "foreach", "do", "last", "next", "redo", "return", "use", "require",
                    "package", "bless", "ref", "defined", "undef", "eval"]
    )
}
