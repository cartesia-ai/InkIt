#!/usr/bin/env bash
# Publish a GitHub Release for InkIt from already-built artifacts.
#
# Run AFTER ./tools/make-dmg.sh (and ./tools/make-appcast.sh if you want existing
# users to auto-update). This handles only the GitHub side: tag, upload, notes.
#
#   ./tools/publish-release.sh [version] [--draft]
#     version     e.g. 0.2.0 (leading "v" optional). Omit to read the version
#                 from InkIt/Info.plist — the version the DMG was built with, so
#                 the tag always matches the binary.
#     --draft     stage as a draft to review before publishing (default: publish)
#
# Uploads three assets so the README button keeps working:
#   InkIt_<version>_arm64.dmg   versioned, shown on the releases page
#   InkIt.dmg                   stable name the README button downloads
#   appcast.xml                 Sparkle auto-update feed (if present)

set -euo pipefail

cd "$(dirname "$0")/.."

REPO="cartesia-ai/InkIt"
DMG="build/dist/InkIt.dmg"
APPCAST="build/dist/appcast.xml"

step() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31mError:\033[0m %s\n" "$1"; exit 1; }
confirm() { read -r -p "$1 [y/N] " yn; [ "$yn" = "y" ] || [ "$yn" = "Y" ] || fail "Aborted."; }

# --- args (version and --draft may appear in any order) ---
VER=""
DRAFT_FLAG=""
for a in "$@"; do
  case "$a" in
    --draft) DRAFT_FLAG="--draft" ;;
    -*) fail "unknown option: $a" ;;
    *) VER="$a" ;;
  esac
done

PLIST_VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' InkIt/Info.plist 2>/dev/null || true)"
if [ -z "$VER" ]; then
  [ -n "$PLIST_VER" ] || fail "no version given and couldn't read InkIt/Info.plist"
  VER="$PLIST_VER"      # default: ship the version the DMG was built with
fi
VER="${VER#v}"          # tolerate "v0.2.0"
TAG="v$VER"

# --- preflight ---
command -v gh >/dev/null 2>&1 || fail "gh CLI not found. Run: brew install gh"
[ -f "$DMG" ] || fail "$DMG not found — run ./tools/make-dmg.sh first."

if [ "$PLIST_VER" != "$VER" ]; then
  step "Version mismatch"
  echo "Info.plist says $PLIST_VER, but you asked to publish $VER."
  echo "The DMG was built from Info.plist, so its tag won't match its contents."
  confirm "Publish $VER anyway?"
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  fail "tag $TAG already exists — bump the version first (./tools/bump-version.sh)."
fi

step "Checking git state (the tag is created at origin/main)"
[ -z "$(git status --porcelain)" ] || { echo "Uncommitted changes — they will NOT be in the release."; confirm "Continue?"; }
git fetch -q origin main
if [ "$(git rev-parse @)" != "$(git rev-parse origin/main 2>/dev/null || echo none)" ]; then
  echo "Local main differs from origin/main. Push first so the tag lands on the right commit."
  confirm "Continue?"
fi

step "Verifying the DMG is signed, notarized, stapled"
xcrun stapler validate "$DMG" || fail "DMG is not stapled — re-run ./tools/make-dmg.sh."
spctl -a -t open --context context:primary-signature "$DMG" || fail "DMG fails Gatekeeper — do not ship."

# --- assemble assets ---
VDMG="build/dist/InkIt_${VER}_arm64.dmg"
cp "$DMG" "$VDMG"
ASSETS=("$VDMG" "$DMG")
if [ -f "$APPCAST" ]; then
  # Guard against a malformed enclosure URL (e.g. a missing trailing slash on the
  # generate_appcast prefix collapsing ".../latest/download/InkIt.dmg" down to
  # ".../latest/InkIt.dmg", which 404s and silently breaks auto-update).
  ENCLOSURE="$(grep -o 'url="[^"]*"' "$APPCAST" | grep -i '\.dmg' | head -1 | sed 's/^url="//;s/"$//')"
  [ -n "$ENCLOSURE" ] || fail "$APPCAST has no DMG enclosure URL — regenerate with ./tools/make-appcast.sh."
  case "$ENCLOSURE" in
    */releases/latest/download/InkIt.dmg) ;;  # correct: tracks the stable latest asset
    *) fail "appcast enclosure URL is wrong: $ENCLOSURE
   expected it to end in /releases/latest/download/InkIt.dmg — regenerate with ./tools/make-appcast.sh." ;;
  esac
  ASSETS+=("$APPCAST")
else
  echo "No $APPCAST — publishing without an auto-update feed."
  echo "(Run ./tools/make-appcast.sh first if existing users should auto-update.)"
  confirm "Publish without the appcast?"
fi

# --- publish ---
step "Creating release $TAG"
gh release create "$TAG" "${ASSETS[@]}" \
  --repo "$REPO" \
  --target main \
  --title "InkIt $VER" \
  --generate-notes \
  $DRAFT_FLAG

# --- verify ---
step "Assets on $TAG"
gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name'
URL="$(gh release view "$TAG" --repo "$REPO" --json url -q .url)"
if [ -n "$DRAFT_FLAG" ]; then
  printf "\n\033[1;32mDraft staged:\033[0m %s\n" "$URL"
  echo "Review it, then publish with:  gh release edit $TAG --repo $REPO --draft=false"
else
  printf "\n\033[1;32mPublished:\033[0m %s\n" "$URL"
  echo "Download button → https://github.com/$REPO/releases/latest/download/InkIt.dmg"
fi
