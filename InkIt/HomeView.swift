import SwiftUI
import AppKit

// MARK: - Stat formatting

/// Numeric formatting for the Home stat band.
enum StatFormat {
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
        if hours < 24 { return (String(format: "%.1f", hours), "hr") }
        let days = hours / 24
        return (days < 10 ? String(format: "%.1f", days) : "\(Int(days.rounded()))", "days")
    }
}

// MARK: - Home

/// The Home section: the transcript history log + stats rail that used to be
/// the whole main window, now one view inside the sidebar shell. Modals (the
/// Settings sheet, the delete-all confirm) live on the shell so their scrims
/// cover the sidebar too — Home asks for them through the two closures.
struct HomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: TranscriptHistoryStore
    /// Durable day aggregates — the stat band's streak reads the same source
    /// Insights does.
    @EnvironmentObject var aggregates: UsageAggregateStore

    /// Opens the Settings modal on a given pane (the Polish nudge and the
    /// Polish-issue card deep-link to `.polish`).
    let onOpenSettings: (SettingsView.Pane) -> Void
    /// Asks the shell to run the delete-all confirm flow.
    let onRequestDeleteAll: () -> Void

    @State private var copiedID: UUID?
    // History controls. Search collapses to a single icon at rest and expands
    // inline; the field stays open while there's a query and collapses only when
    // emptied (macOS toolbar-search convention). Sort persists across launches —
    // it's a stated preference. Delete-all routes through the shell's confirm.
    @State private var searchExpanded = false
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("history.newestFirst") private var newestFirst = true
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

    // The round-12 composed Home: one scrolling column on the content sheet.
    // The page opens with the hero (the product's one promise), then the flat
    // stat band, then the Polish row when relevant, then full-width history.
    // One statement per band — no side rail, no competing columns.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                RotatingDictateHeader(tokens: HotkeyConversion.displayTokens(for: settings.hotkey))
                    .padding(.bottom, 32)
                statBand
                    .padding(.bottom, 20)
                if showPolishNudge {
                    polishNudgeRow
                        .padding(.bottom, 20)
                }
                if settings.polishIssue != nil {
                    polishIssueCard
                        .padding(.bottom, 20)
                }
                if history.entries.isEmpty {
                    // A completed onboarding trial seeds the very first transcript
                    // (see AppCoordinator's trial logging), so most users never see
                    // this. It's reached only when they skipped Try-it — so rather
                    // than a dead-end "nothing here," offer a live try box that
                    // turns the first take into a real history row.
                    HomeTryItPanel()
                        .padding(.top, 20)
                } else {
                    historyHeader
                        .padding(.top, 14)
                    historyGroups
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        // The shell owns Delete All; when the wipe lands (or anything else
        // empties the list) an open search field has nothing left to filter,
        // so it collapses — same reset `confirmDeleteAll` used to do inline.
        .onChange(of: history.entries.isEmpty) { _, isEmpty in
            if isEmpty { collapseSearch() }
        }
    }

    // History header: title + its two quiet actions (search, manage). The hero
    // above already carries the hotkey cue, and live state lives in the sidebar
    // pill + notch HUD — nothing else competes with the list.
    private var historyHeader: some View {
        HStack(spacing: 8) {
            Text("History")
                .font(.inkTitle)
                .foregroundStyle(.primary)
                .padding(.trailing, 2)
            searchControl
            manageMenu
            Spacer(minLength: 0)
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
                .strokeBorder(Color.line)
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
                    onRequestDeleteAll()
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

    // The history log lives directly on the sheet (round 12) — no inner card.
    // Day headers, then rows divided by faint full-width hairlines. These
    // Sections sit inside the body's pinned-headers LazyVStack, so the current
    // day sticks to the sheet top as the page scrolls.
    @ViewBuilder private var historyGroups: some View {
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
                            .fill(Color.line)
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

    // Pinned day header. Carries the sheet fill so scrolling rows pass cleanly
    // beneath it; full-width so nothing peeks through at the edges.
    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(.inkEyebrow)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(Color.canvas)
    }

    // The stat band (round 12): one flat panel, label over value, no icons —
    // the serif numerals are the graphic. Latency is not shown here (it is
    // never prominent, per DESIGN_SYSTEM); the fourth cell is the user's own
    // speaking speed.
    private var statBand: some View {
        HStack(alignment: .top, spacing: 0) {
            statCell(label: "Total words",
                     value: history.lifetimeWords.formatted(), unit: nil)
            bandDivider
            statCell(label: "Time saved",
                     value: timeSavedParts.value, unit: timeSavedParts.unit)
            bandDivider
            statCell(label: "Day streak",
                     value: "\(currentStreak)", unit: currentStreak == 1 ? "day" : "days")
            bandDivider
            statCell(label: "Average speed", value: averageWpm, unit: "wpm")
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 26)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
    }

    private func statCell(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.inkCallout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.inkStat)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let unit {
                    Text(unit)
                        .font(.inkBody)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bandDivider: some View {
        Rectangle()
            .fill(Color.line)
            .frame(width: 1)
            .padding(.horizontal, 24)
    }

    private var showPolishNudge: Bool {
        !settings.correctionEnabled && !settings.polishNudgeDismissed
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
                    .font(.inkCaption.weight(.medium))
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
                .stroke(Color.line, lineWidth: 1)
        )
    }

    // MARK: Polish-issue copy + actions

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
            onOpenSettings(.polish)
        case .outOfCredits:
            NSWorkspace.shared.open(settings.rewriteProvider.billingURL)
        }
    }

    // The Polish nudge (round 12): one flat row — glyph, pitch, CTA. The
    // before→after demo lives behind the CTA (the Settings Polish pane), not
    // on Home; this row's action is the accent's one Home spend.
    private var polishNudgeRow: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Color.accentSoft)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))  // ds-allow: icon
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Polish your dictation")
                    .font(.inkBodyEmphasized)
                    .foregroundStyle(.primary)
                Text("Fillers, fumbles, and punctuation cleaned up automatically — talk like yourself.")
                    .font(.inkCallout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button { onOpenSettings(.polish) } label: {
                Text("Set up Polish →")
                    .font(.inkCalloutEmphasized)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())

            Button { settings.polishNudgeDismissed = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))  // ds-allow: icon
                    .foregroundStyle(.tertiary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
    }

    // MARK: Stat sources

    private var timeSavedParts: (value: String, unit: String) {
        StatFormat.timeSaved(words: history.lifetimeWords)
    }

    /// Consecutive active days, from the same durable aggregates Insights reads
    /// — the two surfaces can never disagree about the streak.
    private var currentStreak: Int {
        InsightsMath.currentStreak(days: aggregates.days, today: Date())
    }

    /// Lifetime mean speaking speed. Shares `InsightsMath.averageWordsPerMinute`
    /// with the Insights hero so the two surfaces can't show different numbers;
    /// "—" until a minute of timed dictation has accrued.
    private var averageWpm: String {
        InsightsMath.averageWordsPerMinute(entries: history.entries).map(String.init) ?? "—"
    }

    private func transcriptRow(_ entry: TranscriptHistoryStore.Entry) -> some View {
        TranscriptHistoryRow(
            text: entry.text,
            timestamp: Self.timeFmt.string(from: entry.timestamp),
            latency: entry.latency,
            original: entry.original,
            polish: entry.polish,
            failure: entry.failure,
            appName: entry.appName,
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
