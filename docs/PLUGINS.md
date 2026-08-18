# Writing a NotepadXX plugin

Plugins are JavaScript, not native code. A dylib cannot be sandboxed or safely
revoked and would tie every plugin to our exact binary layout; scripts also
cover the large majority of what Notepad++ plugins actually do (text
transforms, linters, formatters, build runners).

## Layout

A plugin is a folder containing `plugin.json` and its script:

```
com.example.shout/
  plugin.json
  main.js
```

Install it with **Plugins > Plugins Admin… > Install…**, or drop the folder in
**Plugins > Open Plugins Folder** and press Reload.

## plugin.json

```json
{
  "name": "Shout",
  "identifier": "com.example.shout",
  "version": "1.0.0",
  "description": "Uppercases the document",
  "author": "you",
  "main": "main.js",
  "commands": [
    { "id": "shout", "title": "Uppercase Document", "keyEquivalent": "" },
    { "id": "count", "title": "Count Characters", "handler": "countChars" }
  ]
}
```

Each command becomes a menu item under **Plugins > <name>**. `handler` names
the exported function; it defaults to `id`.

The `identifier` must be unique — a second plugin claiming an identifier
already in use is listed as a conflict rather than silently replacing the
first. It also names the folder on disk, sanitised so a hostile manifest
cannot write outside the plugins directory.

## main.js

Export one function per command:

```js
exports.shout = function () {
  notepadxx.setText(notepadxx.getText().toUpperCase());
  console.log("shouted");
};

exports.countChars = function () {
  notepadxx.showMessage("Characters: " + notepadxx.getText().length);
};
```

Each plugin runs in its own function scope, so two plugins declaring the same
top-level variable do not clobber each other.

## API

Everything reachable from a plugin is on the `notepadxx` global. Plugins never
touch AppKit or the document objects directly, which keeps the surface small
enough to document and means a misbehaving plugin cannot corrupt editor state
in ways the host has not sanctioned.

| Call | Returns | Notes |
|---|---|---|
| `notepadxx.getText()` | string | The active document's full text |
| `notepadxx.setText(s)` | — | Replaces the document; one undo step |
| `notepadxx.getSelection()` | `{location, length}` | UTF-16 offsets |
| `notepadxx.setSelection(loc, len)` | — | |
| `notepadxx.replaceSelection(s)` | — | Inserts at the caret when the selection is empty |
| `notepadxx.getFilePath()` | string \| null | null for an unsaved buffer |
| `notepadxx.getDocumentCount()` | number | Open tabs |
| `notepadxx.showMessage(s)` | — | Modal alert |
| `notepadxx.log(s)` | — | Also available as `console.log` |

## Errors

A script that fails to parse, or a command whose handler is not exported, is
reported in Plugins Admin against that plugin and the plugin is not enabled —
it is never dropped silently. A command that throws at run time shows the
JavaScript error rather than doing nothing.

## Limits

This is the script tier. It deliberately cannot register dockable panels or
draw custom UI. A second native tier (XPC-hosted, notarized, direct-download
only) is the intended home for that; it is not implemented yet.
