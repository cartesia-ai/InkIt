import SwiftUI
import AppKit
import SwiftData

// MARK: - Design tokens
//
// Single source of truth for color and type, per DESIGN_SYSTEM.md. Views must
// reference these — never re-enter a raw hex/RGB or a bare `.system(size:)` for
// text. (Icon/glyph point sizes and the fixed-geometry notch HUD are exempt:
// glyphs scale by point size, the HUD is intentionally un-themed.)

extension Color {
    // Brand — the Ink skin (design round 10, prototypes/design-direction-round10.md):
    // warm amber (#D97A0D light / #FFB454 dark via `AccentColor`) on paper neutrals.
    /// Soft accent fill behind glyphs/badges — an opaque warm cream in light,
    /// the accent at 12% in dark (via catalog).
    static let accentSoft = Color("accentSoft")
    /// Live recording signal — dot + waveform glow. One flat amber in all
    /// appearances so it reads on the always-dark HUD and on light surfaces.
    static let recordingAmber = Color("recordingAmber")
    /// "Added / fixed" text in the Polish before→after diff.
    static let diffAdd = Color.green
    /// Destructive fill — a warm brick red tuned to the paper palette (not the
    /// neon system red), backing the `InkButtonStyle(.destructive)` confirm CTA.
    static let inkDanger = Color("InkDanger")

    // Warm-paper neutrals (asset catalog, light + dark). The app's chrome reads
    // warmer than raw system gray; these back every surface, Settings included.
    // In the Ink skin `surface`/`lift`/`card` all resolve to the same "panel"
    // value and `paper` matches `canvas` — the names stay distinct because call
    // sites encode *role*, and the values may diverge again in a future skin.
    static let canvas  = Color("HomeCanvas")  // window background ("ground")
    static let surface = Color("HomeSurface") // raised panel (stats rail)
    static let lift    = Color("HomeLift")    // top panel (history log)
    static let card    = Color("CardBG")      // cards, fields, controls
    static let paper   = Color("PaperBG")     // inset wells (ground inside a panel)
    // A floating modal is its own lifted "sheet": in Dark mode a black drop shadow
    // is invisible, so (per Material's dark-theme elevation guidance) the sheet
    // reads as raised by being *lighter* than the window behind it. The whole sheet
    // lifts as a unit — ground and cards both step up — so the card-above-ground
    // hierarchy is preserved (a lifted ground alone would sink the cards into it).
    // Both match the app's `canvas` / `card` in Light, so Light is unchanged.
    /// Modal sheet ground (the paper the sections sit on). Above `canvas` in Dark.
    static let modalBG   = Color("ModalBG")
    /// Modal section/field surface. A clear step above `modalBG` in Dark.
    static let modalCard = Color("ModalCard")

    // Shell & structure tokens (new with the sidebar shell, round 10).
    /// Sidebar column background — a step warmer/deeper than the canvas.
    static let sidebar = Color("SidebarBG")
    /// The one hairline border for panels, cards, chips, and dividers.
    static let line = Color("InkLine")
    /// Chip / track fill — segmented controls, bar-chart tracks, keycaps.
    static let chip = Color("InkChip")
    /// Selected navigation item backdrop (sidebar nav) — neutral, not accent.
    static let navSelected = Color("NavSelected")
    /// Full-width row hover tint (history rows) — warmer than a gray overlay.
    static let rowHover = Color("RowHover")

    // Foreground ramp. New shell/Insights code reads these; older views still
    // use `.primary`/`.secondary` until they're swept (DESIGN_SYSTEM.md › Color).
    /// Primary text on the warm papers.
    static let inkText = Color("InkText")
    /// Secondary text — captions, sublabels.
    static let inkSub = Color("InkSub")
    /// Tertiary text — faint metadata, axis labels, placeholders.
    static let inkFaint = Color("InkFaint")

    /// Always-dark tooltip / HUD-adjacent pill. Matches the notch HUD; ignores
    /// appearance by design.
    static let hudPill = Color.black

    /// Dimming scrim behind a modal sheet (the delete-all confirm).
    static let scrim = Color.black.opacity(0.18)
}

/// Corner-radius scale. Every `RoundedRectangle(cornerRadius:)` / `.hoverBackdrop`
/// reads from here so the app's curvature stays on one ladder (DESIGN_SYSTEM.md ›
/// Shape). Named by the role each step plays, smallest to largest.
enum Radius {
    static let bar: CGFloat = 2        // thin accent bars
    static let inset: CGFloat = 5      // small insets inside the appearance preview
    static let chip: CGFloat = 6       // icon chips, copy glyph
    static let keycap: CGFloat = 7     // keycap & field chips
    static let control: CGFloat = 8    // header icons, history row, sidebar, close
    static let button: CGFloat = 9     // buttons, gear, send, the appearance swatch
    static let card: CGFloat = 10      // selectable option cards
    static let well: CGFloat = 12      // the inset result well in the practice card
    static let tile: CGFloat = 14      // glyph tiles, benefit & permission rows
    static let key: CGFloat = 15       // the hero push-to-talk keycap
    static let panel: CGFloat = 16     // modal / large rounded panels
    static let practice: CGFloat = 18  // the Try-It practice-card container
    static let ring: CGFloat = 19      // the invite ring around the keycap
}

/// Drop-shadow inks — the app's elevation palette as neutral black at fixed
/// opacities, lightest (barely-there contact) to heaviest (modal). One source of
/// truth so depth reads consistently; the blur/offset stays at the call site
/// since it varies per surface (DESIGN_SYSTEM.md › Shape).
enum Elevation {
    static let ambient = Color.black.opacity(0.04)  // faint contact shadow
    static let soft    = Color.black.opacity(0.06)  // resting cards (practice card, keycap)
    static let hover   = Color.black.opacity(0.07)  // an option card lifting on hover
    static let drop    = Color.black.opacity(0.08)  // onboarding card drop
    static let card    = Color.black.opacity(0.12)  // appearance swatch at rest
    static let lifted  = Color.black.opacity(0.18)  // swatch on hover / onboarding hero mark
    static let chip    = Color.black.opacity(0.22)  // small floating chip
    static let modal   = Color.black.opacity(0.28)  // modal sheet
}

extension Font {
    // One comfortable scale shared by Home, Settings, and Onboarding. Sizes are
    // fixed (not Dynamic Type) so the dense dashboard/settings layouts stay
    // stable; the point is that every surface draws from the *same* ladder, so
    // nothing reads jarringly larger than anything else.
    // The display voice (round 12) is New York — Apple's system serif, via
    // `design: .serif`, nothing bundled. It appears ONLY at display scale:
    // the heroes and the stat numerals. Body, nav, and chrome stay SF.
    /// Onboarding hero title. New York, medium — display confidence comes
    /// from scale and air; bold is retired from the app (round 11).
    static let inkLargeTitle = Font.system(size: 34, weight: .medium, design: .serif)
    /// Home hero statement — the page-opening "dictate anywhere" promise line.
    static let inkHero = Font.system(size: 33, weight: .regular, design: .serif)
    /// The SF keycap chip sitting inside the serif hero line — key labels are
    /// chrome, not prose, so they stay SF at a size tuned to the hero.
    static let inkHeroKeycap = Font.system(size: 21, weight: .medium)
    /// Screen / pane / column title (History, Insights, Settings pane).
    static let inkTitle = Font.system(size: 20, weight: .regular)
    /// Compact sheet / popover header title — smaller than a full-window pane
    /// title (the Settings popover header).
    static let inkSheetTitle = Font.system(size: 16, weight: .medium)
    /// The sidebar wordmark — the app name beside its icon. Sits a touch above
    /// the pane titles it navigates to (round 13): the brand leads the rail, so
    /// it earns a hair more size than the content. Medium, never bold.
    static let inkWordmark = Font.system(size: 21, weight: .medium)
    /// Card / sub-section heading (nudge title, field group). Medium — one
    /// step above the 15pt body beside it, never two.
    static let inkHeadline = Font.system(size: 15, weight: .medium)
    /// Featured stat number (the Home stat band) — New York, big and light:
    /// the number earns its place with size, not weight. Monospaced digits
    /// applied at use.
    static let inkStat = Font.system(size: 30, weight: .regular, design: .serif)
    /// Card-level stat number (Insights streaks) — the same serif numeral
    /// voice a step down; medium for legibility at this size.
    static let inkStatSmall = Font.system(size: 20, weight: .medium, design: .serif)
    /// Uppercase eyebrow: group headers, day dividers, diff row labels.
    /// Structure comes from tracking (~1.1pt at call sites), not weight.
    static let inkEyebrow = Font.system(size: 11.5, weight: .medium)
    /// Primary body / row text (transcripts, row labels).
    static let inkBody = Font.system(size: 15)
    /// Emphasized body — button labels, selectable item titles.
    static let inkBodyEmphasized = Font.system(size: 15, weight: .medium)
    /// Reading text for the Try-It practice card — a touch larger than body so
    /// the prompt and the user's words have room to breathe.
    static let inkReading = Font.system(size: 17)
    /// Emphasized reading text — the practice prompt itself.
    static let inkReadingEmphasized = Font.system(size: 17, weight: .medium)
    /// Monospaced credential entry (API-key fields), at body size.
    static let inkMono = Font.system(size: 15, design: .monospaced)
    // (inkNav was removed in round 11 — sidebar rows deliberately sit on the
    // body pair, per the SidebarNavItem comment.)
    /// Secondary body / metadata that still needs to read easily.
    static let inkCallout = Font.system(size: 13.5)
    /// Emphasized callout — selectable card / control titles that sit at the
    /// body-row scale rather than the heavier 15pt (Settings option cards).
    static let inkCalloutEmphasized = Font.system(size: 13.5, weight: .medium)
    /// Small medium-weight UI label at the same scale step — grouped-section
    /// headers in Settings and keycap chips in the shortcut recorder.
    static let inkSectionHeader = Font.system(size: 13, weight: .medium)
    /// Helper / captions / units.
    static let inkCaption = Font.system(size: 12.5)
    /// Always-dark notch HUD micro-type — the fixed-size strip by the camera
    /// notch (DESIGN_SYSTEM.md principle 4). Off the content scale by design;
    /// not for general app UI. Brand wordmark and status label.
    static let inkNotchBrand = Font.system(size: 10, weight: .semibold)
    static let inkNotchLabel = Font.system(size: 10, weight: .medium)
}

// MARK: - Interaction tokens
//
// Hover/press affordances are part of the design language too, so the values that
// drive them live here as named tokens — one source of truth — instead of being
// re-derived as magic numbers at each call site. See DESIGN_SYSTEM.md ›
// Interaction. Prefer the `.hoverBackdrop()` modifier below for the common case;
// reach for these constants only for the bespoke surfaces (the ink button's
// brightened fill, the progress dots, a full-width row tint).

/// The app's motion timings — one named curve per kind of transition so no view
/// re-types a raw `.easeOut(duration:)`. See DESIGN_SYSTEM.md › Interaction.
enum Motion {
    /// Quick UI transition — hover lifts, popover/panel show-hide, confirm dialogs.
    static let quick: Animation = .easeOut(duration: 0.12)
    /// State-change feedback — a control switching look (copied ✓, field focus).
    static let state: Animation = .easeOut(duration: 0.15)
    /// Inline expand/collapse — the toolbar search field opening and closing.
    static let expand: Animation = .easeOut(duration: 0.16)
    /// Onboarding step change — slide + dots, critically damped (no bounce).
    static let step: Animation = .spring(response: 0.45, dampingFraction: 1)
    /// Fade-and-drift between rotating content (the Home "dictate anywhere"
    /// header) — eased and unhurried so the swap reads as a settle, not a cut.
    static let rotate: Animation = .easeInOut(duration: 0.5)
}

enum Hover {
    /// Soft backdrop a *borderless* control lifts on hover (icon chips, nav rows,
    /// header buttons). Opacity of `.primary` so it adapts to appearance.
    static let backdropOpacity: Double = 0.08
    /// How far a solid fill shifts on hover (the ink button brightens by this;
    /// the progress dots darken by it). Brighten-only, no movement — locked.
    static let fillShift: Double = 0.07
    /// Firmed border on a selectable card while hovered, vs the hairline at rest.
    static let borderOpacity: Double = 0.22
    /// Warm tint a full-width row lifts on hover (the transcript history rows).
    static let rowTintOpacity: Double = 0.055
    /// The one timing for every hover transition.
    static let animation: Animation = Motion.quick

    /// Stroke for a selectable card: amber when chosen, a firmed neutral on
    /// hover, the warm `Color.line` hairline at rest. Shared by the
    /// activation-mode and appearance cards so both pick the same way.
    static func cardBorder(isSelected: Bool, hovering: Bool) -> Color {
        if isSelected { return .accentColor }
        return hovering ? Color.primary.opacity(borderOpacity) : Color.line
    }
}

/// The standard hover affordance for a *borderless* control: a soft rounded
/// backdrop that fades in under the content on hover, on the shared
/// `Hover.animation` timing. One definition so every icon chip, nav row, gear,
/// and header button lifts identically (DESIGN_SYSTEM.md › Interaction) — apply
/// it with `.hoverBackdrop()` rather than re-writing the `@State`/`onHover`/
/// `background` block. Pass `isActive` for a selected/current control that should
/// hold the amber `accentSoft` fill and ignore hover, so selection and hover
/// never stack.
struct HoverBackdrop: ViewModifier {
    var cornerRadius: CGFloat = 8
    var isActive: Bool = false
    /// Fill held while `isActive`. Defaults to the amber `accentSoft`; the
    /// sidebar nav passes `.navSelected` — its selection reads as a neutral
    /// deepening of the sidebar paper, per the round-10 shell.
    var activeFill: Color = .accentSoft
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape.fill(isActive
                           ? activeFill
                           : Color.primary.opacity(hovering ? Hover.backdropOpacity : 0))
            )
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Hover.animation, value: hovering)
    }
}

extension View {
    /// Lift the app's standard soft hover backdrop. See `HoverBackdrop`.
    func hoverBackdrop(cornerRadius: CGFloat = 8, isActive: Bool = false,
                       activeFill: Color = .accentSoft) -> some View {
        modifier(HoverBackdrop(cornerRadius: cornerRadius, isActive: isActive,
                               activeFill: activeFill))
    }
}

/// Swaps the cursor to the pointing-hand while hovering, signalling that a
/// control is clickable. Shared across Home / Settings / Onboarding.
struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

/// The app's one hyperlink treatment: brand-orange (`accentColor`) text with a
/// trailing `arrow.up.right` that signals "opens externally." Trailing — not
/// leading — because the arrow modifies the label, matching web convention
/// (GitHub Primer, Material, Apple HIG). Used for every "Get your … key" link
/// across Onboarding and Settings so they read identically. Pass a `font` to
/// match the surrounding text; the layout stays left-aligned.
///
/// The color is set with `.foregroundStyle` on the label, not `.tint`: on macOS
/// `Link` renders its text in the system link color (blue) and ignores `.tint`,
/// so tinting alone left every link blue. `.buttonStyle(.plain)` keeps the label
/// from re-applying the default link styling on top.
struct ExternalLink: View {
    let title: String
    let url: URL
    var font: Font = .caption

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.right")
            }
            .font(font)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}

/// The shared visual for a quiet 28×28 header affordance: a tinted glyph that
/// lifts a soft rounded backdrop on hover, with the hand cursor + a hover hint —
/// the same treatment as `IconChip`/`CopyTranscriptGlyph`, sized for the header.
/// Hover state lives on the glyph itself so it works whether the parent is a
/// plain `Button` (search) or a `Menu` label (manage) — a `Menu` doesn't forward
/// hover to its container, which is why the affordance must sit on the label.
private struct HeaderIconLabel: View {
    let systemName: String
    let hint: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))  // ds-allow: icon
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .hoverBackdrop(cornerRadius: Radius.control)
            .modifier(PointingHandCursor())
            .inkHoverHint(hint)
    }
}

/// A quiet header icon *button* (History search). Wraps the shared
/// `HeaderIconLabel`, so it reads as one family with the manage menu and the gear.
struct HeaderIconButton: View {
    let systemName: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderIconLabel(systemName: systemName, hint: hint)
        }
        .buttonStyle(.plain)
    }
}

/// One row in the "Manage transcripts" popover. Leading column is either a
/// checkmark (sort rows, shown when selected) or an icon (Delete All), so labels
/// stay aligned. Lifts the same soft hover backdrop as the rest of the chrome.
struct ManageMenuRow: View {
    let title: String
    var icon: String? = nil
    var checked: Bool = false
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon ?? "checkmark")
                    .font(.inkCallout)
                    .opacity(icon == nil && !checked ? 0 : 1)
                    .frame(width: 16)
                Text(title)
                    .font(.inkCallout)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverBackdrop(cornerRadius: Radius.chip)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}

/// The app's one modal treatment: a centered card on the warm paper (`Color.canvas`,
/// 16pt continuous corners, a hairline border, a soft drop shadow) over a dimmed
/// backdrop. Defining it once keeps "an InkIt modal" a single source of truth, so
/// Settings and the Delete-all confirm can't drift apart. Tap-out runs `onDismiss`;
/// the caller owns Esc/Return via the content's keyboard shortcuts.
private struct InkModal<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            // A plain, slight dim behind the card — no material blur, which tints
            // dark under a Dark appearance and reads as a near-blackout.
            Color.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content
                .background(Color.modalBG)
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
                .shadow(color: Elevation.modal, radius: 40, y: 18)
        }
        // Dim the whole window — traffic-light strip included — and center the
        // card in the full frame, so the breathing room reads equal on every
        // side rather than adding the titlebar band to the top gap.
        .ignoresSafeArea()
        .transition(.opacity)
    }
}

/// The app's icon ✕ — a 26pt circle that lifts the standard hover backdrop,
/// for the Settings header and any modal that needs a corner dismiss. One source
/// of truth so every close affordance reads identically. Callers add the Esc
/// shortcut themselves only where one isn't already claimed (e.g. by a Cancel
/// button), so two `.cancelAction`s never collide in the same view.
struct InkCloseButton: View {
    let onClose: () -> Void
    var help: String = "Close"

    var body: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .hoverBackdrop(cornerRadius: Radius.control)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .help(help)
        .accessibilityLabel(help)
    }
}

extension Notification.Name {
    /// Posted by the "Settings…" menu command (⌘,); the main window opens the
    /// settings modal in response. Lets the menu reach in-window @State.
    static let openSettings = Notification.Name("InkIt.openSettings")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Apply the saved appearance (default Light) as early as possible so the
    // first window doesn't flash the system appearance before settling.
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.applyAppearance()
        UpdateManager.shared.start()
    }

    // Restore the main window when the user clicks the Dock icon after
    // closing it. SwiftUI's WindowGroup default activates the app but
    // doesn't reliably re-show the window on macOS, causing a "flash" with
    // nothing visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where !(window is NSPanel) && window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return false
            }
        }
        return true
    }
}

@main
struct InkItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var history = TranscriptHistoryStore.shared
    // Created at launch on purpose: seeding reads the persisted transcript
    // rows, so the store must exist before the first dictation is added (see
    // UsageAggregateStore.shared).
    @StateObject private var aggregates = UsageAggregateStore.shared

    var body: some Scene {
        WindowGroup("InkIt", id: "main") {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(aggregates)
        }
        // Share the history store's single SwiftData container with the
        // environment so any future `@Query`-based read can use it directly,
        // while the store keeps owning all writes.
        .modelContainer(history.modelContainer)
        .windowResizability(.contentMinSize)
        // The onboarding view is flexible (maxWidth/maxHeight: .infinity), so its
        // idealWidth/idealHeight never reach the window — SwiftUI falls back to a
        // small default. defaultSize is the reliable way to set the first-launch
        // window size; once a frame is saved it takes over on later launches.
        //
        // Width lands the Home content column (capped at 860, with a 44pt gutter
        // each side) flush against the sheet's right edge: 180 sidebar + 860 +
        // 2×44 + 10 sheet inset ≈ 1138. Anything wider just opens dead canvas on
        // the right, since the column stays left-aligned at its cap.
        .defaultSize(width: 1140, height: 860)
        .commands {
            // Strip the system menu bar down to the bare minimum. macOS won't
            // let us remove the leading "InkIt" menu (About/Quit live there)
            // while we keep the Dock icon, but everything else can go.
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateManager.shared.checkForUpdates()
                }
                .disabled(!UpdateManager.shared.canCheckForUpdates)
            }
            // Real "Settings…" item in the app menu. This replaces the invisible
            // in-window ⌘, button so the macOS-standard shortcut is discoverable
            // and fires whenever InkIt is active, not only when the window is key.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // A small Help menu — the OSS on-ramp. Source + issues, nothing else.
            CommandGroup(replacing: .help) {
                Button("InkIt on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/cartesia-ai/InkIt")!)
                }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(URL(string: "https://forms.gle/jXNtDsTaLt2rKQ8N9")!)
                }
            }
        }
        // CommandsBuilder caps at 10 groups per block, so the strip-down empties
        // live in a second .commands modifier (SwiftUI merges them).
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowList) {}
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                // Floor: the Settings modal must always fit with a little
                // breathing room on every side. That card (840×600) is the
                // largest thing the window ever hosts, so it — not the history
                // panel — sets the minimum. See SettingsPopover.size.
                //
                // The card centers in the full window (the scrim ignores the
                // safe area), so the target window *frame* is card + 2×room. The
                // SwiftUI minimum sizes the content region below the titlebar, so
                // subtract the titlebar band from the height to land the frame
                // exactly there; width has no such inset.
                MainWindowView()
                    .frame(minWidth: SettingsPopover.size.width + 2 * SettingsPopover.breathingRoom,
                           minHeight: SettingsPopover.size.height + 2 * SettingsPopover.breathingRoom
                                      - MainWindowView.titlebarHeight)
            } else {
                OnboardingRootView()
                    .frame(minWidth: 620, idealWidth: 1140, maxWidth: .infinity,
                           minHeight: 560, idealHeight: 860, maxHeight: .infinity)
            }
        }
        // Hide the centered "InkIt" window title on every surface, onboarding
        // included (MainWindowView also carries this, harmlessly idempotent).
        .background(WindowChrome())
        .onAppear { settings.applyAppearance() }
    }
}

struct MainWindowView: View {
    /// The standard macOS titlebar band. `.windowResizability(.contentMinSize)`
    /// applies the SwiftUI minimum to the content region below the titlebar, so
    /// the window frame ends up this much taller than the requested minHeight —
    /// the minimum-size math subtracts it back out.
    static let titlebarHeight: CGFloat = 28

    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: TranscriptHistoryStore

    // The round-10 shell: a fixed sidebar (Home · Insights · Settings + the
    // armed pill) beside one switched content column. Modals, toasts, and the
    // update pill overlay the *whole* shell so scrims dim the sidebar too;
    // the dictation-issue banner sits above the switched view so a paused
    // dictation is visible from every section.
    // "--open-insights" / "--open-settings" are for the screenshot-based
    // design-review protocol: they land the window on a specific surface
    // without UI scripting. No-ops in normal use.
    @State private var section: MainSection =
        ProcessInfo.processInfo.arguments.contains("--open-insights") ? .insights : .home
    @State private var showSettings =
        ProcessInfo.processInfo.arguments.contains("--open-settings")
    // "--settings-pane <general|dictation|polish>" lands Settings on a specific
    // pane for the screenshot-based design-review protocol (no-op in normal use).
    @State private var settingsPane: SettingsView.Pane = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--settings-pane"), args.indices.contains(i + 1),
              let pane = SettingsView.Pane(rawValue: args[i + 1]) else { return .general }
        return pane
    }()
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(section: $section,
                        onOpenSettings: { openSettings(pane: .general) })
            // The one sheet (round 12): all content lives on a single rounded
            // canvas panel floating on the sidebar paper. No divider hairline
            // between sidebar and content, no titlebar separator — the sheet's
            // own edge is the only structural line the window has.
            VStack(spacing: 0) {
                dictationIssueBanner
                switch section {
                case .home:
                    HomeView(onOpenSettings: { openSettings(pane: $0) },
                             onRequestDeleteAll: {
                                 withAnimation(Motion.quick) { showDeleteConfirm = true }
                             })
                case .insights:
                    InsightsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
            .shadow(color: Elevation.ambient, radius: 8, y: 1)
            // Start the sheet below the traffic-light row so the top of the
            // window is one uninterrupted band of sidebar paper — the close/
            // minimize controls float on the same ground as the wordmark, with
            // no separate titlebar-colored strip (round 13, matching the sheet
            // top to the sidebar wordmark).
            .padding(.top, 26)
            .padding([.trailing, .bottom], 10)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sidebar)
            .background(WindowChrome())
            // Floating update pill, bottom-center, over the content but below the
            // settings modal's dimmed backdrop (added after this overlay).
            .overlay(alignment: .bottom) { UpdatePill() }
            .overlay { settingsModal }
            .overlay { deleteConfirmModal }
            // Toasts live on the main window's lower-right, above any modal, so a
            // confirmation/error stays put rather than riding the Settings card.
            .overlay(alignment: .bottomTrailing) { ToastOverlay() }
            // The "Settings…" menu item (⌘,) posts this; open the modal in response.
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                openSettings(pane: .general)
            }
    }

    // Always lands on the caller's pane (General from the sidebar/⌘, — Settings
    // doesn't remember the last pane; a deep link names its own).
    private func openSettings(pane: SettingsView.Pane) {
        settingsPane = pane
        withAnimation(Motion.quick) { showSettings = true }
    }

    // Settings as a centered modal over a dimmed backdrop (Flow-style), not a
    // gear-anchored popover. Click-out or the pane's ✕ / Esc dismisses it.
    // The backdrop + card chrome come from the shared `InkModal`.
    @ViewBuilder private var settingsModal: some View {
        if showSettings {
            InkModal(onDismiss: dismissSettings) {
                SettingsPopover(pane: $settingsPane, onClose: dismissSettings)
            }
        }
    }

    private func dismissSettings() {
        withAnimation(Motion.quick) { showSettings = false }
    }

    // Destructive confirm, on the same warm centered-card chrome as the Settings
    // modal (dimmed backdrop, Color.canvas card, 16pt corners). Click-out or
    // Cancel/Esc backs out; Delete All clears history (HomeView collapses its
    // own search when the list empties).
    @ViewBuilder private var deleteConfirmModal: some View {
        if showDeleteConfirm {
            InkModal(onDismiss: dismissDeleteConfirm) {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("Delete all transcripts")
                            .font(.inkSheetTitle)
                            .foregroundStyle(.primary)
                        Text(deleteConfirmMessage)
                            .font(.inkCallout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Button("Cancel") { dismissDeleteConfirm() }
                            .buttonStyle(InkSecondaryButtonStyle(compact: true))
                            .keyboardShortcut(.cancelAction)
                            .modifier(PointingHandCursor())
                        Button("Delete All", role: .destructive) { confirmDeleteAll() }
                            .buttonStyle(InkButtonStyle(variant: .destructive, compact: true))
                            .keyboardShortcut(.defaultAction)
                            .modifier(PointingHandCursor())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 36)
                .padding(.bottom, 32)
                .frame(width: 400)
                // Corner ✕ — the same icon close button used in the Settings
                // header — so the modal reads as dismissable at a glance.
                .overlay(alignment: .topTrailing) {
                    InkCloseButton(onClose: dismissDeleteConfirm)
                        .padding(10)
                }
            }
        }
    }

    // Exact count + plural so the number itself adds a beat of friction before an
    // irreversible wipe. "will be permanently removed" per the locked copy.
    private var deleteConfirmMessage: String {
        let n = history.entries.count
        let noun = n == 1 ? "transcript" : "transcripts"
        return "\(n) \(noun) will be permanently removed. This can't be undone."
    }

    private func dismissDeleteConfirm() {
        withAnimation(Motion.quick) { showDeleteConfirm = false }
    }

    private func confirmDeleteAll() {
        history.clear()
        dismissDeleteConfirm()
    }

    // A lost dictation is critical (the core feature is down), so a Cartesia key
    // /credit problem gets a full-width banner across the top of the content
    // column — more noticeable than a rail card, and visible from every section.
    // Polish failing is only degraded (raw text still pastes), so it stays a calm
    // rail card on Home. Both are driven by the persisted flags, so they're
    // sticky until fixed — never a 2.5s flash.
    @ViewBuilder private var dictationIssueBanner: some View {
        if let issue = settings.transcriptionIssue {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))  // ds-allow: icon
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictation is paused")
                        .font(.inkBodyEmphasized)
                        .foregroundStyle(.primary)
                    Text(transcriptionIssueMessage(issue))
                        .font(.inkCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { transcriptionIssueAction(issue) } label: {
                    Text(transcriptionIssueCTA(issue))
                        .font(.inkCaption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
            )
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
    }

    // MARK: Dictation-issue copy + actions

    private func transcriptionIssueMessage(_ issue: SettingsStore.ServiceIssue) -> String {
        switch issue {
        case .keyInvalid:
            return "Your Cartesia API key is invalid. Update it to start dictating again."
        case .outOfCredits:
            return "You're out of Cartesia credits. Review your plan to keep going before your credits reset."
        }
    }
    private func transcriptionIssueCTA(_ issue: SettingsStore.ServiceIssue) -> String {
        switch issue {
        case .keyInvalid:   return "Update your Cartesia key"
        case .outOfCredits: return "Review your Cartesia plan"
        }
    }
    private func transcriptionIssueAction(_ issue: SettingsStore.ServiceIssue) {
        switch issue {
        case .keyInvalid:
            openSettings(pane: .dictation)
        case .outOfCredits:
            NSWorkspace.shared.open(URL(string: "https://play.cartesia.ai/subscription")!)
        }
    }
}

/// The current hotkey as one amber highlight, tokens joined by "+", e.g.
/// "⌃ Ctrl + s". Sets the shortcut apart from surrounding prose. Inherits the
/// ambient font; the vertical padding gives the highlight breathing room so it
/// reads as a proper keycap against the hero line rather than a thin band.
struct HotkeyCaps: View {
    let tokens: [String]

    var body: some View {
        Text(tokens.joined(separator: " + "))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
                    .fill(Color.accentSoft)
            )
    }
}

/// The Home hero (round 12): the page opens with the product's one promise —
/// "Hold fn to dictate in …" — set in the New York display voice. The category
/// word + its three app logos swap together on a soft cross-fade so the line
/// reads as one alive cue rather than a static banner. Pauses on hover so a
/// bucket is readable; honors Reduce Motion by holding the first bucket still.
struct RotatingDictateHeader: View {
    let tokens: [String]

    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var hovering = false
    @State private var timer: Timer?

    /// Seconds each bucket holds before the next swaps in.
    private static let dwell: TimeInterval = 2.4

    private struct Bucket { let category: String; let logos: [String] }

    // Asset names live in Assets.xcassets (Logo*). AI leads; the rest are the
    // everyday surfaces a dictation user lands in.
    private static let buckets: [Bucket] = [
        .init(category: "AI",       logos: ["LogoClaude", "LogoChatgpt", "LogoGemini"]),
        .init(category: "email",    logos: ["LogoGmail", "LogoMail", "LogoOutlook"]),
        .init(category: "messages", logos: ["LogoMessages", "LogoSlack", "LogoWhatsapp"]),
        .init(category: "your editor", logos: ["LogoVscode", "LogoTerminal", "LogoXcode"]),
        .init(category: "your notes", logos: ["LogoNotion", "LogoObsidian", "LogoNotes"]),
        .init(category: "the browser", logos: ["LogoChrome", "LogoSafari", "LogoFirefox"]),
    ]

    var body: some View {
        HStack(spacing: 10) {
            // Hands-free (toggle) taps to start/stop, so the verb flips per mode
            // (shared with the status line + Settings via `dictationModeVerb`).
            Text(settings.dictationModeVerb)
                .foregroundStyle(.primary)
            HotkeyCaps(tokens: tokens)
                .font(.inkHeroKeycap)  // key labels are chrome — SF inside the serif line
            Text("to dictate in")
                .foregroundStyle(.primary)
            bucketView
                .id(index)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity.combined(with: .offset(y: -6))
                ))
            Spacer(minLength: 0)
        }
        // The display voice: New York at hero scale. Layout padding belongs to
        // the caller (HomeView owns the page grid). The whole promise is one
        // line — never let a narrow window wrap it.
        .font(.inkHero)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering = $0 }
        .onAppear(perform: startRotating)
        .onDisappear { timer?.invalidate() }
    }

    private var bucketView: some View {
        let bucket = Self.buckets[index]
        return HStack(spacing: 11) {
            Text(bucket.category)
                .foregroundStyle(.primary)
            HStack(spacing: 7) {
                ForEach(bucket.logos, id: \.self) { logoTile($0) }
            }
        }
    }

    private func logoTile(_ name: String) -> some View {
        // The image already carries its own optical padding (normalized to ~80%
        // of a square), so it fills the tile directly.
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: Elevation.soft, radius: 2, y: 1)
    }

    private func startRotating() {
        guard !reduceMotion else { return }  // hold the first bucket still
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.dwell, repeats: true) { _ in
            guard !hovering else { return }   // let a reader linger
            withAnimation(Motion.rotate) {
                index = (index + 1) % Self.buckets.count
            }
        }
    }
}

/// Shown on Home only when there's no history at all — i.e. the user skipped the
/// onboarding Try-it step. Rather than dead-ending, it offers the same practice
/// card as onboarding: read the line, hold the key, fix anything, send. The card
/// logs each sent take to history; that first row flips Home off this empty state
/// and the transcript list takes over, so `onSend` here stays a no-op.
struct HomeTryItPanel: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text("No transcripts yet")
                    .font(.headline)
                Text("Give it a try right here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TryItPracticeCard()

            Text("Or \(settings.dictationModeVerb.lowercased()) \(settings.hotkeyDisplayString) in any app and start talking.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        // Sized to content — it now sits inside Home's scrolling column
        // (round 12), not a full-window switch.
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }
}

struct TranscriptHistoryRow: View {
    let text: String
    let timestamp: String
    let latency: TranscriptHistoryStore.Latency?
    /// Raw pre-rewrite transcript; non-nil whenever correction ran successfully
    /// (identical to `text` for a no-op rewrite). Feeds the before/after diff.
    let original: String?
    /// How AI correction turned out; drives the row indicator.
    let polish: TranscriptHistoryStore.PolishOutcome?
    /// Why polish failed (when `polish == .failed`); drives the warning tooltip.
    let failure: TranscriptHistoryStore.PolishFailure?
    /// Where the dictation landed (Slack, Mail, …) — the resting label in the
    /// trailing column; the hover affordances take its place. Nil pre-shell rows
    /// simply rest empty.
    let appName: String?
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false
    @State private var showingDiff = false
    @State private var showingLatency = false
    @State private var showingFailure = false

    /// Resolves the indicator to show. Legacy entries (no stored `polish`) fall
    /// back to "polished if there's a diff to show, otherwise nothing."
    private var outcome: TranscriptHistoryStore.PolishOutcome {
        if let polish { return polish }
        return original != nil ? .polished : .off
    }

    // A compact transcript-log entry: timestamp in a fixed left gutter, the
    // cleaned-up text in the middle, affordances on the trailing edge. Polish /
    // time / copy are hover-only so resting rows are just time + words and stay
    // tight — except a *failed* polish, which shows at rest (silently hiding a
    // failure is worse than a touch of clutter). The trailing column is a fixed
    // width so text wraps consistently and nothing shifts on hover.
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timestamp)
                .font(.inkCallout)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 74, alignment: .leading)
                .padding(.top, 1)

            Text(text)
                .font(.inkBody)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Keep long text clear of the icon cluster, especially with all
                // three chips visible.
                .padding(.trailing, 16)

            trailingControls
                // Wide enough to hold all three chips (3×24 + 2×8) without
                // spilling back into the text.
                .frame(width: 88, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(Hover.rowTintOpacity) : Color.clear)
        )
        // Whole row is click-to-copy. The chips swallow their own taps so
        // inspecting the diff/latency never triggers a copy.
        .onTapGesture { copy() }
        .modifier(PointingHandCursor())
        .onHover { isHovering in
            withAnimation(Hover.animation) {
                hovering = isHovering
            }
        }
        .animation(Motion.state, value: copied)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }

    // Trailing column: the faint app name at rest, swapped for the affordances
    // on hover — so resting rows stay time + words + where it landed.
    private var trailingControls: some View {
        ZStack(alignment: .trailing) {
            if let appName, !hovering, !copied {
                Text(appName)
                    .font(.inkCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                CopyTranscriptGlyph(copied: copied)
                    .opacity(hovering || copied ? 1 : 0)
                if outcome == .polished {
                    polishPill.opacity(hovering ? 1 : 0)
                }
                if outcome == .failed {
                    failurePill.opacity(hovering ? 1 : 0)
                }
                if let latency {
                    timePill(latency).opacity(hovering ? 1 : 0)
                }
            }
        }
    }

    /// Sparkle glyph — a single click reveals the before/after diff. The label
    /// and exact stats live in the popover so the row stays uncluttered.
    private var polishPill: some View {
        IconChip(systemName: "sparkles", fg: Color.accentColor, help: "See what changed")
            .onTapGesture { showingDiff.toggle() }
            .inkDetailPopover(isPresented: $showingDiff) {
                DiffPopover(before: original ?? text, after: text)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel("Polished — show changes")
    }

    /// Warning triangle in soft amber — polish failed and raw text was pasted.
    /// Click for the actionable reason. (The earlier `sparkles.slash` glyph drew
    /// nothing — SF Symbols has no such symbol — so the row looked iconless
    /// while the hover hint still fired.)
    private var failurePill: some View {
        IconChip(systemName: "exclamationmark.triangle.fill", fg: .orange, help: "Polish failed")
            .onTapGesture { showingFailure.toggle() }
            .inkDetailPopover(isPresented: $showingFailure) {
                Text(Self.failureMessage(failure))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
                    .padding(12)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel(Text(Self.failureMessage(failure)))
    }

    /// Clock glyph — the exact total and per-stage split stay hidden until the
    /// click opens the breakdown, keeping the row quiet.
    private func timePill(_ latency: TranscriptHistoryStore.Latency) -> some View {
        IconChip(systemName: "clock", fg: .secondary, help: "Speed")
            .onTapGesture { showingLatency.toggle() }
            .inkDetailPopover(isPresented: $showingLatency) {
                LatencyPopover(latency: latency, polishFailed: outcome == .failed)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel("Time to text \(Self.fmt(latency.totalMs)) — show breakdown")
    }

    /// Terse, provider-aware reason for why polish failed, with the action the
    /// user can take. Computed at hover time so the rate-limit countdown is live.
    static func failureMessage(_ failure: TranscriptHistoryStore.PolishFailure?) -> String {
        guard let failure else {
            return "Polish failed — raw text pasted. Re-dictate to retry."
        }
        let p = failure.provider
        switch failure.reason {
        case .rateLimited:
            return "\(p) rate limit — raw text pasted. \(retryHint(failure.retryAt))"
        case .offline:
            return "No internet — raw text pasted. Reconnect and re-dictate."
        case .timedOut:
            return "Polish timed out — raw text pasted. Re-dictate to retry."
        case .invalidKey:
            return "Invalid \(p) API key — raw text pasted. Fix it in Settings."
        case .outOfCredits:
            return "Out of \(p) credits — raw text pasted. Review your \(p) plan to re-enable Polish."
        case .serverError:
            return "\(p) server error — raw text pasted. Try again shortly."
        case .unknown:
            return "Polish failed — raw text pasted. Re-dictate to retry."
        }
    }

    private static func retryHint(_ retryAt: Date?) -> String {
        guard let retryAt else { return "Retry soon or switch provider." }
        let secs = retryAt.timeIntervalSinceNow
        if secs <= 5 { return "Try again now or switch provider." }
        let mins = Int(ceil(secs / 60))
        if mins <= 1 { return "Try again in ~1 min or switch provider." }
        return "Try again in ~\(mins) min or switch provider."
    }

    private static func fmt(_ ms: Int) -> String {
        ms < 1000 ? "\(ms)ms" : String(format: "%.1fs", Double(ms) / 1000)
    }
}

/// Per-stage breakdown shown when hovering the "Time to text" stat on a row.
/// The row keeps the clean total; this reveals where the time went —
/// transcribe (release → final transcript) and polish (the AI rewrite). Paste
/// is omitted on purpose: it's a fixed floor the user can't influence, so it's
/// recorded but not shown (see `Latency.totalMs`). The polish row is omitted
/// when correction didn't run (polishMs == 0), so it never reads as a stalled 0ms.
/// When polish ran but failed, the same time exists but produced no rewrite, so
/// the row reads "Polish attempt" — honest about the cost without implying the
/// text was actually polished.
private struct LatencyPopover: View {
    let latency: TranscriptHistoryStore.Latency
    /// Polish was attempted but failed (rate limit, timeout, …); the time landed
    /// in `polishMs` even though the rewrite was discarded for raw text.
    var polishFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time to text")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text("Hotkey release → text on screen")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                stageRow("Transcribe", latency.transcribeMs)
                if latency.polishMs > 0 {
                    stageRow(polishFailed ? "Polish attempt" : "Polish", latency.polishMs)
                }
            }

            Divider()

            stageRow("Total", latency.totalMs, emphasized: true)
        }
        .padding(14)
        .frame(width: 220)
    }

    private func stageRow(_ label: String, _ ms: Int, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(emphasized ? .primary : .secondary)
            Spacer(minLength: 12)
            Text(Self.fmt(ms))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(emphasized ? .caption.weight(.semibold) : .caption)
    }

    private static func fmt(_ ms: Int) -> String {
        ms < 1000 ? "\(ms)ms" : String(format: "%.1fs", Double(ms) / 1000)
    }
}

/// Inline word-level before/after diff shown when hovering a polished row's
/// sparkle. Additions/fixes are highlighted; dropped words are struck through.
private struct DiffPopover: View {
    let before: String
    let after: String

    private var changed: Bool { before != after }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(changed ? "Polished" : "Polished — no changes")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(Self.diff(from: before, to: after))
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                // Definite width, not a ceiling: `fixedSize(vertical:)` computes
                // height for the proposed width, and the popover's ideal-size pass
                // proposes an unspecified width. With only `maxWidth` the text
                // collapsed to a near-zero width on some macOS builds → a runaway
                // intrinsic height → an 800pt popover. A fixed width pins the
                // height pass to the real wrap width on every OS version, matching
                // the sibling Latency/failure popovers (which already use width:).
                .frame(width: 280, alignment: .leading)

            if changed {
                HStack(spacing: 12) {
                    Label("added", systemImage: "circle.fill")
                        .foregroundStyle(Self.addColor)
                    Label("removed", systemImage: "circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .labelStyle(DiffLegendLabelStyle())
            }
        }
        .padding(14)
        // Size to content (capped at 280pt by the text frame) instead of a
        // fixed 300pt box, so short diffs read tight and left-aligned rather
        // than a stub of text floating in dead space.
        .frame(maxWidth: 308, alignment: .leading)
    }

    private static let addColor = Color.diffAdd

    private enum Kind { case same, added, removed }
    // A character-level run inside a single displayed word.
    private struct Piece { let kind: Kind; let text: String }
    // One whitespace-delimited slot in the diff output. Most slots hold a single
    // piece; a refined replacement (e.g. "100%" → "100%.") holds several so only
    // the changed characters get marked.
    private struct WordToken { let pieces: [Piece] }

    private static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Alphanumeric, lowercased skeleton of a word — used to recognise that a
    /// removed/added pair differs only in punctuation or case ("So," vs "so").
    private static func core(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func diff(from before: String, to after: String) -> AttributedString {
        let tokens = wordTokens(from: before, to: after)
        var result = AttributedString()
        for (i, token) in tokens.enumerated() {
            for piece in token.pieces {
                var s = AttributedString(piece.text)
                switch piece.kind {
                case .same:
                    s.foregroundColor = .primary
                case .added:
                    s.foregroundColor = addColor
                    s.backgroundColor = addColor.opacity(0.16)
                case .removed:
                    s.foregroundColor = .secondary
                    s.strikethroughStyle = .single
                }
                result += s
            }
            // Space only *between* word slots — pieces within a slot stay tight,
            // so a refined punctuation change reads as one word.
            if i < tokens.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    private static func wordTokens(from before: String, to after: String) -> [WordToken] {
        let beforeWords = tokenize(before)
        let afterWords = tokenize(after)
        let changes = afterWords.difference(from: beforeWords)

        var removedSet = Set<Int>()
        var insertedSet = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removedSet.insert(offset)
            case .insert(let offset, _, _): insertedSet.insert(offset)
            }
        }

        // Flatten into an ordered stream of word-level changes.
        struct Raw { let kind: Kind; let word: String }
        var raw: [Raw] = []
        var bi = 0, ai = 0
        while bi < beforeWords.count || ai < afterWords.count {
            if bi < beforeWords.count, removedSet.contains(bi) {
                raw.append(Raw(kind: .removed, word: beforeWords[bi]))
                bi += 1
            } else if ai < afterWords.count, insertedSet.contains(ai) {
                raw.append(Raw(kind: .added, word: afterWords[ai]))
                ai += 1
            } else {
                if ai < afterWords.count {
                    raw.append(Raw(kind: .same, word: afterWords[ai]))
                }
                bi += 1
                ai += 1
            }
        }

        // Collapse each removed-run-followed-by-added-run (a replacement region)
        // so look-alike pairs are refined to a character-level diff instead of a
        // full strike + re-add.
        var tokens: [WordToken] = []
        var i = 0
        while i < raw.count {
            if raw[i].kind == .same {
                tokens.append(WordToken(pieces: [Piece(kind: .same, text: raw[i].word)]))
                i += 1
                continue
            }
            var removedRun: [String] = []
            while i < raw.count, raw[i].kind == .removed { removedRun.append(raw[i].word); i += 1 }
            var addedRun: [String] = []
            while i < raw.count, raw[i].kind == .added { addedRun.append(raw[i].word); i += 1 }
            tokens.append(contentsOf: refine(removed: removedRun, added: addedRun))
        }
        return tokens
    }

    /// Pairs each added word with a removed word sharing the same core (a
    /// punctuation/case-only edit) and renders those as a tight character diff.
    /// Genuine word swaps and pure insert/deletes stay as whole-word marks.
    private static func refine(removed: [String], added: [String]) -> [WordToken] {
        var usedRemoved = Array(repeating: false, count: removed.count)
        var pairFor: [Int: Int] = [:]   // added index → removed index
        for (aIdx, a) in added.enumerated() {
            let ac = core(a)
            guard !ac.isEmpty else { continue }
            for rIdx in removed.indices where !usedRemoved[rIdx] && core(removed[rIdx]) == ac {
                usedRemoved[rIdx] = true
                pairFor[aIdx] = rIdx
                break
            }
        }

        var tokens: [WordToken] = []
        // Unpaired removals (genuine deletions) lead, in original order.
        for rIdx in removed.indices where !usedRemoved[rIdx] {
            tokens.append(WordToken(pieces: [Piece(kind: .removed, text: removed[rIdx])]))
        }
        for (aIdx, a) in added.enumerated() {
            if let rIdx = pairFor[aIdx] {
                tokens.append(WordToken(pieces: charPieces(from: removed[rIdx], to: a)))
            } else {
                tokens.append(WordToken(pieces: [Piece(kind: .added, text: a)]))
            }
        }
        return tokens
    }

    /// Character-level diff between two similar words, coalescing runs.
    private static func charPieces(from before: String, to after: String) -> [Piece] {
        let b = Array(before), a = Array(after)
        let changes = a.difference(from: b)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var pieces: [Piece] = []
        func append(_ kind: Kind, _ ch: Character) {
            if let last = pieces.last, last.kind == kind {
                pieces[pieces.count - 1] = Piece(kind: kind, text: last.text + String(ch))
            } else {
                pieces.append(Piece(kind: kind, text: String(ch)))
            }
        }

        var bi = 0, ai = 0
        while bi < b.count || ai < a.count {
            if bi < b.count, removed.contains(bi) {
                append(.removed, b[bi]); bi += 1
            } else if ai < a.count, inserted.contains(ai) {
                append(.added, a[ai]); ai += 1
            } else {
                if ai < a.count { append(.same, a[ai]) }
                bi += 1; ai += 1
            }
        }
        return pieces
    }
}

/// Tiny dot + caption used for the diff legend.
private struct DiffLegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))  // ds-allow: icon
            configuration.title
        }
    }
}

/// Hides the window's title text while keeping the unified toolbar and traffic
/// lights, so the toolbar shows just the status item and the Home/Settings
/// tabs. The leading status item already identifies the app.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in configure(view?.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in configure(nsView?.window) }
    }
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        // Round 12 "one sheet" chrome: no window title, no titlebar separator —
        // the traffic lights float directly on the sidebar paper, and the only
        // structural device is the rounded content sheet (see MainWindowView).
        // Lines never divide the window; they live inside the sheet as hairlines.
        // Keep the titlebar transparent + full-size content so the warm canvas
        // extends all the way to the top; our own content (the hint/gear strip
        // and lists) lays out below the titlebar safe area, unobscured.
        // Empty title (not just hidden) so no app name ever draws in the titlebar.
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        // Pin the window background to the sidebar paper — it is the window's
        // ground now (the content sheet floats on it). With a transparent
        // titlebar + full-size content, the titlebar shows the window background
        // wherever the SwiftUI layer isn't fully opaque — and the default
        // (white) bleeds through on a later redraw. Setting the asset keeps it
        // constant.
        if let ground = NSColor(named: "SidebarBG") {
            window.backgroundColor = ground
        }
        // InkIt is a fixed utility window — full screen is meaningless and only
        // litters the menu bar with a "View ▸ Enter Full Screen" item. Opting the
        // window out removes both the green-button behavior and that menu entry.
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
    }
}

// MARK: - Tooltips (design system)
//
// Two deliberately distinct "floating panel" styles. Keep them apart:
//
//   • Hover hint  — a small dark pill that *names* a control. Appears fast on
//     hover (short grace delay so a quick pass-through doesn't flash),
//     dismisses on exit, never reacts to clicks. For icon buttons whose
//     purpose isn't obvious. `.inkHoverHint("Copy")`. Replaces `.help()`,
//     which lagged ~1.5s behind the system tooltip delay.
//   • Detail popover — the light system card opened by a *click*, holding the
//     richer payload (a diff, a latency breakdown, an error reason).
//     `.inkDetailPopover(isPresented:) { … }`.
//
// A control can carry both: the hint says what it is on hover; the popover
// shows the detail on click. They never share a look, so the two gestures
// always read as two different things.

/// The dark pill itself — single line, white on near-black, soft shadow.
private struct HoverHintLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))  // ds-allow: hover-hint pill
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(Color.hudPill)
            )
            .shadow(color: Elevation.chip, radius: 5, y: 1)
    }
}

/// Padded host content for the floating panel — the transparent inset gives the
/// pill's drop shadow room so the panel doesn't clip it.
private struct HoverHintPanelContent: View {
    let text: String
    var body: some View { HoverHintLabel(text: text).padding(6) }
}

/// A borderless floating panel that renders the hover hint OUTSIDE the SwiftUI
/// view tree. The transcript list clips its content to a rounded card and pins
/// section headers on top, so an in-tree overlay gets cut off near the edges —
/// a window sits above all of that, unclipped. One shared instance: you can
/// only hover one control at a time. Any click dismisses it, so a detail
/// popover opening on the same glyph never fights the hint for space.
@MainActor
final class HoverHintWindow {
    static let shared = HoverHintWindow()
    private let panel: NSPanel
    private let hosting: NSHostingView<HoverHintPanelContent>
    private var clickMonitor: Any?

    private init() {
        hosting = NSHostingView(rootView: HoverHintPanelContent(text: ""))
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false               // the pill draws its own shadow
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting
    }

    /// Show `text` centered above `anchor` (a rect in screen coordinates).
    func show(text: String, above anchor: CGRect) {
        hosting.rootView = HoverHintPanelContent(text: text)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.hide()
                return event
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}

/// Captures the host's backing `NSView` so the hint can be positioned in screen
/// coordinates at show time (recomputed each time, so scrolling stays correct).
private struct HostViewReader: NSViewRepresentable {
    let onView: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onView(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class AnchorBox: ObservableObject { weak var view: NSView? }

/// Shows a `HoverHintLabel` floating above the host after a short grace delay,
/// via `HoverHintWindow` so it's never clipped. Dismisses on exit.
private struct HoverHint: ViewModifier {
    let text: String
    @State private var hovering = false
    @StateObject private var anchor = AnchorBox()

    func body(content: Content) -> some View {
        content
            .background(HostViewReader { anchor.view = $0 })
            .onHover { inside in
                hovering = inside
                if inside {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard hovering,
                              let view = anchor.view,
                              let frame = Self.screenFrame(of: view) else { return }
                        HoverHintWindow.shared.show(text: text, above: frame)
                    }
                } else {
                    HoverHintWindow.shared.hide()
                }
            }
            .onDisappear { HoverHintWindow.shared.hide() }
    }

    private static func screenFrame(of view: NSView) -> CGRect? {
        guard let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

extension View {
    /// Style A — a fast dark hover hint naming this control. No click behavior.
    func inkHoverHint(_ text: String) -> some View { modifier(HoverHint(text: text)) }

    /// Style B — the light detail card opened by a click. Distinct from the
    /// hover hint on purpose: richer content, an arrow, opens on tap.
    func inkDetailPopover<C: View>(isPresented: Binding<Bool>,
                                   @ViewBuilder content: @escaping () -> C) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom, content: content)
    }
}

/// A bare SF Symbol affordance with its own hover backdrop and tooltip. No
/// label or fill at rest — just a tinted glyph in a comfortable tap target that
/// lifts a soft rounded backdrop while hovered, and surfaces a hover hint
/// naming the action. The caller's tap gesture swallows the click so the row's
/// click-to-copy never fires when inspecting a chip.
private struct IconChip: View {
    let systemName: String
    let fg: Color
    let help: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))  // ds-allow: icon
            .foregroundStyle(fg)
            .frame(width: 24, height: 24)
            .hoverBackdrop(cornerRadius: Radius.chip)
            .inkHoverHint(help)
    }
}

private struct CopyTranscriptGlyph: View {
    let copied: Bool

    var body: some View {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 12, weight: .medium))  // ds-allow: icon
            .foregroundStyle(copied ? Color.accentColor : .secondary)
            .frame(width: 24, height: 24)
            // `copied` holds the amber fill; otherwise the standard hover lift.
            .hoverBackdrop(cornerRadius: Radius.chip, isActive: copied)
            .inkHoverHint("Copy")
            .animation(Motion.state, value: copied)
    }
}
