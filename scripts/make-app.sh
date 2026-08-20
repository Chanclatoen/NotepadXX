#!/bin/bash
# Assembles NotepadXX.app from the SwiftPM executable.
# Ad-hoc signed for local runs; CI re-signs with a Developer ID for release.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
APP="dist/NotepadXX.app"

# A universal build is opt-in because the second slice is a full cross-compile
# and takes minutes; day-to-day builds do not need it, releases do.
#
# The two slices are built separately and joined with lipo rather than passing
# --arch twice: multiple architectures route SwiftPM through the Xcode build
# system, which cannot resolve the SwiftLint build-tool plugin this package
# pulls in ("Missing package product 'SwiftLint@11'").
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  echo "==> building arm64"
  swift build -c "$CONFIG" --triple arm64-apple-macosx14.0
  echo "==> building x86_64 (cross-compile, slow)"
  swift build -c "$CONFIG" --triple x86_64-apple-macosx14.0

  ARM=$(swift build -c "$CONFIG" --triple arm64-apple-macosx14.0 --show-bin-path)/NotepadXX
  INTEL=$(swift build -c "$CONFIG" --triple x86_64-apple-macosx14.0 --show-bin-path)/NotepadXX
  BIN="$(mktemp -d)/NotepadXX"
  lipo -create -output "$BIN" "$ARM" "$INTEL"
  echo "==> universal: $(lipo -archs "$BIN")"
else
  swift build -c "$CONFIG"
  BIN=$(swift build -c "$CONFIG" --show-bin-path)/NotepadXX
fi

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
    <key>CFBundleShortVersionString</key><string>0.1.1</string>
    <key>CFBundleVersion</key><string>2</string>
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
