import SwiftUI

/// The Insights section — the user's dictation quantified, all of it computed
/// on-device by `InsightsMath` over the durable day aggregates and the
/// transcript history. The page is composed to a single feeling: *be proud of
/// this, and keep going.* A hero trio of personal records leads — deliberately
/// distinct from Home's lifetime totals, and independent of Polish so it never
/// blanks — then the Activity chain is the habit hook, and every card keeps a
/// quiet empty state so the grid never collapses while data accrues.
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
private struct InsightsCard<Content: View, Accessory: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(title: String,
         @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.inkHeadline)
                    .foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                accessory
            }
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

/// Cards without a header accessory (the common case) omit the slot entirely.
extension InsightsCard where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
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

/// The three headline numbers, glanceable at the top of the page — personal
/// records, not lifetime totals (those live on Home). Each is a best the user
/// can beat: most in a day, longest take, fastest day. All are Polish-free, so
/// the trio holds up whether or not Polish is on. Big serif numeral, one
/// sentence-case line beneath — no eyebrow, no second detail row.
private struct HeroRow: View {
    let snapshot: InsightsModel.Snapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HeroStat(value: snapshot.bestDayWords.map { $0.formatted() } ?? "—",
                     label: "most words in a day")
            HeroStat(value: snapshot.longestDictationMs.map { InsightsMath.formatDuration(ms: $0) } ?? "—",
                     label: "longest dictation")
            HeroStat(value: snapshot.fastestWpm.map { "\($0)" } ?? "—",
                     unit: snapshot.fastestWpm != nil ? "wpm" : nil,
                     label: "fastest day")
        }
    }
}

private struct HeroStat: View {
    let value: String
    var unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.inkStat)
                    .monospacedDigit()
                    .foregroundStyle(value == "—" ? Color.inkFaint : Color.inkText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .font(.inkBody)
                        .foregroundStyle(Color.inkSub)
                }
            }
            Text(label)
                .font(.inkCallout)
                .foregroundStyle(Color.inkSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

    /// The day the cursor is over, plus its grid position, so the tooltip can
    /// anchor to that exact square. `nil` when the cursor is off the grid.
    @State private var hover: HoverInfo?

    private struct HoverInfo: Equatable {
        let cell: InsightsMath.HeatCell
        let col: Int
        let row: Int
    }

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

    // The paging control rides in the shared card's header accessory slot,
    // opposite the "Activity" title.
    var body: some View {
        InsightsCard(title: "Activity") {
            if model.snapshot.canPageBack || model.snapshot.canPageForward {
                paging
            }
        } content: {
            GeometryReader { geo in
                HStack(alignment: .top, spacing: Self.hGap) {
                    VStack(alignment: .leading, spacing: Self.axisGap) {
                        monthAxis
                        heatmap
                    }
                    Spacer(minLength: 0)
                    Group {
                        if model.snapshot.hasAnyActivity {
                            streakStats
                        } else {
                            emptyInvite
                        }
                    }
                    // Center the stat group against the grid so it reads as a
                    // balanced pair, not a cluster pinned to the month axis.
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .onAppear { fitWeeks(to: geo.size.width) }
                .onChange(of: geo.size.width) { _, w in fitWeeks(to: w) }
            }
            .frame(height: Self.gridHeight + Self.axisHeight + Self.axisGap)
            .padding(.top, 14)

            legend
        }
    }

    // MARK: Paging

    /// Month range + ‹ › — shown only when history runs past one window. Arrows
    /// grey out at the ends (offset 0 = today; oldest page = first activity).
    private var paging: some View {
        HStack(spacing: 10) {
            Text(model.snapshot.windowRange)
                .font(.inkCaption)
                .monospacedDigit()
                .foregroundStyle(Color.inkFaint)
            HStack(spacing: 4) {
                pageButton("chevron.left", enabled: model.snapshot.canPageBack) { model.pageBack() }
                pageButton("chevron.right", enabled: model.snapshot.canPageForward) { model.pageForward() }
            }
        }
    }

    private func pageButton(_ systemName: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(Color.inkSub)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
                        .stroke(Color.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .modifier(PointingHandCursor())
    }

    /// The heatmap fills the row: as many week-columns as fit beside the
    /// streak column, so the grid always reaches the stats instead of stopping
    /// short and stranding a gap. Capped at 53 (a year) for very wide windows;
    /// floored at 8 so it never collapses. Older history is reached by paging,
    /// not by shrinking the window.
    private func fitWeeks(to width: CGFloat) {
        let available = width - Self.streakColumnWidth - Self.hGap
        let perWeek = Self.cellSize + Self.cellGap
        let weeks = Int((available + Self.cellGap) / perWeek)
        model.setWeekCount(min(53, max(8, weeks)))
    }

    // MARK: Heatmap + axis

    private var heatmap: some View {
        HStack(alignment: .top, spacing: Self.cellGap) {
            ForEach(Array(model.snapshot.heatmapWeeks.enumerated()), id: \.offset) { col, week in
                VStack(spacing: Self.cellGap) {
                    ForEach(Array(week.enumerated()), id: \.element.date) { row, cell in
                        heatCell(cell)
                            // Instant, unlike the system `.help` tooltip's ~1.5s
                            // delay — the number should appear the moment you're
                            // on a square. Clearing is guarded so the fast move
                            // between two squares doesn't blank the new one.
                            .onHover { inside in
                                if inside {
                                    hover = HoverInfo(cell: cell, col: col, row: row)
                                } else if hover?.cell.date == cell.date {
                                    hover = nil
                                }
                            }
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) { tooltipOverlay }
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
            .contentShape(Rectangle())
            .accessibilityLabel(cellHelp(cell))
    }

    // MARK: Hover tooltip

    /// The floating bubble anchored above the hovered square. Bottom-anchored to
    /// the grid so it grows upward off a known point without measuring its own
    /// height; left edge tracks the square's column. `allowsHitTesting(false)`
    /// so it never steals the hover from the cell underneath.
    @ViewBuilder private var tooltipOverlay: some View {
        if let hover {
            let step = Self.cellSize + Self.cellGap
            tooltip(for: hover.cell)
                .allowsHitTesting(false)
                .offset(x: CGFloat(hover.col) * step,
                        y: -(Self.gridHeight - CGFloat(hover.row) * step) - 6)
        }
    }

    private func tooltip(for cell: InsightsMath.HeatCell) -> some View {
        let day = cell.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return VStack(alignment: .leading, spacing: 2) {
            Text(day + (cell.isToday ? " · Today" : ""))
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
            if cell.words > 0 {
                Text("\(cell.words.formatted()) words")
                    .font(.inkCalloutEmphasized)
                    .foregroundStyle(Color.inkText)
                Text("\(cell.dictations) \(cell.dictations == 1 ? "dictation" : "dictations")")
                    .font(.inkCaption)
                    .foregroundStyle(Color.inkFaint)
            } else {
                Text("No dictation")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkFaint)
            }
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
        .shadow(color: Elevation.card, radius: 8, y: 2)
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

    /// Spells out the intensity ramp the squares encode (the ring on today's
    /// square is self-evident and needs no legend entry).
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
    /// True when `icon` is an SF Symbol fallback rather than a real app icon.
    /// Real icons ship with transparent padding; symbols fill their box, so we
    /// inset them to match the surrounding icons' visual weight.
    var iconIsSymbol = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconIsSymbol ? 15 : 20, height: iconIsSymbol ? 15 : 20)
                    .foregroundStyle(Color.inkFaint)  // tints symbol fallbacks only
                    .frame(width: 20, height: 20)
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

    /// The 2-hour bin the pointer is over, if any — drives the hover tooltip.
    @State private var hourHover: Int?

    /// Below this many dictations in the window, the histogram is confetti.
    private static let minDictationsForHours = 5

    var body: some View {
        InsightsCard(title: "Where you dictate") {
            if !snapshot.appShare.isEmpty {
                let top = Double(snapshot.appShare.map(\.count).max() ?? 1)
                ForEach(snapshot.appShare, id: \.name) { share in
                    let mark = Self.appIcon(bundleID: share.bundleID)
                    HBar(label: share.name,
                         fraction: Double(share.count) / max(top, 1),
                         value: "\(share.percent)%",
                         icon: mark.image,
                         iconIsSymbol: mark.isSymbol)
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
    /// "Other" bucket (nil) gets a generic grid glyph standing in for the
    /// long tail of apps; uninstalled apps get a quiet dashed glyph.
    /// Returns the mark and whether it's an SF Symbol fallback (so the row can
    /// inset it to match real icons' padding).
    private static var iconCache: [String: (image: Image, isSymbol: Bool)] = [:]
    private static func appIcon(bundleID: String?) -> (image: Image, isSymbol: Bool) {
        guard let bundleID else { return (Image(systemName: "square.grid.2x2"), true) }
        if let cached = iconCache[bundleID] { return cached }
        let mark: (image: Image, isSymbol: Bool)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            mark = (Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)), false)
        } else {
            mark = (Image(systemName: "app.dashed"), true)
        }
        iconCache[bundleID] = mark
        return mark
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
                // A full-height clear column is the hover target, so the pointer
                // catches the whole time slot — not just the (often tiny) bar.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .overlay(alignment: .bottom) {
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                            .fill(barColor(bin: i, isPeak: i == peak))
                            .frame(height: max(3, 56 * fraction))
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard hasHourData else { return }
                        if inside { hourHover = i }
                        else if hourHover == i { hourHover = nil }
                    }
                    // Bottom-anchored like the heatmap tooltip: grows upward off
                    // the column's bottom without measuring its own height. The
                    // outermost columns anchor to their inner edge so the full
                    // tooltip width can't spill past the card's clip.
                    .overlay(alignment: Self.hourTooltipAlignment(i)) {
                        if hourHover == i {
                            hourTooltip(i)
                                .allowsHitTesting(false)
                                .offset(y: -62)
                        }
                    }
            }
        }
        .frame(height: 56, alignment: .bottom)
    }

    // Center the tooltip on its bar, except at the two ends where a centered,
    // full-width bubble would overflow the card and get clipped — those anchor
    // to the chart's edge and grow inward instead.
    private static func hourTooltipAlignment(_ i: Int) -> Alignment {
        switch i {
        case 0, 1: return .bottomLeading
        case 10, 11: return .bottomTrailing
        default: return .bottom
        }
    }

    private func hourTooltip(_ i: Int) -> some View {
        let count = snapshot.hourBins[i]
        return VStack(alignment: .leading, spacing: 2) {
            Text(Self.binTimeRange(i))
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
            Text("\(count.formatted()) \(count == 1 ? "dictation" : "dictations")")
                .font(.inkCalloutEmphasized)
                .foregroundStyle(count > 0 ? Color.inkText : Color.inkFaint)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
        .shadow(color: Elevation.card, radius: 8, y: 2)
    }

    /// The 2-hour span a bin covers, e.g. "12–2 AM" or "10 PM – 12 AM".
    private static func binTimeRange(_ i: Int) -> String {
        let start = clockLabel(i * 2)
        let end = clockLabel((i * 2 + 2) % 24)
        return start.meridiem == end.meridiem
            ? "\(start.hour)–\(end.hour) \(end.meridiem)"
            : "\(start.hour) \(start.meridiem) – \(end.hour) \(end.meridiem)"
    }

    private static func clockLabel(_ hour24: Int) -> (hour: Int, meridiem: String) {
        let meridiem = hour24 < 12 ? "AM" : "PM"
        let h = hour24 % 12
        return (h == 0 ? 12 : h, meridiem)
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

