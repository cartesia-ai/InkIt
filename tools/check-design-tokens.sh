#!/usr/bin/env bash

set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

violations=0

scan() {
  local pattern="$1" label="$2" first=1
  while IFS= read -r hit; do
    local content="${hit#*:*:}"
    [[ "$content" == *"static let "* ]] && continue
    [[ "$content" == *"ds-allow"* ]] && continue
    local trimmed="${content#"${content%%[![:space:]]*}"}"
    [[ "$trimmed" == //* ]] && continue
    if [ "$first" = 1 ]; then echo "✗ $label:"; first=0; fi
    echo "    $hit"
    violations=$((violations + 1))
  done < <(grep -rnE "$pattern" InkIt/*.swift || true)
}

scan 'system\(size: *[0-9]'  'hardcoded font size — use a Font.ink* token'
scan '\.ink[A-Za-z]+\.weight\(\.(semibold|bold|heavy|black)' 'heavy weight escalation on a Font.ink* token — bold is retired, semibold is display-only; add a token instead'
scan 'Color\((red|white):'   'raw color literal — use a Color token'
scan 'easeOut\(duration:'    'hardcoded animation timing — use a Motion.* token'
scan '\.black\.opacity\('    'raw shadow/scrim ink — use an Elevation.* / Color token'

if [ "$violations" -gt 0 ]; then
  echo
  echo "Found $violations hardcoded design value(s) outside the design system."
  echo "Use a Font.ink* / Color token, or justify a true one-off with  // ds-allow: <reason>"
  exit 1
fi

echo "✓ design tokens: no unjustified literals"
