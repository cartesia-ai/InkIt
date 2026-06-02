import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Apply the saved appearance (default Light) as early as possible so the
    // first window doesn't flash the system appearance before settling.
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.applyAppearance()
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
        .commands {
            // Strip the system menu bar down to the bare minimum. macOS won't
            // let us remove the leading "InkIt" menu (About/Quit live there)
            // while we keep the Dock icon, but everything else can go.
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
                    .frame(minWidth: 620, idealWidth: 940, maxWidth: .infinity,
                           minHeight: 560, idealHeight: 820, maxHeight: .infinity)
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
            emptyState
        } else {
            transcriptList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No transcripts yet")
                .font(.headline)
            Text("Hold \(settings.hotkeyDisplayString) and speak to dictate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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

private struct TranscriptHistoryRow: View {
    let text: String
    let timestamp: String
    let latency: TranscriptHistoryStore.Latency?
    /// Raw pre-rewrite transcript; non-nil whenever correction ran successfully
    /// (identical to `text` for a no-op rewrite). Feeds the before/after diff.
    let original: String?
    /// How AI correction turned out; drives the row indicator.
    let polish: TranscriptHistoryStore.PolishOutcome?
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false
    @State private var showingDiff = false

    /// Resolves the indicator to show. Legacy entries (no stored `polish`) fall
    /// back to "polished if there's a diff to show, otherwise nothing."
    private var outcome: TranscriptHistoryStore.PolishOutcome {
        if let polish { return polish }
        return original != nil ? .polished : .off
    }

    // The list stays clean at rest — just the cleaned-up transcript. The
    // detail line (timestamp, latency, sparkle) fades in on hover. Its height
    // is always reserved so the list never reflows.
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
                .opacity(hovering ? 1 : 0)
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

    private var detailLine: some View {
        HStack(spacing: 8) {
            Text(timestamp)
                .font(.caption)
                .foregroundStyle(.tertiary)

            switch outcome {
            case .polished: sparkle
            case .failed: failureMark
            case .off: EmptyView()
            }

            Spacer(minLength: 8)

            if let latency {
                Text(Self.latencyString(latency))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .help("Latency from hotkey release: transcribe + polish + paste")
            }
        }
    }

    private var sparkle: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
            .onHover { showingDiff = $0 }
            .onTapGesture {}  // swallow taps so the row's copy doesn't fire
            .help("Polished — hover to see what changed")
            .popover(isPresented: $showingDiff, arrowEdge: .bottom) {
                DiffPopover(before: original ?? text, after: text)
            }
    }

    /// Polish ran but the rewrite call failed (e.g. rate limit); the raw
    /// transcript was pasted instead. Warning-amber, distinct from the sparkle.
    private var failureMark: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.orange)
            .help("Polish failed (rate limit or network) — raw transcript pasted")
    }

    /// e.g. `1.1s · transcribe 640ms · polish 410ms · paste 50ms`
    private static func latencyString(_ l: TranscriptHistoryStore.Latency) -> String {
        "\(fmt(l.totalMs)) · transcribe \(fmt(l.transcribeMs)) · polish \(fmt(l.polishMs)) · paste \(fmt(l.pasteMs))"
    }

    private static func fmt(_ ms: Int) -> String {
        ms < 1000 ? "\(ms)ms" : String(format: "%.1fs", Double(ms) / 1000)
    }

    private var rowFill: Color {
        if hovering {
            return Color.accentColor.opacity(0.08)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    private var rowStroke: Color {
        Color.accentColor.opacity(copied ? 0.32 : 0.28)
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
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(width: 300)
    }

    private static let addColor = Color.green

    private enum Kind { case same, added, removed }
    private struct Token { let kind: Kind; let word: String }

    private static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func diffTokens(from before: String, to after: String) -> [Token] {
        let beforeWords = tokenize(before)
        let afterWords = tokenize(after)
        let changes = afterWords.difference(from: beforeWords)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var tokens: [Token] = []
        var bi = 0, ai = 0
        while bi < beforeWords.count || ai < afterWords.count {
            if bi < beforeWords.count, removed.contains(bi) {
                tokens.append(Token(kind: .removed, word: beforeWords[bi]))
                bi += 1
            } else if ai < afterWords.count, inserted.contains(ai) {
                tokens.append(Token(kind: .added, word: afterWords[ai]))
                ai += 1
            } else {
                if ai < afterWords.count {
                    tokens.append(Token(kind: .same, word: afterWords[ai]))
                }
                bi += 1
                ai += 1
            }
        }
        return tokens
    }

    private static func diff(from before: String, to after: String) -> AttributedString {
        let tokens = diffTokens(from: before, to: after)
        var result = AttributedString()
        for (i, token) in tokens.enumerated() {
            var piece = AttributedString(token.word)
            switch token.kind {
            case .same:
                piece.foregroundColor = .primary
            case .added:
                piece.foregroundColor = addColor
                piece.backgroundColor = addColor.opacity(0.16)
            case .removed:
                piece.foregroundColor = .secondary
                piece.strikethroughStyle = .single
            }
            result += piece
            if i < tokens.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
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
