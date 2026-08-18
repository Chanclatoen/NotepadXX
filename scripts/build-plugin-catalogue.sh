#!/bin/bash
# Packages the bundled plugins as zips and writes a catalogue with real
# SHA-256 checksums, so Plugins Admin's Available tab works out of the box and
# the checksum verification path is exercised by the shipped catalogue itself.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Resolve to an absolute path: the zip step runs from inside each plugin
# directory, so a relative destination would land in the wrong place.
RESOURCES_ARG=${1:-dist/NotepadXX.app/Contents/Resources}
mkdir -p "$RESOURCES_ARG/plugins"
RESOURCES="$(cd "$RESOURCES_ARG" && pwd)"

entries=""
for dir in "$REPO_ROOT"/plugins/*/; do
  id=$(basename "$dir")
  [ -f "$dir/plugin.json" ] || continue

  archive="$RESOURCES/plugins/$id.zip"
  rm -f "$archive"
  (cd "$dir" && zip -q -r "$archive" .)

  sha=$(shasum -a 256 "$archive" | awk '{print $1}')
  read -r name version desc <<<"$(/usr/bin/python3 -c "
import json
m = json.load(open('$dir/plugin.json'))
print(m['name'].replace(' ', ' '), m['version'], m.get('description','').replace(' ', ' '))
")"
  name=${name//$' '/ }
  desc=${desc//$' '/ }

  url="file://$RESOURCES/plugins/$id.zip"
  [ -n "$entries" ] && entries="$entries,"
  entries="$entries{\"identifier\":\"$id\",\"name\":\"$name\",\"version\":\"$version\",\"description\":\"$desc\",\"downloadURL\":\"$url\",\"sha256\":\"$sha\",\"author\":\"NotepadXX\"}"
done

printf '{"name":"NotepadXX Bundled Plugins","plugins":[%s]}\n' "$entries" \
  > "$RESOURCES/plugin-catalogue.json"
echo "catalogue: $(/usr/bin/python3 -c "import json;print(len(json.load(open('$RESOURCES/plugin-catalogue.json'))['plugins']))") plugins"
