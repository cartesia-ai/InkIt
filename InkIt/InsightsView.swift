import SwiftUI

/// The Insights section — the user's dictation quantified, all of it computed
/// on-device by `InsightsMath` over the durable day aggregates and the
/// transcript history. The page is composed to a single feeling: *be proud of
/// this, and keep going.* A hero trio leads (what you've said, what Polish
/// cleaned up for you, how fast you move), the Activity chain is the habit
/// hook, and every card keeps a quiet empty state so the grid never collapses
/// while data accrues.
struct InsightsView: View {
    @EnvironmentObject var history: TranscriptHistoryStore
    @EnvironmentObject var aggregates: UsageAggregateStore
    @StateObject private var model = InsightsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HeroRow(snapshot: model.snapshot)
                    ActivityCard(model: model)
                    HStack(alignment: .top, spacing: 14) {
                        WordsCard(snapshot: model.snapshot)
                        WhereWhenCard(snapshot: model.snapshot)
                    }
                    RecordsCard(snapshot: model.snapshot)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.refresh() }
        // New dictation / Delete All both change the entry count; day
        // aggregates only ever change alongside it. Nothing here recomputes
        // while the user is elsewhere (Home search never touches this).
        .onChange(of: history.entries.count) { _, _ in model.refresh() }
    }

    private var header: some View {
        Text("Insights")
            .font(.inkTitle)
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
    }
}

// MARK: - Card chrome

/// The shared Insights card: panel fill, hairline, a plain title, content.
/// Titles carry the whole story — no explainer captions (they read as noise;
/// the data is the explanation).
private struct InsightsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.inkHeadline)
                .foregroundStyle(Color.inkText)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
    }
}

/// A second in-card heading (When you speak, under Where you dictate).
private struct CardSubhead: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.inkHeadline)
            .foregroundStyle(Color.inkText)
            .padding(.top, 18)
    }
}

// MARK: - Hero trio

/// The three headline numbers, glanceable at the top of the page. Each maps to
/// one feeling: pride (words), appreciation of the app (fixes Polish made),
/// pride again (speed). Big serif numeral, uppercase eyebrow, one quiet
/// detail line — the Flow "what good looks like" reading, in Ink's voice.
private struct HeroRow: View {
    let snapshot: InsightsModel.Snapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HeroStat(value: snapshot.totalWords > 0 ? snapshot.totalWords.formatted() : "—",
                     label: "Words dictated",
                     detail: wordsDetail)
            HeroStat(value: snapshot.totalFixes > 0 ? snapshot.totalFixes.formatted() : "—",
                     label: "Words cleaned up",
                     detail: "fillers Polish removed for you")
            HeroStat(value: snapshot.averageWpm.map { "\($0)" } ?? "—",
                     label: "Words per minute",
                     detail: "your average speaking pace")
        }
    }

    private var wordsDetail: String {
        snapshot.activeDays > 0 ? "across \(snapshot.activeDays) active days" : "since you started"
    }
}

private struct HeroStat: View {
    let value: String
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.inkStat)
                .monospacedDigit()
                .foregroundStyle(value == "—" ? Color.inkFaint : Color.inkText)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.inkEyebrow)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.inkSub)
                Text(detail)
                    .font(.inkCaption)
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
    }
}

// MARK: - Activity (wide)

private struct ActivityCard: View {
    @ObservedObject var model: InsightsModel

    private static let cellSize: CGFloat = 12
    private static let cellGap: CGFloat = 4
    private static let axisHeight: CGFloat = 15
    private static let axisGap: CGFloat = 6
    private static let gridHeight: CGFloat = 7 * cellSize + 6 * cellGap
    private static let hGap: CGFloat = 24
    private static let streakColumnWidth: CGFloat = 180

    private struct MonthMark: Identifiable {
        let col: Int
        let text: String
        var id: Int { col }
    }

    var body: some View {
        InsightsCard(title: "Activity") {
            GeometryReader { geo in
                HStack(alignment: .top, spacing: Self.hGap) {
                    VStack(alignment: .leading, spacing: Self.axisGap) {
                        monthAxis
                        heatmap
                    }
                    Spacer(minLength: 0)
                    if model.snapshot.hasAnyActivity {
                        streakStats
                    } else {
                        emptyInvite
                    }
                }
                .onAppear { fitWeeks(to: geo.size.width) }
                .onChange(of: geo.size.width) { _, w in fitWeeks(to: w) }
            }
            .frame(height: Self.gridHeight + Self.axisHeight + Self.axisGap)
            .padding(.top, 14)

            legend
        }
    }

    /// The heatmap is adaptive: as many week-columns as the row can hold, up
    /// to 30 — never an overflowing fixed grid (the window minimum is narrower
    /// than 30 weeks of the larger cells).
    private func fitWeeks(to width: CGFloat) {
        let available = width - Self.streakColumnWidth - Self.hGap
        let perWeek = Self.cellSize + Self.cellGap
        let weeks = Int((available + Self.cellGap) / perWeek)
        model.setWeekCount(min(30, max(8, weeks)))
    }

    // MARK: Heatmap + axis

    private var heatmap: some View {
        HStack(alignment: .top, spacing: Self.cellGap) {
            ForEach(Array(model.snapshot.heatmapWeeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: Self.cellGap) {
                    ForEach(week, id: \.date) { cell in
                        heatCell(cell)
                    }
                }
            }
        }
    }

    private func heatCell(_ cell: InsightsMath.HeatCell) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.chip)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(Self.levelOpacity[cell.level]))
            )
            .overlay {
                if cell.isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.inkText, lineWidth: 1.5)
                }
            }
            .frame(width: Self.cellSize, height: Self.cellSize)
            .help(cellHelp(cell))
    }

    /// "Deeper ink, more words" — the accent-over-chip ramp, mirrored exactly
    /// by the legend below so the color scale is spelled out, not guessed.
    private static let levelOpacity: [Double] = [0, 0.22, 0.45, 0.70, 1.0]

    /// Month abbreviations along the top of the grid — a column gets a label
    /// when its first day lands in a new month, so the timeline reads at a
    /// glance without weekday-aligning the grid.
    private var monthMarkers: [MonthMark] {
        let calendar = Calendar.current
        var marks: [MonthMark] = []
        var lastMonth = -1
        for (i, week) in model.snapshot.heatmapWeeks.enumerated() {
            guard let first = week.first?.date else { continue }
            let month = calendar.component(.month, from: first)
            if month != lastMonth {
                marks.append(MonthMark(col: i, text: first.formatted(.dateTime.month(.abbreviated))))
                lastMonth = month
            }
        }
        return marks
    }

    private var monthAxis: some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarkers) { mark in
                Text(mark.text)
                    .font(.inkCaption)
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize()
                    .offset(x: CGFloat(mark.col) * (Self.cellSize + Self.cellGap))
            }
        }
        .frame(height: Self.axisHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two-line tooltip: the day, then what happened on it — the "hover to
    /// understand a given day" ask, answered with words *and* dictation count.
    private func cellHelp(_ cell: InsightsMath.HeatCell) -> String {
        let day = cell.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let heading = day + (cell.isToday ? " · Today" : "")
        guard cell.words > 0 else { return "\(heading)\nNo dictation" }
        let unit = cell.dictations == 1 ? "dictation" : "dictations"
        return "\(heading)\n\(cell.words.formatted()) words · \(cell.dictations) \(unit)"
    }

    // MARK: Legend

    /// Spells out the two things the squares encode: the intensity ramp, and
    /// the ring that flags today.
    private var legend: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { level in
                    swatch.overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.accentColor.opacity(Self.levelOpacity[level]))
                    )
                }
            }
            Text("More words")
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)

            Spacer(minLength: 12)

            swatch.overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.inkText, lineWidth: 1.5)
            )
            Text("Today")
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
        }
        .padding(.top, 16)
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.chip)
            .frame(width: 12, height: 12)
    }

    // MARK: Streak column

    private var streakStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            streakRow(value: model.snapshot.currentStreak, label: "day current streak")
            streakRow(value: model.snapshot.longestStreak, label: "day longest streak")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(model.snapshot.activeDays)")
                    .font(.inkStatSmall)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkText)
                Text("active days of \(model.snapshot.activeDaysSpan)")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkSub)
            }
        }
        .frame(width: Self.streakColumnWidth, alignment: .leading)
    }

    private func streakRow(value: Int, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(value)")
                .font(.inkStatSmall)
                .monospacedDigit()
                .foregroundStyle(Color.inkText)
            Text(label)
                .font(.inkCallout)
                .foregroundStyle(Color.inkSub)
        }
    }

    private var emptyInvite: some View {
        Text("Your first square inks today — dictate anywhere to start.")
            .font(.inkCallout)
            .foregroundStyle(Color.inkSub)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Self.streakColumnWidth, alignment: .leading)
    }
}

// MARK: - Shared bar row

/// The horizontal bar the two list cards share: label · track · value.
/// Fractions are relative to the list's own maximum, so the top row always
/// reads full.
private struct HBar: View {
    let label: String
    let fraction: Double
    let value: String
    var ghost = false
    /// Optional leading mark (the app icon on the "Where you dictate" rows).
    var icon: Image?

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.inkFaint)  // tints symbol fallbacks only
            }
            Text(label)
                .font(.inkCalloutEmphasized)
                .foregroundStyle(ghost ? Color.inkFaint : Color.inkText)
                .lineLimit(1)
                .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.chip)
                    if !ghost {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(8, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 8)
            Text(value)
                .font(.inkCallout)
                .foregroundStyle(Color.inkSub)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.top, 10)
    }
}

// MARK: - Your favorite words

private struct WordsCard: View {
    let snapshot: InsightsModel.Snapshot

    /// Below this many words this month the counts are noise, not habits.
    private static let minTokensForWords = 200

    var body: some View {
        InsightsCard(title: "Your favorite words") {
            if snapshot.monthTokens >= Self.minTokensForWords && !snapshot.topWords.isEmpty {
                let top = Double(snapshot.topWords.first?.count ?? 1)
                ForEach(snapshot.topWords, id: \.word) { word in
                    HBar(label: word.word,
                         fraction: Double(word.count) / max(top, 1),
                         value: word.count.formatted())
                }
            } else {
                ForEach(0..<5, id: \.self) { _ in
                    HBar(label: " ", fraction: 0, value: "", ghost: true)
                }
                Text("Your five most-said words show up after a few dictations.")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 12)
            }
        }
    }
}

// MARK: - Where you dictate + When you speak

private struct WhereWhenCard: View {
    let snapshot: InsightsModel.Snapshot

    /// Below this many dictations in the window, the histogram is confetti.
    private static let minDictationsForHours = 5

    var body: some View {
        InsightsCard(title: "Where you dictate") {
            if !snapshot.appShare.isEmpty {
                let top = Double(snapshot.appShare.map(\.count).max() ?? 1)
                ForEach(snapshot.appShare, id: \.name) { share in
                    HBar(label: share.name,
                         fraction: Double(share.count) / max(top, 1),
                         value: "\(share.percent)%",
                         icon: Self.appIcon(bundleID: share.bundleID))
                }
            } else {
                ForEach(0..<4, id: \.self) { _ in
                    HBar(label: " ", fraction: 0, value: "", ghost: true)
                }
                Text("The apps you speak into appear here as you dictate.")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 12)
            }

            CardSubhead(title: "When you speak")

            hourChart
                .padding(.top, 14)
            hourLabels
                .padding(.top, 6)
        }
    }

    private var hasHourData: Bool {
        snapshot.windowDictations >= Self.minDictationsForHours
    }

    /// The real app icon via Launch Services, cached per bundle ID. The
    /// "Other" bucket (nil) and uninstalled apps get a quiet dashed glyph.
    private static var iconCache: [String: Image] = [:]
    private static func appIcon(bundleID: String?) -> Image {
        let fallback = Image(systemName: "app.dashed")
        guard let bundleID else { return fallback }
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            iconCache[bundleID] = fallback
            return fallback
        }
        let image = Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        iconCache[bundleID] = image
        return image
    }

    // The peak speaks for itself — the one full-accent bar — so there's no
    // caption spelling it out.
    private var peakBin: Int? {
        guard let maxCount = snapshot.hourBins.max(), maxCount > 0 else { return nil }
        return snapshot.hourBins.firstIndex(of: maxCount)
    }

    private var hourChart: some View {
        let bins = snapshot.hourBins
        let maxCount = max(bins.max() ?? 0, 1)
        let peak = peakBin
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<12, id: \.self) { i in
                let fraction = hasHourData ? Double(bins[i]) / Double(maxCount) : Self.ghostHeights[i]
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                    .fill(barColor(bin: i, isPeak: i == peak))
                    .frame(height: max(3, 56 * fraction))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56, alignment: .bottom)
    }

    /// Quiet placeholder silhouette while there's too little data to mean much.
    private static let ghostHeights: [Double] = [0.12, 0.2, 0.3, 0.42, 0.55, 0.65, 0.72, 0.65, 0.55, 0.42, 0.3, 0.2]

    private func barColor(bin: Int, isPeak: Bool) -> Color {
        guard hasHourData else { return .chip }
        return isPeak ? .accentColor : .accentColor.opacity(0.35)
    }

    private var hourLabels: some View {
        HStack {
            Text("12 AM")
            Spacer()
            Text("noon")
            Spacer()
            Text("11 PM")
        }
        .font(.inkCaption)
        .foregroundStyle(Color.inkFaint)
    }
}

// MARK: - Records (wide)

private struct RecordsCard: View {
    let snapshot: InsightsModel.Snapshot

    var body: some View {
        InsightsCard(title: "Records") {
            // Each label is a plain sentence fragment the number completes —
            // "2,184 · most words in one day" — no parentheses to decode.
            HStack(spacing: 12) {
                tile(value: snapshot.bestDayWords.map { $0.formatted() },
                     label: "most words in one day")
                tile(value: snapshot.longestDictationMs.map { InsightsMath.formatDuration(ms: $0) },
                     label: "longest single dictation")
                tile(value: snapshot.fastestWordsPerMinute.map { "\($0) wpm" },
                     label: "fastest day on record")
            }
            .padding(.top, 14)
        }
    }

    private func tile(value: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value ?? "—")
                .font(.inkStatSmall)
                .monospacedDigit()
                .foregroundStyle(value == nil ? Color.inkFaint : Color.inkText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.inkCallout)
                .foregroundStyle(Color.inkSub)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
    }
}
