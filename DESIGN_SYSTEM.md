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

These roles are codified as `Font` tokens (`inkLargeTitle`, `inkTitle`,
`inkHeadline`, `inkStat`, `inkEyebrow`, `inkBody`, `inkBodyEmphasized`,
`inkCallout`, `inkCaption`) — all built on named system text styles so Dynamic
Type works. **Display text uses a token, never a raw `.system(size:)`.**

Exempt from the token rule (legitimately point-sized): SF Symbol glyph sizes
(icons scale by point size), the fixed-geometry HUD, keycaps, text-field input,
and the onboarding hero (a deliberately larger full-screen moment).

Rule of thumb: **prefer the `inkX` tokens / named text styles** over fixed point
sizes everywhere except the cases above.

---

## Shape, spacing, depth

| Token | Value |
|---|---|
| Radius — window/cards | 10–12 |
| Radius — controls / keycaps | 6–7 |
| Radius — HUD pill (bottom corners) | 11 (unchanged) |
| Hairline border | `separatorColor`, 0.5–1 pt |
| Spacing scale | 4 · 8 · 12 · 16 · 20 · 24 |
| Elevation | system shadow + `.regularMaterial` for floating panels |

---

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
