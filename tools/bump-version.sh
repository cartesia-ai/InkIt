#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

YML="project.yml"
PLIST="InkIt/Info.plist"
PB="/usr/libexec/PlistBuddy"
LEVEL="${1:-patch}"

cur="$(sed -n 's/.*CFBundleShortVersionString: *"\([0-9.]*\)".*/\1/p' "$YML" | head -1)"
build="$(sed -n 's/.*CFBundleVersion: *"\([0-9]*\)".*/\1/p' "$YML" | head -1)"
[ -n "$cur" ] || { echo "Error: couldn't read CFBundleShortVersionString from $YML." >&2; exit 1; }
[ -n "$build" ] || { echo "Error: couldn't read CFBundleVersion from $YML." >&2; exit 1; }
case "$cur" in
  *[!0-9.]*) echo "Error: version '$cur' isn't plain X.Y.Z — bump $YML by hand." >&2; exit 1 ;;
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
newbuild=$((build + 1))

git fetch --tags -q origin 2>/dev/null || true
if git rev-parse "v$new" >/dev/null 2>&1; then
  echo "Error: tag v$new already exists. project.yml ($cur) is behind the releases — set it past the latest tag first." >&2
  exit 1
fi

sed -i '' "s/\(CFBundleShortVersionString: *\"\)[0-9.]*\"/\1$new\"/" "$YML"
sed -i '' "s/\(CFBundleVersion: *\"\)[0-9]*\"/\1$newbuild\"/" "$YML"

$PB -c "Set CFBundleShortVersionString $new" "$PLIST"
$PB -c "Set CFBundleVersion $newbuild" "$PLIST"

echo "$new"
