# NotepadXX Parity Matrix — Search Menu & View Menu (Notepad++ v8.8.x baseline)

Sources: [npp-user-manual.org](https://npp-user-manual.org/) (`/docs/searching/`, `/docs/views/`), and the Notepad++ GitHub source
(`notepad-plus-plus/notepad-plus-plus`, master branch) — specifically `PowerEditor/src/menuCmdID.h` (command ID enumeration),
`PowerEditor/src/Parameters.cpp` (`winKeyDefs[]`, the authoritative default-accelerator table, struct order
`{ vKey, functionId, isCtrl, isAlt, isShift, specialName }`), and `PowerEditor/installer/nativeLang/english.xml` (menu label
text/structure). Shortcuts below were read directly out of `winKeyDefs[]`, not guessed — "none" means the entry exists with
`VK_NULL` (no default binding; user-assignable in Settings > Shortcut Mapper).

## Legend

- **Tier**: **E** = Essential (v1 blocker — daily-driver users notice immediately if missing), **I** = Important (expected by
  power users within weeks), **N** = Nice-to-have (long-tail / rarely-used power feature, safe to defer past v1).
- **Complexity**: **S** = hours, isolated UI action; **M** = ~1 day, touches editor core or one subsystem; **L** = multi-day,
  a real subsystem (dockable panel, multi-file engine); **XL** = a major subsystem in its own right (regex engine, docking
  framework).
- "macOS equivalent/notes" calls out the concrete AppKit/porting decision, not a restatement of the behavior.

---

## 1. Regex Engine — the single biggest porting decision

Notepad++'s Regular Expression search mode uses **Boost.Regex** (`perl_syntax` flavor), version bundled with the app (v1.90
as of NPP 8.9.1; the manual explicitly warns this is *not* PCRE, and PCRE-based regex testers online will give misleading
answers). The natural macOS substitute is **`NSRegularExpression`**, which wraps **ICU regex** — a different engine family
entirely. Below is the reconciliation.

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| REGEX-01 | Find dialog > search mode | Regular expression mode (engine identity) | n/a | Switches the Find/Replace/Find-in-Files pattern interpreter to Boost.Regex Perl-syntax. | Port to `NSRegularExpression` (ICU). This is the right target (Unicode-aware, maintained, no license issue) but is a **different regex flavor** — cannot claim byte-for-byte parity, only "equivalent for the common 95% of patterns." Flag divergences in-app rather than silently reinterpreting. | XL | E |
| REGEX-02 | n/a (engine detail) | Named capture groups | n/a | Boost supports **two** named-group spellings: `(?<NAME>...)` and `(?'NAME'...)`; referenced via `\g{NAME}` or `\k<NAME>` in the pattern, `$1`/named in replacement. | ICU/`NSRegularExpression` supports `(?<NAME>...)` and `\k<NAME>`, but **not** the `(?'NAME'...)` quoting form and **not** `\g{NAME}`. Incompatibility — must transliterate or document as unsupported. | M | I |
| REGEX-03 | n/a (engine detail) | `\K` (keep/reset match start) | n/a | Everything left of `\K` is excluded from the reported match (used heavily for "replace suffix only" style patterns). | **Not supported by ICU regex at all.** No `NSRegularExpression` equivalent — this is the single most-cited PCRE→ICU migration pain point. Must either implement custom match-post-processing (track a synthetic "keep" marker and trim the match range after ICU returns it) or clearly document as unsupported. | L | I |
| REGEX-04 | n/a (engine detail) | Conditional expressions `(?(1)yes|no)` | n/a | Pattern branches based on whether a numbered/named group already matched. | **Not supported by ICU regex.** No equivalent; would require writing a mini regex preprocessor/expander or hand-rolled matcher. Rare in practice — safe to document as unsupported rather than build. | L | N |
| REGEX-05 | n/a (engine detail) | Recursive patterns `(?R)`, `(?N)`, `(?&NAME)` | n/a | Self-referential subpattern recursion for matching nested/balanced constructs. | **Not supported by ICU regex.** Community reports these are already flaky/inconsistent in real Notepad++ too. Document as unsupported; do not attempt to emulate. | L | N |
| REGEX-06 | n/a (engine detail) | Atomic groups `(?>...)` / possessive quantifiers `*+ ++ ?+ {n,m}+` | n/a | Non-backtracking group/quantifier forms, used for catastrophic-backtracking avoidance. | **Compatible** — ICU regex supports both atomic groups and possessive quantifiers natively. No porting gap. | S | I |
| REGEX-07 | n/a (engine detail) | POSIX bracket classes `[[:alpha:]]`, `[[:digit:]]`, `[:d:]` short forms | n/a | Named character classes inside `[...]`, case-insensitive spelling. | **Compatible** — ICU supports POSIX classes inside bracket expressions (`[[:alpha:]]` etc). Boost's single-letter shortcuts like `[[:d:]]` are non-standard, though — verify case by case; may need a small compatibility shim. | S | N |
| REGEX-08 | n/a (engine detail) | `\x{HHHH}` Unicode code point escape, incl. surrogate pairs for >U+FFFF | n/a | Hex Unicode escape; codepoints above U+FFFF are entered as two `\x{}` surrogate escapes. | **Mostly compatible** — ICU also supports `\x{HHHH}`, but ICU works natively in UTF-16/32 codepoints, so the "type two surrogate escapes" workaround Boost needs is unnecessary and should be *simplified* in NotepadXX rather than replicated. | S | N |
| REGEX-09 | n/a (engine detail) | `\C` (single byte, encoding-unsafe) / `\X` (Unicode grapheme cluster) | n/a | `\X` matches one full grapheme cluster; `\C` matches one raw byte regardless of UTF state (dangerous, can split multibyte chars). | `\X` **is supported** by ICU. `\C` **has no ICU equivalent** and arguably shouldn't — it's a footgun in a byte-oriented engine that makes no sense against Swift's `String`/grapheme model. Document as intentionally dropped. | S | N |
| REGEX-10 | n/a (engine detail) | Lookbehind, fixed vs. variable length | n/a | Boost requires lookbehind `pattern` to be **fixed-length** (with `\R` explicitly disallowed inside lookbehind because it's variable-width). | ICU regex supports **bounded variable-length** lookbehind (a length cap, not a fixed-length requirement) — ICU is actually **more permissive** here. Good news for porting, but means some patterns that fail in real Notepad++ will succeed in NotepadXX; decide whether to artificially restrict for behavioral parity or intentionally exceed it (recommend: exceed it, document the deviation). | M | N |
| REGEX-11 | n/a (engine detail) | Backreferences `\1`..`\9` in pattern; `$1`..`$9` in replacement (format_perl syntax) | n/a | Standard backreference syntax; Boost's replace-string formatter (`format_perl`) also supports `$&`, `${n}`, and conditional replace `(?1:yes:no)`-style extensions. | Pattern-side `\1` and replacement-side `$1` are compatible with `NSRegularExpression`'s `NSRegularExpression.replacementString` templating. Boost's extended conditional-replacement syntax is not — expect edge-case divergence in advanced Replace-All macros. | M | I |
| REGEX-12 | Find dialog | `(?i)`, `(?s)`, `(?m)`, `(?x)` inline modifiers | n/a | Inline flags toggle case-insensitivity, dot-matches-newline, multiline anchors, and extended/whitespace-ignoring mode mid-pattern; `(?i)` can override the Match Case checkbox. | ICU regex supports the same inline modifier syntax (`(?i)`, `(?s)`, `(?m)`, `(?x)`) — compatible. Just make sure the "Match Case" checkbox and inline `(?i)`/`(?-i)` interact the same way (inline wins). | S | I |
| REGEX-13 | Find dialog | Backward regex search — **disallowed** | n/a | Notepad++ explicitly disables "Backward direction" when Regular expression mode is active ("disallowed due to sometimes surprising results" per the manual). | `NSRegularExpression` has no inherent directionality restriction (you can search the reversed string or walk matches and pick the last one before caret). Decide: replicate the restriction for behavioral parity, or lift it since ICU handles it safely — recommend lifting it and shipping backward regex search as a NotepadXX improvement, clearly flagged as a deviation. | M | N |
| REGEX-14 | Find dialog | Extended search mode (`\n \r \t \0 \xHH`) | n/a | A middle mode between Normal and Regex: literal text plus a small set of escape sequences, auto-activated when pasting multiline search text. | Straightforward to reimplement as a tiny custom escaper (not ICU-dependent) — string preprocessing before a literal (non-regex) search. | S | E |

---

## 2. Search Menu — top-level commands

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| SRCH-01 | Search > Find... | Find | Ctrl+F | Opens the Find/Replace dialog on the Find tab; searches the active document with the configured mode/options. | Standard `NSTextFinder`/custom find bar; Cmd+F. Core v1 feature. | M | E |
| SRCH-02 | Search > Find in Files... | Find in Files | Ctrl+Shift+F | Opens the dialog's Find in Files tab: recursive directory search across a filesystem tree with filename filters, results in the Search Results panel. | Needs its own multi-file search engine (background-thread directory walk + per-file regex/literal scan), independent of the single-doc find. Significant subsystem. | L | E |
| SRCH-03 | Search > Find in Projects | Find in Projects | none (not a registered command — invoked only via right-click on a Project Panel item; a long-standing feature request (GH #13256) asks for it to become a real assignable command) | Same as Find in Files but scoped to files registered in the Project Panel rather than a directory on disk. | Reuses the Find-in-Files engine against the Project Panel's virtual file list instead of a directory walk. Only buildable once Project Panels (View section) exist. | M | N |
| SRCH-04 | Search > Replace... | Replace | Ctrl+H | Opens the dialog's Replace tab: single/incremental Replace plus Replace All, Replace All in All Opened Documents. | Cmd+Option+F or similar; needs an editable "replace with" field synced to the same history/regex engine as Find. | M | E |
| SRCH-05 | Search > Find Next | Find Next | F3 | Repeats the last Find dialog search forward from the caret, wrapping per the Wrap Around setting. | Trivial once the find-state object exists. | S | E |
| SRCH-06 | Search > Find Previous | Find Previous | Shift+F3 | Same as Find Next but searches backward. | S | E |
| SRCH-07 | Search > Select and Find Next | Select and Find Next | Ctrl+F3 | Takes the current selection (or word under caret if no selection) as the search term, stores it, and jumps to the next occurrence — a "search for this" shortcut without opening the dialog. | Requires syncing the dialog's find-history/last-term state from an ad hoc selection. | S | E |
| SRCH-08 | Search > Select and Find Previous | Select and Find Previous | Ctrl+Shift+F3 | Same as above, backward direction. | S | E |
| SRCH-09 | Search > Find (Volatile) Next | Find (Volatile) Next | Ctrl+Alt+F3 | Same as Select-and-Find-Next but does **not** write to Find history/does not disturb the persisted Find dialog state — a "scratch" quick-search. | Needs a separate ephemeral search-term slot distinct from the persisted one. | S | I |
| SRCH-10 | Search > Find (Volatile) Previous | Find (Volatile) Previous | Ctrl+Alt+Shift+F3 | Volatile search, backward. | S | I |
| SRCH-11 | Search > Incremental Search | Incremental Search | Ctrl+Alt+I | Opens a small in-editor bar (not the modal dialog) that jumps to matches live as you type, browser-style, with Match case / Highlight all / Count. | Directly analogous to Safari/Xcode-style inline find bars — very idiomatic on macOS, arguably the most "native-feeling" of all Search features. | M | E |
| SRCH-12 | Search > Search Results Window | Search Results Window (a.k.a. Focus on Found Results) | F7 | Toggles focus to/visibility of the dockable Search Results panel that accumulates Find-All / Find-in-Files hits, grouped hierarchically by search → file → line. | Needs an `NSOutlineView`-backed dockable results panel (see View section for the docking framework question). | L | E |
| SRCH-13 | Search > Go to Next Found Line | Go to Next Found Result | F4 | Moves the caret to the next hit inside the currently-focused Search Results branch, without leaving the editor. | S | I |
| SRCH-14 | Search > Go to Previous Found Line | Go to Previous Found Result | Shift+F4 | Same, backward. | S | I |

---

## 3. Search Menu — Mark submenu family (style tokens, distinct from Bookmark)

Notepad++ has two independent "mark this text" systems: **Bookmarks** (whole-line markers, section 4) and **Style
Marking** (up to 5 colored highlight styles applied to arbitrary regex/text matches, toggled via `Ctrl+M` → Mark tab, or
directly from these submenu items). They're easy to conflate; keep them as separate NotepadXX features.

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| MARK-01 | Search > Mark... | Mark | Ctrl+M | Opens the Find dialog's Mark tab: enter a pattern, hit Mark All to highlight every match (optionally bookmarking each matched line too). | Same dialog infrastructure as Find; adds a "styled highlight" render layer over Find. | M | I |
| MARK-02 | Search > Style all Occurrences of Token > 1st..5th Style | Mark All using Style N | none ×5 | Highlights every occurrence of the current selection/word using one of 5 predefined highlight colors (persists until cleared). | Needs 5 persistent "highlight layers" tracked as ranges (or regex re-evaluated live) rendered under the text — similar to Xcode's "highlight occurrences of selected symbol" but multi-color and manual. | M | I |
| MARK-03 | Search > Style one Token > 1st..5th Style | Mark One using Style N | none ×5 | Highlights only the single occurrence at the caret/selection with style N, without scanning the whole document for duplicates. | S | N |
| MARK-04 | Search > Clear Style > 1st..5th Style / Clear all styles | Clear style N / Clear all styles | none ×6 | Removes highlighting for one style layer or all five at once. | S | I |
| MARK-05 | Search > Copy Styled Text > 1st..5th Style / All Styles / Find Mark Style (bookmarked/marked lines) | Copy Styled Text | none ×7 | Copies to clipboard the text of everything currently highlighted under a given style (or all styles, or the plain Find-Mark-Style hits from a Ctrl+M "Mark All") — a lightweight "extract all matches" tool. | Straightforward: iterate the tracked highlight ranges, concatenate. | S | N |
| MARK-06 | Search > (accelerator-only) Next/Previous occurrence of style N, and of default Find-Mark style | Go to next/previous marker of style N | Ctrl+1..5 (next) / Ctrl+Shift+1..5 (prev); Ctrl+0/Ctrl+Shift+0 for the default Find-Mark style | Cursor-jumps between highlighted occurrences of a given style, useful for reviewing all marked hits one by one without the Search Results panel. | S | N |

---

## 4. Search Menu — Bookmark submenu

Whole-line markers shown in the bookmark margin, independent of text highlighting.

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| BKMK-01 | Search > Bookmark > Toggle Bookmark | Toggle Bookmark | Ctrl+F2 | Toggles a bookmark glyph on the current line's margin. | Needs a dedicated bookmark gutter/margin (own custom `NSRulerView`-style gutter, or a column inside the line-number gutter). | S | E |
| BKMK-02 | Search > Bookmark > Next Bookmark | Next Bookmark | F2 | Jumps caret to the next bookmarked line, wrapping. | S | E |
| BKMK-03 | Search > Bookmark > Previous Bookmark | Previous Bookmark | Shift+F2 | Same, backward. | S | E |
| BKMK-04 | Search > Bookmark > Clear All Bookmarks | Clear All Bookmarks | none | Removes every bookmark in the current document. | S | I |
| BKMK-05 | Search > Bookmark > Cut Bookmarked Lines | Cut Bookmarked Lines | none | Removes every bookmarked line from the document and places their full text on the clipboard. | M | N |
| BKMK-06 | Search > Bookmark > Copy Bookmarked Lines | Copy Bookmarked Lines | none | Copies every bookmarked line's text to clipboard without removing them. | S | N |
| BKMK-07 | Search > Bookmark > Paste Into Bookmarked Lines | Paste to Bookmarked Lines | none | Replaces the content of each bookmarked line with clipboard text (one clipboard line per bookmarked line, in order). | M | N |
| BKMK-08 | Search > Bookmark > Remove Bookmarked Lines | Delete/Remove Bookmarked Lines | none | Deletes every bookmarked line outright (no clipboard interaction). | S | N |
| BKMK-09 | Search > Bookmark > Delete Un-bookmarked Lines | Delete Un-bookmarked Lines | none | Inverse of the above — keeps only bookmarked lines, deletes everything else. Handy as a crude grep-and-keep tool. | S | N |
| BKMK-10 | Search > Bookmark > Inverse Bookmarks | Inverse Bookmarks | none | Bookmarks every currently-unbookmarked line and clears bookmarks on previously-bookmarked lines. | S | N |

---

## 5. Search Menu — remaining navigation/utility commands

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| SRCH-15 | Search > Go to... | Go to Line | Ctrl+G | Opens a small dialog to jump to a specific line number (or byte/char offset in some builds). | Trivial modal/popover. | S | E |
| SRCH-16 | Search > Go to Matching Brace | Go to Matching Brace | Ctrl+B | If the caret sits next to `( [ {`, jumps to the matching closer (and vice versa), using Scintilla's brace-matching. | Needs a lexer-aware brace matcher (already required for editing parity elsewhere — reuse). | M | E |
| SRCH-17 | Search > Select All In-between {} [] () | Select All Between Matching Braces | Ctrl+Alt+B | Same brace lookup as above, but selects the full span including both delimiters instead of just moving the caret. | S | I |
| SRCH-18 | Search > Find Characters in Range... | Find Characters in Range | none | Small dialog to search by raw character codepoint (decimal, 0–255 only — explicitly does not support values above 255 / arbitrary Unicode). | S | N |
| SRCH-19 | Search > Jump Up | Jump Up | none | Jumps the caret to the previous "paragraph-like" boundary (blank line / indentation change) — a coarse structural navigation aid. | S | N |
| SRCH-20 | Search > Jump Down | Jump Down | none | Same, forward. | S | N |
| SRCH-21 | Search > Change History > Go to Next Change | Next Change | none | Jumps to the next line flagged as modified/added/reverted by the built-in Change History tracker (added NPP v8.5.5). | Requires a change-tracking model similar to Xcode's "changed lines" gutter — diff against last-saved or session-start snapshot. | L | I |
| SRCH-22 | Search > Change History > Go to Previous Change | Previous Change | none | Same, backward. | shares SRCH-21's engine | I |
| SRCH-23 | Search > Change History > Clear Change History | Clear Change History | none | Discards all tracked change markers for the current document. | S | I |

---

## 6. Find/Replace Dialog — shared controls (Find + Replace tabs)

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| DLG-01 | Find dialog | Search mode radio: Normal | n/a | Literal-text search, no escape interpretation. | S | E |
| DLG-02 | Find dialog | Search mode radio: Extended | n/a | Literal text plus `\n \r \t \0 \xHH` escapes; auto-selected when the search field content contains a real newline (e.g. pasted). | See REGEX-14. | S | I |
| DLG-03 | Find dialog | Search mode radio: Regular expression | n/a | Switches to Boost.Regex interpretation of the pattern; unlocks the "`. ` matches newline" checkbox, disables Backward direction. | See REGEX section. | XL | E |
| DLG-04 | Find dialog | ". matches newline" checkbox | n/a | Only enabled in Regex mode; makes `.` match `\n`/`\r` too (equivalent to inline `(?s)`). | Maps directly to `NSRegularExpression.Options.dotMatchesLineSeparators`. | S | I |
| DLG-05 | Find dialog | Backward direction checkbox | n/a | Reverses search direction; force-disabled when Regular expression mode is active (see REGEX-13). | M | I |
| DLG-06 | Find dialog | Match whole word only checkbox | n/a | Requires word-boundary characters (per the app's configured "word chars") on both sides of the match; ASCII vs Unicode boundary detection differs subtly from the more precise `\b` regex anchor. | Map to ICU `\b`-equivalent boundary logic, or `NSString` word-boundary enumeration for the non-regex path. | M | E |
| DLG-07 | Find dialog | Match case checkbox | n/a | Case-sensitive matching; overridable inline via `(?i)`/`(?-i)` in regex mode. | S | E |
| DLG-08 | Find dialog | Wrap around checkbox | n/a | Continues search from the top/bottom of the document once the end/start is reached; also changes Replace-All scope semantics depending on direction. | M | E |
| DLG-09 | Find dialog | In selection checkbox | n/a | Restricts Find All / Count / Replace All to the current selection; works with Notepad++'s multi/rectangular selections (applies per selected range). | Needs multi-range selection support in the editor core as a prerequisite — flag as depending on core editing-parity work, not just Search. | L | I |
| DLG-10 | Find dialog | Transparency (On losing focus / Always) + opacity slider | n/a | Makes the non-modal Find dialog semi-transparent so text underneath remains visible while searching; "On losing focus" only fades when the main editor regains focus, "Always" stays faded. | `NSWindow.alphaValue` + a focus-change observer. Cosmetic, cheap. | S | N |
| DLG-11 | Find dialog | Find field / Replace field with history dropdown (10 entries, deletable via Del key) | n/a | Combo-box style history for both fields, persisted across sessions, capped at 10 by default (configurable via config XML), individual entries deletable. | `NSComboBox`/custom autocomplete field backed by a persisted history array. | M | I |
| DLG-12 | Find dialog | Find field character limit | n/a | 2046 bytes (≤ v8.8.3) / 16383 bytes (v8.8.4+) with a warning dialog if exceeded. | Not really a target — `NSTextField`/Swift `String` have no meaningful practical limit here; just don't impose an artificial one. | S | N |
| DLG-13 | Find tab | Find Next button | n/a (Enter key) | Executes one forward search and advances. | S | E |
| DLG-14 | Find tab | Count button | n/a | Reports total match count (respecting direction/selection scope) in the dialog status area without moving the caret or opening Search Results. | S | I |
| DLG-15 | Find/Replace tabs | Find All in Current Document button | n/a | Populates the Search Results panel with every match in the active buffer only. | Reuses SRCH-12's panel/engine. | M | I |
| DLG-16 | Find/Replace tabs | Find All in All Opened Documents button | n/a | Same, scanning every open document/tab. | Reuses the multi-doc iteration already needed for Replace-All-in-all-opened. | M | I |
| DLG-17 | Replace tab | Replace button | Alt+R (dialog-local) | Replaces the currently-selected/matched occurrence, then advances to the next. | S | E |
| DLG-18 | Replace tab | Replace All button | n/a | Replaces every match in the active document (respecting direction/wrap/selection scope). | M | E |
| DLG-19 | Replace tab | Replace All in All Opened Documents button | n/a | Replace All across every open document/tab in one operation. | L | I |
| DLG-20 | Replace tab | Swap button (⇄ between Find and Replace fields) | n/a | Quickly exchanges the contents of the Find and Replace-with fields. | S | N |
| DLG-21 | Find dialog | Window-flash / beep on "not found" or on wrap | n/a | Visual flash of the dialog/title bar (and optional sound, toggle in Preferences > Misc) when a search fails or wraps around. | `NSWindow` shake animation (already used system-wide for auth failures) is a natural analog; system beep via `NSSound.beep()`. | S | N |

---

## 7. Find/Replace Dialog — Find in Files / Replace in Files tab

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| FIF-01 | Find dialog > Find in Files tab | Directory field | n/a | Root folder for the recursive search; supports manual typing or the browse button. | `NSOpenPanel` (directory mode) + text field. | S | E |
| FIF-02 | Find dialog > Find in Files tab | "«" fill-from-active-document button | n/a | Populates Directory from the active document's folder (re-clickable after switching documents, added v8.7.5). | S | I |
| FIF-03 | Find dialog > Find in Files tab | "..." browse button | n/a | Opens a folder picker. | S | E |
| FIF-04 | Find dialog > Find in Files tab | Filters field | n/a | Space-separated `cmd.exe`-style wildcard list (`*`, `?`); blank defaults to `*.*`; `!pattern` excludes; `!\folder` excludes a folder one level deep, `!+\folder` excludes recursively at all levels; no positive-only folder-include syntax exists. | Reimplement as a small glob matcher (not `cmd.exe`-dependent) — macOS-native equivalent would more naturally use shell-style globs or `NSPredicate`, but keep the same exclusion (`!`) semantics for muscle-memory parity. Document the folder-exclusion asymmetry (no inclusive equivalent) as an intentional carryover quirk or a chance to improve. | M | E |
| FIF-05 | Find dialog > Find in Files tab | In all sub-folders checkbox | n/a | Recurses into subdirectories. | S | E |
| FIF-06 | Find dialog > Find in Files tab | In hidden folders checkbox | n/a | Includes dot-folders/hidden directories in the recursive walk. | S | I |
| FIF-07 | Find dialog > Find in Files tab | Follow current doc (removed as a checkbox in v8.7.5, moved to Preferences > Searching) | n/a | Historically auto-populated Directory from the active doc's folder on every dialog open; now a persistent preference rather than a per-search checkbox. | Implement as a Preferences toggle from the start — no need to replicate the removed UI. | S | N |
| FIF-08 | Find dialog > Find in Files tab | Find All button | n/a | Runs the filtered recursive search, streaming results into the Search Results panel as files are scanned. | Background-queue directory walk + incremental UI updates (don't block main thread). | L | E |
| FIF-09 | Find dialog > Replace in Files tab | Replace in Files button | n/a | Same scope/filter engine as Find in Files, but performs an in-place Replace-All on every matching file on disk. | Needs a safe "write back to disk" path with the same live-buffer-priority rule as FIF-10 — genuinely destructive, needs confirmation UX. | L | I |
| FIF-10 | n/a (documented behavior) | Open-buffer precedence rule | n/a | If a file targeted by Find/Replace in Files is currently open with unsaved edits, the **in-memory buffer** is searched/replaced instead of the on-disk content. | Must route file-content reads for Find-in-Files through the same open-document registry used by the tab system, not straight through the filesystem. Easy to get subtly wrong. | M | I |

---

## 8. Find/Replace Dialog — Find in Projects tab

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| FIP-01 | Right-click Project Panel root > Find in Projects | Find in Projects tab | none | Same UI/engine as Find in Files, but the file set comes from the Project Panel's tree (which can span multiple disjoint on-disk folders added as virtual "projects") instead of one directory + recursion. | Depends on the Project Panel feature existing first (see View section §12). Reuses the FIF-08 engine against an explicit file list instead of a directory walk. | M | N |

---

## 9. Find/Replace Dialog — Mark tab

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| MTAB-01 | Find dialog > Mark tab | Bookmark line checkbox | n/a | When checked, Mark All also drops a bookmark on every line containing a hit (multi-line matches bookmark every spanned line). | Wires MARK-family highlighting into BKMK-family bookmarking. | S | N |
| MTAB-02 | Find dialog > Mark tab | Mark All button | n/a | Highlights every match start-to-end of document (honoring Wrap Around) using the Style Configurator's "Find Mark Style" (or a chosen style 1-5 elsewhere in the UI). | M | I |
| MTAB-03 | Find dialog > Mark tab | Purge for each search checkbox | n/a | Automatically clears previous Mark-All highlights before applying a new search's marks. | S | N |
| MTAB-04 | Find dialog > Mark tab | Copy Marked Text button | n/a | Copies all currently mark-highlighted text to clipboard (same underlying op as MARK-05's "Find Mark Style" clip copy). | S | N |
| MTAB-05 | Find dialog > Mark tab | Clear All marks | n/a | Removes all Mark-tab highlighting and any bookmarks it created. | S | N |

---

## 10. Search Results Window (dockable panel)

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| SRW-01 | View (docked panel, opened via Search > Search Results Window) | Search Results tree | F7 to focus | Hierarchical results: search query → filename → line, with counts at each level; double-click/Enter jumps to the hit. | `NSOutlineView` with 3-level model. Core deliverable, shared by Find-All, Find-in-Files, Find-in-Projects. | L | E |
| SRW-02 | Search Results panel | Fold/unfold branches | n/a | Collapse a search-query or file branch to reduce clutter; new searches auto-fold prior ones. | `NSOutlineView` native expand/collapse — cheap once SRW-01 exists. | S | I |
| SRW-03 | Search Results panel | Right-click > Copy / Copy path(s) / Open file | n/a | Context menu for copying match text, full paths, or opening the containing file directly. | S | I |
| SRW-04 | Search Results panel | "Find in these search results" (secondary search) | n/a | Re-filters an existing results set with a new search term, without re-scanning disk. | M | N |
| SRW-05 | Search Results panel | Delete key on a result/branch | n/a | Removes an individual match line or an entire file/search branch from the results view (does not touch the actual file). | S | N |
| SRW-06 | Search Results panel | Auto-purge old results / line-wrap toggle | n/a | Preferences-driven cap on how many past searches accumulate before old ones are dropped; independent line-wrap setting for the results list. | S | N |

---

## 11. View Menu — window-level modes

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| VIEW-01 | View > Always on Top | Always on Top | none | Keeps the app window above all others; toggle-only, no exclusivity. | `NSWindow.level = .floating`. Trivial. | S | I |
| VIEW-02 | View > Toggle Full Screen Mode | Full Screen | F11 | Hides title bar/menu/toolbar and fills the screen; app-internal shortcuts still work; exit via on-screen glyph, F11, or restart. | Native macOS full screen (`NSWindow.toggleFullScreen`) is the idiomatic target — behaves better than NPP's own reimplementation (has a real green-button affordance, Mission Control integration). Recommend using system full screen rather than hand-rolling NPP's approach. | S | I |
| VIEW-03 | View > Post-It | Post-It Mode | F12 | Hides title/menu/toolbar/tab-bar but keeps the existing window size (distinct from full screen); exits via on-screen glyph/shortcut/restart. | Borderless `NSWindow` (`.borderless` style mask) toggled at runtime; needs custom traffic-light/exit affordance since removing the title bar removes the standard window buttons too. | M | N |
| VIEW-04 | View > Distraction Free | Distraction Free Mode | none | Combines full screen + Post-It's chrome-hiding, plus wide configurable text margins (Preferences > Margins/Border/Edge > Padding > Distraction Free). | Composite of VIEW-02 + wide `NSTextContainer` insets. | S | N |
| VIEW-05 | View > View Current File in > Firefox/Chrome/Edge/IE | View Current File in Browser | none ×4 | Opens the active file's on-disk path in the chosen installed browser (best for HTML, also opens plain text/XML). | `NSWorkspace.open(url, withApplicationAt:)`; on macOS this becomes a generic "Open With Installed Browser" list rather than 4 hardcoded IE-era entries — modernize the option list (Safari, Chrome, Firefox, whatever's installed) instead of copying Windows' fixed 4. | S | N |
| VIEW-06 | View > Word wrap | Word Wrap | none | Soft-wraps long lines at the editor width on word boundaries (mid-word break only if a single word exceeds the width); remembered setting. | `NSTextView`/custom layout manager line-wrap toggle. Core editing-parity item, not really Search/View-specific complexity. | M | E |
| VIEW-07 | View > Focus on Another View | Focus on Another View | F8 | Swaps keyboard focus between the two split editor views (only meaningful once split views exist). | Depends on the split-view/multi-pane editor existing (an Edit/Window-level prerequisite, not itself hard). | S | I |
| VIEW-08 | View > Hide Lines | Hide Lines | Alt+H | Hides the current/selected lines from view (text stays in the file, margin gets an "unhide" affordance); resets on restart. | Needs Scintilla-style "line hiding" — a rendering-layer feature (skip drawing certain logical lines while keeping them in the model), independent of code folding. | L | N |
| VIEW-09 | View > Summary... | File Summary dialog | none | Modal info dialog: full path, timestamps, byte count, char count (excluding EOLs), word count, line count. | S | N |
| VIEW-10 | View > Monitoring (tail -f) | Monitoring | none | Watches the file on disk for external changes and live-appends them to the (now de-facto read-only) buffer, mimicking `tail -f`; tab shows an eye icon. `-monitoringMode` CLI flag (v8.9.8+) applies it to all opened files at once. | `DispatchSourceFileSystemObject` watching the file's vnode, or FSEvents for broader coverage; needs a read-only lock state on the buffer while active. | M | I |

---

## 12. View Menu — Show Symbol submenu

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| SYM-01 | View > Show Symbol > Show Space and Tab | Show Space and Tab | none | Renders spaces as colored dots, tabs as colored arrows spanning the tab width. | Requires a custom `NSLayoutManager`/text-rendering layer that draws invisible-glyph overlays — Cocoa's stock `NSTextView` has no built-in whitespace visualization, unlike Scintilla. This is a recurring theme across all "Show Symbol" items: they demand a custom glyph-drawing layer, which is one of the bigger structural asks of the whole View menu. | M | I |
| SYM-02 | View > Show Symbol > Show End of Line | Show End of Line | none | Renders CR/LF/CRLF as boxed reverse-video glyphs at each line ending, colorable via Global Styles. | M | I |
| SYM-03 | View > Show Symbol > Show Non-Printing Characters | Show Non-Printing Characters (v8.5+) | none | Boxed glyphs for NBSP, ZWJ, and 40+ other invisible Unicode characters, shown as codepoint or abbreviation. | M | N |
| SYM-04 | View > Show Symbol > Show Control Characters & Unicode EOL | Show Control Characters & Unicode EOL (v8.5.3+) | none | Boxed glyphs for ASCII/Unicode C0/C1 control codes plus U+2028 (LS) / U+2029 (PS). | M | N |
| SYM-05 | View > Show Symbol > Show All Characters | Show All Characters (toolbar ¶ button equivalent) | none | Master toggle for SYM-01..04 simultaneously. | S | I |
| SYM-06 | View > Show Symbol > Show Indent Guide | Show Indent Guide | none | Dotted vertical guide lines at each indentation level beyond the first tab stop. | Same custom-rendering-layer dependency as SYM-01. | M | I |
| SYM-07 | View > Show Symbol > Show Wrap Symbol | Show Wrap Symbol | none | Colored arrow glyph (↲) marking a soft-wrap point when Word Wrap is on. | S | N |

---

## 13. View Menu — Zoom submenu

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| ZOOM-01 | View > Zoom > Zoom In | Zoom In | Ctrl+Numpad+ / Ctrl+mouse-wheel-up (not in the accelerator table — handled directly by Scintilla's key map, not `winKeyDefs[]`) | Increases editor font scale for the active View only. | Font-size scaling on the text container; Cmd+= convention. | S | I |
| ZOOM-02 | View > Zoom > Zoom Out | Zoom Out | Ctrl+Numpad- / Ctrl+mouse-wheel-down | Decreases editor font scale for the active View only. | S | I |
| ZOOM-03 | View > Zoom > Restore Default Zoom | Restore Default Zoom | Ctrl+Numpad* (not in accel table) | Resets zoom to 100% for the active View. | S | I |
| ZOOM-04 | View > Zoom > Synchronize Across Views | Synchronize Zoom Across Views (v8.9.5+) | none | Locks zoom level between two visible split Views so they scale together; toggling again unlocks. | Only meaningful once split views exist; a coupled-state flag between two editor panes. | S | N |

---

## 14. View Menu — Move/Clone Current Document submenu

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| MVCL-01 | View > Move/Clone Current Document > Move to Other View | Move to Other View | none | Transfers the active tab from one split View to the other (creates a second View if only one exists). | Needs the split-editor architecture as a prerequisite (shared with VIEW-07/ZOOM-04). | M | I |
| MVCL-02 | View > Move/Clone Current Document > Clone to Other View | Clone to Other View | none | Shows the same document simultaneously in both split Views (two cursors/scroll positions into one buffer) — enables the "two-column reading" trick when combined with Synchronize Scrolling. | L | I |
| MVCL-03 | View > Move/Clone Current Document > Move to New Instance | Move to New Instance | none | Moves an unmodified file to a brand-new app window/process, even if multi-instance mode is off. | `NSDocument`-per-window architecture makes this closer to "move to a new `NSWindow`" than "new process" on macOS — cheaper than the Windows equivalent if built on `NSDocumentController`. | M | N |
| MVCL-04 | View > Move/Clone Current Document > Clone to New Instance | Clone to New Instance | none | Same file open simultaneously in the current and a new window/instance. | M | N |
| MVCL-05 | Right-click the dotted View separator | Rotate View Layout Right/Left | none (mouse-only) | Cycles the two-View arrangement through left/right, top/bottom, right/left, bottom/top. | `NSSplitView` orientation + ordering toggle. | S | N |

---

## 15. View Menu — Tab submenu

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| TAB-01 | View > Tab > 1..9 | Go to Tab N | Ctrl+Numpad1..9 | Jumps directly to the Nth open tab. | Cmd+1..9 is the macOS-native convention (Safari/Chrome/Xcode all use it) — adopt directly, don't force the numpad-only Windows binding. | S | I |
| TAB-02 | View > Tab > Next tab / Previous tab | Next/Previous Tab | Ctrl+PageDown / Ctrl+PageUp | Cycles tabs, wrapping at the ends. | Cmd+Shift+]/[ is the macOS convention; also bind Ctrl+Tab / Ctrl+Shift+Tab (both present in NPP's own table as `IDC_NEXT_DOC`/`IDC_PREV_DOC`). | S | E |
| TAB-03 | View > Tab > First tab / Last tab | Go to First/Last Tab (v8.6.1+) | none | Jumps to the leftmost/rightmost tab. | S | N |
| TAB-04 | View > Tab > Move Tab Forward/Backward | Reorder current tab | Ctrl+Shift+PageDown / Ctrl+Shift+PageUp | Moves the active tab one position right/left in the tab strip. | S | N |
| TAB-05 | View > Tab > Apply Color 1-5 / Remove Color | Tab Color tagging | none ×6 | Assigns one of 5 accent colors to a tab's header for visual grouping, or clears it; also mirrored onto the Document List panel. | `NSTabView`/custom tab strip needs a per-tab accessory color swatch. | M | N |

---

## 16. View Menu — Fold Level / Unfold Level submenus

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| FOLD-01 | View > Fold > Fold All | Fold All | Alt+0 | Collapses every foldable block in the active document, for languages whose lexer defines fold points (no folding for e.g. Markdown UDL or plain text). | Requires per-language fold-point metadata from the syntax-highlighting engine — a shared dependency with the lexer/highlighter subsystem, not standalone. | L | E |
| FOLD-02 | View > Unfold > Unfold All | Unfold All | Alt+Shift+0 | Expands everything. | shares FOLD-01 engine | E |
| FOLD-03 | View > Fold Current Level / Unfold Current Level | Fold/Unfold Current Level | Ctrl+Alt+F / Ctrl+Alt+Shift+F | Collapses/expands the fold block containing the caret; becomes a true toggle if "Make current level folding commands toggleable" is set in Preferences. | S | I |
| FOLD-04 | View > Fold Level > 1..8 | Fold Level N | Alt+1..8 | Collapses every fold block at hierarchy depth N (1 = outermost) across the document. | shares FOLD-01 engine | I |
| FOLD-05 | View > Unfold Level > 1..8 | Unfold Level N | Alt+Shift+1..8 | Expands every fold block at depth N. | shares FOLD-01 engine | I |
| FOLD-06 | Fold margin (mouse only) | Click −/+ to fold/unfold; Shift-click fully expands sub-tree; Ctrl-click +  same; Ctrl-click − collapses line + all sub-folds | mouse-only | Direct margin interaction, several modifier-click variants for "expand/collapse everything under this node" shortcuts. | Gutter click handling with modifier-key branching, once the fold-margin gutter itself is built. | M | I |
| FOLD-07 | n/a (documented behavior) | Fold state persistence | n/a | Fold states are session-only — reloading a file always shows everything expanded (no "+" collapsed markers survive a reload). | Match this on purpose (don't over-engineer persistent fold state unless later adding session-restore, which is a separate feature). | S | N |

---

## 17. View Menu — Dockable Panels

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| PNL-00 | n/a (docking framework itself) | Generic panel docking mechanics | n/a | Panels dock to any of the 4 window edges or float independently; drag title bar to redock/float; double-click floats/redocks; multi-tab panel groups share a tab strip at the bottom of the dock; edge-resize via thin hover-sensitive splitters; recovery path for panels that get dragged off-screen. | This is the real prerequisite for every item below and arguably the single largest View-menu subsystem. No stock AppKit control does this — either build a custom docking framework on `NSSplitView`/`NSViewController` composition, or adopt a proven third-party layout system. Decide this **before** building any individual panel, since retrofitting docking later is expensive. | XL | E |
| PNL-01 | View > Document Map | Document Map | none (remembered setting) | Miniature rendered view of the whole file with a draggable viewport rectangle showing what's currently visible in the main editor — a minimap. | Render a scaled-down `CALayer`/offscreen text render, or reuse the main text renderer at tiny point size; sync viewport rect to scroll position. Xcode's minimap is a good reference. | L | I |
| PNL-02 | View > Document List | Document List (pre-v8.1.3: "Doc Switcher") | none (remembered setting) | Flat list of all open documents across both split Views, sortable by Name/Extension/Path columns, grouped-by-view with collapsible section headers (default on), tab-color-synced, keyboard type-to-select, middle-click closes a tab. | `NSTableView` with sort descriptors + grouped sections; solid, well-understood AppKit territory. | M | I |
| PNL-03 | View > Function List | Function List | none (remembered setting) | Outline of functions/methods/classes/sections for the active file (driven by regex-based per-language config files, not a real parser), double-click to jump. | `NSOutlineView`; the "per-language regex extraction config" approach is itself portable as data, though a real AST-based symbol list would be a legitimate v2 upgrade over Notepad++'s regex approach. | L | I |
| PNL-04 | View > Folder as Workspace | Folder as Workspace | none (remembered setting) | Tree view of an arbitrary folder on disk (like a lightweight file browser sidebar), independent of Project Panels; supports opening files by double-click, some file-ops via context menu. | `NSOutlineView` bound to `FileManager` directory enumeration + `FSEvents` for live updates. | L | I |
| PNL-05 | View > Project Panel 1/2/3 | Project Panels (×3 independent panels) | none ×3 (remembered setting) | Three separate manually-curated virtual project trees (add arbitrary files/folders from anywhere on disk into a named tree, save/load as `.xml` workspace files); source of Find in Projects' file set. | Same `NSOutlineView` approach as PNL-04 but backed by a persisted virtual-tree model instead of a live directory enumeration; needs its own workspace-file format/save-load. | L | N |
| PNL-06 | n/a (Edit menu, not View — but functionally a dockable panel like the above) | Clipboard History | none | Panel listing recent clipboard entries (text) for quick re-paste; **lives under the Edit menu in real Notepad++, not View** — flagging the menu-path mismatch since the task scope names it under View but it isn't actually there upstream. | `NSPasteboard` change-count polling/`NSPasteboardTypeOwner` + a ring-buffer history model rendered in an `NSTableView`. | M | N |
| PNL-07 | n/a (Edit menu, not View) | Character Panel | none | Panel for browsing/inserting Unicode characters by category/search, docks right by default; same menu-path caveat as PNL-06. | Could largely be replaced by macOS's built-in Character Viewer (`NSApp` "Emoji & Symbols" panel, Cmd+Ctrl+Space) rather than reimplemented — recommend deferring/dropping a custom build in favor of the system picker. | S | N |

---

## 18. View Menu — Margins (accessed via right-click margin / Preferences, not a View menu item per se)

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| MRG-01 | Right-click line-number margin, or Preferences > Editing | Line Number margin toggle | none | Shows/hides the line-number gutter. | Custom gutter view alongside the text container (again, no stock AppKit equivalent — `NSTextView` has no built-in line-number ruler; this is shared infrastructure with `NSRulerView`-based approaches used by many third-party Mac code editors). | M | E |
| MRG-02 | Right-click bookmark margin, or Preferences > Editing | Bookmark margin toggle | none | Shows/hides the bookmark-glyph gutter column used by BKMK-01. | Part of the same custom-gutter component as MRG-01. | S | E |
| MRG-03 | Preferences > Editing (not directly in View menu) | Change History margin toggle | none | Shows/hides the colored gutter stripe marking added/modified/reverted lines, feeding SRCH-21/22. | Same gutter component, third column; depends on the change-tracking model from SRCH-21. | S | I |

---

## 19. View Menu — Scrolling, Text Direction

| ID | Menu path | Command | Default Windows shortcut | Behavior (1-2 sentences) | macOS equivalent/notes | Complexity (S/M/L/XL) | Tier (E/I/N) |
|---|---|---|---|---|---|---|---|
| SCR-01 | View > Synchronize Vertical Scrolling | Sync Vertical Scrolling | none | Locks vertical scroll position between the two split Views. | Simple offset-coupling once split views + PNL-00-style layout exist. | S | I |
| SCR-02 | View > Synchronize Horizontal Scrolling | Sync Horizontal Scrolling | none | Same, horizontal — combined with cloning the same doc into both Views (MVCL-02), produces a "two newspaper columns" reading trick. | S | N |
| DIR-01 | View > Text Direction RTL | RTL text direction | Ctrl+Alt+R (note: this is `IDM_EDIT_RTL` in source, i.e. it's registered under the Edit command namespace even though it lives in the View menu) | Switches the active document to right-to-left rendering for Arabic/Hebrew-type scripts; per-file since v8.6.1 (stored in session XML as `RTL="yes/no"`); requires disabling "Use DirectWrite" and restarting on Windows — a Windows-specific rendering-backend conflict that has no macOS analog. | `NSWritingDirection`/`NSParagraphStyle.baseWritingDirection` on the text container — Cocoa text rendering handles RTL natively and far more robustly than Scintilla's DirectWrite-dependent hack. This is a case where the Mac platform primitive is strictly better; no need to replicate the DirectWrite restart caveat at all. | M | I |
| DIR-02 | View > Text Direction LTR | LTR text direction | Ctrl+Alt+L (`IDM_EDIT_LTR`) | Reverts to left-to-right. | S | I |

---

## Summary counts (for quick reference — full detail lives in the tables above)

- Search menu (incl. Mark/Bookmark/Change-History families and dialog-only accelerators): 68 commands
- Find/Replace/Find-in-Files/Find-in-Projects/Mark dialog controls: 40 controls
- Regex engine compatibility notes: 14 rows
- Search Results panel: 6 controls
- View menu (modes, symbols, zoom, move/clone, tabs, folding, panels, margins, scrolling/direction): 61 commands
