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
    @State private var showSettings = false
    @State private var gearHovering = false
    @State private var settingsPane: SettingsView.Pane = .general

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
        homeView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // "InkIt" rides in the native titlebar (no glass). No dedicated top
            // strip — the gear pins to the top-right corner and the dictation
            // hint tucks inline next to the History header (see transcriptList).
            .overlay(alignment: .topTrailing) {
                gearButton
                    .padding(.top, 6)
                    .padding(.trailing, 14)
            }
            .background(Color("HomeCanvas"))
            .background(settingsShortcut)
            .background(WindowChrome())
            .overlay { settingsModal }
    }

    // Settings as a centered modal over a dimmed backdrop (Flow-style), not a
    // gear-anchored popover. Click-out or the pane's ✕ / Esc dismisses it.
    @ViewBuilder private var settingsModal: some View {
        if showSettings {
            ZStack {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissSettings() }
                SettingsPopover(pane: $settingsPane, onClose: dismissSettings)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
            }
            .transition(.opacity)
        }
    }

    private func dismissSettings() {
        withAnimation(.easeOut(duration: 0.12)) { showSettings = false }
    }

    private var gearButton: some View {
        Button { withAnimation(.easeOut(duration: 0.12)) { showSettings.toggle() } } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(showSettings ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(showSettings ? Color.accentSoft : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .help("Settings (⌘,)")
    }

    // Quiet "Hold fn to dictate" line with a live status dot — appended with the
    // active state (recording / transcribing) only while something is happening.
    private var statusHint: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(coordinator.statusColor)
                .frame(width: 7, height: 7)
            Text(statusLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 6)
    }

    // Hotkey hint at rest; appends the live state only while something is
    // actually happening, so the bar stays quiet when idle.
    private var statusLine: String {
        let hint = "Hold \(settings.hotkeyDisplayString) to dictate"
        let status = coordinator.statusText
        return status == "Idle" ? hint : "\(hint) · \(status)"
    }

    // Invisible affordance so ⌘, opens Settings — the macOS-standard shortcut.
    private var settingsShortcut: some View {
        Button("") { showSettings = true }
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

    // Below this content width the stats rail is dropped entirely and the
    // history list takes the full window — small windows stay focused on the
    // transcripts rather than cramming a sidebar alongside them.
    private static let railBreakpoint: CGFloat = 780

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

    // History header: title on the left, the "Hold fn to dictate" cue + live
    // status dot right-aligned to the History box's right edge.
    private var historyHeader: some View {
        HStack(spacing: 14) {
            Text("History")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            statusHint
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    private func columnHeader(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
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
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("HomeLift"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
    }

    // Pinned day header. Carries the panel fill so scrolling rows pass cleanly
    // beneath it; full-width so nothing peeks through at the edges.
    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(Color("HomeLift"))
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
        .background(Color("HomeSurface"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var showPolishNudge: Bool {
        !settings.correctionEnabled && !settings.polishNudgeDismissed
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentSoft)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(label)
                    .font(.system(size: 12))
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
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentSoft)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)

                Spacer(minLength: 0)

                Button { settings.polishNudgeDismissed = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 6)

            Text("Auto-fix filler, punctuation, and misheard words after each dictation.")
                .font(.system(size: 13))
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
                        .font(.system(size: 12, weight: .semibold))
                    Text("Set up Polish")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        if minutes < 1 { return ("0", "min") }
        if minutes < 60 { return ("\(Int(minutes.rounded()))", "min") }
        let hours = minutes / 60
        return (hours < 10 ? String(format: "%.1f", hours) : "\(Int(hours.rounded()))", "h")
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

    // A compact transcript-log entry: timestamp in a fixed left gutter, the
    // cleaned-up text in the middle, affordances on the trailing edge. Polish /
    // time / copy are hover-only so resting rows are just time + words and stay
    // tight — except a *failed* polish, which shows at rest (silently hiding a
    // failure is worse than a touch of clutter). The trailing column is a fixed
    // width so text wraps consistently and nothing shifts on hover.
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timestamp)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 74, alignment: .leading)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailingControls
                .frame(width: 68, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(0.055) : Color.clear)
        )
        // Whole row is click-to-copy. The chips swallow their own taps so
        // inspecting the diff/latency never triggers a copy.
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

    // Trailing affordances, right-aligned in a fixed-width column. A failed
    // polish stays visible at rest; everything else fades in on hover.
    private var trailingControls: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            CopyTranscriptGlyph(copied: copied)
                .opacity(hovering || copied ? 1 : 0)
            if outcome == .polished {
                polishPill.opacity(hovering ? 1 : 0)
            }
            if outcome == .failed {
                failurePill
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

    /// Struck-through sparkle in soft amber — polish failed and raw text was
    /// pasted. Click for the actionable reason.
    private var failurePill: some View {
        IconChip(systemName: "sparkles.slash", fg: .orange, help: "Polish failed")
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

/// The Home nudge's teaching moment: a compact before→after that animates once
/// on appear (the polished line reveals after a beat), using the app's diff
/// vocabulary — struck-through filler, accent-green fixes. "Show, don't tell."
private struct PolishMiniDemo: View {
    @State private var revealed = false

    private var before: Text {
        Text("um so like ").strikethrough().foregroundColor(.secondary)
        + Text("can you send me ")
        + Text("the ").strikethrough().foregroundColor(.secondary)
        + Text("the report by friday")
    }
    private var after: Text {
        Text("Can").foregroundColor(.green)
        + Text(" you send me the report by ")
        + Text("Friday?").foregroundColor(.green)
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
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
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
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(accent ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            content
                .font(.system(size: 12.5))
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.13))
            )
            .shadow(color: .black.opacity(0.22), radius: 5, y: 1)
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
    @State private var hovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(fg)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .inkHoverHint(help)
    }
}

private struct CopyTranscriptGlyph: View {
    let copied: Bool
    @State private var hovering = false

    var body: some View {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(copied ? .green : .secondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(copied ? Color.green.opacity(0.15) : Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .inkHoverHint("Copy")
            .animation(.easeOut(duration: 0.15), value: copied)
    }
}
