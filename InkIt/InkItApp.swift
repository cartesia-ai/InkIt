import SwiftUI
import AppKit

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
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(replacing: .help) {}
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
    @State private var tab: MainTab = .home

    private enum MainTab: Hashable { case home, settings }

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

    private var groupedEntries: [TranscriptGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                let entries = grouped[day, default: []].sorted { $0.timestamp > $1.timestamp }
                return TranscriptGroup(id: day, title: title(for: day, calendar: calendar), entries: entries)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ZStack {
                switch tab {
                case .home:
                    homeView.transition(.opacity)
                case .settings:
                    SettingsView().transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .background(settingsShortcut)
        .background(WindowTitleHider())
    }

    // In-app tab bar. Lives in the content rather than the window toolbar so
    // the native title bar stays clean — just the traffic lights.
    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(.home, title: "Home", icon: "house")
            tabButton(.settings, title: "Settings", icon: "gearshape")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // Hotkey hint at rest; appends the live state only while something is
    // actually happening, so the bar stays quiet when idle.
    private var statusLine: String {
        let hint = "Hold \(settings.hotkeyDisplayString) to dictate"
        let status = coordinator.statusText
        return status == "Idle" ? hint : "\(hint) · \(status)"
    }

    // Icon + label pill tab. The active tab is tinted; tapping crossfades the
    // content and the highlight together.
    @ViewBuilder
    private func tabButton(_ value: MainTab, title: String, icon: String) -> some View {
        let selected = (tab == value)
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { tab = value }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // Invisible affordance so ⌘, still jumps to Settings — the macOS-standard
    // shortcut, preserved even though Settings is now a tab rather than a
    // separate window.
    private var settingsShortcut: some View {
        Button("") { withAnimation(.easeInOut(duration: 0.18)) { tab = .settings } }
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var homeView: some View {
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

    private var transcriptList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedEntries) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 2)

                            LazyVStack(spacing: 8) {
                                ForEach(group.entries) { entry in
                                    transcriptRow(entry)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            Divider()
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(coordinator.statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(history.entries.count) transcript\(history.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    history.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .modifier(PointingHandCursor())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
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

/// Shown on Home only when there's no history at all — i.e. the user skipped the
/// onboarding Try-it step. Rather than dead-ending, it offers a live dictation
/// box: read the line, hold the key, watch the words land. Reuses the onboarding
/// trial routing (`beginOnboardingTrial`) and opts that path into history logging
/// so the first take immediately becomes a real row and the empty state is gone.
private struct HomeTryItPanel: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore

    private let sampleLine = "Help me plan a slow Sunday full of pancakes, sunshine, and a long nap."
    private static let recordingAmber = Color(red: 1.0, green: 0.62, blue: 0.04)

    @State private var invite = false
    @State private var hasPressed = false

    private var isRecording: Bool { coordinator.state == .recording }
    private var transcript: String { coordinator.liveTranscript }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text("No transcripts yet")
                    .font(.headline)
                Text("Give it a try right here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            panel

            Text("Or hold \(settings.hotkeyDisplayString) in any app and start talking.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear {
            // Route takes into the box below and persist them, so trying it here
            // populates Home. Cleared on disappear (which fires the moment the
            // first take lands and the list replaces this panel).
            coordinator.logTrialTakesToHistory = true
            coordinator.beginOnboardingTrial()
        }
        .onDisappear {
            coordinator.logTrialTakesToHistory = false
            coordinator.endOnboardingTrial()
        }
        .onChange(of: isRecording) { _, recording in
            if recording { hasPressed = true }
        }
    }

    private var panel: some View {
        VStack(spacing: 20) {
            promptBar
            keyCap
            resultBox
        }
        .padding(22)
        .frame(maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("CardBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }

    private var promptBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("READ THIS ALOUD")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.accentColor)
            Text(sampleLine)
                .font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3)
        }
    }

    private var keyCap: some View {
        HStack(spacing: 10) {
            if isRecording {
                Circle()
                    .fill(Self.recordingAmber)
                    .frame(width: 11, height: 11)
                    .shadow(color: Self.recordingAmber.opacity(0.7), radius: 5)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15))
            }
            Text(isRecording ? "Listening…" : "Hold \(settings.hotkeyDisplayString) to talk")
                .font(.system(size: 15, weight: .bold))
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isRecording ? Color.accentSoft : Color("PaperBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isRecording ? Self.recordingAmber : Color(nsColor: .separatorColor),
                        lineWidth: 1.5)
        )
        .scaleEffect(isRecording ? 0.97 : 1)
        .overlay(inviteRing.opacity(showInvite ? 1 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isRecording)
        .animation(.easeOut(duration: 0.4), value: showInvite)
    }

    private var resultBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT INKIT HEARD")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(transcript.isEmpty ? "Your words appear here after you let go." : transcript)
                .font(.system(size: 15))
                .foregroundStyle(transcript.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("PaperBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// Glow that invites only the first press, then retires (matches onboarding).
    private var showInvite: Bool { !hasPressed && !isRecording }

    private var inviteRing: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(-5)
            .scaleEffect(invite ? 1.09 : 0.97)
            .opacity(invite ? 0 : 0.5)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 2.1).repeatForever(autoreverses: false)) {
                    invite = true
                }
            }
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

    // Each row is a soft card. At rest it shows the cleaned-up transcript plus a
    // dimmed timestamp anchor; the rest of the detail line (latency, polish
    // sparkle) fades in on hover. A failure warning is the one signal that stays
    // visible at rest. The detail line's height is always reserved so hovering
    // never reflows the list.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CopyTranscriptGlyph(copied: copied, highlighted: hovering)
                    .opacity(hovering || copied ? 1 : 0)
            }

            detailLine
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(rowStroke, lineWidth: hovering || copied ? 1 : 0)
        )
        // Whole row is click-to-copy. The sparkle below swallows its own taps
        // so inspecting the diff never triggers a copy.
        .onTapGesture { copy() }
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = isHovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: copied)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }

    // The detail line carries two always-visible, tappable pills — polish and
    // time-to-text — anchored by a dim timestamp. Earlier these were hidden until
    // hover and opened on a second hover, which testers found undiscoverable and
    // "wonky." Now the affordances read at rest and open on a single click.
    private var detailLine: some View {
        HStack(spacing: 8) {
            // Always-on anchor: a dim timestamp keeps the row from reading blank.
            // Brightens slightly on hover alongside the pills.
            Text(timestamp)
                .font(.caption)
                .foregroundStyle(hovering ? .secondary : .tertiary)

            // Pills group on the left, next to the timestamp: polish first (when
            // it ran), then time-to-text. With polish off, the time pill sits
            // directly beside the timestamp.
            switch outcome {
            case .polished: polishPill
            case .failed:   failurePill
            case .off:      EmptyView()
            }

            if let latency {
                timePill(latency)
            }

            Spacer(minLength: 0)
        }
    }

    /// Sparkle glyph — a single click reveals the before/after diff. The label
    /// and exact stats live in the popover so the row stays uncluttered.
    private var polishPill: some View {
        iconChip("sparkles", fg: Color.accentColor)
            .onTapGesture { showingDiff.toggle() }
            .popover(isPresented: $showingDiff, arrowEdge: .bottom) {
                DiffPopover(before: original ?? text, after: text)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel("Polished — show changes")
    }

    /// Struck-through sparkle in soft amber — polish failed and raw text was
    /// pasted. Click for the actionable reason.
    private var failurePill: some View {
        iconChip("sparkles.slash", fg: .orange)
            .onTapGesture { showingFailure.toggle() }
            .popover(isPresented: $showingFailure, arrowEdge: .bottom) {
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
        iconChip("clock", fg: .secondary)
            .onTapGesture { showingLatency.toggle() }
            .popover(isPresented: $showingLatency, arrowEdge: .bottom) {
                LatencyPopover(latency: latency, polishFailed: outcome == .failed)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel("Time to text \(Self.fmt(latency.totalMs)) — show breakdown")
    }

    /// A bare SF Symbol affordance: no label, no fill — just a tinted glyph with
    /// a comfortable tap target. The caller's tap gesture swallows the click so
    /// the row's click-to-copy never fires when inspecting a chip.
    private func iconChip(_ systemName: String, fg: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
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

    private var rowFill: Color {
        if hovering {
            return Color.accentColor.opacity(0.08)
        }
        // Soft card: a faint, borderless fill that lifts the row off the window
        // background just enough to read as a distinct item. Adapts to light/dark.
        return Color.primary.opacity(0.04)
    }

    private var rowStroke: Color {
        Color.accentColor.opacity(copied ? 0.32 : 0.28)
    }
}

/// Per-stage breakdown shown when hovering the "Time to text" stat on a row.
/// The row keeps the clean total; this reveals where the time went —
/// transcribe (release → final transcript), polish (the AI rewrite), and
/// paste (insertion into the target app). The polish row is omitted when
/// correction didn't run (polishMs == 0), so it never reads as a stalled 0ms.
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
                stageRow("Paste", latency.pasteMs)
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

    private static let addColor = Color.green

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
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

/// Hides the window's title text while keeping the unified toolbar and traffic
/// lights, so the toolbar shows just the status item and the Home/Settings
/// tabs. The leading status item already identifies the app.
private struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in hide(view?.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in hide(nsView?.window) }
    }
    private func hide(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.title = ""
    }
}

private struct CopyTranscriptGlyph: View {
    let copied: Bool
    let highlighted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(copied ? Color.green.opacity(0.15) : Color.primary.opacity(highlighted ? 0.06 : 0))
                .frame(width: 24, height: 24)

            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .frame(width: 24, height: 24)
        .animation(.easeOut(duration: 0.15), value: copied)
    }
}
