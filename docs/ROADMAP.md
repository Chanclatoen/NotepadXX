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

**Files and tabs**
- [x] Recent files, print, rename/move/trash, reload from disk, copy path
- [x] Tab reorder by drag, pin, colour, sort, close variants, read-only
- [x] File-change detection, drag-and-drop of files onto the window

**Automation and customisation**
- [x] Macros (record/playback/N-times/until-EOF), Run menu with variables
- [x] Preferences (10 pages), themes, Shortcut Mapper with conflict detection
- [x] Plugin system (JavaScriptCore) + Plugins Admin
- [x] 73 built-in languages, UDL authoring GUI
- [x] Projects and named sessions

**Distribution**
- [x] Notarization pipeline written; every step validated except the
      notarytool call, which needs credentials (see below)

**Editing and views (complete)**
- [x] Change-history margin with two-tier tracking and navigation
- [x] Edge guide, clickable URLs
- [x] Docked project panel, vertical and multi-line tab layouts, floating panels

- [x] 95 lexers, per-language completion data with call-tip signatures

**Distribution**
- [x] Developer ID signed DMG produced by `./scripts/release.sh`, with the
      hardened runtime and a secure timestamp. `spctl` reports
      "Unnotarized Developer ID" — the signature is recognised.
- [ ] Notarization — **deliberately not done.** The app is signed and
      installable; notarizing additionally removes Gatekeeper's first-launch
      warning on other Macs. Jaber declined to notarize under the App Store
      Connect key on this machine, which belongs to another project. Run
      `NOTARY_PROFILE=<profile> ./scripts/release.sh` (or supply
      `NOTARY_APPLE_ID`/`NOTARY_PASSWORD`/`NOTARY_TEAM_ID`) to complete it.

## Remaining

Nothing outstanding in the parity matrices. Future work is depth rather than
coverage: more languages, richer completion data, a native XPC plugin tier,
and chunked storage for multi-GB files.

## Open decisions

- **Regex flavor.** Notepad++ uses Boost; `NSRegularExpression` is ICU. `\K`,
  conditionals, recursion and `\g{NAME}` have no ICU equivalent. Currently
  these surface as errors rather than being silently reinterpreted. Either
  document the divergence in-app or vendor a Boost-compatible engine.
- **Unbounded large files.** Storage is ~6x file size in RAM, so multi-GB
  files are not supported. True GB-scale needs chunked/memory-mapped storage.
- **Native plugin tier.** The script tier cannot register dockable panels. An
  XPC-hosted native tier would allow it, direct-download only.
