#!/usr/bin/env bash
# Generate the Sparkle appcast for a manually built release DMG.
#
# Run after tools/make-dmg.sh, then attach both files to the GitHub Release:
#   - build/dist/InkIt.dmg
#   - build/dist/appcast.xml

set -euo pipefail

cd "$(dirname "$0")/.."

DMG_PATH="${1:-build/dist/InkIt.dmg}"
APPCAST_DIR="build/dist/appcast"
APPCAST_PATH="build/dist/appcast.xml"
# Trailing slash is required: generate_appcast joins this with the filename via
# RFC 3986 rules, so without it the final "download" segment gets replaced
# (".../latest/download" + "InkIt.dmg" -> ".../latest/InkIt.dmg", a 404).
DOWNLOAD_URL_PREFIX="https://github.com/cartesia-ai/InkIt/releases/latest/download/"

fail() { printf "\n\033[1;31mError:\033[0m %s\n" "$1"; exit 1; }
step() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }

[ -f "$DMG_PATH" ] || fail "DMG not found at $DMG_PATH. Run tools/make-dmg.sh first, or pass a DMG path."

PUBLIC_KEY="$(sed -n 's/^SPARKLE_PUBLIC_ED_KEY[[:space:]]*=[[:space:]]*//p' Config/Sparkle.xcconfig | tr -d '[:space:]')"
[ -n "$PUBLIC_KEY" ] || fail "Config/Sparkle.xcconfig is missing SPARKLE_PUBLIC_ED_KEY. Generate Sparkle keys first."

GENERATE_APPCAST="$(find build -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -type f | head -1)"
[ -n "$GENERATE_APPCAST" ] || fail "Sparkle generate_appcast not found. Run xcodebuild or tools/make-dmg.sh first."

step "Preparing appcast input"
rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$DMG_PATH" "$APPCAST_DIR/InkIt.dmg"

step "Generating signed Sparkle appcast"
"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --maximum-versions 1 \
  -o "$APPCAST_DIR/appcast.xml" \
  "$APPCAST_DIR"

cp "$APPCAST_DIR/appcast.xml" "$APPCAST_PATH"

step "Done"
printf "Sparkle appcast ready: \033[1m%s\033[0m\n" "$APPCAST_PATH"
