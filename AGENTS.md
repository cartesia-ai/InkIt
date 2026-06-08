# Contributing with a coding agent

Rules for AI coding agents (Claude Code, Cursor, Copilot, …) and humans working
on InkIt. CI enforces the mechanical ones — a PR that breaks them won't merge.

## Design system — use tokens, never hardcode

InkIt has one source of truth for type and color: the `Font` and `Color`
extensions at the top of `InkIt/InkItApp.swift` (`Font.inkBody`, `Font.inkTitle`,
`Color.canvas`, `Color.card`, the amber accent, …). Full rationale in
[`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md).

**Do**
- Use a named token for every piece of display text: `.font(.inkBody)`, not
  `.font(.system(size: 15))`.
- Use semantic color tokens / system semantics (`Color.canvas`, `.secondary`,
  `Color(nsColor: .separatorColor)`), not raw RGB or hex.
- Need a size or weight that doesn't exist yet? **Add a token** to the extension
  block (with a doc comment) and reference it — don't inline the literal.

**Don't**
- Re-enter a bare `.font(.system(size: N))` for display text.
- Write a raw `Color(red:…)` / hex color for app UI.

**The one escape hatch.** A genuine one-off — an SF Symbol icon glyph sized to
its container, a bespoke compact surface (the always-dark notch HUD), the
dual-appearance `AppearanceThumbnail` — may opt out with a trailing comment that
says why:

```swift
Image(systemName: "gearshape").font(.system(size: 17, weight: .medium))  // ds-allow: icon
```

Use it sparingly, and only for things that genuinely don't belong on the shared
scale. If a value recurs or is plain running text, it's a token, not a one-off.

**Check locally before pushing:**

```sh
./tools/check-design-tokens.sh
```

CI runs this on every PR (`.github/workflows/ci.yml`).

## Build & test

```sh
xcodegen generate                                   # regenerate the Xcode project
xcodebuild -project InkIt.xcodeproj -scheme InkIt -configuration Debug \
  -destination 'platform=macOS' test                # unit tests
```

`InkIt.xcodeproj` is generated from `project.yml` by XcodeGen — edit
`project.yml`, not the `.pbxproj`.

## Commit messages

The repo is public. Keep messages factual and low-profile.

- **Subject:** imperative, states *what changed* mechanically. No product or
  strategy framing, no editorializing, no intent cues. Avoid things like "prep
  for open source", "visual-first landing page", "privacy gating",
  "leaner/cleaner repo".
- **Body (optional):** only the technical mechanism a future maintainer needs
  (e.g. *why* a fix works). Never narrative about product or business goals.
- Propose messages for approval before committing.
