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
    // Brand
    /// Amber tint fill behind glyphs/badges (14% light / 18% dark, via catalog).
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
    static let canvas  = Color("HomeCanvas")  // window background
    static let surface = Color("HomeSurface") // raised panel (stats rail)
    static let lift    = Color("HomeLift")    // top panel (history log)
    static let card    = Color("CardBG")      // cards, fields, controls
    static let paper   = Color("PaperBG")     // inset wells (try-it box)

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
    /// Onboarding hero title.
    static let inkLargeTitle = Font.system(size: 28, weight: .bold)
    /// Screen / pane / column title (History, Your stats, Settings pane).
    static let inkTitle = Font.system(size: 18, weight: .regular)
    /// Top-of-Home banner (the "dictate anywhere" cue) — a step above the column
    /// titles so it leads, without the weight of the onboarding hero.
    static let inkBanner = Font.system(size: 22, weight: .regular)
    /// Compact sheet / popover header title — smaller than a full-window pane
    /// title (the Settings popover header).
    static let inkSheetTitle = Font.system(size: 16, weight: .medium)
    /// Card / sub-section heading (nudge title, field group).
    static let inkHeadline = Font.system(size: 15, weight: .semibold)
    /// Featured stat number — monospaced digits applied at use.
    static let inkStat = Font.system(size: 22, weight: .semibold)
    /// Uppercase eyebrow: group headers, day dividers, diff row labels.
    static let inkEyebrow = Font.system(size: 11, weight: .semibold)
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
    /// Secondary body / metadata that still needs to read easily.
    static let inkCallout = Font.system(size: 13)
    /// Emphasized callout — selectable card / control titles that sit at the
    /// body-row scale rather than the heavier 15pt (Settings option cards).
    static let inkCalloutEmphasized = Font.system(size: 13, weight: .medium)
    /// Sidebar / navigation item label. A hair above the 13pt detail rows so
    /// the nav reads as primary without overpowering the content it points to.
    static let inkNav = Font.system(size: 13.5)
    /// Small medium-weight UI label at the same scale step — grouped-section
    /// headers in Settings and keycap chips in the shortcut recorder.
    static let inkSectionHeader = Font.system(size: 12.5, weight: .medium)
    /// Helper / captions / units.
    static let inkCaption = Font.system(size: 12)
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
    /// hover, the system hairline at rest. Shared by the activation-mode and
    /// appearance cards so both pick the same way.
    static func cardBorder(isSelected: Bool, hovering: Bool) -> Color {
        if isSelected { return .accentColor }
        return hovering ? Color.primary.opacity(borderOpacity) : Color(nsColor: .separatorColor)
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
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape.fill(isActive
                           ? Color.accentSoft
                           : Color.primary.opacity(hovering ? Hover.backdropOpacity : 0))
            )
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Hover.animation, value: hovering)
    }
}

extension View {
    /// Lift the app's standard soft hover backdrop. See `HoverBackdrop`.
    func hoverBackdrop(cornerRadius: CGFloat = 8, isActive: Bool = false) -> some View {
        modifier(HoverBackdrop(cornerRadius: cornerRadius, isActive: isActive))
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
private struct HeaderIconButton: View {
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
private struct ManageMenuRow: View {
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
            Color.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content
                .background(Color.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .shadow(color: Elevation.modal, radius: 40, y: 18)
        }
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

    var body: some Scene {
        WindowGroup("InkIt", id: "main") {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(history)
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
        .defaultSize(width: 1159, height: 862)
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
                MainWindowView()
                    .frame(minWidth: 520, minHeight: 480)
            } else {
                OnboardingRootView()
                    .frame(minWidth: 620, idealWidth: 1159, maxWidth: .infinity,
                           minHeight: 560, idealHeight: 862, maxHeight: .infinity)
            }
        }
        .onAppear { settings.applyAppearance() }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: TranscriptHistoryStore
    @State private var copiedID: UUID?
    @State private var showSettings = false
    @State private var settingsPane: SettingsView.Pane = .general
    // History controls. Search collapses to a single icon at rest and expands
    // inline; the field stays open while there's a query and collapses only when
    // emptied (macOS toolbar-search convention). Sort persists across launches —
    // it's a stated preference. Delete-all routes through a confirm modal.
    @State private var searchExpanded = false
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("history.newestFirst") private var newestFirst = true
    @State private var showDeleteConfirm = false
    @State private var showManageMenu = false

    private struct TranscriptGroup: Identifiable {
        let id: Date
        let title: String
        let entries: [TranscriptHistoryStore.Entry]
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    // Case-insensitive substring match on the visible transcript text. Empty
    // query returns everything, so the list renders unchanged when search is idle.
    private var filteredEntries: [TranscriptHistoryStore.Entry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.lowercased().contains(q) }
    }

    private var groupedEntries: [TranscriptGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        // Day groups and the rows within them both follow the sort toggle, so
        // "Oldest first" flips the whole list, not just the order inside a day.
        return grouped.keys
            .sorted(by: newestFirst ? (>) : (<))
            .map { day in
                let entries = grouped[day, default: []].sorted {
                    newestFirst ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp
                }
                return TranscriptGroup(id: day, title: title(for: day, calendar: calendar), entries: entries)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            dictationIssueBanner
            homeView
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // "InkIt" rides in the native titlebar (no glass). No dedicated top
            // strip — the gear floats in the bottom-right corner and the
            // dictation hint tucks inline next to the History header (see
            // transcriptList).
            .overlay(alignment: .bottomTrailing) {
                gearButton
                    .padding(.bottom, 14)
                    .padding(.trailing, 14)
            }
            .background(Color.canvas)
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
                settingsPane = .general
                withAnimation(Motion.quick) { showSettings = true }
            }
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

    private var gearButton: some View {
        Button {
            // Always land on General — Settings doesn't remember the last pane.
            if !showSettings { settingsPane = .general }
            withAnimation(Motion.quick) { showSettings.toggle() }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))  // ds-allow: icon
                .foregroundStyle(showSettings ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .hoverBackdrop(cornerRadius: Radius.button, isActive: showSettings)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .inkHoverHint("Settings")
    }

    // Quiet "Hold fn to dictate" line with a live status dot — appended with the
    // active state (recording / transcribing) only while something is happening.
    private var statusHint: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(coordinator.statusColor)
                .frame(width: 7, height: 7)
            // Keycaps set the shortcut apart from the surrounding prose; the live
            // state appends only while something is happening, so it stays quiet
            // when idle.
            HStack(spacing: 5) {
                Text(settings.dictationModeVerb)
                HotkeyCaps(tokens: HotkeyConversion.displayTokens(for: settings.hotkey))
                Text(settings.dictationMode == .toggle ? "to start and stop" : "to dictate")
                if coordinator.statusText != "Idle" {
                    Text("· \(coordinator.statusText)")
                }
            }
            .font(.inkCaption)
            .foregroundStyle(.secondary)
        }
        .padding(.trailing, 6)
    }


    @ViewBuilder private var homeView: some View {
        VStack(spacing: 0) {
            // While the user is still finding their feet (under two transcripts),
            // a rotating header spells out that dictation works in any app —
            // the post-onboarding "can I use this elsewhere?" gap. It self-
            // retires once they've dictated a couple of times.
            if history.entries.count < 2 {
                RotatingDictateHeader(tokens: HotkeyConversion.displayTokens(for: settings.hotkey))
            }
            if history.entries.isEmpty {
                // A completed onboarding trial seeds the very first transcript (see
                // AppCoordinator's trial logging), so most users never see this.
                // It's reached only when they skipped Try-it — so rather than a
                // dead-end "nothing here," offer a live try box that turns the first
                // take into a real history row, closing the activation loop in place.
                HomeTryItPanel()
            } else {
                transcriptList
            }
        }
    }

    // Below this content width the stats rail is dropped entirely and the
    // history list takes the full window — small windows stay focused on the
    // transcripts rather than cramming a sidebar alongside them.
    private static let railBreakpoint: CGFloat = 960

    // Two columns on the warm canvas, each with a section header above a soft
    // rounded panel — history on the left, stats (+ Polish nudge) on the right.
    // No vertical divider; the gap separates them. Below the breakpoint the rail
    // drops and history takes the full width.
    private var transcriptList: some View {
        GeometryReader { geo in
            let showRail = geo.size.width >= Self.railBreakpoint
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    historyHeader
                    mainPanel
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if showRail {
                    VStack(alignment: .leading, spacing: 0) {
                        columnHeader("Your stats", subtitle: nil)
                        railPanel
                        if settings.polishIssue != nil {
                            polishIssueCard
                                .padding(.top, 14)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 300)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
    }

    // History header: title + its two quiet actions (search, manage) on the left,
    // the "Hold fn to dictate" cue + live status dot right-aligned. The actions
    // sit by the title so the list itself stays the loudest thing on screen.
    private var historyHeader: some View {
        HStack(spacing: 8) {
            Text("History")
                .font(.inkTitle)
                .foregroundStyle(.primary)
                .padding(.trailing, 2)
            searchControl
            manageMenu
            Spacer(minLength: 0)
            // Suppressed while the rotating "dictate anywhere" header is up
            // (under two transcripts) — it already carries the hotkey cue, so
            // the hint would just be duplicated.
            if history.entries.count >= 2 {
                statusHint
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
        .animation(Motion.expand, value: searchExpanded)
        // ⌘F opens (and focuses) search from anywhere in the window. Zero-opacity
        // so it carries the shortcut without drawing anything.
        .background(
            Button(action: expandSearch) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        )
    }

    // Collapsed: a lone magnifier. Expanded: an inline field on a card. The field
    // collapses only when it loses focus while empty (see onChange below).
    @ViewBuilder private var searchControl: some View {
        if searchExpanded {
            searchField
                .transition(.opacity)
        } else {
            HeaderIconButton(systemName: "magnifyingglass",
                             hint: "Search transcripts",
                             action: expandSearch)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))  // ds-allow: icon
                .foregroundStyle(.tertiary)
            TextField("Search transcripts…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.inkCallout)
                .focused($searchFocused)
                .onExitCommand { collapseSearch() }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))  // ds-allow: icon
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        // Click anywhere outside the field collapses it and drops the caret,
        // reusing the app's shared click-outside dismisser (a non-consuming
        // NSEvent monitor — the click still does its normal job). Esc and the ✕
        // also collapse; clicks inside the field keep it open.
        .dismissOnClickOutside(isActive: searchExpanded) { collapseSearch() }
    }

    // The "Manage transcripts" overflow: sort order (checkmarked) + the
    // destructive Delete All. Built as a HeaderIconButton (so it inherits the
    // working hover fill + hand cursor, exactly like search and the gear) opening
    // an inkDetailPopover — SwiftUI's Menu swallows hover on its label, so it
    // can't carry the affordance the rest of the chrome has.
    private var manageMenu: some View {
        HeaderIconButton(systemName: "ellipsis", hint: "Manage transcripts") {
            showManageMenu.toggle()
        }
        .inkDetailPopover(isPresented: $showManageMenu) {
            VStack(alignment: .leading, spacing: 1) {
                ManageMenuRow(title: "Newest first", checked: newestFirst) {
                    newestFirst = true
                    showManageMenu = false
                }
                ManageMenuRow(title: "Oldest first", checked: !newestFirst) {
                    newestFirst = false
                    showManageMenu = false
                }
                Divider()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                ManageMenuRow(title: "Delete All", icon: "trash", destructive: true) {
                    showManageMenu = false
                    withAnimation(Motion.quick) { showDeleteConfirm = true }
                }
            }
            .padding(5)
            .frame(width: 200)
        }
    }

    private func expandSearch() {
        withAnimation(Motion.expand) { searchExpanded = true }
        // Focus on the next runloop tick so the field exists before we target it.
        DispatchQueue.main.async { searchFocused = true }
    }

    private func collapseSearch() {
        searchQuery = ""
        searchFocused = false
        withAnimation(Motion.expand) { searchExpanded = false }
    }

    // Destructive confirm, on the same warm centered-card chrome as the Settings
    // modal (dimmed backdrop, Color.canvas card, 16pt corners). Click-out or
    // Cancel/Esc backs out; Delete All clears history and any active filter.
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
        collapseSearch()
        dismissDeleteConfirm()
    }

    private func columnHeader(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(title)
                .font(.inkTitle)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.inkCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    // The history log — a soft near-white page. Day headers, then rows divided by
    // faint full-width hairlines (no per-row boxes).
    private var mainPanel: some View {
        ScrollView {
            // Pinned section headers keep the current day (Today / Yesterday / …)
            // stuck to the top of the panel as you scroll its rows.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Reached only with an active query (the empty-history case shows
                // the Try-It panel upstream), so this is always a "no match" state.
                if groupedEntries.isEmpty {
                    Text("No transcripts match “\(searchQuery)”")
                        .font(.inkCallout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 56)
                }
                ForEach(groupedEntries) { group in
                    Section {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 1)
                                    .padding(.horizontal, 8)
                            }
                            transcriptRow(entry)
                        }
                    } header: {
                        dayHeader(group.title)
                    }
                }
            }
            // Soft cap so transcripts don't run edge-to-edge on a maximized window.
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 6)
            // Breathing room so rows aren't flush against the card edges at the
            // scroll extremes; the fade mask below softens everything in between.
            .padding(.top, 6)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dissolve rows into the card at both edges instead of a hard clip
        // against the rounded corners. Applied to the scrolling content only —
        // the background fill (added next) stays solid edge to edge.
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)
            }
        )
        .background(Color.lift)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: Elevation.ambient, radius: 6, y: 1)
    }

    // Pinned day header. Carries the panel fill so scrolling rows pass cleanly
    // beneath it; full-width so nothing peeks through at the edges.
    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(.inkEyebrow)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(Color.lift)
    }

    // Stats (warm amber icon tiles) and, when Polish is off, the nudge — all in
    // one panel that sizes to its content, so there's never an empty void.
    private var railPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordsStatRow
            timeSavedStatRow
            avgLatencyStatRow

            if showPolishNudge {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.vertical, 14)
                nudgeContent
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var showPolishNudge: Bool {
        !settings.correctionEnabled && !settings.polishNudgeDismissed
    }

    // A lost dictation is critical (the core feature is down), so a Cartesia key
    // /credit problem gets a full-width banner across the top of Home — more
    // noticeable than a rail card. Polish failing is only degraded (raw text
    // still pastes), so it stays a calm rail card below. Both are driven by the
    // persisted flags, so they're sticky until fixed — never a 2.5s flash.
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
                        .font(.inkCaption.weight(.semibold))
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

    // The Polish (provider) problem as a calm rail card below the stats. Soft
    // amber, same language as the stats/nudge — guidance, not alarm.
    @ViewBuilder private var polishIssueCard: some View {
        if let issue = settings.polishIssue {
            statusCard(
                icon: "exclamationmark.triangle.fill",
                title: "Polish is paused",
                message: polishIssueMessage(issue),
                cta: polishIssueCTA(issue),
                action: { polishIssueAction(issue) }
            )
        }
    }

    private func statusCard(icon: String, title: String, message: String,
                            cta: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Color.accentSoft)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))  // ds-allow: icon
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.inkBodyEmphasized)
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.inkCaption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: action) {
                Text(cta)
                    .font(.inkCaption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())
            .padding(.leading, 41)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: Status-card copy + actions

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
            settingsPane = .dictation
            showSettings = true
        case .outOfCredits:
            NSWorkspace.shared.open(URL(string: "https://play.cartesia.ai/subscription")!)
        }
    }

    private func polishIssueMessage(_ issue: SettingsStore.ServiceIssue) -> String {
        let p = settings.rewriteProvider.displayName
        switch issue {
        case .keyInvalid:
            return "Your \(p) API key is invalid. Update it to turn Polish back on."
        case .outOfCredits:
            return "You're out of \(p) credits. Review your \(p) plan to re-enable Polish."
        }
    }
    private func polishIssueCTA(_ issue: SettingsStore.ServiceIssue) -> String {
        let p = settings.rewriteProvider.displayName
        switch issue {
        case .keyInvalid:   return "Update your \(p) key"
        case .outOfCredits: return "Review your \(p) plan"
        }
    }
    private func polishIssueAction(_ issue: SettingsStore.ServiceIssue) {
        switch issue {
        case .keyInvalid:
            settingsPane = .polish
            showSettings = true
        case .outOfCredits:
            NSWorkspace.shared.open(settings.rewriteProvider.billingURL)
        }
    }

    private var wordsStatRow: some View {
        statRow(icon: "text.alignleft",
                value: Self.compactNumber(history.lifetimeWords),
                unit: "words", label: "dictated")
    }

    @ViewBuilder private var timeSavedStatRow: some View {
        let saved = Self.timeSaved(words: history.lifetimeWords)
        statRow(icon: "clock", value: saved.value, unit: saved.unit, label: "saved vs typing")
    }

    @ViewBuilder private var avgLatencyStatRow: some View {
        if let avg = averageLatencyMs {
            let f = Self.latencyValue(avg)
            statRow(icon: "bolt.fill", value: f.value, unit: f.unit, label: "avg time to text")
        } else {
            statRow(icon: "bolt.fill", value: "—", unit: "", label: "avg time to text")
        }
    }

    // A friendly stat: amber icon tile + big number/unit + quiet label beneath.
    private func statRow(icon: String, value: String, unit: String, label: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.accentSoft)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))  // ds-allow: icon
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.inkStat)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.inkCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(label)
                    .font(.inkCaption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    // Inline nudge content (no card chrome — it lives inside the stats panel).
    private var nudgeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Color.accentSoft)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))  // ds-allow: icon
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)

                Spacer(minLength: 0)

                Button { settings.polishNudgeDismissed = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))  // ds-allow: icon
                        .foregroundStyle(.tertiary)
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
                .accessibilityLabel("Dismiss")
            }
            .padding(.bottom, 12)

            Text("Polish your dictation")
                .font(.inkHeadline)
                .foregroundStyle(.primary)
                .padding(.bottom, 6)

            Text("Talk like yourself. Polish cleans up fillers, fumbles, and punctuation automagically.")
                .font(.inkCallout)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            PolishMiniDemo()
                .padding(.bottom, 14)

            Button {
                settingsPane = .polish
                showSettings = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))  // ds-allow: icon
                    Text("Set up Polish")
                        .font(.inkBodyEmphasized)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())
        }
    }

    /// Mean total time-to-text over the stored history (entries that recorded a
    /// latency). A rolling recent average — more relevant than a lifetime mean.
    private var averageLatencyMs: Int? {
        let totals = history.entries.compactMap { $0.latency?.totalMs }
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / totals.count
    }

    private func transcriptRow(_ entry: TranscriptHistoryStore.Entry) -> some View {
        TranscriptHistoryRow(
            text: entry.text,
            timestamp: Self.timeFmt.string(from: entry.timestamp),
            latency: entry.latency,
            original: entry.original,
            polish: entry.polish,
            failure: entry.failure,
            copied: copiedID == entry.id
        ) {
            copy(entry)
        }
    }

    // MARK: Stat formatting

    /// 412 · 8.4K · 1.2M — compact so a big lifetime total stays one glance.
    static func compactNumber(_ n: Int) -> String {
        switch n {
        case ..<1_000:
            return "\(n)"
        case ..<1_000_000:
            let k = Double(n) / 1_000
            return k < 10 ? String(format: "%.1fK", k) : "\(Int(k.rounded()))K"
        default:
            let m = Double(n) / 1_000_000
            return String(format: "%.1fM", m)
        }
    }

    /// Estimated time saved vs typing: the gap between typing the words (~40 wpm)
    /// and speaking them (~150 wpm). An estimate — the "saved vs typing" label
    /// signals as much.
    static func timeSaved(words: Int) -> (value: String, unit: String) {
        let minutes = Double(words) * (1.0 / 40.0 - 1.0 / 150.0)
        // Below a minute, show seconds so the very first dictation registers
        // something rather than a discouraging "0 min".
        if minutes < 1 { return ("\(Int((minutes * 60).rounded()))", "sec") }
        if minutes < 60 { return ("\(Int(minutes.rounded()))", "min") }
        let hours = minutes / 60
        if hours < 24 { return (hours < 10 ? String(format: "%.1f", hours) : "\(Int(hours.rounded()))", "h") }
        let days = hours / 24
        return (days < 10 ? String(format: "%.1f", days) : "\(Int(days.rounded()))", "days")
    }

    static func latencyValue(_ ms: Int) -> (value: String, unit: String) {
        ms < 1000 ? ("\(ms)", "ms") : (String(format: "%.1f", Double(ms) / 1000), "s")
    }

    private func copy(_ entry: TranscriptHistoryStore.Entry) {
        let pb = NSPasteboard.general
        pb.declareTypes([.string], owner: nil)
        pb.setString(entry.text, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        let startOfToday = calendar.startOfDay(for: Date())
        if let daysAgo = calendar.dateComponents([.day], from: day, to: startOfToday).day,
           daysAgo < 7 {
            return Self.dayFmt.string(from: day)
        }

        return Self.dayFmt.string(from: day)
    }
}

/// The current hotkey as one amber highlight, tokens joined by "+", e.g.
/// "⌃ Ctrl + s". Sets the shortcut apart from surrounding prose. Inherits the
/// ambient font and adds no vertical padding, so its text and highlight match
/// the line it sits in.
private struct HotkeyCaps: View {
    let tokens: [String]

    var body: some View {
        Text(tokens.joined(separator: " + "))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
                    .fill(Color.accentSoft)
            )
    }
}

/// The Home "you can dictate anywhere" header. Sits above the Home content while
/// the user has fewer than two transcripts (see `homeView`), then retires. The
/// category word + its three app logos swap together on a soft cross-fade so the
/// line reads as one alive cue rather than a static banner. Pauses on hover so a
/// bucket is readable; honors Reduce Motion by holding the first bucket still.
private struct RotatingDictateHeader: View {
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
            HotkeyCaps(tokens: tokens)  // inherits the .inkBanner weight, matching the sentence
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
        // Leads the page — a step above the History / Your-stats column titles
        // (inkTitle), without the bulk of the onboarding hero.
        .font(.inkBanner)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 8)
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
private struct HomeTryItPanel: View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct TranscriptHistoryRow: View {
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

    // Trailing affordances, right-aligned in a fixed-width column. All fade in
    // on hover so resting rows stay just time + words.
    private var trailingControls: some View {
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

/// The Home nudge's teaching moment: a compact before→after that animates once
/// on appear. The raw line is shown verbatim; the polished line reveals after a
/// beat as an inline diff using the app's vocabulary — struck-through removals,
/// accent-green fixes. "Show, don't tell."
private struct PolishMiniDemo: View {
    @State private var revealed = false

    private var before: Text {
        Text("um hey are you free this this weekend to grab coffee slash lunch")
    }
    private var after: Text {
        Text("um ").strikethrough().foregroundColor(.secondary)
        + Text("Hey,").foregroundColor(Color.diffAdd)
        + Text(" are you free this ")
        + Text("this ").strikethrough().foregroundColor(.secondary)
        + Text("weekend to grab coffee")
        + Text(" slash").strikethrough().foregroundColor(.secondary)
        + Text("/").foregroundColor(Color.diffAdd)
        + Text("lunch")
        + Text("?").foregroundColor(Color.diffAdd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("YOU SAID", before, accent: false)
            if revealed {
                row("POLISHED", after, accent: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(Color.primary.opacity(0.04)))
        .onAppear {
            // Animate once: hold on the raw line, then reveal the polished one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { revealed = true }
            }
        }
    }

    private func row(_ label: String, _ content: Text, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.inkEyebrow)
                .tracking(0.5)
                .foregroundStyle(accent ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            content
                .font(.inkCallout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Show the native, system-drawn title "InkIt" — centered on the traffic-
        // lights row with no toolbar (so no macOS 26 glass capsule). Keep the
        // titlebar transparent + full-size content so the warm canvas extends all
        // the way to the top behind the title; our own content (the hint/gear
        // strip and lists) lays out below the titlebar safe area, unobscured.
        window.title = "InkIt"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // Pin the window background to the warm canvas. With a transparent
        // titlebar + full-size content, the titlebar shows the window background
        // wherever the SwiftUI layer isn't fully opaque — and the default
        // (white) bleeds through on a later redraw, flipping the titlebar from
        // canvas-grey to white. Setting it to the canvas asset keeps it constant.
        if let canvas = NSColor(named: "HomeCanvas") {
            window.backgroundColor = canvas
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
