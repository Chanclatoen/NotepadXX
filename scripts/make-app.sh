#!/bin/bash
# Assembles NotepadXX.app from the SwiftPM executable.
# Ad-hoc signed for local runs; CI re-signs with a Developer ID for release.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
APP="dist/NotepadXX.app"

swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/NotepadXX

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotepadXX"

# The icon is generated from scripts/make-icon.swift, so it is drawn from the
# same design tokens as the app rather than kept as an opaque binary blob.
if [[ ! -f Resources/AppIcon.icns ]] || [[ scripts/make-icon.swift -nt Resources/AppIcon.icns ]]; then
  swift scripts/make-icon.swift Resources >/dev/null
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NotepadXX</string>
    <key>CFBundleDisplayName</key><string>NotepadXX</string>
    <key>CFBundleIdentifier</key><string>nl.jmour.notepadxx</string>
    <key>CFBundleExecutable</key><string>NotepadXX</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# The bundled plugin catalogue must exist before signing, or the signature
# would not cover it.
./scripts/build-plugin-catalogue.sh "$APP/Contents/Resources"

codesign --force --deep --sign - "$APP"
echo "built $APP"
