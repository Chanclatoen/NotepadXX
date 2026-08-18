# Roadmap

Ordered by what makes NotepadXX trustworthy first, then by what makes it
Notepad++ rather than a generic editor. Parity is tracked against the matrices
in `docs/parity/` (~884 catalogued commands).

## Done

**Foundation**
- [x] Tabs, open/save/save as/save all/close, CLI open at `file:line:column`
- [x] Session restore with crash-safe unsaved buffers (verified against `kill -9`)
- [x] Encoding detection, BOM handling, convert-to vs encode-in
- [x] Line ending detection/conversion, status bar
- [x] Large-file performance: 100MB / 927k lines opens in 401ms

**Editing**
- [x] Line operations, case conversions, blank operations, tab/space conversion
- [x] Column Editor (text and incrementing numbers, dec/oct/hex/bin)
- [x] Bookmarks with gutter markers, navigation, cut/copy/remove
- [x] Brace matching (comment- and string-aware), smart highlight
- [x] Show whitespace / tabs / EOL, zoom, word wrap, line numbers

**Search**
- [x] Normal/Extended/Regex, case, whole word, wrap, backward, in-selection
- [x] Find/Replace panel, clickable Search Results, recursive Find in Files

**Languages**
- [x] Keyword/delimiter lexer, 24 built-in languages, extension + shebang detection
- [x] Incremental viewport highlighting (sub-50ms on a 200k-line file)
- [x] Folding (brace and indentation), Function List
- [x] Autocomplete (words/keywords/functions/paths), call tips
- [x] UDL import/export in the real Notepad++ XML format

**Views**
- [x] Dockable panel framework, split view with shared-buffer clone
- [x] Document Map, Function List, Folder as Workspace, Clipboard History,
      Character Panel
- [x] Full screen, distraction-free, always-on-top equivalent

**Automation and customisation**
- [x] Macros (record/playback/N-times/until-EOF), Run menu with variables
- [x] Preferences (10 pages), themes, Shortcut Mapper with conflict detection
- [x] Plugin system (JavaScriptCore) + Plugins Admin

**Distribution**
- [x] Notarization pipeline written; every step validated except the
      notarytool call, which needs credentials (see below)

## Remaining

**Files/Tabs**
- [ ] Tab reorder by drag, pin/lock, per-tab colour, sort tabs
- [ ] Recent files menu, print, drag-and-drop of files onto the window
- [ ] File-change detection UI (the model exists; the prompt does not)
- [ ] Rename / move / delete from the File menu

**Editing**
- [ ] Multi-caret editing beyond what the engine provides by default
- [ ] Change-history margin, edge guide rendering, clickable URLs

**Languages**
- [ ] The remaining ~70 built-in languages (data entries, not new code)
- [ ] UDL authoring GUI (import/export and the lexer engine already work)

**Views/Sessions**
- [ ] Project panels and project files, named sessions

**Distribution**
- [ ] Notarized DMG — **blocked**: needs a Developer ID Application
      certificate plus `NOTARY_APPLE_ID`/`NOTARY_PASSWORD`/`NOTARY_TEAM_ID`
      or an App Store Connect API key. `scripts/release.sh` refuses to run
      without them rather than emitting a build Gatekeeper would reject.

## Open decisions

- **Regex flavor.** Notepad++ uses Boost; `NSRegularExpression` is ICU. `\K`,
  conditionals, recursion and `\g{NAME}` have no ICU equivalent. Currently
  these surface as errors rather than being silently reinterpreted. Either
  document the divergence in-app or vendor a Boost-compatible engine.
- **Unbounded large files.** Storage is ~6x file size in RAM, so multi-GB
  files are not supported. True GB-scale needs chunked/memory-mapped storage.
- **Native plugin tier.** The script tier cannot register dockable panels. An
  XPC-hosted native tier would allow it, direct-download only.
