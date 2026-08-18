# NotepadXX

Notepad++ for macOS. Native Swift/AppKit, MIT licensed.

Not a "Mac editor inspired by Notepad++" — the goal is functional parity. The
matrices in `docs/parity/` enumerate **~884 user-visible commands** from the
Notepad++ manual and source; the project is done when each is implemented or has
a documented OS-level reason to differ.

## Why this exists

macOS has good editors, but nothing combines what Notepad++ users actually rely
on: native and instant-launching, a scratchpad you can trust with unsaved work,
real rectangular/column selection, find-in-files with a clickable results tree,
and GUI-authored custom syntax highlighting — free, with no nag screens.

## Status

Working editor, not yet at parity. Implemented and verified:

- Tabs, open/save/save-as/save-all/close, CLI open at `file:line:column`
- Session restore including **crash-safe unsaved buffers** — untitled scratch
  buffers survive `kill -9` and come back with no save prompt
- Syntax highlighting for 96 languages, folding, Function List, autocomplete with call tips
- Column mode with the Column Editor, bookmarks, brace matching
- Find/Replace, Find in Files with a clickable results panel
- Split view, Document Map, Folder as Workspace, Clipboard History
- Macros, Run menu, Preferences, themes, Shortcut Mapper
- A JavaScript plugin system with Plugins Admin (see `docs/PLUGINS.md`)
- Encoding/BOM handling with Notepad++'s "Convert to" vs "Encode in" split
- Large-file performance validated (see below)

Every feature category in the parity matrices now has a working
implementation. See `docs/ROADMAP.md` for the remaining detail.

## Performance

Measured on an M4 MacBook Pro, release build:

| file | result |
|---|---|
| 100 MB log, 926,660 lines | opens in **401 ms** |
| edit (insert at start) | 1.0 ms |
| scroll to bottom | 4.9 ms |
| peak memory | 625 MB |

For comparison, CotEditor beachballs on a 120MB file (their issue #1924).

Known limit: memory is ~6x file size, so multi-GB files are not yet supported.
Documents consisting of one multi-megabyte line cost ~65-80ms per edit.

## Building

Requires macOS 14+ and Swift 6.

```sh
swift test          # 34 tests
./scripts/make-app.sh   # produces dist/NotepadXX.app
```

## Documentation

- `docs/ARCHITECTURE.md` — engine choice, the performance rule, rejected
  dependencies and why
- `docs/parity/` — the full Notepad++ command matrices
- `docs/ROADMAP.md` — order of work

## License

MIT. See `LICENSE`.
