import SwiftUI
import AppKit

enum StatFormat {
    static func timeSaved(words: Int) -> (value: String, unit: String) {
        let minutes = Double(words) * (1.0 / 40.0 - 1.0 / 150.0)
        if minutes < 1 { return ("\(Int((minutes * 60).rounded()))", "sec") }
        if minutes < 60 { return ("\(Int(minutes.rounded()))", "min") }
        let hours = minutes / 60
        if hours < 24 { return (String(format: "%.1f", hours), "hr") }
        let days = hours / 24
        return (days < 10 ? String(format: "%.1f", days) : "\(Int(days.rounded()))", "days")
    }
}

struct HomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: TranscriptHistoryStore
    @EnvironmentObject var aggregates: UsageAggregateStore

    let onOpenSettings: (SettingsView.Pane) -> Void
    let onRequestDeleteAll: () -> Void

    @State private var copiedID: UUID?
    @State private var searchExpanded = false
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("history.newestFirst") private var newestFirst = true
    @State private var showManageMenu = false

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var filteredEntries: [TranscriptHistoryStore.Entry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.lowercased().contains(q) }
    }

    private var groupedEntries: [DayGroup<TranscriptHistoryStore.Entry>] {
        DateGrouping.byDay(filteredEntries, newestFirst: newestFirst) { $0.timestamp }
    }

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
                    HomeTryItPanel()
                        .padding(.top, 20)
                } else {
                    historyHeader
                        .padding(.top, 14)
                    historyGroups
                }
            }
            .pageFrame()
        }
        .scrollIndicators(.hidden)
        .onChange(of: history.entries.isEmpty) { _, isEmpty in
            if isEmpty { collapseSearch() }
        }
    }

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
        .background(
            Button(action: expandSearch) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        )
    }

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
        .dismissOnClickOutside(isActive: searchExpanded) { collapseSearch() }
    }

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
        DispatchQueue.main.async { searchFocused = true }
    }

    private func collapseSearch() {
        searchQuery = ""
        searchFocused = false
        withAnimation(Motion.expand) { searchExpanded = false }
    }

    @ViewBuilder private var historyGroups: some View {
        if groupedEntries.isEmpty {
            Text("No transcripts match “\(searchQuery)”")
                .font(.inkCallout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 56)
        }
        ForEach(groupedEntries) { group in
            Section {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.line)
                            .frame(height: 1)
                            .padding(.horizontal, 8)
                    }
                    transcriptRow(entry)
                }
            } header: {
                DayGroupHeader(title: group.title)
            }
        }
    }

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

    private var timeSavedParts: (value: String, unit: String) {
        StatFormat.timeSaved(words: history.lifetimeWords)
    }

    private var currentStreak: Int {
        InsightsMath.currentStreak(days: aggregates.days, today: Date())
    }

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

}
