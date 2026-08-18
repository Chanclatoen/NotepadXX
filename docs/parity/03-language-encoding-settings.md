# NotepadXX Parity Matrix — Language, Encoding & Settings Menus
Scope: Notepad++ v8.8.x — **Language menu**, **Encoding menu**, **Settings menu** (Preferences dialog, Style Configurator, Shortcut Mapper, Import, Edit Popup ContextMenu).

Sources: npp-user-manual.org (`preferences`, `encoding`, `user-defined-language-system` pages, raw markdown fetched from `github.com/notepad-plus-plus/npp-usermanual`), and `github.com/notepad-plus-plus/notepad-plus-plus` source: `PowerEditor/src/menuCmdID.h`, `PowerEditor/src/langs.model.xml`, `PowerEditor/src/EncodingMapper.cpp`, `PowerEditor/installer/nativeLang/english.xml`.

Legend — **Complexity**: S=Small (native API/1 control), M=Medium (custom UI/logic, existing building blocks), L=Large (bespoke subsystem), XL=Extra-Large (foundational engine, multi-week). **Tier**: E=Essential (must-have for parity claim), I=Important (most power users expect it), N=Niche/Nice-to-have.

---

## PART 1 — LANGUAGE MENU

### 1.1 Built-in Languages (95 `<Language>` entries in `langs.model.xml`)

`javascript` (no extension) is a deprecated internal alias kept only so old `stylers.xml`/theme files referencing it don't break; the real JS lexer is `javascript.js`. `searchResult` is not user-selectable — it's the internal lexer for the Find-Results window. `normal` is "Normal Text," the default/plain-text style. All others appear as `Language > <Name>` menu items (or nested under a letter submenu if "Make language menu compact" is on).

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| LANG-001 | Language > Normal Text | `normal` (.txt) | Default/no-lexer plain text styling | Plain NSTextView styling, no lexer needed | S | E |
| LANG-002 | Language > ActionScript | `actionscript` (.as .mx) | Flash ActionScript syntax highlighting | No modern grammar; custom lexer port from Scintilla `LexCPP`-family variant | L | N |
| LANG-003 | Language > Ada | `ada` (.ada .ads .adb) | Ada syntax highlighting | tree-sitter-ada exists but immature; may need custom port | M | N |
| LANG-004 | Language > Assembly | `asm` (.asm) | x86/generic ASM highlighting | tree-sitter-asm available | M | I |
| LANG-005 | Language > ASN.1 | `asn1` (.mib) | ASN.1/MIB highlighting | No grammar; custom lexer | L | N |
| LANG-006 | Language > ASP | `asp` (.asp .aspx) | Classic ASP (embedded VBScript/JS in HTML) | Embedded-language lexer like HTML; custom port | L | N |
| LANG-007 | Language > AutoIt | `autoit` (.au3) | AutoIt scripting highlighting | No grammar; custom lexer | L | N |
| LANG-008 | Language > AviSynth | `avs` (.avs .avsi) | AviSynth script highlighting | No grammar; custom lexer | L | N |
| LANG-009 | Language > Baan C | `baanc` (.bc .cln) | Baan 4GL/C highlighting | No grammar; custom lexer, very niche | L | N |
| LANG-010 | Language > Shell/Bash | `bash` (.bash .sh .bsh .csh .profile etc.) | POSIX shell highlighting | tree-sitter-bash | M | E |
| LANG-011 | Language > Batch | `batch` (.bat .cmd .nt) | Windows batch-file highlighting | No native macOS batch grammar (Windows-specific syntax); custom lexer | M | I |
| LANG-012 | Language > BlitzBasic | `blitzbasic` (.bb) | BlitzBasic highlighting | No grammar; custom lexer | L | N |
| LANG-013 | Language > C | `c` (.c .lex) | C highlighting | tree-sitter-c | S | E |
| LANG-014 | Language > Caml | `caml` (.ml .mli .sml .thy) | OCaml/SML highlighting | tree-sitter-ocaml | M | I |
| LANG-015 | Language > CMake | `cmake` (.cmake) | CMake highlighting | tree-sitter-cmake | S | I |
| LANG-016 | Language > COBOL | `cobol` (.cbl .cbd .cob .cpy ...) | COBOL highlighting | No modern grammar; custom lexer, legacy enterprise niche | L | N |
| LANG-017 | Language > Csound | `csound` (.orc .sco .csd) | Csound audio-DSL highlighting | No grammar; custom lexer | L | N |
| LANG-018 | Language > CoffeeScript | `coffeescript` (.coffee .litcoffee) | CoffeeScript highlighting | tree-sitter-coffeescript (community) | M | N |
| LANG-019 | Language > C++ | `cpp` (.cpp .h .hpp .hxx .ino ...) | C++ highlighting | tree-sitter-cpp | S | E |
| LANG-020 | Language > C# | `cs` (.cs) | C# highlighting | tree-sitter-c-sharp | S | E |
| LANG-021 | Language > CSS | `css` (.css) | CSS highlighting | tree-sitter-css / native WebKit CSS parser | S | E |
| LANG-022 | Language > D | `d` (.d) | D language highlighting | tree-sitter-d (community) | M | N |
| LANG-023 | Language > Diff | `diff` (.diff .patch) | Unified-diff highlighting | Simple line-prefix based; trivial custom lexer | S | I |
| LANG-024 | Language > Erlang | `erlang` (.erl .hrl) | Erlang highlighting | tree-sitter-erlang | M | N |
| LANG-025 | (internal) Error List | `errorlist` (.err) | Console/build-output styling lexer, not in Language menu picker in practice | Trivial pattern-matched output pane styling | S | N |
| LANG-026 | Language > ANSI Escape Sequences | `escseq` (.ans) | Renders/interprets ANSI escape codes as color | Map to `NSAttributedString` via ANSI-to-attributed-string converter (existing OSS libs) | M | N |
| LANG-027 | Language > EScript | `escript` (.src .em) | EScript (Second Life-era) highlighting | No grammar; custom lexer, effectively dead language | L | N |
| LANG-028 | Language > Forth | `forth` (.forth) | Forth highlighting | No mainstream grammar; custom lexer | L | N |
| LANG-029 | Language > Fortran (free form) | `fortran` (.f .for .f90 .f95 .f2k .f23) | Fortran highlighting | tree-sitter-fortran | M | N |
| LANG-030 | Language > Fortran77 (fixed form) | `fortran77` (.f77) | Fixed-column Fortran77 highlighting | Column-sensitive; extend fortran grammar with fixed-form rules | M | N |
| LANG-031 | Language > FreeBasic | `freebasic` (.bas .bi) | FreeBasic highlighting | No grammar; custom lexer | L | N |
| LANG-032 | Language > Go | `go` (.go) | Go highlighting | tree-sitter-go | S | E |
| LANG-033 | Language > Gui4Cli | `gui4cli` (.gui) | Gui4Cli highlighting | No grammar; custom lexer, extremely niche (NPP-adjacent legacy tool) | L | N |
| LANG-034 | Language > Haskell | `haskell` (.hs .lhs .las) | Haskell highlighting | tree-sitter-haskell | M | I |
| LANG-035 | Language > Hollywood | `hollywood` (.hws) | Hollywood (Amiga-descended) highlighting | No grammar; custom lexer | L | N |
| LANG-036 | Language > HTML | `html` (.html .htm .xhtml .hta ...) | HTML + embedded CSS/JS highlighting | tree-sitter-html + injections | M | E |
| LANG-037 | Language > INI | `ini` (.ini .inf .url .wer) | INI-file highlighting | tree-sitter-ini or trivial custom lexer | S | E |
| LANG-038 | Language > Inno Setup | `inno` (.iss) | Inno Setup script highlighting | No grammar; custom lexer | L | N |
| LANG-039 | Language > Intel HEX | `ihex` (.hex) | Intel HEX record highlighting | Fixed-column format; trivial regex-based lexer | S | N |
| LANG-040 | Language > Java | `java` (.java) | Java highlighting | tree-sitter-java | S | E |
| LANG-041 | (internal/legacy) JavaScript alias | `javascript` (no ext) | Deprecated internal id kept for backward theme compatibility | N/A — do not implement; alias `javascript.js` only | S | N |
| LANG-042 | Language > JavaScript | `javascript.js` (.js .jsx .mjs .vue ...) | JavaScript/JSX highlighting (incl. Vue SFC) | tree-sitter-javascript (+ tree-sitter-vue for injections) | M | E |
| LANG-043 | Language > JSON | `json` (.json) | JSON highlighting | tree-sitter-json | S | E |
| LANG-044 | Language > JSON5 | `json5` (.json5 .jsonc) | JSON5/JSONC highlighting | tree-sitter-json5 | S | I |
| LANG-045 | Language > JSP | `jsp` (.jsp) | JSP (embedded Java in HTML) highlighting | Embedded-language lexer, custom port | L | N |
| LANG-046 | Language > KiXtart | `kix` (.kix) | KiXtart highlighting | No grammar; custom lexer | L | N |
| LANG-047 | Language > Lisp | `lisp` (.lsp .lisp) | Lisp highlighting | tree-sitter-commonlisp | M | N |
| LANG-048 | Language > LaTeX | `latex` (.tex .sty) | LaTeX highlighting | tree-sitter-latex | M | I |
| LANG-049 | Language > Lua | `lua` (.lua) | Lua highlighting | tree-sitter-lua | S | I |
| LANG-050 | Language > Makefile | `makefile` (.mak .mk) | Makefile highlighting | tree-sitter-make | S | I |
| LANG-051 | Language > MATLAB | `matlab` (.m) | MATLAB highlighting | tree-sitter-matlab (community); collides with Objective-C `.m` — needs content-sniff | M | I |
| LANG-052 | Language > MS SQL | `mssql` (.tsql) | T-SQL dialect highlighting | Extend tree-sitter-sql grammar with T-SQL dialect rules | M | N |
| LANG-053 | Language > MMIX | `mmixal` (.mms) | MMIX assembly highlighting | No grammar; custom lexer, academic/Knuth-only use | L | N |
| LANG-054 | Language > Nim | `nim` (.nim) | Nim highlighting | tree-sitter-nim | M | N |
| LANG-055 | Language > nnCron Tab | `nncrontab` (.tab .spf) | nnCron scheduler-file highlighting | No grammar; custom lexer, Windows-only tool, dead weight on macOS | L | N |
| LANG-056 | Language > NFO | `nfo` (.nfo) | Renders CP437 ASCII-art .nfo files | Needs CP437→glyph rendering with a fixed-width DOS-art font; not a real lexer | S | N |
| LANG-057 | Language > NSIS | `nsis` (.nsi .nsh) | NSIS installer-script highlighting | No grammar; custom lexer; NSIS itself is Windows-only tooling | L | N |
| LANG-058 | Language > OScript | `oscript` (.osx) | OpenEdge/O-Script highlighting | No grammar; custom lexer, very niche enterprise tool | L | N |
| LANG-059 | Language > Objective-C | `objc` (.mm) | Objective-C++ highlighting | tree-sitter-objc (native to macOS toolchain) | S | E |
| LANG-060 | Language > Pascal | `pascal` (.pas .pp .p .inc .lpr .dpr) | Pascal/Delphi highlighting | tree-sitter-pascal | M | I |
| LANG-061 | Language > Perl | `perl` (.pl .pm .plx .t) | Perl highlighting | tree-sitter-perl | M | I |
| LANG-062 | Language > PHP | `php` (.php .php3-5 .phps .phpt .phtml) | PHP (+ embedded HTML) highlighting | tree-sitter-php | M | E |
| LANG-063 | Language > PostScript | `postscript` (.ps) | PostScript highlighting | No grammar; custom lexer | L | N |
| LANG-064 | Language > PowerShell | `powershell` (.ps1 .psm1 .psd1) | PowerShell highlighting | tree-sitter-powershell (community) | M | I |
| LANG-065 | Language > Properties file | `props` (.properties .conf .cfg .gitattributes .gitconfig .editorconfig ...) | Key=value config-file highlighting | tree-sitter-properties or trivial custom lexer | S | I |
| LANG-066 | Language > PureBasic | `purebasic` (.pb) | PureBasic highlighting | No grammar; custom lexer | L | N |
| LANG-067 | Language > Python | `python` (.py .pyw .pyx .pxd .pxi .pyi) | Python highlighting | tree-sitter-python | S | E |
| LANG-068 | Language > GDScript | `gdscript` (.gd) | Godot GDScript highlighting | tree-sitter-gdscript | M | N |
| LANG-069 | Language > R | `r` (.r .s .splus) | R highlighting | tree-sitter-r | M | I |
| LANG-070 | Language > Raku | `raku` (.raku .rakumod .p6 .pm6 .pod6 ...) | Raku/Perl6 highlighting | No mature grammar; custom lexer | L | N |
| LANG-071 | Language > REBOL | `rebol` (.r2 .r3 .reb) | REBOL highlighting | No grammar; custom lexer | L | N |
| LANG-072 | Language > Windows Registry | `registry` (.reg) | .reg file highlighting | Trivial line-based custom lexer | S | N |
| LANG-073 | Language > Windows Resource file | `rc` (.rc) | Win32 .rc resource-script highlighting | Windows-specific format; custom lexer, low value on macOS | M | N |
| LANG-074 | Language > Ruby | `ruby` (.rb .rbw) | Ruby highlighting | tree-sitter-ruby | S | E |
| LANG-075 | Language > Rust | `rust` (.rs) | Rust highlighting | tree-sitter-rust | S | E |
| LANG-076 | Language > SAS | `sas` (.sas) | SAS highlighting | No mainstream grammar; custom lexer | L | N |
| LANG-077 | Language > Scheme | `scheme` (.scm .smd .ss) | Scheme highlighting | tree-sitter-scheme | M | N |
| LANG-078 | Language > Smalltalk | `smalltalk` (.st) | Smalltalk highlighting | tree-sitter-smalltalk (community, immature) | L | N |
| LANG-079 | Language > Spice | `spice` (.scp .out) | SPICE netlist highlighting | No grammar; custom lexer | L | N |
| LANG-080 | Language > SQL | `sql` (.sql) | SQL highlighting | tree-sitter-sql | S | E |
| LANG-081 | Language > S-Record | `srec` (.mot .srec) | Motorola S-record highlighting | Fixed-column format; trivial regex-based lexer | S | N |
| LANG-082 | Language > Swift | `swift` (.swift) | Swift highlighting | tree-sitter-swift (native to macOS toolchain) | S | E |
| LANG-083 | Language > TCL | `tcl` (.tcl .itcl) | Tcl/Itcl highlighting | tree-sitter-tcl (community) | M | N |
| LANG-084 | Language > Tektronix Extended HEX | `tehex` (.tek) | Tektronix hex-record highlighting | Fixed-column format; trivial regex-based lexer | S | N |
| LANG-085 | Language > TeX | `tex` (.tex) | Plain TeX highlighting (distinct entry from LaTeX; shares .tex ext — conflict is resolved by which one is registered) | Reuse LaTeX grammar with reduced macro set | S | N |
| LANG-086 | Language > TOML | `toml` (.toml) | TOML highlighting | tree-sitter-toml | S | I |
| LANG-087 | Language > Visual Basic | `vb` (.vb .vba .vbs) | VB/VBA/VBScript highlighting | tree-sitter-vba / custom for VBScript | M | I |
| LANG-088 | Language > txt2tags | `txt2tags` (.t2t) | txt2tags markup highlighting | No grammar; custom lexer, small OSS niche | L | N |
| LANG-089 | Language > TypeScript | `typescript` (.ts .tsx) | TypeScript/TSX highlighting | tree-sitter-typescript | S | E |
| LANG-090 | Language > Verilog | `verilog` (.v .sv .vh .svh) | Verilog/SystemVerilog highlighting | tree-sitter-verilog | M | I |
| LANG-091 | Language > VHDL | `vhdl` (.vhd .vhdl) | VHDL highlighting | tree-sitter-vhdl | M | I |
| LANG-092 | Language > Visual Prolog | `visualprolog` (.pro .cl .i .pack .ph) | Visual Prolog highlighting | No grammar; custom lexer | L | N |
| LANG-093 | Language > XML | `xml` (.xml .xaml .xsl .svg .plist .csproj .vcxproj ...) | XML highlighting (huge ext list incl. many project-file formats) | tree-sitter-xml | S | E |
| LANG-094 | Language > YAML | `yaml` (.yml .yaml) | YAML highlighting | tree-sitter-yaml | S | E |
| LANG-095 | (internal) Search Result | `searchResult` (no ext, not user-selectable) | Lexer used only by the Find-in-Files results window | Custom results-pane renderer, not a Language-menu item | S | E |

**Aggregate for the built-in-language subsystem (all 95 rows above as one deliverable):** Complexity **XL**, Tier **E** — a working syntax-highlighting engine covering the mainstream ~35 languages is Essential; full 95-language parity (incl. Baan C, Gui4Cli, MMIX, SAS, REBOL, Hollywood, OScript, etc.) is largely **N**-tier long-tail work best sequenced last.

### 1.2 Language menu structure & mechanics

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| LANG-096 | Language menu (top) | Active-language indicator | Currently active lexer is marked with `•` in the menu and shown in the status bar | NSMenu checkmark + status bar label | S | E |
| LANG-097 | Settings > Preferences > Language | `☐ Make language menu compact` | Groups 80+ languages into A–Z letter submenus instead of one flat list | NSMenu with alphabetic submenus, or a filterable command-palette-style picker (arguably better UX than replicating Win32 menu nesting) | S | I |
| LANG-098 | Settings > Preferences > Language | Available items ⇄ Disabled items (two-column mover) | Lets user hide specific languages from the menu entirely | Preferences pane with a two-list mover (`NSTableView` drag-and-drop or +/- buttons) | S | N |
| LANG-099 | Settings > Preferences > Language | `☐ Treat backslash as escape character for SQL` | SQL-lexer-specific backslash handling toggle | Per-language lexer option flag | S | N |
| LANG-100 | Language > User Defined Language (submenu) | List of user-created UDLs | Shows each UDL the user has defined, selectable like a built-in language | Same menu mechanics, backed by user-created grammar files | M | I |

### 1.3 User-Defined Language (UDL) system — "Language > Define your language..."

The single most Notepad++-specific, hardest-to-replicate feature in this whole scope: a full **GUI-authored, regex/keyword-list-driven custom lexer builder**, entirely independent of any real parser — no macOS text-editor equivalent ships this (BBEdit/TextMate ship *static* `.tmLanguage`/codeless-language-module formats that must be hand-authored as files, not built interactively in a dialog).

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| LANG-101 | Language > Define your language... | UDL dialog: language selector | Pulldown to select an existing UDL or the shared "default" scratch UDL | Custom NSPanel with a language list | S | I |
| LANG-102 | UDL dialog | `Create new…` | Clones the default template under a new name | Creates new user-lexer definition | S | I |
| LANG-103 | UDL dialog | `Save as…` | Duplicates current UDL under a new name | File/record duplication | S | I |
| LANG-104 | UDL dialog | `Rename` / `Remove` (named UDLs only) | Renames or deletes a saved UDL | CRUD on user-lexer store | S | I |
| LANG-105 | UDL dialog | `Ext.:` field | Space-separated file extensions bound to this UDL | Maps to a UTType/extension→lexer table, same as built-in languages | S | I |
| LANG-106 | UDL dialog | `Import…` / `Export…` | Load/save a UDL as a portable XML file for sharing (community "UDL Collection") | Needs an equivalent portable format — either support NPP's UDL XML schema directly for drop-in community compatibility, or define a NotepadXX JSON/plist schema + one-time UDL-XML importer | M | I |
| LANG-107 | UDL dialog | `☐ Ignore Case` | Keyword matching case sensitivity for the whole UDL | Lexer flag | S | I |
| LANG-108 | UDL dialog | `☐ Transparency` (+ opacity slider) | Makes the floating UDL dialog semi-transparent (so user can see sample text behind it) | `NSWindow.alphaValue` binding | S | N |
| LANG-109 | UDL dialog | Dock/Undock | Toggle dialog between floating and docked panel | NSPanel vs. sidebar embedding | M | N |
| LANG-110 | UDL dialog > Folder & Default tab | Default Style (font/size/color/decoration) | Base style for unstyled text in this UDL | Style-picker control, reuse Style Configurator widget | M | I |
| LANG-111 | UDL dialog > Folder & Default tab | Folding in comment / code style 1 / code style 2 | Defines which token pairs create foldable regions, with adjacency-vs-whitespace-sensitive trigger rules (open/middle/close boxes) | Custom folding-rule engine; no off-the-shelf equivalent — must be built to spec | L | I |
| LANG-112 | UDL dialog > Keywords Lists tab | 8 keyword groups + per-group Styler + `☐ Prefix Mode` | Up to 8 independently-styled, space-separated keyword lists; prefix mode matches "starts with" instead of exact match | Custom keyword-classification engine (trie/hash-based) with 8 style slots | M | I |
| LANG-113 | UDL dialog > Comment & Number tab | Line comment position, folding-of-comments toggle, line/block comment triggers+styles | Defines comment syntax and whether comments are foldable | Regex/token-based comment recognizer | M | I |
| LANG-114 | UDL dialog > Comment & Number tab | Number style: prefix/suffix/extra/range fields | Defines custom numeric literal syntax (hex/binary/octal prefixes, currency suffixes, ranges) | Custom numeric-token recognizer, configurable | M | N |
| LANG-115 | UDL dialog > Operators & Delimiters tab | Operators 1 (adjacency-sensitive) / Operators 2 (whitespace-sensitive) | Two operator-token classes with different matching context rules | Token classifier w/ context sensitivity | M | I |
| LANG-116 | UDL dialog > Operators & Delimiters tab | 8 Delimiter pairs (open/close/escape char + styler), `☐ Allow on several lines` | Defines paired delimiters (quotes, custom brackets) with escape-char support and per-pair styling | Paired-delimiter tokenizer, 8 configurable slots | M | I |
| LANG-117 | UDL dialog > Styles tab / Styler sub-dialog | Font name/size, Bold/Italic/Underline, fg/bg color + inherit (right-click "stripe") toggle | Per-token-class style editor identical in spirit to Style Configurator | Reuse the same style-editing widget as 3.3 | S | I |
| LANG-118 | UDL dialog | Nesting options (comments/delimiters) | Checkboxes controlling whether nested constructs keep their own style vs. inherit parent's | Nested-scope style resolution logic | M | N |
| LANG-119 | Language > Open User Defined Language Folder | Opens the UDL storage directory in Finder/Explorer | Reveals `%AppData%\Notepad++\userDefineLangs\` in Explorer | Reveal `~/Library/Application Support/NotepadXX/userDefineLangs/` in Finder | S | I |
| LANG-120 | Language > UDL Collection (community site link) | Opens the community UDL-sharing site in browser | `NSWorkspace.shared.open(url)` | S | N |

**Aggregate for UDL subsystem:** Complexity **XL** overall (custom scripting-free lexer-authoring GUI + folding engine + tokenizer), Tier **I** — power users rely on this heavily but it's not blocking for a v1 "credible NPP alternative."

### 1.4 Language auto-detection

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| LANG-121 | (automatic, no menu) | Extension-map lookup | On open, matches file extension against each language's `ext=` list (see 1.1) to pick the lexer; ties (e.g. `.tex` shared by `tex`/`latex`, `.m` shared by `matlab`/`objc`) resolved by declaration order/heuristic | Build an extension→language table from the same data; disambiguate collisions with content sniffing (shebang/keyword heuristics) same as NPP does informally | M | E |
| LANG-122 | (automatic, no menu) | Shebang detection | For extensionless scripts, some lexers are chosen via `#!/usr/bin/perl`-style first-line shebang | Regex first-line shebang table → language map | S | I |
| LANG-123 | Settings > Preferences > New Document | `Default Language` pulldown | Language applied to new files, and to opened files whose type can't be determined; UDLs cannot be selected here | Preferences dropdown bound to same language table (built-ins only) | S | I |

---

## PART 2 — ENCODING MENU

### 2.1 Core / top-of-menu encodings

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| ENC-001 | Encoding > ANSI | `IDM_FORMAT_ANSI` | Interprets/saves bytes using the active Windows system code page (whatever "Current ANSI codepage" is — commonly Windows-1252 in the US, but can be Shift-JIS/GBK/Big5/UHC on CJK Windows, or even CP65001/UTF-8 on Win11 w/ "Use Unicode UTF-8" enabled, in which case NPP **disables** this entry as of v8.8.8) | **No macOS equivalent concept exists** — macOS has no single system-wide legacy "ANSI" code page; always Unicode-native. Must define NotepadXX's own default legacy fallback (probably Windows-1252, exposed as a distinct Preferences > New Document `Legacy/Fallback encoding` picker) rather than mirroring "ANSI" | L | E |
| ENC-002 | Encoding > UTF-8 | `IDM_FORMAT_UTF_8` | Interpret/save as UTF-8, no BOM | `String.Encoding.utf8` / `CFStringEncoding.UTF8` | S | E |
| ENC-003 | Encoding > UTF-8-BOM | `IDM_FORMAT_UTF_8` + BOM flag | Interpret/save as UTF-8 with a 3-byte `EF BB BF` BOM; BOM is treated as file metadata, never shown/editable in the text buffer | `String.Encoding.utf8` + manual BOM byte handling on read/write (Foundation has no native "UTF-8 with BOM" `String.Encoding` — must add/strip the 3 bytes manually) | M | E |
| ENC-004 | Encoding > UTF-16 BE BOM | `IDM_FORMAT_UTF_16BE` | Interpret/save as big-endian UTF-16 with BOM (pre-v8.0 label: "UCS-2") | `String.Encoding.utf16BigEndian` (BOM handling needs manual check, Foundation's plain `.utf16BigEndian` doesn't auto-write BOM) | S | E |
| ENC-005 | Encoding > UTF-16 LE BOM | `IDM_FORMAT_UTF_16LE` | Interpret/save as little-endian UTF-16 with BOM | `String.Encoding.utf16LittleEndian` + manual BOM | S | E |
| ENC-006 | Encoding (below separator) > Convert to ANSI | `IDM_FORMAT_CONV2_ANSI` | **Re-encodes bytes on disk**, keeping glyphs the same, into the active ANSI code page | Re-encode via chosen legacy fallback encoding (see ENC-001) | M | E |
| ENC-007 | Encoding > Convert to UTF-8 | `IDM_FORMAT_CONV2_UTF_8` | Re-encodes bytes into UTF-8 (no BOM), same glyphs | `.data(using: .utf8)` | S | E |
| ENC-008 | Encoding > Convert to UTF-8-BOM | `IDM_FORMAT_CONV2_AS_UTF_8` | Re-encodes into UTF-8 and writes the BOM | Same as ENC-003 write path | S | E |
| ENC-009 | Encoding > Convert to UTF-16 BE BOM | `IDM_FORMAT_CONV2_UTF_16BE` | Re-encodes into big-endian UTF-16 + BOM | Standard transcode | S | E |
| ENC-010 | Encoding > Convert to UTF-16 LE BOM | `IDM_FORMAT_CONV2_UTF_16LE` | Re-encodes into little-endian UTF-16 + BOM | Standard transcode | S | E |

### 2.2 "Encode in..." vs "Convert to..." semantics (the core conceptual distinction to replicate)

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| ENC-011 | (conceptual — applies to all entries above the separator line) | "Encode in / interpret as X" | **Reinterprets the existing on-disk bytes** under a new encoding without altering them; glyphs displayed change, byte content on disk stays identical until next save. Internally NPP always edits as UTF-8 (or UTF-16 for the UTF-16 choices) in-buffer and transcodes on load/save. | This is the trickiest correctness point to port: NotepadXX needs an internal canonical in-memory representation (Swift `String`/UTF-16-backed) plus a "declared source encoding" tag per document, and must NOT re-encode on mere "reinterpret" — only on explicit save or explicit "Convert to." Off-by-one bugs here (auto re-encoding on reinterpret) are the #1 way clones get this wrong | L | E |
| ENC-012 | (conceptual — applies to all "Convert to..." entries) | "Convert to X" | **Re-encodes the underlying bytes**, preserving the glyphs/meaning, and marks the buffer dirty (since the on-disk representation will change on next save) | Explicit transcode-and-mark-dirty action | M | E |
| ENC-013 | (behavioral note) | BOM handling on interpret vs convert | For BOM-having encodings, BOM bytes exist on disk but are never inserted into/visible in the editable text buffer; only "Convert to X-BOM" / "Convert to X (no BOM)" toggles BOM presence | BOM must live as document metadata (a `hasBOM: Bool` field), stripped before decode, re-added before write for BOM variants | M | E |

### 2.3 Character Sets submenu — 16 regional categories, 45 legacy codepages (from `EncodingMapper.cpp`, `IDM_FORMAT_ENCODE`..`IDM_FORMAT_ENCODE_END`)

Category names verified against `PowerEditor/installer/nativeLang/english.xml` (`encoding-arabic`, `encoding-baltic`, `encoding-celtic`, `encoding-cyrillic`, `encoding-centralEuropean`, `encoding-chinese`, `encoding-easternEuropean`, `encoding-greek`, `encoding-hebrew`, `encoding-japanese`, `encoding-korean`, `encoding-northEuropean`, `encoding-thai`, `encoding-turkish`, `encoding-westernEuropean`, `encoding-vietnamese` — all 16 confirmed present). Exact per-item nesting under each category could not be pulled from the (inaccessible) `.rc` menu resource; the grouping below follows standard regional/Windows-codepage convention and should be spot-checked against a live v8.8.x install before final sign-off, but **the codepage set itself is authoritative** (straight from `EncodingMapper.cpp`'s `encodings[]` array, which is what actually drives conversion).

| ID | Category | Command/Setting (codepage : IANA aliases) | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| ENC-014 | Arabic | Windows-1256 (`windows-1256`) | Encode in / no direct Convert-to for legacy codepages (Character-Set entries are "Encode in" only) | `CFStringEncoding.windowsArabic` exists in CoreFoundation (`kCFStringEncodingWindowsArabic`) — usable directly | S | I |
| ENC-015 | Arabic | OEM 720 (`IBM720/cp720/oem720`) | DOS Arabic code page | **No Foundation/CFString constant** — CP720 has no macOS built-in; needs ICU (`ibm-720` converter) or a hand-rolled table | L | N |
| ENC-016 | Baltic | Windows-1257 (`windows-1257`) | Baltic Windows codepage | `kCFStringEncodingWindowsBalticRim` | S | I |
| ENC-017 | Baltic | ISO 8859-4 (`latin4`) | Baltic ISO codepage | `kCFStringEncodingISOLatin4` | S | N |
| ENC-018 | Baltic | ISO 8859-13 (`ISO-8859-13`) | Baltic ISO codepage (superset of 8859-4) | **No CFString constant for 8859-13** — needs ICU | M | N |
| ENC-019 | Baltic | OEM 775 (`IBM775/cp775`) | DOS Baltic codepage | No CF constant — ICU (`ibm-775`) required | L | N |
| ENC-020 | Celtic | ISO 8859-14 (`iso-celtic/latin8`) | Celtic-languages ISO codepage | No CF constant — ICU (`iso-8859-14`) required | M | N |
| ENC-021 | Central European | Windows-1250 (`windows-1250`) | Central European Windows codepage | `kCFStringEncodingWindowsLatin2` | S | I |
| ENC-022 | Central European | OEM 852 (`IBM852/cp852`) | DOS Central European codepage | `kCFStringEncodingDOSLatin2` exists | S | N |
| ENC-023 | Eastern European | ISO 8859-2 (`latin2`) | Eastern European ISO codepage (manual explicitly calls this "Eastern European ISO 8859-2") | `kCFStringEncodingISOLatin2` | S | I |
| ENC-024 | Eastern European | ISO 8859-3 (`latin3`) | South-European/Maltese-Esperanto ISO codepage, grouped here by NPP | `kCFStringEncodingISOLatin3` | S | N |
| ENC-025 | Cyrillic | Windows-1251 (`windows-1251`) | Cyrillic Windows codepage | `kCFStringEncodingWindowsCyrillic` | S | I |
| ENC-026 | Cyrillic | ISO 8859-5 (`cyrillic`) | Cyrillic ISO codepage | `kCFStringEncodingISOLatinCyrillic` | S | N |
| ENC-027 | Cyrillic | OEM 855 (`IBM855/cp855`) | DOS Cyrillic codepage | No CF constant — ICU (`ibm-855`) required | L | N |
| ENC-028 | Cyrillic | OEM 866 (`IBM866/cp866`) | DOS Russian codepage (very common for legacy RU files) | `kCFStringEncodingDOSRussian` exists | S | I |
| ENC-029 | Cyrillic | KOI8-R (`koi8_r`) | Russian KOI8 codepage | `kCFStringEncodingKOI8_R` | S | I |
| ENC-030 | Cyrillic | KOI8-U (`koi8_u`) | Ukrainian KOI8 codepage | **No CFString constant for KOI8-U** — ICU (`koi8-u`) required | M | N |
| ENC-031 | Cyrillic | Mac Cyrillic (`x-mac-cyrillic`) | Classic Mac OS Cyrillic codepage | `kCFStringEncodingMacCyrillic` — the one legacy codepage that's *more* native on macOS than Windows | S | N |
| ENC-032 | Chinese | Big5 — Traditional (`big5`) | Traditional Chinese | `kCFStringEncodingBig5` | S | I |
| ENC-033 | Chinese | GB2312 — Simplified (`gb2312/gbk/gb18030`) | Simplified Chinese (note: NPP's alias list conflates GB2312/GBK/GB18030, which are NOT byte-identical — a fidelity gap in NPP itself) | `kCFStringEncodingGB_2312_80` / `kCFStringEncodingGBK_95`; must decide which exact variant to target, don't just alias-match like NPP does | M | I |
| ENC-034 | Japanese | Shift-JIS (`Shift_JIS/MS_Kanji/csWindows31J`) | Japanese Windows codepage | `kCFStringEncodingShiftJIS` | S | I |
| ENC-035 | Korean | Windows-949/UHC (`windows-949/korean`) | Korean Unified Hangul Code | `kCFStringEncodingDOSKorean` / `kCFStringEncodingWindowsKoreanJohab` — verify exact UHC vs Johab match | M | I |
| ENC-036 | Korean | EUC-KR (`euc-kr/csEUCKR`) | Korean EUC codepage | `kCFStringEncodingEUC_KR` | S | I |
| ENC-037 | North European | (Windows-1252 / Nordic OEM codepages e.g. OEM 865) | Nordic-language grouping | `kCFStringEncodingWindowsLatin1`; OEM 865 needs ICU | S/L | N |
| ENC-038 | Thai | TIS-620 (`tis-620`) | Thai codepage | `kCFStringEncodingThaiWindows` (verify exact TIS-620 vs Windows-874 distinction) | M | N |
| ENC-039 | Turkish | Windows-1254 (`windows-1254`) | Turkish Windows codepage | `kCFStringEncodingWindowsLatin5` | S | N |
| ENC-040 | Turkish | ISO 8859-9 (`latin5`) | Turkish ISO codepage | `kCFStringEncodingISOLatin5` | S | N |
| ENC-041 | Western European | Windows-1252 (`windows-1252`) | Western European Windows codepage — the most common "ANSI" default on US/EU Windows | `kCFStringEncodingWindowsLatin1` | S | E |
| ENC-042 | Western European | ISO 8859-1 (`latin1`) | Western European ISO/Latin-1 | `kCFStringEncodingISOLatin1` | S | I |
| ENC-043 | Western European | ISO 8859-15 (`Latin-9`) | Western European ISO w/ Euro sign | `kCFStringEncodingISOLatin9` | S | I |
| ENC-044 | Western European | OEM 437 (`IBM437/cp437`) | Original DOS US codepage | `kCFStringEncodingDOSLatinUS` | S | N |
| ENC-045 | Western European | OEM 850 (`IBM850/cp850`) | DOS Western European codepage | `kCFStringEncodingDOSLatin1` | S | N |
| ENC-046 | Western European | OEM 858 (`IBM858/cp858`) | DOS Western European w/ Euro | No CF constant — ICU (`ibm-858`) required | M | N |
| ENC-047 | Western European | OEM 860 (`IBM860/cp860`) : Portuguese | DOS Portuguese codepage | No CF constant — ICU (`ibm-860`) required | L | N |
| ENC-048 | Western European | OEM 861 (`IBM861/cp861`) : Icelandic | DOS Icelandic codepage | No CF constant — ICU (`ibm-861`) required | L | N |
| ENC-049 | Western European | OEM 862 (`IBM862/cp862`) : Hebrew | DOS Hebrew codepage | No CF constant — ICU (`ibm-862`) required | L | N |
| ENC-050 | Western European | OEM 863 (`IBM863/cp863`) : French Canadian | DOS French-Canadian codepage | No CF constant — ICU (`ibm-863`) required | L | N |
| ENC-051 | Western European | OEM 737 (`IBM737/cp737`) : Greek | (technically Greek-content but appears in NPP's Greek category) | No CF constant — ICU (`ibm-737`) required | L | N |
| ENC-052 | Greek | Windows-1253 (`windows-1253`) | Greek Windows codepage | `kCFStringEncodingWindowsGreek` | S | N |
| ENC-053 | Greek | ISO 8859-7 (`greek`) | Greek ISO codepage | `kCFStringEncodingISOLatinGreek` | S | N |
| ENC-054 | Hebrew | Windows-1255 (`windows-1255`) | Hebrew Windows codepage (manual flags this as commonly mis-autodetected) | `kCFStringEncodingWindowsHebrew` | S | I |
| ENC-055 | Hebrew | ISO 8859-8 (`hebrew`) | Hebrew ISO codepage | `kCFStringEncodingISOLatinHebrew` | S | N |
| ENC-056 | Arabic | ISO 8859-6 (`arabic`) | Arabic ISO codepage | `kCFStringEncodingISOLatinArabic` | S | N |
| ENC-057 | Vietnamese | Windows-1258 (`windows-1258`) | Vietnamese Windows codepage | `kCFStringEncodingWindowsVietnamese` | S | N |
| ENC-058 | (unassigned / dropped by upstream) | ISO 8859-10, 8859-11, 8859-16 | Present as commented-out/disabled `#define`s in `menuCmdID.h` and `{-1,""}` placeholder rows in `EncodingMapper.cpp` — **not actually available** in current Notepad++ builds despite being valid standards | Do not implement — matches upstream's own current omission, note as intentional non-parity | S | N |

**Aggregate note (ENC-014–058, 45 codepages total):** roughly half have a direct 1:1 `CFStringEncoding`/`NSStringEncoding` constant (cheap, S); the other half — mostly DOS/OEM codepages (720, 737, 775, 855, 858, 860–863) and KOI8-U, ISO-8859-13/14 — **have no Cocoa/Foundation equivalent at all** and require linking ICU (`libicucore.dylib`, already present in the OS, or bundled `icu4c`) and its named converters. This ICU dependency for legacy-codepage completeness is the single biggest "no clean macOS analogue" item in the entire Encoding menu.

### 2.4 Encoding auto-detection & the "ANSI" disabling edge case

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| ENC-059 | (automatic) | BOM-based detection | Files starting with a UTF-16 BOM or UTF-8 BOM are always decoded per the BOM, no matter other settings | Read first 2–4 bytes, match against known BOM signatures | S | E |
| ENC-060 | (automatic) | XML/HTML prolog/declaration encoding | `<?xml encoding="...">` / `<meta charset>` declarations override auto-detection for those file types | Parse first N bytes for declaration before full decode | M | I |
| ENC-061 | Settings > Preferences > MISC | `☐ Autodetect character encoding` | If enabled, statistically analyzes byte patterns (heuristic charset sniffing, e.g. via `uchardet`-style analysis) to guess encoding when no BOM/declaration is present | Port or vendor a charset-detection library (ICU's `ucsdet`, or `uchardet`); ship as opt-out per this checkbox, mirroring NPP's own community complaint that it's sometimes wrong (esp. Hebrew) | L | I |
| ENC-062 | (automatic fallback chain) | ASCII/UTF-8-valid fallback, then locale-based fallback | If nothing else applies: pure-ASCII → chosen ANSI/UTF-8 per New-Document setting; else valid-UTF-8-byte-sequence → UTF-8; else falls back to system locale's legacy encoding or "ANSI" | Same fallback chain, with macOS's "locale legacy encoding" being ill-defined (see ENC-001) — must pick an explicit NotepadXX default (Windows-1252 recommended for cross-platform file compatibility) | M | E |
| ENC-063 | Settings > Preferences > New Document | `☐ Apply to opened ANSI files` (under UTF-8) | Auto-"upgrades" ANSI-detected files to UTF-8 on open | Preference toggle on the decode pipeline | S | I |
| ENC-064 | (Windows-OS-level interaction, v8.8.8+) | "Use Unicode UTF-8 for worldwide language support" disables ANSI/Convert-to-ANSI | When the *Windows OS* (not NPP) has this system setting on, system codepage becomes UTF-8, and NPP grays out `ANSI`/`Convert to ANSI` because "ANSI" has no coherent meaning anymore | **This entire Windows Control-Panel setting has no macOS analogue** — macOS is always UTF-8/Unicode at the OS layer, so NotepadXX's "ANSI"/legacy-fallback concept should probably be permanently a distinct, always-available "Legacy encoding" picker rather than something that can be silently disabled by an OS toggle | N/A (no OS-level toggle to mirror) | N |
| ENC-065 | (internal editing model) | In-buffer editing encoding | NPP edits ANSI/UTF-8 documents in their native encoding, but internally re-represents UTF-16 and Character-Set-encoded documents as UTF-8 while editing, transcoding on load/save | Simplify: keep a single canonical in-memory `String` (UTF-16-backed Swift String) always, transcode on load/save for *every* encoding, no special-casing — cleaner than NPP's own mixed model | M | E |

---

## PART 3 — SETTINGS MENU

### 3.1 Settings menu — top-level items

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-001 | Settings > Preferences... | `IDM_SETTING_PREFERENCE` | Opens the multi-page Preferences dialog | macOS `Settings…`/`Preferences…` window (Cmd+,), the standard system-provided pattern | S | E |
| SET-002 | Settings > Style Configurator... | `IDM_LANGSTYLE_CONFIG_DLG` | Opens the theming dialog (see 3.3) | Custom preferences tab or dedicated window | L | E |
| SET-003 | Settings > Shortcut Mapper... | `IDM_SETTING_SHORTCUT_MAPPER` | Opens the 5-tab keybinding editor (see 3.4) | Custom window; note macOS convention is normally System Settings > Keyboard > App Shortcuts (far less granular — NPP's Scintilla-level remapping has no macOS system equivalent) | L | I |
| SET-004 | Settings > Import > Import Plugins... | `IDM_SETTING_IMPORTPLUGIN` | Copies a plugin DLL into the plugins folder for load on next launch | macOS: copy a signed/notarized `.bundle`/`.appex` into `~/Library/Application Support/NotepadXX/Plugins/`; Gatekeeper/notarization adds friction Windows DLL-drop doesn't have | M | N |
| SET-005 | Settings > Import > Import Style Themes... | `IDM_SETTING_IMPORTSTYLETHEMES` | Copies a theme XML file into the themes folder | Copy a theme file (own format or NPP-XML-compatible) into app-support themes dir | S | N |
| SET-006 | Settings > Preferences (General) | `☐ Enable trayicon` | Puts app icon in the Windows system tray | **No literal tray on macOS** — closest analogue is an `NSStatusItem` in the menu bar; behaviorally different UX convention (macOS apps don't typically "minimize to tray") | M | N |
| SET-007 | Settings > Remember current session for next launch | `IDM_SETTING_REMEMBER_LAST_SESSION` (mirrors Backup pref) | Toggles session persistence | `NSDocumentController` restorable state / custom session store | S | I |
| SET-008 | Settings > Edit Popup ContextMenu... | `IDM_SETTING_EDITCONTEXTMENU` | Opens `contextMenu.xml` for manual editing of the right-click editor context menu | No Windows-XML-editing equivalent needed — expose an in-app "Customize context menu" list editor instead of raw-file editing, or support editing a plist/JSON equivalent directly | M | N |
| SET-009 | Settings > Open Plugins Folder... | `IDM_SETTING_OPENPLUGINSDIR` | Reveals plugins folder in Explorer | Reveal in Finder | S | N |
| SET-010 | Settings > Plugins Admin... | `IDM_SETTING_PLUGINADM` | Opens the plugin marketplace/manager | Custom in-app plugin browser (would need NotepadXX's own plugin registry/CDN — no equivalent central repo exists yet) | L | N |

### 3.2 Preferences dialog — all pages and controls

#### General
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-011 | Preferences > General | Localization pulldown | Selects UI language; copies chosen XML to `nativeLang.xml`; requires re-selecting after editing a localization file | macOS: use native `.strings`/`.xcstrings` localization + system language, OR a lightweight in-app language override for parity with power users who override OS locale | M | N |
| SET-012 | Preferences > General > Menu | `☐ Hide menu bar (Alt/F10 to toggle)` | Hides the Win32 menu bar; togglable via Alt/F10 | **macOS apps cannot hide the global menu bar** (it's owned by the OS, not the app window) — this entire feature has no macOS equivalent; closest analogue is a distraction-free/full-screen mode | N/A | N |
| SET-013 | Preferences > General > Menu | `☐ Hide right shortcuts + ▼ ✕` | Hides the +/▼/✕ icons at the right of the menu bar | N/A (menu-bar icons are a Win32-menu-bar-specific affordance); map instead to toolbar button visibility toggles | N/A | N |
| SET-014 | Preferences > General > Status bar | `☐ Hide` | Hides the bottom status bar | `NSView.isHidden` on a bottom status bar | S | I |
| SET-015 | Preferences > General > Document List Panel | `☐ Show` (moved to View menu in modern versions) | Toggles the open-files list panel | Sidebar panel visibility toggle | S | I |

#### Toolbar
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-016 | Preferences > Toolbar | `☐ Hide` | Hides the icon toolbar | `NSWindow.toolbar = nil` toggle, or native "Customize Toolbar" hide affordance | S | I |
| SET-017 | Preferences > Toolbar | Icon style radio (Fluent small/large, Filled Fluent small/large, Standard small) | Selects toolbar icon set | Use native SF Symbols with size variants instead of shipping 5 bespoke icon families — simplifies vs. porting Fluent UI assets | S | N |
| SET-018 | Preferences > Toolbar > Colorization | `☐ Complete` / `☐ Partial` + color choice (Default/System Accent/Custom) | Recolors toolbar icon foreground | macOS: `NSColor.controlAccentColor` gives "System Accent" for free; Custom via `NSColorPanel` | S | N |
| SET-019 | Preferences > Toolbar | System Accent hover-help | Explains how to change OS accent color | Point to System Settings > Appearance | S | N |

#### Tab Bar
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-020 | Preferences > Tab Bar | `☐ Hide` | Hides the document tab bar | `NSWindow.tabbingMode`/custom tab strip visibility | S | I |
| SET-021 | Preferences > Tab Bar > Behavior | `☐ Vertical` | Tabs render on the left side instead of top | Custom vertical tab strip (native `NSWindow` tabs are always horizontal — must build custom tab bar to support this) | M | N |
| SET-022 | Preferences > Tab Bar > Behavior | `☐ Multi-line` | Tabs wrap to a 2nd row when too many | Custom tab bar layout logic | M | N |
| SET-023 | Preferences > Tab Bar > Behavior | `☐ Lock (no drag and drop)` | Disables tab reordering | Disable drag gesture recognizer | S | N |
| SET-024 | Preferences > Tab Bar > Behavior | `☐ Double click to close document` | Double-click on tab closes it | Gesture handler | S | I |
| SET-025 | Preferences > Tab Bar > Behavior | `☐ Exit on close the last tab` | Quits app when last tab closes | Custom app-lifecycle hook (macOS convention is normally NOT to quit on last window close — flag as a deliberate NPP-parity deviation from platform HIG) | S | N |
| SET-026 | Preferences > Tab Bar > Behavior | `Max. tab label length` (0=unlimited) | Truncates tab titles to N chars + ellipsis | Tab title string-truncation logic | S | N |
| SET-027 | Preferences > Tab Bar > Look & Feel | `☐ Reduce` | Smaller tab region/font | Style variant toggle | S | N |
| SET-028 | Preferences > Tab Bar > Look & Feel | `☐ Alternate icons` | Swaps colored-disk save-state icons for checkmark/pencil/lock symbols (accessibility-oriented) | Custom tab status-icon set; genuinely useful a11y feature worth keeping | S | N |
| SET-029 | Preferences > Tab Bar > Look & Feel | `☐ Change inactive tab color` | Uses Style-Configurator "Inactive Tabs" background for unfocused tabs | Custom tab styling bound to theme | S | N |
| SET-030 | Preferences > Tab Bar > Look & Feel | `☐ Draw a coloured bar on active tab` | Colored accent bar on active tab | Custom tab decoration | S | N |
| SET-031 | Preferences > Tab Bar > Look & Feel | `☐ Show close button` | Per-tab close (×) button | Standard on macOS tabs already (`NSWindow` native tabs show this) — cheap to match | S | I |
| SET-032 | Preferences > Tab Bar > Look & Feel | `☐ Enable pin tab feature` + `☐ Show only pinned button` | Pin tabs to prevent accidental close/reorder-out | Custom tab-pin state + UI | M | N |
| SET-033 | Preferences > Tab Bar > Look & Feel | `☐ Show buttons on inactive tabs` | Always-visible vs. hover-only close/pin buttons | Hover-state UI logic | S | N |

#### Editing 1
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-034 | Preferences > Editing 1 | Current Line Indicator: None / Highlight Background / Frame (+Width slider) | Controls how the caret's line is emphasized | Custom `NSTextView` line-background/frame drawing (Cocoa doesn't do this natively) | M | I |
| SET-035 | Preferences > Editing 1 | Caret Width pulldown (1/2/3/0/Block/Block After) | Sets caret shape/width | `NSTextView` caret customization (block-caret requires custom insertion-point drawing, not default Cocoa behavior) | M | I |
| SET-036 | Preferences > Editing 1 | Caret Blink Rate slider | Adjusts blink speed | Custom timer-driven blink vs. macOS system blink rate (`NSTextInsertionIndicator` uses system setting by default — must override) | S | N |
| SET-037 | Preferences > Editing 1 | Line Wrap: Default/Aligned/Indent | Controls wrap-continuation indentation style | Custom `NSLayoutManager`/TextKit 2 line-fragment indent logic | M | I |
| SET-038 | Preferences > Editing 1 | `☐ Enable smooth font` | Windows font-smoothing toggle | N/A — macOS text rendering (Core Text/CoreGraphics) is always anti-aliased; no equivalent toggle needed | N/A | N |
| SET-039 | Preferences > Editing 1 | `☐ Enable virtual space` | Allows caret past line end | Custom `NSTextView` virtual-space caret positioning (not native) | M | I |
| SET-040 | Preferences > Editing 1 | `☐ Make current level folding/unfolding commands toggleable` | Fold command toggles instead of one-way | Fold-controller flag | S | N |
| SET-041 | Preferences > Editing 1 | `☐ Enable scrolling beyond last line` | Allows scrolling a page past EOF | Custom scroll-content-inset | S | N |
| SET-042 | Preferences > Editing 1 | `☐ Keep selection when right-click outside of selection` | Prevents right-click from clearing selection | Custom event handling (default `NSTextView` right-click behavior differs) | S | N |
| SET-043 | Preferences > Editing 1 | `☐ Enable Copy/Cut Line without selection` | Whole-line copy/cut when nothing selected | Custom key-command logic | S | I |
| SET-044 | Preferences > Editing 1 | `☐ Apply custom color to selected text foreground` | Lets selection foreground color be themed, not just background | Custom `NSTextView` selection-attribute override (Cocoa selection color is normally system-controlled) | M | N |
| SET-045 | Preferences > Editing 1 | `☐ Disable advanced scrolling feature (touchpad)` | Workaround for touchpad scroll bugs | Likely unnecessary on macOS (native trackpad scrolling is first-class) — candidate to omit entirely | N/A | N |
| SET-046 | Preferences > Editing 1 | `☐ Disable selected text drag-and-drop` | Disables drag-to-move selected text | Disable drag gesture on selection | S | N |

#### Editing 2
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-047 | Preferences > Editing 2 > Multi-Editing | `☐ Enable Multi-Editing (Ctrl+Mouse Click)` | Multiple simultaneous non-contiguous carets | Multi-cursor editing (map Ctrl+Click → Cmd+Click per macOS convention); needs custom multi-caret `NSTextView` subclass (not native) | L | E |
| SET-048 | Preferences > Editing 2 > Multi-Editing | `☐ Enable Column Selection to Multi-Editing` | Converts column/box selection into multi-caret selection | Extends multi-caret engine to block-selection mode | M | I |
| SET-049 | Preferences > Editing 2 | EOL rendering: Default / Plain Text / Custom Color | How CR/LF/CRLF glyphs render when "Show End of Line" is on | Custom glyph rendering for EOL markers, theme-bound color | M | N |
| SET-050 | Preferences > Editing 2 | Non-Printing Characters: Abbreviation / Codepoint / Custom Color | How control chars/NBSP etc. render when shown | Custom glyph rendering | M | N |
| SET-051 | Preferences > Editing 2 | `☐ Apply to C0, C1 & Unicode EOL` | Extends NPC rendering to control codes + U+2028/U+2029 | Extend the same rendering rule set | S | N |
| SET-052 | Preferences > Editing 2 | `☐ Prevent control character (C0 code) typing into document` | Blocks Ctrl+letter combos from inserting raw control bytes | Key-event filter | S | N |

#### Dark Mode
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-053 | Preferences > Dark Mode | `☐ Dark Mode` / `☐ Light Mode` / `☐ Follow Windows` | Sets app-wide light/dark/system-follow theme | **macOS has first-class native Dark Mode** (`NSAppearance`) — this is actually *easier* to implement well on macOS than on Windows; "Follow Windows" → "Follow System" via `NSApp.appearance = nil` | S | E |
| SET-054 | Preferences > Dark Mode | Theme auto-switch on mode change (remembers separate theme per mode) | Switching Dark/Light also swaps active Style Configurator theme | Store separate theme preference per `NSAppearance.Name` | S | I |
| SET-055 | Preferences > Dark Mode > Tones | Black/Red/Green/Blue/Purple/Cyan/Olive preset tones | Recolors dark-mode chrome with a tint | Custom accent-tinted dark palette presets | M | N |
| SET-056 | Preferences > Dark Mode > Tones | `☐ Customized` + 12 individual component color pickers (Top, Menu hot track, Active, Main, Error, Text, Darker text, Disabled text, Link, Edge, Edge highlight, Edge disabled) | Full manual control of every dark-chrome color, with a Reset-to-preset button | Custom theming system w/ 12 semantic color slots; macOS `NSColor` dynamic-provider pattern is a clean fit here | L | N |

#### Margins/Border/Edge
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-057 | Preferences > Margins/Border/Edge | Fold Margin Style: Simple/Arrow/Circle tree/Box tree/None | Selects fold-gutter glyph style | Custom gutter glyph rendering (5 style variants) | M | N |
| SET-058 | Preferences > Margins/Border/Edge | Border Width slider + `☐ No edge` | Editor pane sunken-border thickness | Custom `NSView` border drawing (macOS doesn't do "sunken" borders natively — flat/vibrancy is the platform norm; consider simplifying to a plain hairline) | S | N |
| SET-059 | Preferences > Margins/Border/Edge | Vertical Edge(s): multi-column text field, `☐ Background mode` | One or more vertical ruler lines/backgrounds at given columns | Custom text-view column-guide overlay (common editor feature, e.g. "ruler at 80 chars") | M | I |
| SET-060 | Preferences > Margins/Border/Edge | Legacy single-edge controls (Show/Line mode/Background mode/Number of columns) | Older single-column-guide UI, superseded by multi-edge above | Superseded — implement only the multi-edge version | S | N |
| SET-061 | Preferences > Margins/Border/Edge > Change History | `☐ Show in the margin` / `☐ Show in the text` | Shows git-blame-style modified/saved/reverted markers in gutter and/or as text background | Custom in-memory diff-vs-last-save tracking + gutter/background rendering (no Cocoa built-in) | L | I |
| SET-062 | Preferences > Margins/Border/Edge > Line Number | `☐ Display` + `☐ Dynamic width` / `☐ Constant width` | Line-number gutter visibility and width behavior | Custom line-number gutter view | M | E |
| SET-063 | Preferences > Margins/Border/Edge > Padding | Left / Right / Distraction Free pixel sliders | Text-inset padding, incl. separate value for distraction-free mode | `NSTextContainer` inset configuration | S | N |
| SET-064 | Preferences > Margins/Border/Edge | `☐ Display bookmark` | Shows bookmark gutter with circle markers + hidden-line brackets | Custom bookmark gutter + folding-bracket glyphs | M | N |

#### New Document
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-065 | Preferences > New Document | Format: Windows (CRLF) / Unix (LF) / Macintosh (CR) | Default EOL style for new files | Default should be LF on macOS (matches modern macOS/Unix convention) but must still support CRLF/CR for parity with cross-platform files | S | E |
| SET-066 | Preferences > New Document | Encoding: ANSI/UTF-8/UTF-8-BOM/UTF-16BE/UTF-16LE + `☐ Apply to opened ANSI files` + Character-Set dropdown | Default encoding for new documents | Same encoding engine as Part 2; default should be UTF-8 no-BOM per Unix convention | S | E |
| SET-067 | Preferences > New Document | Default Language pulldown | Syntax highlighting applied to new/undetectable files (UDLs excluded from this list) | Bound to language table from Part 1 | S | I |
| SET-068 | Preferences > New Document | `☐ Always open a new document in addition at startup` | Always spawns a blank tab at launch alongside session/CLI files | App-launch logic flag | S | N |
| SET-069 | Preferences > New Document | `☐ Use the first line of document as untitled tab name` | Names "Untitled" tabs from first line of content instead of "new N" | Tab-title derivation logic | S | N |

#### Default Directory
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-070 | Preferences > Default Directory | Follow current document / Remember last used / Fixed browse path | Determines default folder for Open/Save panels | `NSOpenPanel`/`NSSavePanel` `directoryURL` logic | S | I |
| SET-071 | Preferences > Default Directory | `☐ Open all files of folder instead of launching Folder as Workspace on folder dropping` | Drag-a-folder behavior toggle | Custom drag-and-drop handler branch | S | N |

#### Recent Files History
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-072 | Preferences > Recent Files History | `☐ Don't check at launch time` | Skips existence-check of recent files on startup (useful for flaky network drives) | Skip `FileManager.fileExists` check at launch | S | N |
| SET-073 | Preferences > Recent Files History | `Max number of entries` | Caps recent-files list length | Could largely defer to native `NSDocumentController` recent-documents list, which already handles most of this on macOS | S | I |
| SET-074 | Preferences > Recent Files History | `☐ In Submenu` | Nests recent files under a submenu vs. flat in File menu | Menu-structure toggle | S | N |
| SET-075 | Preferences > Recent Files History | `☐ Only File Name` / `☐ Full File Name Path` / `☐ Customize Maximum Length` | Display format for each recent-file entry | Menu-item title formatting | S | N |

#### File Association
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-076 | Preferences > File Association | Two-column mover (filetype → extension → registered) | Registers NPP as the default handler for chosen extensions; **requires Admin mode** since it writes the Windows Registry | **No registry on macOS.** File-type ownership is declared via `Info.plist` `CFBundleDocumentTypes`/`UTExportedTypeDeclarations` at build time, and *default handler per user* is set via Launch Services (`LSSetDefaultRoleHandlerForContentType`, or the `duti` CLI pattern, or System Settings > right-click file > Get Info > Open With > Change All). No admin privileges required, but also **no live "claim these extensions" UI inside the app is idiomatic** — must build a custom in-app panel that shells out to Launch Services APIs, which is a real UX gap vs. NPP's built-in mover UI | L | I |

#### Language (preferences page)
Covered in section 1.2 (LANG-097–099).

#### Indentation
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-077 | Preferences > Indentation | Per-language selector ([Default], normal, + each language) | Chooses which language's indent settings are being edited | List-driven settings panel bound to language table | S | I |
| SET-078 | Preferences > Indentation | `☐ Use default value` (non-Default languages only) | Inherits [Default]'s indent settings instead of overriding | Inheritance flag per language | S | I |
| SET-079 | Preferences > Indentation | `Indent size` | Tab-stop width in columns | Per-language int setting | S | E |
| SET-080 | Preferences > Indentation | Indent Using: Space character(s) / Tab character | Whether Tab key inserts spaces or a literal tab | Per-language enum setting | S | E |
| SET-081 | Preferences > Indentation | `☐ Backspace key unindents instead of removing single space` | Backspace jumps to previous tab stop instead of deleting 1 char | Custom backspace-key handling logic | S | I |
| SET-082 | Preferences > Indentation | Auto-indent: None / Basic / Advanced | Controls Enter-key indent carry-over/brace-aware indenting | Custom indent engine (Basic = simple carry current indent; Advanced = brace/block-aware, needs per-language rules) | L | I |

#### Highlighting
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-083 | Preferences > Highlighting > Style All Occurrences of Token | `☐ Match case` / `☐ Match whole word only` | Controls "Mark All"/token-styling match rules | Search-matching config, shared logic w/ Find | S | I |
| SET-084 | Preferences > Highlighting > Smart Highlighting | `☐ Enable` / `☐ Highlight another view` / `☐ Match case` / `☐ Match whole word only` / `☐ Use Find dialog settings` | Auto-highlights all occurrences of the selected text as you select it | Custom live-highlight-on-selection engine (not a Cocoa built-in) | M | I |
| SET-085 | Preferences > Highlighting > Highlight Matching Tags | `☐ Enable` / `☐ Highlight tag attributes` / `☐ Highlight comment/php/asp zone` | HTML/XML open/close tag pair highlighting on caret position | Tag-matching engine tied to the HTML/XML lexer | M | I |

#### Print
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-086 | Preferences > Print | Color Options: WYSIWYG / Invert / Black on White / No background color | Controls print color rendering mode | Custom `NSPrintOperation` color-transform pass | M | N |
| SET-087 | Preferences > Print | Margin Setting (mm) | Page margins for printing | `NSPrintInfo` margin properties | S | N |
| SET-088 | Preferences > Print | Header/Footer: Left/Middle/Right parts + variable picker (`$(FULL_CURRENT_PATH)`, `$(FILE_NAME)`, `$(CURRENT_DIRECTORY)`, `$(CURRENT_PRINTING_PAGE)`, `$(SHORT_DATE)`, `$(LONG_DATE)`, `$(TIME)`) + font/size | Configurable print header/footer template with variable substitution | Custom print-template renderer w/ same variable set | M | N |
| SET-089 | Preferences > Print | `☐ Print line number` | Includes line numbers on printed pages | Print-time gutter rendering | S | N |
| SET-090 | Preferences > Print | `☐ Print formfeed as page break` | Treats `FF` (0x0C) char as an explicit page break | Custom pagination logic honoring `\f` | S | N |

#### Searching
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-091 | Preferences > Searching | `Minimum Size for Auto-Checking 'In selection'` (0–1024) | Auto-toggles "In Selection" search scope based on selection size | Custom Find-dialog auto-scope logic | S | N |
| SET-092 | Preferences > Searching | `☐ Fill Find Field with Selected Text` + `Max Characters to Auto-Fill` | Pre-fills Find field from current selection | Standard behavior for most macOS find bars (`NSTextFinder` already does similar) — cheap win | S | I |
| SET-093 | Preferences > Searching | `☐ Select Word Under Caret when Nothing Selected` | Pre-fills Find field from word at caret if no selection | Word-boundary detection at caret | S | I |
| SET-094 | Preferences > Searching | `☐ Fill Find in Files Directory Field Based On Active Document` | Auto-populates Find-in-Files directory from active doc's folder | Directory-field default logic | S | N |
| SET-095 | Preferences > Searching | `☐ Use Monospaced font in Find dialog` | Switches Find dialog textboxes to monospace | Font override on find-panel fields | S | N |
| SET-096 | Preferences > Searching | `☐ Find dialog remains open after search that outputs to results window` | Keeps Find window open post-search | Panel-dismissal logic branch | S | N |
| SET-097 | Preferences > Searching | `☐ Confirm Replace All in All Opened Documents` | Adds confirmation prompt before global replace-all | Confirmation alert | S | N |
| SET-098 | Preferences > Searching | `☐ Replace: Don't move to the following occurrence` | Keeps caret at replaced text instead of jumping to next match | Replace-flow caret logic | S | N |
| SET-099 | Preferences > Searching | `☐ Search Result window: show only one entry per found line` | Collapses multiple same-line matches to one results entry | Results-list dedup logic | S | N |
| SET-100 | Preferences > Searching | `☐ Find in Files: Ignore unsaved changes in opened files` | Searches on-disk content instead of unsaved in-memory buffers | Search-source selection logic | S | N |

#### Backup
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-101 | Preferences > Backup | `☐ Remember current session for next launch` | Restores open-file list on next launch | `NSDocumentController` restorable-state / custom session store | S | I |
| SET-102 | Preferences > Backup | `☐ Enable session snapshot and periodic backup` (+ directory) | Auto-saves unsaved changes to a backup dir every N seconds, enabling crash recovery without prompting to save on exit | Analogous to macOS's own Auto Save/Versions (`NSDocument` autosaving-in-place) — but NPP's model (backup file, not silent overwrite) is closer to a custom "draft" store; recommend leaning on `NSDocument` autosave with a custom draft folder to match semantics | M | I |
| SET-103 | Preferences > Backup | `☐ Remember inaccessible files from past session` | Session remembers files even if they've vanished from disk | Session-store tolerance for missing files | S | N |
| SET-104 | Preferences > Backup | Backup on save: None / Simple / Verbose + `☐ Custom Backup Directory` | Simple = one `.bak` per file overwritten each save; Verbose = timestamped `.bak` per save; both optionally redirected to a single custom folder | Custom backup-on-save pipeline (not the same as macOS Versions/Time Machine — must implement independently since it needs to work even without those enabled) | M | I |

#### Auto-Completion
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-105 | Preferences > Auto-Completion | `☐ Enable auto-completion on each input` + Function/Word/Function-and-word radio | Live completion popup as you type | Custom completion-popup engine (Cocoa's built-in `NSTextView` completion is far more limited — needs a bespoke implementation) | L | I |
| SET-106 | Preferences > Auto-Completion | `From nth character` | Min chars typed before completion triggers | Completion-trigger threshold | S | I |
| SET-107 | Preferences > Auto-Completion | `☐ Ignore numbers` | Skips completion while typing numeric literals | Token-type check in completion trigger | S | N |
| SET-108 | Preferences > Auto-Completion | Insert Selection: `☐ TAB` / `☐ ENTER` | Which keys accept the highlighted completion | Completion-popup key handling | S | N |
| SET-109 | Preferences > Auto-Completion | `☐ Make auto-completion list brief` | List shrinks to match typed prefix vs. staying full-size | Completion-list filtering behavior | S | N |
| SET-110 | Preferences > Auto-Completion | `☐ Function parameters hint on input` | Shows parameter-hint tooltip while typing a call | Signature-help popup (needs per-language function signature data source) | L | N |
| SET-111 | Preferences > Auto-Completion > Auto-Insert | `☐ ()` `☐ []` `☐ {}` `☐ ""` `☐ ''` `☐ html/xml close tag` + 3 custom matched pairs | Auto-inserts closing bracket/quote/tag on typing the opener | Custom paired-insertion logic (Cocoa has none built in) | M | I |

#### Multi-Instance and Date
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-112 | Preferences > Multi-Instance and Date | Default (mono-instance) / Always multi-instance / Open session in new instance | Controls whether opening files from the OS reuses the running app instance or spawns new ones | **Fundamentally different app models.** macOS apps are single-process-multi-window by default (`NSDocumentController` handles "open in existing app, new window" natively) — true independent-process "multi-instance" (separate Dock icons, separate unsynced preferences) requires deliberately launching multiple copies of the app bundle, which macOS actively discourages and code-signing/sandboxing complicates. Recommend: support "new window" as the default macOS-native behavior and treat literal multi-process instancing as an explicit, lower-priority power-user feature | L | N |
| SET-113 | Preferences > Multi-Instance and Date | Panel State and [-nosession] checkboxes (Clipboard History, Document List, Character Panel, Folder as Workspace, Project Panels, Document Map, Function List, Plugin panels) | Per-panel toggle for whether panel visibility persists across `-nosession` / multi-instance launches | Per-panel persisted-visibility flags | S | N |
| SET-114 | Preferences > Multi-Instance and Date | `☐ Reverse default date time order` | Swaps date/time order in Insert-Date-Time output | Date-format string flag | S | N |
| SET-115 | Preferences > Multi-Instance and Date | Custom Format field (d/dd/ddd/dddd, M/MM/MMM/MMMM, y/yy/yyyy, h/hh/H/HH, m/mm, s/ss, t/tt tokens) | User-defined date/time insertion format string | Port the same token vocabulary onto `DateFormatter` (needs a translation layer since ICU/`DateFormatter` pattern letters mostly but not 100% match NPP's Win32-`GetDateFormat`-derived tokens — e.g. `g`/`gg` era tokens need special-casing) | M | N |

#### Delimiter
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-116 | Preferences > Delimiter | `☐ Use default Word character list as it is` | Uses Unicode-alphanumeric+underscore as "word" boundary definition | `CharacterSet.alphanumerics` + underscore, Unicode-aware by default | S | I |
| SET-117 | Preferences > Delimiter | `☐ Add your character as part of word` (free-text field) | Extends the word-character set with custom chars | Custom `CharacterSet` union | S | N |
| SET-118 | Preferences > Delimiter | Open/close delimiter pair fields + `☐ Allow on several lines` | Defines Ctrl+DoubleClick "select everything inside these delimiters" behavior | Custom double-click delimiter-scan logic (map Ctrl → Cmd on macOS) | M | N |

#### Performance
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-119 | Preferences > Performance | `☐ Enable Large File Restriction` + `Define Large File Size (MB)` | Disables expensive features above a size threshold | Size-gated feature-flag system | M | I |
| SET-120 | Preferences > Performance | `☐ Deactivate Word Wrap globally` | Force-disables wrap app-wide when a large file opens | Global wrap-state override triggered by large-file open | S | N |
| SET-121 | Preferences > Performance | `☐ Allow Auto-completion` / `☐ Allow Smart Highlighting` / `☐ Allow Brace Match` / `☐ Allow URL Clickable Link` | Per-feature opt-back-in for large files | Feature-flag exceptions under the large-file gate | S | N |

#### Cloud & Link
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-122 | Preferences > Cloud & Link | `☐ No Cloud` / `☐ Set your cloud location path here` | Redirects all config-file storage from `%AppData%` to a chosen (typically cloud-synced) folder, so settings roam via Dropbox/OneDrive/etc. | **macOS has a much more natural fit here**: default to `~/Library/Application Support/NotepadXX/`, and let this setting instead point at `~/Library/Mobile Documents/...` (iCloud Drive) or any Dropbox/etc. folder — same net effect, cleaner platform story since there's no registry entanglement to work around | S | I |
| SET-123 | Preferences > Cloud & Link > Clickable Link Settings | `☐ Enable` / `☐ No underline` / `☐ Enable fullbox mode` / `URI Customized Schemes` | Makes URL-shaped text clickable to open in default browser; schemes `ftp/http/https/mailto/file` always recognized, extra schemes configurable | `NSDataDetector` (`.link` type) does most of this natively on macOS — significant implementation shortcut vs. NPP's hand-rolled URL matcher | S | I |

#### Search Engine
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-124 | Preferences > Search Engine | Preset dropdown: DuckDuckGo / Google / Bing / Yahoo! + custom URL w/ `$(CURRENT_WORD)` placeholder | Backs the "Search on Internet" command (Edit > On Selection, or right-click) | Store as a URL template, substitute selected/caret word, `NSWorkspace.shared.open` | S | N |

#### MISC.
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-125 | Preferences > MISC > Document Switcher | `☐ Enable` / `☐ Enable MRU behavior` | Ctrl+Tab document switcher popup, optionally most-recently-used ordered | Custom switcher UI (map Ctrl+Tab → Cmd+`\`` per macOS convention, being mindful of the system's own Cmd+`\`` window-switch binding) | M | I |
| SET-126 | Preferences > MISC > Document Peeker | `☐ Peek on tab` / `☐ Peek on document map` | Hover-preview of inactive tabs | Custom hover-preview popover (loosely analogous to macOS Quick Look, but must be built bespoke for in-app tabs) | M | N |
| SET-127 | Preferences > MISC > File Status Auto-Detection | Enable / Enable for all open files / Disable + `☐ Update silently` + `☐ Scroll to last line after update` | Watches open files for external changes and reloads/prompts | `DispatchSource.makeFileSystemObjectSource` (FSEvents-based) file-change watcher | M | I |
| SET-128 | Preferences > MISC | System Tray dropdown: No action / Minimize to tray / Close to tray / Minimize+Close to tray | Controls tray-icon-on-minimize/close behavior | No tray on macOS — map at most to "hide in Dock" via `NSStatusItem`, but this is a fundamentally Windows-specific UX pattern; recommend omitting rather than force-fitting | N/A | N |
| SET-129 | Preferences > MISC | DirectWrite rendering mode dropdown (GDI / DirectWrite default / retain frames / draw-to-GDI-DC / DirectX 11) | Selects Windows text-rendering backend, affects ligature support | **N/A on macOS** — Core Text is the only, always-available, always-ligature-capable text renderer; nothing to build, nothing to expose as a setting | N/A | N |
| SET-130 | Preferences > MISC | Auto-updater dropdown: Disable / Enable on Startup / Enable on Exit | Controls background update-check timing | Sparkle framework (the de facto macOS auto-update solution) covers this, or Mac App Store auto-updates if distributed that way | S | I |
| SET-131 | Preferences > MISC | `☐ Mute all sounds` | Silences feedback sounds (e.g., search-not-found beep) | `NSSound` gating flag | S | N |
| SET-132 | Preferences > MISC | `☐ Autodetect character encoding` | (Cross-referenced with Encoding section, ENC-061) | See ENC-061 | L | I |
| SET-133 | Preferences > MISC | `☐ Show only filename in title bar` | Title bar shows name only vs. full path | `NSWindow.title` vs. `representedURL`-derived path display (macOS titlebars conventionally show just the filename with a proxy icon anyway — natural fit) | S | N |
| SET-134 | Preferences > MISC | `☐ Enable Save All confirm dialog` | Confirms before Save All, with a "stop asking" option | Confirmation alert with a "don't ask again" checkbox that clears this same preference | S | N |
| SET-135 | Preferences > MISC | `Session file ext.` / `Workspace file ext.` | Custom extensions that, when opened, are treated as session/workspace files rather than edited as text | Extension-based dispatch in the file-open pipeline; on macOS this also needs a matching `UTExportedTypeDeclaration` so Launch Services routes double-clicks correctly | M | N |

#### Advanced/hidden preferences (config.xml-only, no UI)
| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-136 | (config.xml only) | `regexBackward4PowerUser="yes"` | Enables backward regex search (off by default; deemed unreliable enough to hide) | Equivalent hidden flag in a NotepadXX prefs plist/defaults domain (`defaults write`-style) | S | N |
| SET-137 | (config.xml only) | `nbMaxFindHistoryFind/Replace/Path/Filter` | Caps size of Find/Replace/Directory/Filter history dropdowns | Same, as hidden `UserDefaults` keys | S | N |
| SET-138 | (config.xml only) | `fifFilterFollowsDoc` | Auto-populates Find-in-Files filter from active doc's extension | Hidden flag | S | N |
| SET-139 | (config.xml only, pre-8.9.6.1) | `commandLineInterpreter` (e.g. force PowerShell instead of cmd for "Open Containing Folder > cmd") | Customizes which shell launches from File menu; removed upstream in 8.9.6.1 for security reasons | macOS equivalent: "Open in Terminal" launching user's `$SHELL` (zsh/bash) — note upstream itself deprecated this exact feature for security, so NotepadXX should not resurrect a config-file shell-override either | S | N |
| SET-140 | (config.xml only) | `darkTabUseTheme` / `lightTabUseTheme` / icon-set overrides | Whether tab colors follow the active theme's Style-Configurator colors, per light/dark mode independently | Hidden per-appearance-mode override flags | S | N |

### 3.3 Style Configurator

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-141 | Settings > Style Configurator > Select theme | Theme pulldown | Chooses the active named theme (bundled or imported XML) | Theme registry + picker; consider adopting NPP's `stylers.xml`/`themes/*.xml` schema directly for community-theme drop-in compatibility | M | I |
| SET-142 | Style Configurator > Language pulldown | Global Styles / any built-in or UDL language | Selects which style-scope is being edited | List-driven scope selector | S | I |
| SET-143 | Style Configurator > Style list | Per-language style/token list (e.g. Perl > INSTRUCTION WORD) | Selects the specific token class to restyle | Token-class list bound to the active lexer's style IDs | S | I |
| SET-144 | Style Configurator | `Default ext.` (read-only) / `User ext.` (editable) | Shows built-in extensions for the language, lets user add more (applies only to newly-opened files) | Per-language, per-theme extension override list | S | N |
| SET-145 | Style Configurator > Colour Style | Foreground/Background color boxes + right-click "inherit" (diagonal-stripe) toggle | Sets fg/bg per style, or explicitly inherits from Default Style | `NSColorWell` pair + tri-state inherit flag | S | I |
| SET-146 | Style Configurator > Font Style | Font name, size, Bold/Italic/Underline | Per-style font override (blank = inherit from Global Styles > Default Style) | Font picker + style-inherit-if-blank logic | S | I |
| SET-147 | Style Configurator | User-defined keywords box (per lexer/style, ~30,000-byte GUI limit, unlimited via manual XML edit) | Lets user add extra keywords to a given highlighting bucket, where the lexer supports it | Text field bound to lexer keyword-list injection; no hard byte cap needed in a modern implementation | S | N |
| SET-148 | Style Configurator | Save & Close / Cancel / `☐ Transparency` | Standard dialog actions + window-opacity toggle | Standard dialog buttons + `NSWindow.alphaValue` | S | N |
| SET-149 | Style Configurator > Global Styles | ~30 global style entries: Default style, Indent guideline, Brace highlight, Bad brace, Current line background, Selected text, Multi-selected text, Caret colour, Multi-edit carets, Edge colour, Line number margin, Bookmark margin, Change History margin/modified/revert-modified/revert-origin/saved, Fold/Fold active/Fold margin, White space symbol, Smart Highlighting, Find Mark Style, Find status (3 variants), Mark Style 1–5, Incremental highlight all, Tags match highlighting, Tags attribute, Active/inactive tab text+bg (+focused/unfocused indicators), Tab color 1–5 (light) + 1–5 (dark), URL hovered, Document map, EOL Custom Color, Non-printing chars Custom Color, Global override | Theme-wide fallback styles applied wherever a language-specific style doesn't override them | Full semantic color/token system with ~35 named slots — the single largest piece of styling surface area to port; each slot needs an explicit mapping to NotepadXX's rendering pipeline (many, like "Change History," also require their own tracked-state subsystem, see SET-061) | XL | E |
| SET-150 | Style Configurator > Global Styles > Global override | Per-attribute "Enable global xxx" checkboxes | Forces the override style's attributes onto literally everything, superseding all per-language styling | Master-override flag set, applied last in the style-resolution pipeline | S | N |
| SET-151 | Style Configurator > Search result styles | Search Header, File Header, Line Number, Hit Word, Current line background (5 styles) | Styles specific to the Find-in-Files results window, independent of language styles | 5 more named style slots for the results-pane renderer | S | I |
| SET-152 | (config file) `stylers.xml` / `themes/*.xml` | Manual XML editing of themes | Power-user path for style edits beyond the 30,000-byte GUI keyword limit, or for hand-crafting themes | Support a human-editable theme file format (JSON/plist, or NPP-XML-compatible) as an escape hatch alongside the GUI | M | N |

### 3.4 Shortcut Mapper

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-153 | Settings > Shortcut Mapper > Main menu tab | Remaps any File/Edit/Search/View/Encoding/Language/Settings/Run/Help menu command | Two-column Name/Shortcut list, filterable, with a Category column | Custom shortcut-editor UI (macOS System Settings > Keyboard > App Shortcuts can only rename-and-rebind *existing menu items by exact title* — far less flexible; NPP-parity requires a fully custom, in-app remapper) | L | I |
| SET-154 | Shortcut Mapper > Macros tab | Remaps shortcuts for user-recorded macros | Same list UI, scoped to Macros menu | Same custom remapper, macro-scoped | M | N |
| SET-155 | Shortcut Mapper > Run commands tab | Remaps shortcuts for user-added Run-menu entries | Same list UI, scoped to Run menu | Same custom remapper, Run-menu-scoped | M | N |
| SET-156 | Shortcut Mapper > Plugin commands tab | Remaps shortcuts for plugin-registered commands, w/ Plugin column | Same list UI + plugin-name column | Same custom remapper, plugin-scoped (depends on a plugin API existing at all) | M | N |
| SET-157 | Shortcut Mapper > Scintilla commands tab | Remaps low-level editor commands (cursor movement, selection, copy/paste, etc. — the `SCI_xxxx` message set), uniquely allows **multiple simultaneous shortcuts** per command via Add/Remove | Exposes internal text-engine commands for rebinding — most granular tier | **No equivalent concept on macOS** where basic text navigation is handled by system-wide `NSResponder` selectors/Text Editing key bindings (`~/Library/KeyBindings/DefaultKeyBinding.dict`), not a per-app remappable list; would need to enumerate NotepadXX's own internal editor-command set and build the same multi-shortcut-per-command UI from scratch | L | N |
| SET-158 | Shortcut Mapper (all tabs) | Filter field (multi-token, matches Name/Shortcut/Plugin/Category in any order) | Live-filters the shortcut list by typed substrings | Standard search-field + token-matching predicate | S | N |
| SET-159 | Shortcut Mapper (all tabs) | Conflict-detection message area | Flags when the selected shortcut collides with another command's binding | Conflict-check against the full keybinding table | S | I |
| SET-160 | Shortcut Mapper | Modify dialog: Ctrl/Alt/Shift checkboxes + key pulldown | Assigns/edits a shortcut for the selected command | Map Ctrl/Alt/Shift → Control/Option/Shift, note Cmd is the dominant macOS modifier (not a 1:1 semantic port — many Ctrl-based NPP defaults should remap to Cmd for platform-native feel, which is itself a design decision to flag to the team) | M | I |
| SET-161 | Shortcut Mapper | Clear / Delete buttons | Clear removes a shortcut; Delete (Macros/Run tabs only) removes the whole menu entry | Standard list-remove actions | S | N |
| SET-162 | (config file) `shortcuts.xml` | Manual XML editing of all shortcuts | Power-user escape hatch for bulk shortcut edits | Equivalent editable config format (JSON/plist) | S | N |

### 3.5 Import submenu & Edit Popup ContextMenu (recap, cross-referenced from 3.1)

| ID | Menu path | Command/Setting | Behavior | macOS equivalent/notes | Complexity | Tier |
|---|---|---|---|---|---|---|
| SET-163 | Settings > Import > Import Plugins... | (= SET-004) | — | — | M | N |
| SET-164 | Settings > Import > Import Style Themes... | (= SET-005) | — | — | S | N |
| SET-165 | Settings > Edit Popup ContextMenu... | (= SET-008) | — | — | M | N |
| SET-166 | Save Session dialog | `☐ Save Folder as Workspace` | Include/exclude active Folder-as-Workspace in a saved session | Session-serialization flag | S | N |
| SET-167 | Save As dialog | `☐ Append extension` | Auto-appends the chosen Save-As-type's extension to the filename | `NSSavePanel` extension-append behavior (largely handled natively by `NSSavePanel` already) | S | N |

---

## Cross-cutting Windows-concept-has-no-macOS-analogue flags (summary)

1. **"ANSI" / system default code page** (ENC-001, SET-...) — macOS has no single mutable system legacy codepage; requires inventing an explicit "legacy/fallback encoding" concept instead of mirroring Windows' ambient one.
2. **Registry-backed File Association with Admin-mode requirement** (SET-076) — macOS uses Launch Services + `Info.plist` UTIs, no admin needed, but also no live in-app "claim these extensions" GUI convention to copy.
3. **`%AppData%` / Cloud & Link settings-roaming path** (SET-122) — cleanly replaced by `~/Library/Application Support/` + optional iCloud Drive container, actually simpler than the Windows story.
4. **Multi-Instance semantics** (SET-112) — macOS's single-process/multi-window `NSDocumentController` model doesn't map to "always spawn a new OS process," which is what NPP's "Always multi-instance" literally does.
5. **System tray icon** (SET-006, SET-128) — no tray on macOS; `NSStatusItem` menu-bar icon is the nearest but behaviorally different (no "minimize to tray" convention).
6. **DirectWrite/GDI rendering-mode choice** (SET-129) — N/A; Core Text is the only renderer, nothing to expose as a setting.
7. **Hiding the menu bar** (SET-012/013) — macOS's global menu bar is OS-owned and cannot be hidden by an app.
8. **Scintilla-level command remapping (multiple shortcuts per low-level editor command)** (SET-157) — no `NSResponder`-selector-remapping UI convention exists to lean on; must be built as a fully bespoke system.
9. **Per-monitor DPI** — not mentioned as a distinct Preferences control in NPP (Windows handles this more automatically in modern versions too), and macOS's `NSScreen.backingScaleFactor` + resolution-independent drawing make this a non-issue by default — flagged as **no work needed**, not a gap.
10. **Legacy DOS/OEM codepages with no CFString/NSStringEncoding constant** (ENC-015, 019, 027, 030, 046–051) — CP720, CP775, CP855, CP858, CP860–863, CP737, KOI8-U, ISO-8859-13/14 all require linking ICU (`libicucore.dylib`) since Foundation has no built-in constant for them.
11. **Windows "Use Unicode UTF-8 for worldwide language support" OS toggle interaction** (ENC-064) — this Windows-Control-Panel-level setting that dynamically disables NPP's ANSI menu items has no macOS counterpart at all; macOS is unconditionally UTF-8 at the OS layer.
