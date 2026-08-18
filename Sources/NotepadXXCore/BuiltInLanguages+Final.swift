import Foundation

/// The remaining shipped lexers, bringing coverage in line with Notepad++.
extension BuiltInLanguages {

    public static let awk = LanguageDefinition(
        name: "AWK", fileExtensions: ["awk"], shebangs: ["awk", "gawk"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        keywords1: ["BEGIN", "END", "if", "else", "while", "for", "do", "break", "continue",
                    "next", "exit", "return", "function", "delete", "in", "getline"],
        keywords2: ["NR", "NF", "FS", "OFS", "RS", "ORS", "FILENAME"],
        keywords3: ["print", "printf", "split", "substr", "length", "index", "match", "gsub",
                    "sub", "sprintf", "tolower", "toupper", "system"]
    )

    public static let sed = LanguageDefinition(
        name: "sed", fileExtensions: ["sed"], shebangs: ["sed"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        operatorCharacters: "/;,{}", foldOpen: [], foldClose: []
    )

    public static let cs = LanguageDefinition(
        name: "Clojure", fileExtensions: ["cljs", "cljc", "edn"],
        lineCommentTokens: [";"], stringDelimiters: ["\""],
        operatorCharacters: "()[]{}'`~@^",
        keywords1: ["def", "defn", "defmacro", "defrecord", "defprotocol", "let", "fn", "if",
                    "when", "cond", "case", "loop", "recur", "do", "ns", "require", "import"],
        keywords2: ["nil", "true", "false"],
        foldOpen: ["("], foldClose: [")"]
    )

    public static let fsharp = LanguageDefinition(
        name: "F#", fileExtensions: ["fs", "fsi", "fsx"],
        lineCommentTokens: ["//"], blockCommentOpen: "(*", blockCommentClose: "*)",
        stringDelimiters: ["\""],
        keywords1: ["let", "mutable", "type", "module", "namespace", "open", "member", "override",
                    "match", "with", "when", "if", "then", "else", "for", "while", "do", "rec",
                    "and", "function", "fun", "try", "finally", "yield", "return", "inherit"],
        keywords2: ["int", "float", "string", "bool", "char", "unit", "list", "array", "option",
                    "Some", "None", "true", "false"]
    )

    public static let julia = LanguageDefinition(
        name: "Julia", fileExtensions: ["jl"], shebangs: ["julia"],
        lineCommentTokens: ["#"], blockCommentOpen: "#=", blockCommentClose: "=#",
        blockCommentsNest: true, stringDelimiters: ["\"", "'"],
        keywords1: ["function", "end", "if", "elseif", "else", "for", "while", "begin", "let",
                    "do", "try", "catch", "finally", "return", "break", "continue", "module",
                    "using", "import", "export", "struct", "mutable", "abstract", "macro"],
        keywords2: ["Int", "Int64", "Float64", "Bool", "String", "Char", "Array", "Dict",
                    "Vector", "Matrix", "Nothing", "true", "false", "nothing"],
        foldOpen: ["function", "if", "for", "while", "begin"], foldClose: ["end"]
    )

    public static let nim = LanguageDefinition(
        name: "Nim", fileExtensions: ["nim", "nims"],
        lineCommentTokens: ["#"], blockCommentOpen: "#[", blockCommentClose: "]#",
        stringDelimiters: ["\"", "'"],
        keywords1: ["proc", "func", "method", "iterator", "template", "macro", "type", "var",
                    "let", "const", "if", "elif", "else", "case", "of", "while", "for", "block",
                    "return", "yield", "discard", "import", "export", "include", "when", "try",
                    "except", "finally", "raise", "object", "ref", "ptr"],
        keywords2: ["int", "float", "string", "char", "bool", "seq", "array", "nil",
                    "true", "false"]
    )

    public static let crystal = LanguageDefinition(
        name: "Crystal", fileExtensions: ["cr"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        keywords1: ["def", "class", "module", "struct", "enum", "lib", "fun", "macro", "if",
                    "elsif", "else", "unless", "case", "when", "while", "until", "begin",
                    "rescue", "ensure", "end", "return", "yield", "require", "include", "extend"],
        keywords2: ["Int32", "Int64", "Float64", "String", "Bool", "Char", "Array", "Hash",
                    "Nil", "true", "false", "nil"],
        foldOpen: ["def", "class", "do"], foldClose: ["end"]
    )

    public static let vala = LanguageDefinition(
        name: "Vala", fileExtensions: ["vala", "vapi"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["namespace", "class", "interface", "struct", "enum", "public", "private",
                    "protected", "internal", "static", "abstract", "virtual", "override", "if",
                    "else", "for", "foreach", "while", "do", "switch", "case", "return", "try",
                    "catch", "finally", "throw", "using", "construct", "signal", "delegate"],
        keywords2: ["void", "bool", "char", "int", "uint", "long", "double", "string", "var",
                    "null", "true", "false"]
    )

    public static let racket = LanguageDefinition(
        name: "Racket", fileExtensions: ["rkt"],
        lineCommentTokens: [";"], blockCommentOpen: "#|", blockCommentClose: "|#",
        stringDelimiters: ["\""], operatorCharacters: "()[]'`,",
        keywords1: ["define", "lambda", "let", "let*", "letrec", "if", "cond", "else", "case",
                    "when", "unless", "begin", "require", "provide", "struct", "module"],
        foldOpen: ["("], foldClose: [")"]
    )

    public static let prolog = LanguageDefinition(
        name: "Prolog", fileExtensions: ["pro", "pl2"],
        lineCommentTokens: ["%"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["'", "\""],
        keywords1: ["is", "not", "fail", "true", "false", "assert", "asserta", "assertz",
                    "retract", "findall", "bagof", "setof", "forall", "dynamic", "discontiguous"],
        foldOpen: [], foldClose: []
    )

    public static let abap = LanguageDefinition(
        name: "ABAP", fileExtensions: ["abap"],
        lineCommentTokens: ["*", "\""], stringDelimiters: ["'"], isCaseSensitive: false,
        keywords1: ["REPORT", "DATA", "TYPES", "CONSTANTS", "FORM", "ENDFORM", "IF", "ELSE",
                    "ENDIF", "LOOP", "ENDLOOP", "DO", "ENDDO", "WHILE", "ENDWHILE", "CASE",
                    "WHEN", "ENDCASE", "SELECT", "ENDSELECT", "WRITE", "PERFORM", "CALL"],
        foldOpen: [], foldClose: []
    )

    public static let rexx = LanguageDefinition(
        name: "REXX", fileExtensions: ["rex", "rexx"],
        lineCommentTokens: [], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["'", "\""], isCaseSensitive: false,
        keywords1: ["do", "end", "if", "then", "else", "select", "when", "otherwise", "call",
                    "return", "exit", "parse", "say", "iterate", "leave", "signal", "procedure"],
        foldOpen: ["do"], foldClose: ["end"]
    )

    public static let haxe = LanguageDefinition(
        name: "Haxe", fileExtensions: ["hx"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["package", "import", "class", "interface", "enum", "abstract", "typedef",
                    "function", "var", "static", "public", "private", "override", "if", "else",
                    "for", "while", "do", "switch", "case", "return", "try", "catch", "throw",
                    "new", "extends", "implements", "inline", "macro"],
        keywords2: ["Int", "Float", "Bool", "String", "Array", "Map", "Dynamic", "Void",
                    "null", "true", "false"]
    )

    public static let purebasic = LanguageDefinition(
        name: "PureBasic", fileExtensions: ["pb", "pbi"],
        lineCommentTokens: [";"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["Procedure", "EndProcedure", "If", "Else", "ElseIf", "EndIf", "For", "Next",
                    "While", "Wend", "Repeat", "Until", "Select", "Case", "EndSelect",
                    "Structure", "EndStructure", "Global", "Protected", "Define", "Macro"],
        foldOpen: [], foldClose: []
    )

    public static let inno = LanguageDefinition(
        name: "Inno Setup", fileExtensions: ["iss"],
        lineCommentTokens: [";"], stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["Setup", "Files", "Icons", "Tasks", "Registry", "Run", "Code", "Languages",
                    "Components", "Dirs", "InstallDelete", "UninstallDelete", "Messages"],
        foldOpen: [], foldClose: []
    )

    public static let caml = LanguageDefinition(
        name: "Standard ML", fileExtensions: ["sml", "sig"],
        blockCommentOpen: "(*", blockCommentClose: "*)", blockCommentsNest: true,
        stringDelimiters: ["\""],
        keywords1: ["val", "fun", "fn", "let", "in", "end", "if", "then", "else", "case", "of",
                    "datatype", "type", "structure", "signature", "functor", "local", "open",
                    "handle", "raise", "while", "do", "andalso", "orelse"],
        keywords2: ["int", "real", "bool", "char", "string", "unit", "list", "option",
                    "true", "false", "NONE", "SOME"],
        foldOpen: ["let", "struct"], foldClose: ["end"]
    )

    public static let blitz = LanguageDefinition(
        name: "BlitzBasic", fileExtensions: ["bb"],
        lineCommentTokens: [";"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["Function", "End", "If", "Then", "Else", "EndIf", "For", "Next", "While",
                    "Wend", "Repeat", "Until", "Select", "Case", "Type", "Field", "Global",
                    "Local", "Const", "Return", "Goto", "Gosub"],
        foldOpen: [], foldClose: []
    )

    public static let spice = LanguageDefinition(
        name: "SPICE", fileExtensions: ["cir", "sp"],
        lineCommentTokens: ["*", ";"], stringDelimiters: ["'"], isCaseSensitive: false,
        keywords1: [".model", ".subckt", ".ends", ".tran", ".dc", ".ac", ".print", ".plot",
                    ".option", ".include", ".lib", ".end", ".param", ".meas"],
        foldOpen: [], foldClose: []
    )

    public static let mmixal = LanguageDefinition(
        name: "MMIXAL", fileExtensions: ["mms"],
        lineCommentTokens: ["%"], stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["IS", "LOC", "GREG", "BYTE", "WYDE", "TETRA", "OCTA", "SET", "ADD", "SUB",
                    "MUL", "DIV", "JMP", "PUSHJ", "POP", "TRAP", "LDA", "LDO", "STO"],
        foldOpen: [], foldClose: []
    )

    public static let txt2tags = LanguageDefinition(
        name: "txt2tags", fileExtensions: ["t2t"],
        lineCommentTokens: ["%"], stringDelimiters: [],
        operatorCharacters: "=-*/_+[]", foldOpen: [], foldClose: []
    )

    public static let osascript = LanguageDefinition(
        name: "AppleScript", fileExtensions: ["applescript", "scpt"],
        lineCommentTokens: ["--", "#"], blockCommentOpen: "(*", blockCommentClose: "*)",
        stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["tell", "end", "if", "then", "else", "repeat", "with", "without", "set",
                    "to", "of", "on", "return", "try", "error", "considering", "ignoring",
                    "script", "property", "global", "local", "my", "its"],
        keywords2: ["application", "text", "integer", "real", "boolean", "list", "record",
                    "true", "false", "missing value"],
        foldOpen: ["tell", "repeat"], foldClose: ["end"]
    )

    public static let plist = LanguageDefinition(
        name: "Swift Package Manifest", fileExtensions: ["resolved"],
        stringDelimiters: ["\""], operatorCharacters: "{}[],:",
        keywords1: ["true", "false", "null"], foldOpen: ["{"], foldClose: ["}"]
    )

    /// The final tranche, appended to the rest.
    public static let remaining: [LanguageDefinition] = [
        awk, sed, cs, fsharp, julia, nim, crystal, vala, racket, prolog, abap, rexx,
        haxe, purebasic, inno, caml, blitz, spice, mmixal, txt2tags, osascript, plist,
    ]
}
