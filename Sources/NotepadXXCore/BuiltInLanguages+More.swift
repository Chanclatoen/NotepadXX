import Foundation

/// The rest of the shipped language set.
///
/// Notepad++ ships ~95 lexers. These are data, not code: each entry is a
/// keyword/delimiter description the shared `Lexer` drives, so extending
/// coverage never means writing a parser.
extension BuiltInLanguages {

    static let cLike = "+-*/%=<>!&|^~?:;,.()[]{}"

    // MARK: - C family and systems

    public static let objectiveC = LanguageDefinition(
        name: "Objective-C", fileExtensions: ["m", "mm"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"], preprocessorPrefixes: ["#"],
        keywords1: ["@interface", "@implementation", "@end", "@property", "@synthesize", "@class",
                    "@protocol", "@selector", "if", "else", "for", "while", "switch", "case",
                    "break", "continue", "return", "typedef", "struct", "enum", "static", "const"],
        keywords2: ["id", "BOOL", "NSString", "NSArray", "NSDictionary", "NSObject", "IBOutlet",
                    "IBAction", "instancetype", "nil", "YES", "NO", "void", "int", "float", "double"]
    )

    public static let csharpScript = LanguageDefinition(
        name: "C# Script", fileExtensions: ["csx"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        keywords1: BuiltInLanguages.csharp.keywords1, keywords2: BuiltInLanguages.csharp.keywords2
    )

    public static let d = LanguageDefinition(
        name: "D", fileExtensions: ["d"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        keywords1: ["module", "import", "class", "struct", "interface", "template", "mixin",
                    "auto", "immutable", "const", "if", "else", "foreach", "while", "return",
                    "switch", "case", "public", "private", "protected", "override", "static"],
        keywords2: ["bool", "byte", "char", "int", "long", "float", "double", "real", "string",
                    "void", "size_t", "true", "false", "null"]
    )

    public static let rustScript = LanguageDefinition(
        name: "Zig", fileExtensions: ["zig"],
        lineCommentTokens: ["//"], stringDelimiters: ["\"", "'"],
        keywords1: ["const", "var", "fn", "pub", "return", "if", "else", "while", "for", "switch",
                    "struct", "enum", "union", "defer", "errdefer", "try", "catch", "comptime",
                    "test", "inline", "export", "extern", "async", "await", "suspend", "resume"],
        keywords2: ["bool", "u8", "u16", "u32", "u64", "usize", "i8", "i16", "i32", "i64", "isize",
                    "f32", "f64", "void", "anytype", "type", "null", "undefined", "true", "false"]
    )

    public static let assembly = LanguageDefinition(
        name: "Assembly", fileExtensions: ["asm", "s", "nasm"],
        lineCommentTokens: [";", "#"], stringDelimiters: ["\"", "'"],
        isCaseSensitive: false,
        keywords1: ["mov", "push", "pop", "add", "sub", "mul", "div", "inc", "dec", "cmp", "jmp",
                    "je", "jne", "jg", "jl", "call", "ret", "lea", "int", "nop", "xor", "and",
                    "or", "not", "shl", "shr", "test", "loop"],
        keywords2: ["eax", "ebx", "ecx", "edx", "esi", "edi", "esp", "ebp", "rax", "rbx", "rcx",
                    "rdx", "rsi", "rdi", "rsp", "rbp", "al", "bl", "cl", "dl",
                    "byte", "word", "dword", "qword", "section", "global", "extern"],
        foldOpen: [], foldClose: []
    )

    public static let fortran = LanguageDefinition(
        name: "Fortran", fileExtensions: ["f", "for", "f90", "f95"],
        lineCommentTokens: ["!"], stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["program", "end", "subroutine", "function", "module", "use", "implicit",
                    "none", "if", "then", "else", "elseif", "endif", "do", "enddo", "while",
                    "call", "return", "contains", "interface", "type", "select", "case"],
        keywords2: ["integer", "real", "double", "precision", "complex", "logical", "character",
                    "dimension", "parameter", "allocatable", "pointer", "intent"],
        foldOpen: ["then", "do"], foldClose: ["endif", "enddo", "end"]
    )

    public static let pascal = LanguageDefinition(
        name: "Pascal", fileExtensions: ["pas", "pp", "dpr"],
        lineCommentTokens: ["//"], blockCommentOpen: "{", blockCommentClose: "}",
        stringDelimiters: ["'"], isCaseSensitive: false,
        keywords1: ["program", "unit", "uses", "interface", "implementation", "begin", "end",
                    "var", "const", "type", "procedure", "function", "if", "then", "else",
                    "for", "to", "downto", "do", "while", "repeat", "until", "case", "of",
                    "record", "array", "class", "constructor", "destructor", "try", "except"],
        keywords2: ["integer", "real", "string", "boolean", "char", "byte", "word", "longint",
                    "double", "pointer", "true", "false", "nil"],
        foldOpen: ["begin"], foldClose: ["end"]
    )

    public static let ada = LanguageDefinition(
        name: "Ada", fileExtensions: ["ads", "adb"],
        lineCommentTokens: ["--"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["package", "body", "is", "begin", "end", "procedure", "function", "return",
                    "if", "then", "else", "elsif", "loop", "for", "while", "case", "when",
                    "declare", "type", "subtype", "with", "use", "new", "record", "null"],
        keywords2: ["Integer", "Float", "Boolean", "Character", "String", "Natural", "Positive"],
        foldOpen: ["begin", "loop"], foldClose: ["end"]
    )

    public static let cobol = LanguageDefinition(
        name: "COBOL", fileExtensions: ["cbl", "cob"],
        lineCommentTokens: ["*"], stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["IDENTIFICATION", "DIVISION", "PROGRAM-ID", "ENVIRONMENT", "DATA", "WORKING-STORAGE",
                    "PROCEDURE", "SECTION", "MOVE", "TO", "IF", "ELSE", "END-IF", "PERFORM",
                    "UNTIL", "DISPLAY", "ACCEPT", "STOP", "RUN", "COMPUTE", "CALL"],
        keywords2: ["PIC", "PICTURE", "VALUE", "OCCURS", "REDEFINES", "COMP", "COMP-3"],
        foldOpen: [], foldClose: []
    )

    // MARK: - Scripting

    public static let powershell = LanguageDefinition(
        name: "PowerShell", fileExtensions: ["ps1", "psm1", "psd1"],
        lineCommentTokens: ["#"], blockCommentOpen: "<#", blockCommentClose: "#>",
        stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["function", "param", "begin", "process", "end", "if", "elseif", "else",
                    "switch", "foreach", "for", "while", "do", "until", "break", "continue",
                    "return", "try", "catch", "finally", "throw", "filter", "workflow", "class"],
        keywords3: ["Write-Host", "Write-Output", "Get-ChildItem", "Get-Content", "Set-Content",
                    "Where-Object", "ForEach-Object", "Select-Object", "Test-Path", "Join-Path"]
    )

    public static let tcl = LanguageDefinition(
        name: "Tcl", fileExtensions: ["tcl"], shebangs: ["tclsh", "wish"],
        lineCommentTokens: ["#"], stringDelimiters: ["\""],
        keywords1: ["proc", "set", "if", "else", "elseif", "while", "for", "foreach", "switch",
                    "return", "break", "continue", "expr", "global", "upvar", "namespace",
                    "package", "source", "catch", "error"]
    )

    public static let r = LanguageDefinition(
        name: "R", fileExtensions: ["r"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        keywords1: ["function", "if", "else", "for", "while", "repeat", "break", "next", "return",
                    "library", "require", "in"],
        keywords2: ["TRUE", "FALSE", "NULL", "NA", "Inf", "NaN"],
        keywords3: ["c", "data.frame", "matrix", "list", "vector", "apply", "sapply", "lapply",
                    "print", "paste", "length", "nrow", "ncol", "summary", "plot"]
    )

    public static let matlab = LanguageDefinition(
        name: "MATLAB", fileExtensions: ["mat"],
        lineCommentTokens: ["%"], blockCommentOpen: "%{", blockCommentClose: "%}",
        stringDelimiters: ["'", "\""],
        keywords1: ["function", "end", "if", "elseif", "else", "for", "while", "switch", "case",
                    "otherwise", "break", "continue", "return", "try", "catch", "global",
                    "persistent", "classdef", "properties", "methods"],
        foldOpen: ["function", "if", "for", "while"], foldClose: ["end"]
    )

    public static let vhdl = LanguageDefinition(
        name: "VHDL", fileExtensions: ["vhd", "vhdl"],
        lineCommentTokens: ["--"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["entity", "architecture", "begin", "end", "process", "signal", "variable",
                    "constant", "port", "map", "component", "if", "then", "else", "elsif",
                    "case", "when", "for", "loop", "while", "library", "use", "package"],
        keywords2: ["std_logic", "std_logic_vector", "integer", "boolean", "bit", "bit_vector",
                    "natural", "positive", "signed", "unsigned"],
        foldOpen: ["begin"], foldClose: ["end"]
    )

    public static let verilog = LanguageDefinition(
        name: "Verilog", fileExtensions: ["v", "sv", "svh"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\""],
        keywords1: ["module", "endmodule", "input", "output", "inout", "wire", "reg", "always",
                    "assign", "begin", "end", "if", "else", "case", "endcase", "for", "while",
                    "function", "endfunction", "task", "endtask", "initial", "posedge", "negedge"],
        keywords2: ["integer", "real", "time", "parameter", "localparam", "logic", "bit", "byte"],
        foldOpen: ["begin"], foldClose: ["end"]
    )

    public static let ini2 = LanguageDefinition(
        name: "Properties", fileExtensions: ["properties"],
        lineCommentTokens: ["#", "!"], stringDelimiters: [],
        operatorCharacters: "=:", foldOpen: [], foldClose: []
    )

    // MARK: - Web and markup

    public static let jsp = LanguageDefinition(
        name: "JSP", fileExtensions: ["jsp"],
        blockCommentOpen: "<%--", blockCommentClose: "--%>",
        stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: BuiltInLanguages.html.keywords1, keywords2: BuiltInLanguages.html.keywords2,
        foldOpen: ["<"], foldClose: [">"]
    )

    public static let asp = LanguageDefinition(
        name: "ASP", fileExtensions: ["asp", "aspx"],
        lineCommentTokens: ["'"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["Dim", "Set", "If", "Then", "Else", "End", "For", "Each", "Next", "While",
                    "Wend", "Function", "Sub", "Call", "Response", "Request", "Server"],
        foldOpen: [], foldClose: []
    )

    public static let vb = LanguageDefinition(
        name: "Visual Basic", fileExtensions: ["vb", "vbs", "bas"],
        lineCommentTokens: ["'", "REM"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["Dim", "As", "Set", "If", "Then", "Else", "ElseIf", "End", "For", "To",
                    "Next", "Each", "While", "Wend", "Do", "Loop", "Until", "Function", "Sub",
                    "Call", "Class", "Module", "Public", "Private", "Protected", "Friend",
                    "Return", "Select", "Case", "Try", "Catch", "Finally", "New", "Nothing"],
        keywords2: ["Integer", "Long", "Single", "Double", "String", "Boolean", "Object",
                    "Variant", "Byte", "Date", "True", "False"],
        foldOpen: [], foldClose: []
    )

    public static let latex = LanguageDefinition(
        name: "LaTeX", fileExtensions: ["tex", "sty", "cls"],
        lineCommentTokens: ["%"], stringDelimiters: [],
        operatorCharacters: "\\{}[]$&#^_~",
        keywords1: ["\\begin", "\\end", "\\section", "\\subsection", "\\chapter", "\\usepackage",
                    "\\documentclass", "\\item", "\\label", "\\ref", "\\cite", "\\textbf",
                    "\\textit", "\\emph", "\\newcommand", "\\includegraphics"],
        foldOpen: ["{"], foldClose: ["}"]
    )

    public static let rst = LanguageDefinition(
        name: "reStructuredText", fileExtensions: ["rst"],
        lineCommentTokens: [".."], stringDelimiters: ["`"],
        operatorCharacters: "*=-~^#", foldOpen: [], foldClose: []
    )

    public static let diff = LanguageDefinition(
        name: "Diff", fileExtensions: ["diff", "patch"],
        lineCommentTokens: [], stringDelimiters: [],
        operatorCharacters: "+-@", foldOpen: [], foldClose: []
    )

    public static let makefile = LanguageDefinition(
        name: "Makefile", fileExtensions: ["makefile", "mk", "mak"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        operatorCharacters: ":=$()",
        keywords1: [".PHONY", ".DEFAULT", ".PRECIOUS", "include", "ifeq", "ifneq", "ifdef",
                    "ifndef", "else", "endif", "define", "endef", "export", "unexport"],
        foldOpen: [], foldClose: []
    )

    public static let cmake = LanguageDefinition(
        name: "CMake", fileExtensions: ["cmake"],
        lineCommentTokens: ["#"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["cmake_minimum_required", "project", "add_executable", "add_library",
                    "target_link_libraries", "include_directories", "set", "if", "elseif",
                    "else", "endif", "foreach", "endforeach", "while", "endwhile", "function",
                    "endfunction", "macro", "endmacro", "option", "find_package"],
        foldOpen: [], foldClose: []
    )

    public static let dockerfile = LanguageDefinition(
        name: "Dockerfile", fileExtensions: ["dockerfile"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["FROM", "RUN", "CMD", "LABEL", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT",
                    "VOLUME", "USER", "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK",
                    "SHELL", "AS"],
        foldOpen: [], foldClose: []
    )

    public static let nsis = LanguageDefinition(
        name: "NSIS", fileExtensions: ["nsi", "nsh"],
        lineCommentTokens: [";", "#"], stringDelimiters: ["\""], isCaseSensitive: false,
        keywords1: ["Section", "SectionEnd", "Function", "FunctionEnd", "OutFile", "InstallDir",
                    "SetOutPath", "File", "WriteUninstaller", "Delete", "RMDir", "MessageBox"],
        foldOpen: [], foldClose: []
    )

    public static let autoit = LanguageDefinition(
        name: "AutoIt", fileExtensions: ["au3"],
        lineCommentTokens: [";"], blockCommentOpen: "#cs", blockCommentClose: "#ce",
        stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: ["Func", "EndFunc", "If", "Then", "Else", "ElseIf", "EndIf", "For", "To",
                    "Next", "While", "WEnd", "Do", "Until", "Select", "Case", "EndSelect",
                    "Switch", "EndSwitch", "Return", "Local", "Global", "Dim", "Const"],
        foldOpen: [], foldClose: []
    )

    public static let haskell = LanguageDefinition(
        name: "Haskell", fileExtensions: ["hs", "lhs"],
        lineCommentTokens: ["--"], blockCommentOpen: "{-", blockCommentClose: "-}",
        blockCommentsNest: true, stringDelimiters: ["\"", "'"],
        keywords1: ["module", "where", "import", "data", "newtype", "type", "class", "instance",
                    "deriving", "do", "let", "in", "case", "of", "if", "then", "else", "infix",
                    "infixl", "infixr"],
        keywords2: ["Int", "Integer", "Float", "Double", "Char", "String", "Bool", "Maybe",
                    "Either", "IO", "True", "False", "Nothing", "Just"],
        foldOpen: [], foldClose: []
    )

    public static let erlang = LanguageDefinition(
        name: "Erlang", fileExtensions: ["erl", "hrl"],
        lineCommentTokens: ["%"], stringDelimiters: ["\"", "'"],
        keywords1: ["module", "export", "import", "compile", "define", "record", "include",
                    "case", "of", "end", "if", "when", "fun", "receive", "after", "try",
                    "catch", "begin", "let", "andalso", "orelse"],
        foldOpen: [], foldClose: ["end"]
    )

    public static let elixir = LanguageDefinition(
        name: "Elixir", fileExtensions: ["ex", "exs"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        keywords1: ["defmodule", "def", "defp", "defmacro", "defstruct", "defprotocol", "defimpl",
                    "do", "end", "if", "unless", "else", "case", "cond", "with", "fn", "receive",
                    "after", "try", "rescue", "catch", "raise", "import", "alias", "require", "use"],
        keywords2: ["true", "false", "nil", "when", "and", "or", "not", "in"],
        foldOpen: ["do"], foldClose: ["end"]
    )

    public static let scheme = LanguageDefinition(
        name: "Scheme", fileExtensions: ["scm", "ss", "lisp", "el", "clj"],
        lineCommentTokens: [";"], stringDelimiters: ["\""],
        operatorCharacters: "()'`,@",
        keywords1: ["define", "lambda", "let", "let*", "letrec", "if", "cond", "else", "case",
                    "and", "or", "not", "begin", "do", "quote", "quasiquote", "set!", "defun",
                    "defmacro", "defn", "defrecord", "loop", "recur"],
        keywords2: ["#t", "#f", "nil", "true", "false"],
        foldOpen: ["("], foldClose: [")"]
    )

    public static let groovy = LanguageDefinition(
        name: "Groovy", fileExtensions: ["groovy", "gradle"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["def", "class", "interface", "trait", "enum", "package", "import", "if",
                    "else", "for", "while", "switch", "case", "return", "try", "catch",
                    "finally", "throw", "new", "static", "final", "public", "private", "protected"],
        keywords2: ["int", "long", "float", "double", "boolean", "char", "byte", "String",
                    "void", "var", "true", "false", "null"]
    )

    public static let dart = LanguageDefinition(
        name: "Dart", fileExtensions: ["dart"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["abstract", "async", "await", "class", "const", "extends", "final", "for",
                    "if", "else", "import", "library", "mixin", "new", "return", "static",
                    "super", "switch", "case", "this", "throw", "try", "catch", "var", "while",
                    "with", "yield", "factory", "get", "set", "late", "required"],
        keywords2: ["bool", "double", "dynamic", "int", "num", "String", "List", "Map", "Set",
                    "void", "Future", "Stream", "null", "true", "false"]
    )

    public static let kotlin = LanguageDefinition(
        name: "Kotlin", fileExtensions: ["kt", "kts"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        blockCommentsNest: true, stringDelimiters: ["\"", "'"],
        keywords1: ["package", "import", "class", "interface", "object", "fun", "val", "var",
                    "if", "else", "when", "for", "while", "do", "return", "try", "catch",
                    "finally", "throw", "is", "as", "in", "out", "by", "companion", "data",
                    "sealed", "suspend", "override", "private", "public", "internal", "protected"],
        keywords2: ["Boolean", "Byte", "Short", "Int", "Long", "Float", "Double", "Char",
                    "String", "Any", "Unit", "Nothing", "List", "Map", "Set", "true", "false", "null"]
    )

    public static let scala = LanguageDefinition(
        name: "Scala", fileExtensions: ["scala", "sc"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["package", "import", "class", "object", "trait", "def", "val", "var", "if",
                    "else", "match", "case", "for", "while", "do", "return", "try", "catch",
                    "finally", "throw", "extends", "with", "implicit", "lazy", "sealed",
                    "abstract", "override", "private", "protected", "new", "yield", "type"],
        keywords2: ["Int", "Long", "Double", "Float", "Boolean", "Char", "String", "Unit", "Any",
                    "AnyRef", "Nothing", "Option", "Some", "None", "List", "Map", "Seq",
                    "true", "false", "null"]
    )

    public static let swiftPackage = LanguageDefinition(
        name: "TOML", fileExtensions: ["toml"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        operatorCharacters: "=[]{},.",
        keywords1: ["true", "false"], foldOpen: ["["], foldClose: ["]"]
    )

    public static let graphql = LanguageDefinition(
        name: "GraphQL", fileExtensions: ["graphql", "gql"],
        lineCommentTokens: ["#"], stringDelimiters: ["\""],
        keywords1: ["query", "mutation", "subscription", "fragment", "on", "type", "input",
                    "interface", "union", "enum", "scalar", "schema", "extend", "implements",
                    "directive"],
        keywords2: ["Int", "Float", "String", "Boolean", "ID", "true", "false", "null"]
    )

    public static let protobuf = LanguageDefinition(
        name: "Protocol Buffers", fileExtensions: ["proto"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["syntax", "package", "import", "option", "message", "enum", "service",
                    "rpc", "returns", "repeated", "optional", "required", "oneof", "map",
                    "reserved", "extend", "stream"],
        keywords2: ["double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64",
                    "fixed32", "fixed64", "bool", "string", "bytes", "true", "false"]
    )

    public static let nginx = LanguageDefinition(
        name: "nginx", fileExtensions: ["nginx"],
        lineCommentTokens: ["#"], stringDelimiters: ["\"", "'"],
        operatorCharacters: "{};",
        keywords1: ["server", "location", "upstream", "http", "events", "listen", "server_name",
                    "root", "index", "proxy_pass", "rewrite", "return", "include", "worker_processes",
                    "error_log", "access_log", "ssl_certificate", "add_header", "if"]
    )

    public static let sqlDialect = LanguageDefinition(
        name: "PL/SQL", fileExtensions: ["pls", "plsql", "pks", "pkb"],
        lineCommentTokens: ["--"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["'", "\""], isCaseSensitive: false,
        keywords1: ["declare", "begin", "end", "procedure", "function", "package", "body", "is",
                    "as", "if", "then", "elsif", "else", "loop", "while", "for", "exit", "when",
                    "return", "exception", "cursor", "open", "fetch", "close", "commit", "rollback"],
        keywords2: ["number", "varchar2", "date", "boolean", "clob", "blob", "integer", "pls_integer"],
        foldOpen: ["begin"], foldClose: ["end"]
    )

    public static let objectiveJ = LanguageDefinition(
        name: "ActionScript", fileExtensions: ["as"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"],
        keywords1: ["package", "import", "class", "interface", "extends", "implements", "public",
                    "private", "protected", "internal", "static", "override", "function", "var",
                    "const", "if", "else", "for", "each", "while", "do", "switch", "case",
                    "return", "try", "catch", "finally", "throw", "new"],
        keywords2: ["Boolean", "int", "uint", "Number", "String", "Array", "Object", "void",
                    "null", "undefined", "true", "false"]
    )

    public static let coffeescript = LanguageDefinition(
        name: "CoffeeScript", fileExtensions: ["coffee"],
        lineCommentTokens: ["#"], blockCommentOpen: "###", blockCommentClose: "###",
        stringDelimiters: ["\"", "'"],
        keywords1: ["class", "extends", "if", "else", "unless", "for", "in", "of", "while",
                    "until", "loop", "switch", "when", "then", "return", "try", "catch",
                    "finally", "throw", "new", "do", "yield", "await"],
        keywords2: ["true", "false", "null", "undefined", "this", "@"],
        foldOpen: [], foldClose: []
    )

    public static let ocaml = LanguageDefinition(
        name: "OCaml", fileExtensions: ["ml", "mli"],
        blockCommentOpen: "(*", blockCommentClose: "*)", blockCommentsNest: true,
        stringDelimiters: ["\""],
        keywords1: ["let", "in", "rec", "and", "fun", "function", "match", "with", "if", "then",
                    "else", "type", "module", "struct", "sig", "end", "open", "val", "mutable",
                    "try", "raise", "begin", "for", "while", "do", "done"],
        keywords2: ["int", "float", "bool", "char", "string", "unit", "list", "array", "option",
                    "true", "false", "None", "Some"],
        foldOpen: ["begin", "struct"], foldClose: ["end"]
    )

    public static let smalltalk = LanguageDefinition(
        name: "Smalltalk", fileExtensions: ["st"],
        blockCommentOpen: "\"", blockCommentClose: "\"",
        stringDelimiters: ["'"],
        keywords1: ["self", "super", "true", "false", "nil", "thisContext", "class", "subclass"],
        foldOpen: ["["], foldClose: ["]"]
    )

    public static let rebol = LanguageDefinition(
        name: "Rust Config", fileExtensions: ["ron"],
        lineCommentTokens: ["//"], stringDelimiters: ["\""],
        operatorCharacters: "(){}[],:", keywords1: ["Some", "None", "true", "false"],
        foldOpen: ["("], foldClose: [")"]
    )

    public static let sass = LanguageDefinition(
        name: "Sass", fileExtensions: ["sass"],
        lineCommentTokens: ["//"], blockCommentOpen: "/*", blockCommentClose: "*/",
        stringDelimiters: ["\"", "'"], isCaseSensitive: false,
        keywords1: BuiltInLanguages.css.keywords1, keywords2: BuiltInLanguages.css.keywords2,
        foldOpen: [], foldClose: []
    )

    public static let csv = LanguageDefinition(
        name: "CSV", fileExtensions: ["csv", "tsv"],
        lineCommentTokens: [], stringDelimiters: ["\""],
        operatorCharacters: ",;\t", foldOpen: [], foldClose: []
    )

    public static let log = LanguageDefinition(
        name: "Log", fileExtensions: ["log"],
        lineCommentTokens: [], stringDelimiters: ["\""],
        operatorCharacters: "[]:", isCaseSensitive: false,
        keywords1: ["ERROR", "FATAL", "CRITICAL"],
        keywords2: ["WARN", "WARNING"],
        keywords3: ["INFO", "DEBUG", "TRACE", "NOTICE"],
        foldOpen: [], foldClose: []
    )

    public static let gitConfig = LanguageDefinition(
        name: "Git Config", fileExtensions: ["gitconfig", "gitignore", "gitattributes"],
        lineCommentTokens: ["#", ";"], stringDelimiters: ["\""],
        operatorCharacters: "=[]", foldOpen: [], foldClose: []
    )

    public static let editorConfig = LanguageDefinition(
        name: "EditorConfig", fileExtensions: ["editorconfig"],
        lineCommentTokens: ["#", ";"], stringDelimiters: [],
        operatorCharacters: "=[]",
        keywords1: ["root", "indent_style", "indent_size", "tab_width", "end_of_line",
                    "charset", "trim_trailing_whitespace", "insert_final_newline"],
        foldOpen: [], foldClose: []
    )

    /// Everything defined above, appended to the original set.
    public static let additional: [LanguageDefinition] = [
        objectiveC, csharpScript, d, rustScript, assembly, fortran, pascal, ada, cobol,
        powershell, tcl, r, matlab, vhdl, verilog, ini2,
        jsp, asp, vb, latex, rst, diff, makefile, cmake, dockerfile, nsis, autoit,
        haskell, erlang, elixir, scheme, groovy, dart, kotlin, scala, swiftPackage,
        graphql, protobuf, nginx, sqlDialect, objectiveJ, coffeescript, ocaml,
        smalltalk, rebol, sass, csv, log, gitConfig, editorConfig,
    ]
}
