#!/bin/bash
# Builds, signs, notarizes and staples NotepadXX, then produces a DMG.
#
# Requires (from the environment, never committed):
#   DEVELOPER_ID       e.g. "Developer ID Application: Jane Doe (TEAMID)"
#   NOTARY_APPLE_ID    Apple ID for notarytool
#   NOTARY_PASSWORD    app-specific password
#   NOTARY_TEAM_ID     Apple Developer team id
# Or, for API-key auth instead of Apple ID:
#   NOTARY_KEY_ID, NOTARY_KEY_ISSUER, NOTARY_KEY_PATH
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/NotepadXX.app"
DMG="dist/NotepadXX.dmg"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")

if [[ -z "${DEVELOPER_ID:-}" ]]; then
  echo "error: DEVELOPER_ID is not set." >&2
  echo "A Developer ID Application certificate is required to produce a" >&2
  echo "distributable build. Without it only ad-hoc signing is possible," >&2
  echo "which Gatekeeper will refuse on another machine." >&2
  exit 1
fi

echo "==> build"
CONFIG=release ./scripts/make-app.sh

echo "==> sign ($VERSION)"
# Nested code must be signed before the enclosing bundle.
find "$APP/Contents" -type f \( -name "*.dylib" -o -name "*.framework" \) -print0 |
  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$item"
  done
codesign --force --options runtime --timestamp \
  --entitlements scripts/NotepadXX.entitlements \
  --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> package"
rm -f "$DMG"
hdiutil create -volname "NotepadXX" -srcfolder "$APP" -ov -format ULFO "$DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

echo "==> notarize"
if [[ -n "${NOTARY_KEY_ID:-}" ]]; then
  xcrun notarytool submit "$DMG" --wait \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_KEY_ISSUER"
else
  xcrun notarytool submit "$DMG" --wait \
    --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID"
fi

echo "==> staple"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "==> OK: $DMG"
