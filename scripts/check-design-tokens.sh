#!/usr/bin/env bash
#
# Design-system guard. Display text and colors must come from the named tokens
# defined once in the Font / Color extensions at the top of InkIt/InkItApp.swift
# (Font.inkBody, Color.canvas, …). Views never re-enter a bare `.system(size:)`
# or a raw RGB/hex color — that's how the scale and palette drift.
#
# A genuine one-off (an icon glyph sized to its container, a bespoke compact
# surface like the notch HUD, the dual-appearance preview) may opt out with a
# trailing  // ds-allow: <reason>  on the same line.
#
# This runs in CI and fails the build on any unjustified literal. Run it locally
# anytime:  ./scripts/check-design-tokens.sh
# See DESIGN_SYSTEM.md and AGENTS.md.

set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

violations=0

scan() {
  local pattern="$1" label="$2" first=1
  while IFS= read -r hit; do
    local content="${hit#*:*:}"                       # strip "file:lineno:"
    [[ "$content" == *"static let ink"* ]] && continue   # token definitions
    [[ "$content" == *"ds-allow"* ]] && continue         # explicit opt-out
    local trimmed="${content#"${content%%[![:space:]]*}"}"
    [[ "$trimmed" == //* ]] && continue                  # comment lines
    if [ "$first" = 1 ]; then echo "✗ $label:"; first=0; fi
    echo "    $hit"
    violations=$((violations + 1))
  done < <(grep -rnE "$pattern" InkIt/*.swift || true)
}

scan 'system\(size: *[0-9]'  'hardcoded font size — use a Font.ink* token'
scan 'Color\((red|white):'   'raw color literal — use a Color token'

if [ "$violations" -gt 0 ]; then
  echo
  echo "Found $violations hardcoded design value(s) outside the design system."
  echo "Use a Font.ink* / Color token, or justify a true one-off with  // ds-allow: <reason>"
  exit 1
fi

echo "✓ design tokens: no unjustified literals"
