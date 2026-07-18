#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

KEYCHAIN_PROFILE="inkit-notary"
APP_PATH="build/Build/Products/Release/InkIt.app"
DMG_PATH="build/dist/InkIt.dmg"
STAGING_DIR="build/dist/dmg-staging"
ICON_PATH="InkIt/Assets.xcassets/AppIcon.appiconset/app-icon-512.png"
BG_1X="tools/assets/dmg-background.png"
BG_2X="tools/assets/dmg-background@2x.png"

step() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31mError:\033[0m %s\n" "$1"; exit 1; }

command -v create-dmg >/dev/null 2>&1 || fail "create-dmg not installed. Run: brew install create-dmg"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not available — install Xcode."
command -v xcodegen >/dev/null 2>&1 || fail "xcodegen not installed. Run: brew install xcodegen"
[ -f Config/Signing.local.xcconfig ] \
  || fail "Config/Signing.local.xcconfig missing — release builds need a Developer ID. Copy Config/Signing.local.xcconfig.example and fill in your Team ID."
xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1 \
  || fail "Keychain profile '$KEYCHAIN_PROFILE' missing. See setup steps at top of this script."

step "Generating Xcode project from project.yml"
xcodegen generate

step "Building Release"
xcodebuild \
  -project InkIt.xcodeproj \
  -scheme InkIt \
  -configuration Release \
  -derivedDataPath build \
  build \
  | xcbeautify 2>/dev/null || xcodebuild \
    -project InkIt.xcodeproj \
    -scheme InkIt \
    -configuration Release \
    -derivedDataPath build \
    build \
    | tail -5

[ -d "$APP_PATH" ] || fail "Release build missing at $APP_PATH"

step "Verifying signature on .app"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime" || true

ADHOC=$(find "$APP_PATH/Contents/Frameworks/Sparkle.framework" \
    \( -name '*.xpc' -o -name '*.app' -o -name 'Autoupdate' \) -print 2>/dev/null \
  | while read -r b; do codesign -dvv "$b" 2>&1 | grep -q 'Signature=adhoc' && echo "$b"; done) || true
if [ -n "$ADHOC" ]; then
  fail "Ad-hoc (unsigned) nested binaries found — notarization will reject these:
$ADHOC
Check the 'Deep-sign Sparkle helpers' postBuildScript in project.yml."
fi

step "Staging app for DMG"
mkdir -p build/dist
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

step "Regenerating background art"
swift tools/generate_dmg_background.swift

step "Clearing Finder icon cache for old DMG view"
osascript -e 'tell application "Finder" to close (every window whose name is "InkIt")' >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true

step "Building DMG layout"
create-dmg \
  --volname "InkIt" \
  --background "$BG_1X" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "InkIt.app" 160 200 \
  --hide-extension "InkIt.app" \
  --app-drop-link 440 200 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGING_DIR/"

rm -rf "$STAGING_DIR"

step "Signing DMG"
codesign --sign "Developer ID Application" \
  --timestamp \
  "$DMG_PATH"

step "Submitting DMG to notarization (this takes 1-5 min)"
NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait 2>&1 | tee /dev/stderr)
NOTARY_ID=$(echo "$NOTARY_OUTPUT" | awk '/id:/{print $2; exit}')
if ! echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
  printf "\n\033[1;31mNotarization failed.\033[0m Fetching log for id %s:\n\n" "$NOTARY_ID"
  xcrun notarytool log "$NOTARY_ID" --keychain-profile "$KEYCHAIN_PROFILE"
  exit 1
fi

step "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

step "Done"
printf "Notarized DMG ready: \033[1m%s\033[0m\n" "$DMG_PATH"
printf "Verify on a clean machine: spctl -a -t open --context context:primary-signature %s\n" "$DMG_PATH"
