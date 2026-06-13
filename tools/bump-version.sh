#!/usr/bin/env bash
# Increment InkIt's version for the next release.
#
#   ./tools/bump-version.sh [patch|minor|major]    (default: patch)
#
# Reads the current marketing version (CFBundleShortVersionString) from
# InkIt/Info.plist, increments it, and also bumps CFBundleVersion — Sparkle's
# monotonic build number, which must strictly increase every release. Prints the
# new marketing version on stdout. Does NOT commit (the caller does that).

set -euo pipefail

cd "$(dirname "$0")/.."

PLIST="InkIt/Info.plist"
PB="/usr/libexec/PlistBuddy"
LEVEL="${1:-patch}"

cur="$($PB -c 'Print CFBundleShortVersionString' "$PLIST")"
case "$cur" in
  *[!0-9.]*) echo "Error: version '$cur' isn't plain X.Y.Z — bump InkIt/Info.plist by hand." >&2; exit 1 ;;
esac
IFS=. read -r maj min pat <<EOF
$cur
EOF
maj=${maj:-0}; min=${min:-0}; pat=${pat:-0}

case "$LEVEL" in
  major) maj=$((maj + 1)); min=0; pat=0 ;;
  minor) min=$((min + 1)); pat=0 ;;
  patch) pat=$((pat + 1)) ;;
  *) echo "usage: $0 [patch|minor|major]" >&2; exit 1 ;;
esac
new="$maj.$min.$pat"

# Never reuse a tag — guards against Info.plist drifting behind the releases.
git fetch --tags -q origin 2>/dev/null || true
if git rev-parse "v$new" >/dev/null 2>&1; then
  echo "Error: tag v$new already exists. Info.plist ($cur) is behind the releases — set it past the latest tag first." >&2
  exit 1
fi

build="$($PB -c 'Print CFBundleVersion' "$PLIST")"
$PB -c "Set CFBundleShortVersionString $new" "$PLIST"
$PB -c "Set CFBundleVersion $((build + 1))" "$PLIST"

echo "$new"
