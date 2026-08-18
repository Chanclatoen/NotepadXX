# Roadmap

Ordered by what makes NotepadXX trustworthy first, then by what makes it
Notepad++ rather than a generic editor.

## v0.1 — Foundation (done)

- [x] Tabs, open/save/save as/save all/close
- [x] Session restore with crash-safe unsaved buffers
- [x] Encoding detection, BOM handling, convert-to vs encode-in
- [x] Line ending detection/conversion
- [x] Status bar
- [x] Large-file performance validated (100MB in 401ms)

## v0.2 — The differentiators

These are the features people say they cannot find on macOS.

- [ ] Rectangular/column selection + Column Editor dialog
- [ ] Multi-cursor editing
- [ ] Find/Replace dialog: Normal/Extended/Regex modes, match case, whole word,
      wrap, in-selection, backward
- [ ] Find in Files with a clickable, foldable Search Results panel
- [ ] Bookmarks and the bookmark margin
- [ ] Go to Line/Offset

## v0.3 — Language support

- [ ] tree-sitter highlighting (grammars packaged by us, license-clean)
- [ ] User Defined Language system + GUI editor, XML import/export
- [ ] Code folding
- [ ] Auto-completion (word/function), brace and tag matching
- [ ] Function List panel

## v0.4 — Panels and views

- [ ] Dockable panel framework (prerequisite for everything below)
- [ ] Split view / clone document to second view
- [ ] Document Map, Document List, Folder as Workspace, Clipboard History,
      Character Panel

## v0.5 — Automation

- [ ] Macro record/playback/save, run N times / to end of file
- [ ] Run menu with variable substitution
- [ ] Shortcut Mapper
- [ ] CLI shim (`notepadxx file:line:col`)

## v0.6 — Customisation

- [ ] Preferences (24 pages)
- [ ] Style Configurator, themes, dark mode
- [ ] Compare/diff built in

## v1.0 — Ship

- [ ] Plugin system (JavaScriptCore script tier + native XPC tier)
- [ ] Notarized DMG, Sparkle updates
- [ ] Parity matrix fully reconciled

## Open decisions

- **Regex flavor.** Notepad++ uses Boost; `NSRegularExpression` is ICU. `\K`,
  conditionals, recursion and `\g{NAME}` have no ICU equivalent. Either ship ICU
  and document divergence, or vendor a Boost-compatible engine. Must not
  silently reinterpret patterns.
- **Unbounded large files.** Current storage is ~6x file size in RAM. True
  GB-scale support needs chunked/memory-mapped storage.
- **Plugin tiers.** Script-only is App Store compatible; native XPC is more
  powerful but direct-download only.
