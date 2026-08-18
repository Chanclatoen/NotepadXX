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

# Fall back to the Developer ID identity in the keychain, so a machine that
# already has one does not need it spelled out.
if [[ -z "${DEVELOPER_ID:-}" ]]; then
  DEVELOPER_ID=$(security find-identity -v -p codesigning |
    sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
fi
if [[ -z "$DEVELOPER_ID" ]]; then
  echo "error: no Developer ID Application identity found." >&2
  echo "Without one only ad-hoc signing is possible, which Gatekeeper will" >&2
  echo "refuse on another machine. Set DEVELOPER_ID or install the certificate." >&2
  exit 1
fi
echo "==> identity: $DEVELOPER_ID"

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

# Notarization needs credentials beyond the certificate. Without them the
# build is still Developer ID signed and installable, but Gatekeeper shows a
# warning on first launch on another Mac, so say so plainly rather than
# implying the artifact is fully blessed.
if [[ -z "${NOTARY_APPLE_ID:-}" && -z "${NOTARY_KEY_ID:-}" && -z "${NOTARY_PROFILE:-}" ]]; then
  echo "==> SIGNED but NOT notarized: $DMG"
  echo "    Signed with: $DEVELOPER_ID"
  echo "    Gatekeeper will warn on first launch on another Mac until this is"
  echo "    notarized. Re-run with NOTARY_APPLE_ID/NOTARY_PASSWORD/NOTARY_TEAM_ID,"
  echo "    or NOTARY_PROFILE=<keychain profile>, to complete notarization."
  exit 0
fi

echo "==> notarize"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --wait --keychain-profile "$NOTARY_PROFILE"
elif [[ -n "${NOTARY_KEY_ID:-}" ]]; then
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
