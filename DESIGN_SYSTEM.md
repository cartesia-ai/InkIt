# InkIt Design System

InkIt is an open-source showcase for Cartesia's `ink-2` speech-to-text — fast,
accurate, cuts through noise. The design exists to make the *model* the star: a
calm, native-feeling Mac app with one confident point of personality.

**Direction (locked):**

| Axis | Decision |
|---|---|
| Personality | Warm & precise — "signal clarity" |
| Accent | Amber |
| Typeface | SF Pro (system) — no custom faces |
| Onboarding | Tinted (subtle, on-brand) — no rainbow gradients |
| Appearance | Light **and** Dark, user-selectable (default: follow system) |

## Principles

1. **The model is the hero, the chrome is quiet.** Restraint over decoration.
   One accent, generous neutrals, system materials.
2. **Native first.** Lean on Apple's semantic colors, materials, and text styles
   so the app inherits Dark Mode, Increase Contrast, Reduce Transparency, and
   Dynamic Type for free. Define custom values *only* for brand identity (the
   accent) and the few places the system has no token (the recording amber).
3. **Accent = live signal, not background.** Amber marks interactive and active
   things (selection, toggles, buttons, focus). It is never a large fill.
4. **The notch HUD stays dark, always.** It lives in the menu-bar strip and must
   blend with the camera notch. Theme/appearance do not apply to it; the accent
   only appears in live feedback (recording dot, waveform).

---

## Color

### How it's built (the token rule)

Every color and type value comes from a **named token** — defined once in the
`extension Color` / `extension Font` block at the top of `InkItApp.swift`, backed
by the asset catalog. Views reference `Color.canvas`, `Font.inkTitle`, etc.; they
**never** re-enter a raw hex/RGB or a bare `.system(size:)` for display text. The
one sanctioned exception is the `AppearanceThumbnail` preview, which must render
both light and dark at once and so can't resolve an appearance-aware token.

- **Brand color → asset catalog.** Define an `AccentColor` color set with Any
  (light) and Dark appearances. Setting it as the project's accent makes every
  `Button`, `Toggle`, `Picker`, focus ring, and `.tint(.accent)` adopt amber
  automatically — no per-view wiring.
- **Warm-paper neutrals → asset catalog.** The chrome reads warmer than raw
  system gray. `canvas` / `surface` / `lift` / `card` / `paper` (each with a
  light + dark variant) back **every** surface — Home, Onboarding, *and*
  Settings — so the whole app is one paper. Settings still uses
  `.formStyle(.grouped)` for native layout, but hides the Form's system scroll
  background (`.scrollContentBackground(.hidden)`) and sits on `Color.canvas`.
- **Text foreground → system semantics.** `.primary`, `.secondary`, `.tertiary`,
  `Color(nsColor: .separatorColor)` for hairlines. These adapt to appearance +
  accessibility for free.
- **Custom brand tokens → color sets.** `recordingAmber` (live signal) and
  `diffAdd` (Polish "added" text). Everything else is semantic.

### Amber accent (the one brand color)

| Token | Light | Dark | Use |
|---|---|---|---|
| `AccentColor` | `#E8830E` | `#FFB454` | toggles, buttons, selection, focus, links |
| `accentSoft` (fill) | `#E8830E` @ 14% | `#FFB454` @ 18% | tinted glyph backgrounds, badges |

> Both live in the asset catalog (`AccentColor.colorset`, `accentSoft.colorset`)
> with Any (light) + Dark variants. The dark amber (`#FFB454`) is lightened so it
> reads on dark surfaces. Reference them as `Color.accentColor` /
> `Color("accentSoft")` — never re-enter the hex.

### Brand tokens (custom, beyond the accent)

| Token | Value | Use |
|---|---|---|
| `recordingAmber` | `#FF9F0A` (colorset, flat) | recording dot + waveform glow (works on the always-dark HUD) |
| `diffAdd` | system `.green` | "added / fixed" words in the Polish before→after diff |
| `hudPill` | `Color.black` | always-dark tooltip / HUD-adjacent pill (un-themed by design) |

> The accent and `recordingAmber` are both warm/amber and intentionally close —
> the accent marks interactive chrome; `recordingAmber` is reserved for the live
> recording signal on the always-dark HUD and waveform.

### Chrome — use system semantics (reference only)

These are what the system gives you; the hex columns are just so designers know
roughly where things land. **Don't hardcode them — use the semantic color.**

| Role | SwiftUI source | ~Light | ~Dark |
|---|---|---|---|
| Window bg | `Color(nsColor: .windowBackgroundColor)` | `#ECECEE` | `#1E1E1E` |
| Grouped content bg | `.formStyle(.grouped)` background | `#FFFFFF` | `#1C1C1E` |
| Card / control bg | `Color(nsColor: .controlBackgroundColor)` | `#FFFFFF` | `#2C2C2E` |
| Primary text | `.primary` | `#1A1A1F` | `#F2F2F5` |
| Secondary text | `.secondary` | `#6B6B74` | `#9A9AA4` |
| Separator | `Color(nsColor: .separatorColor)` | — | — |
| Success | `.green` (or brand `#1FA85B`/`#34D17F`) | — | — |
| Warning | `.orange` (or brand `#E8820A`/`#FFA928`) | — | — |

### The notch HUD is exempt

The pill is `Color.black` with a `white.opacity(0.08)` hairline in **all**
appearances. Foreground text/glyphs are `white` at varying opacity. The only
color is `recordingAmber` on the dot + waveform. This is intentional and should
not be themed.

---

## Typography

**SF Pro, system text styles, throughout.** No custom faces, no
`design: .rounded`. Use semantic `Font.TextStyle` so Dynamic Type works.

| Role | Style | Size / weight | Notes |
|---|---|---|---|
| Onboarding title | `.largeTitle` bold | ~30 / 700 | was rounded-bold → switch to system bold |
| Section / window title | `.headline` | 13 / 600 | |
| Settings group header | `.caption` semibold, uppercase | 11 / 600 | `.foregroundStyle(.secondary)` |
| Body / row label | `.body` | 13 / 400 | |
| Caption / helper | `.caption` | 11.5 / 400 | `.secondary` |
| HUD label | `.system(size: 10, weight: .medium)` | 10 / 500 | fixed (not Dynamic Type — HUD is fixed-size) |
| Keycaps | `.system(size: 13, weight: .medium)` | 13 / 500 | drop `.rounded`; monospaced-digit optional |

These roles are codified as `Font` tokens, defined once in `InkItApp.swift`:
`inkLargeTitle`, `inkStat`, `inkTitle`, `inkSheetTitle`, `inkHeadline`,
`inkBody` / `inkBodyEmphasized`, `inkReading` / `inkReadingEmphasized` (Try-It
practice text), `inkMono` (credential entry), `inkNav` (sidebar), `inkCallout` /
`inkCalloutEmphasized`, `inkSectionHeader` (grouped headers + keycaps),
`inkEyebrow`, `inkCaption`. Need a size/weight that isn't here? **Add a token**,
don't inline the literal. **Display text uses a token, never a raw
`.system(size:)`.**

### Enforcement (the `ds-allow` escape hatch)

`scripts/check-design-tokens.sh` runs in CI and fails any PR that introduces a
hardcoded design value: a bare `.system(size: N)` for display text, a raw
`Color(red:/white:)`, a raw `.easeOut(duration:)` (use a `Motion.*` token), or a
raw `.black.opacity(…)` shadow/scrim ink (use `Elevation.*` / `Color.scrim`).
Corner radii live in `enum Radius` by convention — not yet lint-enforced, but
held to the same rule. A genuine one-off opts out with a trailing comment that
names the reason:

```swift
Image(systemName: "gearshape").font(.system(size: 17, weight: .medium))  // ds-allow: icon
```

Sanctioned one-offs: SF Symbol icon glyphs (sized to their container), the
always-dark notch HUD micro-type, the dual-appearance `AppearanceThumbnail`, the
onboarding hero mark. Everything that recurs or is plain running text is a token,
not a one-off.

---

## Shape, spacing, depth

**Corner radii are tokens too** — `enum Radius` in `InkItApp.swift`, named by the
role each step plays. Every `RoundedRectangle(cornerRadius:)` / `.hoverBackdrop()`
reads from it; never inline a raw radius number.

| Token | Value | Use |
|---|---|---|
| `Radius.bar` | 2 | thin accent bars |
| `Radius.inset` | 5 | small insets inside the appearance preview |
| `Radius.chip` | 6 | icon chips, copy glyph |
| `Radius.keycap` | 7 | keycap & field chips (`SettingsMetrics.fieldCornerRadius` aliases this) |
| `Radius.control` | 8 | header icons, history row, sidebar row, close button |
| `Radius.button` | 9 | buttons, gear, send, appearance swatch |
| `Radius.card` | 10 | selectable option cards |
| `Radius.well` | 12 | the inset result well in the practice card |
| `Radius.tile` | 14 | glyph tiles, benefit & permission rows |
| `Radius.key` | 15 | the hero push-to-talk keycap |
| `Radius.panel` | 16 | modal / large rounded panels |
| `Radius.practice` | 18 | the Try-It practice-card container |
| `Radius.ring` | 19 | the invite ring around the keycap |

**Depth is a token** — `enum Elevation` holds the drop-shadow inks (neutral black
at fixed opacities, `ambient` 0.04 → `modal` 0.28). Use `.shadow(color: Elevation.x, …)`;
the blur/offset stays at the call site since it varies per surface. A modal's
dimming backdrop is `Color.scrim`. **Never** write a raw `.black.opacity(…)` — the
lint rejects it.

| Other | Value |
|---|---|
| Hairline border | `separatorColor`, 0.5–1 pt |
| Spacing scale | 4 · 8 · 12 · 16 · 20 · 24 |
| HUD pill radius | 11 (bottom corners, unchanged) |

### Motion

One named curve per kind of transition — `enum Motion` in `InkItApp.swift`. Never
re-type a raw `.easeOut(duration:)` (the lint rejects it); a genuinely bespoke
animation (a reveal, a repeating pulse) opts out with `// ds-allow: <reason>`.

| Token | Value | Use |
|---|---|---|
| `Motion.quick` | easeOut 0.12 | hover lifts, popover/panel show-hide, confirm dialogs |
| `Motion.state` | easeOut 0.15 | a control switching look (copied ✓, field focus) |
| `Motion.expand` | easeOut 0.16 | the toolbar search field opening/closing |

---

## Interaction (hover / press)

Hover and press feedback is part of the language, not a per-view afterthought.
Every clickable surface gives the same family of cues, driven by **one source of
truth** — the `Hover` token enum and the `.hoverBackdrop()` modifier in
`InkItApp.swift`. Don't re-derive these numbers at a call site.

| Token | Value | Use |
|---|---|---|
| `Hover.backdropOpacity` | `.primary` @ 8% | soft backdrop a *borderless* control lifts on hover (icon chips, nav rows, gear, header buttons, close) |
| `Hover.fillShift` | ±0.07 brightness | solid fills: the ink button brightens on hover; the progress dots darken. Brighten-only, no movement — locked |
| `Hover.borderOpacity` | `.primary` @ 22% | firmed border on a selectable card while hovered (vs the hairline at rest) |
| `Hover.rowTintOpacity` | `accent` @ 5.5% | warm tint a full-width row lifts on hover (transcript history) |
| `Hover.animation` | `.easeOut(0.12)` | the one timing for every hover transition |

**Patterns (use these, don't hand-roll):**

- **Borderless control** (icon button, nav row, menu row): apply
  `.hoverBackdrop(cornerRadius:)`. It owns the `@State`, the `onHover`, the
  animated fill, and the hit shape. Pass `isActive:` for a selected/current
  control — it then holds the amber `accentSoft` fill and ignores hover, so
  **selection and hover never stack**. Pair with `PointingHandCursor()` (and an
  `.inkHoverHint()` where a label helps).
- **Selectable card** (activation mode, appearance swatch): border via
  `Hover.cardBorder(isSelected:hovering:)` — amber when chosen, firmed neutral on
  hover, hairline at rest — animated with `Hover.animation`.
- **Solid CTA fill** (the ink button): brighten by `Hover.fillShift`; the
  press-dim (`isPressed → 0.82`) stays. No scale, no lift.

Selection is always amber (`accentColor` / `accentSoft`); hover is always the
neutral lift. Keeping those two channels separate is what stops the chrome from
reading busy.

**Cursor (locked):** every clickable control gets `PointingHandCursor` — buttons,
chips, nav, cards, *and toggles*. This is a web idiom, not the macOS default
(native controls keep the arrow; the hand is reserved for links), but the app
applies it everywhere on purpose for one consistent "this is clickable" signal.
Don't "fix" a control back to the arrow — it'd be the odd one out.

**Toggles / native controls:** a `Toggle` gets the hand cursor and nothing else —
the switch's own built-in knob/track hover is the affordance. We deliberately do
**not** add a custom row backdrop behind toggles, pickers, or steppers; full-row
hover behind form controls isn't the macOS norm and would make one row type read
differently from its neighbors.

## Appearance (Light / Dark / System)

- Add a **`SettingsStore.appearancePreference`** enum: `.system` (default),
  `.light`, `.dark`, persisted in `UserDefaults`.
- Apply with `NSApp.appearance = NSAppearance(named:)` (or
  `.preferredColorScheme` on SwiftUI window roots) so it covers Settings,
  onboarding, and the transcript panel.
- Surface it in Settings as a segmented `Picker` ("Appearance: System / Light /
  Dark").
- The HUD pill ignores this (stays dark).

---

## Onboarding — from rainbow to tinted

Today each step is a full-bleed multi-hue gradient with forced dark. New
direction:

- Background = the **appearance's** window background (light or dark), not a
  gradient.
- Per-step accent collapses to **one amber accent** used for the glyph tile,
  progress indicator, and primary button.
- Glyph sits on an `accentSoft` rounded tile (amber @ ~14%) — a quiet nod to
  color without the carnival.
- Title in system bold (not rounded). Body in `.secondary`.
- Result: onboarding now feels like the same app as Settings.

---

## Component checklist (what changes in code)

| Component | Today | After |
|---|---|---|
| App accent | none → system blue | `AccentColor` asset (amber) |
| `NotchHUD` | black + amber | unchanged (already on-system) |
| Transcript panel | hardcoded black/white | keep dark (it's HUD-adjacent) — or theme later |
| `SettingsView` | `.tint(.accentColor)` w/ no asset | inherits amber automatically |
| `OnboardingView` | per-step gradients, `.rounded`, forced dark | tinted, system font, respects appearance |
| Appearance picker | none | new in Settings |

---

## Apple HIG alignment

- Semantic colors + materials → automatic Dark Mode, Increase Contrast, Reduce
  Transparency, Reduce Motion support.
- `.formStyle(.grouped)` is the native macOS Settings idiom — keep it.
- One accent color set drives system controls; don't fight the platform with
  custom-styled buttons.
- Respect the menu-bar/notch convention: the HUD stays dark and minimal.
