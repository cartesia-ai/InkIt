# InkIt Design System

InkIt is an open-source showcase for Cartesia's `ink-2` speech-to-text — fast,
accurate, cuts through noise. The design exists to make the *model* the star: a
calm, native-feeling Mac app with one confident point of personality.

**Direction (locked):**

| Axis | Decision |
|---|---|
| Personality | Warm & precise — "signal clarity" |
| Accent | Amber — the **Ink skin** (design round 10, see `prototypes/design-direction-round10.md`) |
| Typeface | SF Pro (system) body + **New York** (system serif, `design: .serif`) display voice — no bundled faces |
| Onboarding | Tinted (subtle, on-brand) — no rainbow gradients |
| Appearance | Light **and** Dark, user-selectable (default: follow system) |
| IA | Left-sidebar shell: Home · Insights (Dictionary · Styles later); Settings stays a modal |

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
  Settings — so the whole app is one paper. In the Ink skin, `surface` / `lift`
  / `card` all resolve to the same "panel" value and `paper` matches `canvas`;
  the token *names* stay distinct because call sites encode role. Settings
  still uses `.formStyle(.grouped)` for native layout, but hides the Form's
  system scroll background (`.scrollContentBackground(.hidden)`) and sits on
  `Color.canvas`.
- **Text foreground.** New shell/Insights code reads the warm foreground ramp
  (`inkText` / `inkSub` / `inkFaint`, below). Pre-shell views still use
  `.primary` / `.secondary` / `.tertiary` and `Color(nsColor: .separatorColor)`
  — they render acceptably on the retuned papers and get swept opportunistically,
  not wholesale. Don't mix the two ramps inside one new view.
- **Custom brand tokens → color sets.** `recordingAmber` (live signal) and
  `diffAdd` (Polish "added" text). Everything else is semantic.

### Amber accent (the one brand color)

| Token | Light | Dark | Use |
|---|---|---|---|
| `AccentColor` | `#D97A0D` | `#FFB454` | toggles, buttons, selection, focus, links |
| `accentSoft` (fill) | `#F9EEDC` (opaque cream) | `#FFB454` @ 12% | tinted glyph backgrounds, badges, chips |

> Both live in the asset catalog (`AccentColor.colorset`, `accentSoft.colorset`)
> with Any (light) + Dark variants. The dark amber (`#FFB454`) is lightened so it
> reads on dark surfaces. Reference them as `Color.accentColor` /
> `Color("accentSoft")` — never re-enter the hex.
>
> Contrast note: `#D97A0D` on white is ~3.2:1 — fine for glyphs, fills, bars,
> and semibold ≥13pt, but avoid it for *small running text* in light mode.

### Shell & structure tokens (Ink skin, round 10)

| Token | Light | Dark | Use |
|---|---|---|---|
| `Color.sidebar` (`SidebarBG`) | `#F6F4EF` | `#1F1D18` | sidebar column background |
| `Color.line` (`InkLine`) | `#ECE7DD` | `#363126` | the one hairline for panels, cards, dividers |
| `Color.chip` (`InkChip`) | `#F2EEE5` | `#2B2820` | chip/track fills — segmented controls, bar tracks, keycaps |
| `Color.navSelected` (`NavSelected`) | `#EFEADF` | `#2C2921` | selected sidebar nav backdrop (neutral, **not** accent) |
| `Color.rowHover` (`RowHover`) | `#FAF7F0` | `#282419` | full-width row hover tint |
| `Color.inkText` (`InkText`) | `#26251F` | `#EDE9E0` | primary text (new code) |
| `Color.inkSub` (`InkSub`) | `#75716A` | `#A29B8D` | secondary text (new code) |
| `Color.inkFaint` (`InkFaint`) | `#A29D92` | `#746E60` | tertiary/faint text (new code) |

> Sidebar selection is the *neutral* `navSelected` deepening — not `accentSoft`
> — so the accent stays reserved for live signal and interactive emphasis.
> `.hoverBackdrop(isActive:activeFill:)` takes the fill for this case.

### Brand tokens (custom, beyond the accent)

| Token | Value | Use |
|---|---|---|
| `recordingAmber` | `#FF9E0A` (colorset, flat) | recording dot + waveform glow (works on the always-dark HUD) |
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

**Two system voices, no bundled faces.** SF Pro carries everything people
*use* — body, nav, controls, captions. **New York** (Apple's system serif via
`Font.system(design: .serif)`) is the **display voice** (round 12): it appears
*only* at display scale — the Home hero, the onboarding hero, and stat
numerals — where its editorial character does the "professionally designed"
work that composition alone can't. A nib draws serifs; it suits the ink
metaphor. Never use it below 20pt, never for running text, and key-label
chrome inside a serif line stays SF (`inkHeroKeycap`). No `design: .rounded`
anywhere. Sizes are fixed (not Dynamic Type) so the dense dashboard/settings
layouts stay stable; every surface draws from the same ladder.

**The ramp's stance (round 11):** for a persona that should feel *composed and
unhurried*, confidence comes from **scale and air, not weight**. Three rules:

1. **Big and light, small and firm.** As type grows it sheds weight — stat
   numbers especially (28pt *medium*, never 22pt semibold). As it shrinks it
   may gain at most half a step.
2. **Bold is retired.** Semibold is the ceiling and lives only at display scale
   (the 32pt onboarding hero). In-app emphasis is **one weight step** (regular
   → medium), carried by an `…Emphasized` twin token — never a call-site
   `.weight()` escalation. The lint rejects `.ink*.weight(.semibold/.bold)`.
3. **Raise the reading floor.** Nothing informational below 12.5pt. Uppercase
   eyebrows get structure from tracking (~1.1pt), not weight. Metadata that
   carries meaning is callout (13.5), not caption.

| Token | Face | Size / weight | Use |
|---|---|---|---|
| `inkLargeTitle` | New York | 34 / medium | onboarding hero |
| `inkHero` | New York | 33 / regular | Home hero — the "dictate anywhere" promise line |
| `inkStat` | New York | 30 / regular | Home stat-band number (monospaced digits at use) |
| `inkHeroKeycap` | SF | 21 / medium | the keycap chip inside the serif hero line |
| `inkTitle` | SF | 20 / regular | pane / column title |
| `inkStatSmall` | New York | 20 / medium | card-level numbers (Insights streaks) |
| `inkReading` / `…Emphasized` | SF | 17 / regular · medium | Try-It practice text + hint |
| `inkSheetTitle` | SF | 16 / medium | compact sheet / popover header |
| `inkHeadline` | SF | 15 / medium | card / sub-section heading |
| `inkBody` / `…Emphasized` | SF | 15 / regular · medium | body, rows, buttons, sidebar nav |
| `inkMono` | SF Mono | 15 / mono | credential entry |
| `inkCallout` / `…Emphasized` | SF | 13.5 / regular · medium | secondary body / metadata, stat-band labels |
| `inkSectionHeader` | SF | 13 / medium | grouped headers, keycap chips |
| `inkCaption` | SF | 12.5 / regular | helper / captions / units |
| `inkEyebrow` | SF | 11.5 / medium | uppercase group labels, + `.tracking(1.1)` |
| `inkNotchBrand` / `inkNotchLabel` | SF | 10 / semibold · medium | notch HUD micro-type (exempt, fixed) |

Need a size/weight that isn't here? **Add a token**, don't inline the literal.
**Display text uses a token, never a raw `.system(size:)`** — and never a
heavier `.weight()` stacked on a token.

### Enforcement (the `ds-allow` escape hatch)

`tools/check-design-tokens.sh` runs in CI and fails any PR that introduces a
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
not a one-off. See `AGENTS.md` for the contributor-facing summary.

---

## Structure — the one sheet (round 12)

The window has exactly **one structural device**: the content sheet — a
rounded `Color.canvas` panel (`Radius.panel`, hairline `line` border, ambient
shadow) floating on the sidebar paper, which is the window's ground
(`window.backgroundColor = SidebarBG`). Everything else that used to divide
the window is gone, on purpose:

- **No titlebar separator** (`titlebarSeparatorStyle = .none`) — the traffic
  lights float directly on the sidebar paper; the window title is hidden.
- **No sidebar/content divider** — the sheet's own edge is that boundary.
- **Hairlines live only *inside* the sheet** (row separators, card borders).
  A `line` stroke never spans the window.

Mixing devices — a separator line *and* a rounded panel *and* a column
hairline — is what reads as unconsidered; pick the sheet, and let it be the
whole answer. (Willow/Flow comparison, round 12.)

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

## Changelog

- **2026-07-12 — Display voice + the one sheet (round 12).** New York (system
  serif, `design: .serif`) becomes the display voice: `inkHero` (33/regular,
  new), `inkLargeTitle` 32/semibold → 34/medium serif, `inkStat` 28/medium →
  30/regular serif, `inkStatSmall` → serif; `inkHeroKeycap` (SF 21/medium) for
  key chips inside serif lines; `inkBanner` retired. Home rebuilt as one
  column: rotating hero (now permanent), flat 4-cell stat band (label over
  value, no icons; latency out, avg wpm in), one-row Polish nudge
  (`PolishMiniDemo` deleted), full-width history with resting app-name labels.
  Window chrome unified to the one sheet: no titlebar separator, hidden title,
  sidebar paper as window ground, content on a rounded floating panel, the
  sidebar/content divider hairline deleted. Source: round-12 artifact.
- **2026-07-12 — Type ramp (round 11).** Weight down, size up: bold retired
  from app UI (hero 28/bold → 32/semibold; Insights numbers lose their
  `.weight(.bold)` escalations to a new `inkStatSmall` 20/medium; `inkStat`
  22/semibold → 28/medium; `inkHeadline` semibold → medium; eyebrow semibold →
  medium + wider tracking). Reading floor raised: caption 12 → 12.5, callout 13
  → 13.5, sectionHeader 12.5 → 13, title 18 → 20, banner 22 → 24. Call-site
  `.weight(.semibold/.bold)` escalations on ink tokens are now lint-rejected.
  Unused `inkNav` removed (sidebar deliberately sits on the body pair). Source:
  round-11 typography artifact.
- **2026-07-11 — Ink skin (round 10).** Accent retuned `#E8830E` → `#D97A0D`
  (light); `accentSoft` became an opaque cream in light; the paper neutrals
  warmed and flattened (`surface`/`lift`/`card` → one panel white/`#23211B`);
  new shell tokens (`sidebar`, `line`, `chip`, `navSelected`, `rowHover`) and
  the `inkText`/`inkSub`/`inkFaint` foreground ramp landed with the sidebar
  shell + Insights tab. Source: `prototypes/design-direction-round10.md`
  (gitignored) and the round-10 design-directions artifact.

---

## Apple HIG alignment

- Semantic colors + materials → automatic Dark Mode, Increase Contrast, Reduce
  Transparency, Reduce Motion support.
- `.formStyle(.grouped)` is the native macOS Settings idiom — keep it.
- One accent color set drives system controls; don't fight the platform with
  custom-styled buttons.
- Respect the menu-bar/notch convention: the HUD stays dark and minimal.
