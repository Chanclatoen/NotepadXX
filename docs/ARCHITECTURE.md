# NotepadXX Architecture

## Goal

A native macOS editor with functional parity to Notepad++. Not an MVP — the
parity matrices in `docs/parity/` enumerate ~884 user-visible commands, and the
project is not done until each is implemented or has a documented OS-level
justification for deviating.

## Text engine: CodeEditTextView

We build on [CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView)
(MIT), the text engine behind CodeEdit.

**Why not TextKit.** TextKit 2 has documented, Apple-acknowledged viewport
instability (`usageBoundsForTextContainer` is an estimate that changes
significantly during scroll — confirmed by an Apple DTS engineer on the developer
forums) and degrades badly past ~10k lines. TextKit 1 works but is what CotEditor
uses, and CotEditor beachballs on a 120MB file (their issue #1924, still open).
"Handles huge log files" is a top-3 reason people use Notepad++, so neither is
acceptable. CodeEditTextView is a custom `NSView` + Core Text engine over a
line-indexed red-black tree (`TextLineStorage`), the same architecture Runestone
arrived at independently.

**What we get for free:** multi-cursor (`setSelectedRanges`), rectangular/column
selection via Option+drag (`TextView+ColumnSelection.swift`, wired into
`mouseDragged`), the line index, and undo grouping. Column selection is the
single most-cited missing feature on macOS and nothing else in the Swift
ecosystem implements it — STTextView doesn't, and IBeam is pre-production.

What the engine does *not* provide is Notepad++'s **Column Editor** — batch
insertion of text or an incrementing number down a rectangular block. That lives
in `NotepadXXCore/ColumnSelection.swift`, which also exposes offset<->(line,
column) conversion and programmatic block-range computation. Short lines in a
ragged block collapse to an empty range at their end rather than being dropped,
so typing still affects every spanned line (Notepad++'s virtual-space
behaviour).

**What we do NOT depend on:** `CodeEditSourceEditor`. See "Rejected dependencies".

## THE performance rule (read this before touching editor setup)

> **Never construct a `TextView` with a populated string.**
> Create it empty, install it in a correctly-sized `NSScrollView`, *then* call
> `setText(_:)`.

`TextView(string: hugeDocument)` runs its initial layout while the view's frame
is still `.zero`. The viewport calculation degenerates and it lays out **every
line in the document**, creating one `NSView` subview per line. AppKit's
`-[NSView addSubview:]` performs an O(n) z-order scan (`NSViewInvalidateZOrder`
→ `indexOfObjectIdenticalTo:`), so N line-views cost O(n²).

Measured on an M4 MacBook Pro (16GB), release build, plain log fixtures:

| lines | `init(string:)` | empty init + `setText` |
|------:|----------------:|-----------------------:|
| 10k   | 397 ms          | ~5 ms                  |
| 50k   | 10,899 ms       | **23 ms**              |
| 100k  | 73,171 ms       | **42 ms**              |
| 400k  | timed out       | **161 ms**             |

Wired correctly the engine is linear and virtualised — loading a 100MB /
926,660-line log materialises only **89** line views.

### Validated performance envelope

100MB log, 926,660 lines, unwrapped:

| metric | result |
|---|---|
| read from disk | 39 ms |
| load into editor | **401 ms** |
| insert at end | 0.2 ms |
| insert at start | 1.0 ms |
| scroll to bottom | 4.9 ms |
| peak memory | 625 MB |
| line views created | 89 |

Word wrap on the same file is equivalent (396 ms). Known soft spot: documents
that are one very long line (10M-char line, minified JSON) cost ~65–80 ms per
edit, because a single line fragment must be re-typeset. Notepad++ is also poor
here. Revisit only if it shows up in real use.

**Memory is ~6× file size.** A 1GB file would not fit in RAM. True unbounded
large-file support needs memory-mapped/chunked storage, which the current
`NSTextStorage` backing does not do. Tracked as a known limit, not solved.

## Rejected dependencies

**CodeEditSourceEditor** — rejected on three independent grounds:
1. **Does not build under plain SwiftPM.** Its transitive dependency
   `CodeEditSymbols` ships an undeclared `Symbols.xcassets`, so `Bundle.module`
   is never generated and compilation fails.
2. **Licensing.** It pulls `CodeEditLanguages` and `CodeEditSymbols`, *neither of
   which ships a LICENSE file*. GitHub's license API returns null for both. Open
   issues asking for clarification (CodeEditLanguages #93/#94, CodeEditSymbols
   #23) have sat unanswered; both repos have been dormant since 2025. We cannot
   ship an MIT app on an unlicensed dependency.
3. **`_RopeModule`.** It imports swift-collections' underscored, explicitly
   unstable module ("needs more time in the oven before it can become public
   API") in 5 files — and does not even declare it as a dependency, relying on
   transitive visibility that a future toolchain may tighten.

`CodeEditTextView` itself has none of these problems: MIT with an actual LICENSE
file, and it depends only on the *public* `Collections` product.

We therefore implement ourselves the things CodeEditSourceEditor would have
provided: tree-sitter wiring, folding, minimap/document map.

## Syntax highlighting plan

Two tiers, mirroring how CotEditor 7 does it:

1. **tree-sitter** via [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter)
   (BSD-3) for languages with maintained grammars. Grammars are packaged by us
   from upstream repos with per-grammar license attribution — not via
   CodeEditLanguages. Upstream grammar licenses were audited: all MIT except
   tree-sitter-elixir (Apache-2.0). Note that some `.scm` query files are
   Apache-2.0 (sourced from nvim-treesitter) even where the grammar is MIT, so
   NOTICE must aggregate both.
2. **UDL** — Notepad++'s GUI-authored keyword/delimiter/regex lexer, for
   everything else. This is a genuine Notepad++ differentiator (no Mac editor
   has it) and doubles as our fallback for languages without a grammar.

## Regex

Notepad++ uses **Boost** regex. `NSRegularExpression` is ICU. These differ in
ways users will hit: `\K`, conditionals `(?(1)yes|no)`, recursion `(?R)`,
`(?'NAME'...)` quoting and `\g{NAME}` backreferences have no ICU equivalent.
ICU is *more* permissive on lookbehind (bounded variable-length vs Boost's
fixed-length). Decision pending: ship ICU and document divergence in-app, or
vendor a Boost-compatible engine. Do not silently reinterpret patterns.

## Module layout

- `NotepadXXCore` — document model, buffers, session/crash recovery, encoding
  and EOL handling. No AppKit dependency where avoidable; unit-testable.
- `NotepadXXEditor` — the editor view, wrapping CodeEditTextView and enforcing
  the performance rule above.
- `NotepadXX` — app shell, menus, tab bar, panels, status bar.
