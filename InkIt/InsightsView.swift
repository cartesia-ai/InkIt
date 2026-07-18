import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var history: TranscriptHistoryStore
    @EnvironmentObject var aggregates: UsageAggregateStore
    @StateObject private var model = InsightsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Insights")
                    .font(.inkTitle)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 14) {
                    HeroRow(snapshot: model.snapshot)
                    ActivityCard(model: model)
                    HStack(alignment: .top, spacing: 14) {
                        WordsCard(snapshot: model.snapshot)
                        WhereCard(snapshot: model.snapshot)
                    }
                    WhenCard(snapshot: model.snapshot)
                }
                .padding(.top, 16)
            }
            .pageFrame()
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.refresh() }
        .onChange(of: history.entries.count) { _, _ in model.refresh() }
    }

}

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

extension InsightsCard where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

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

private struct ActivityCard: View {
    @ObservedObject var model: InsightsModel

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
                    .zIndex(1)
                    Spacer(minLength: 0)
                    Group {
                        if model.snapshot.hasAnyActivity {
                            streakStats
                        } else {
                            emptyInvite
                        }
                    }
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

    private func fitWeeks(to width: CGFloat) {
        let available = width - Self.streakColumnWidth - Self.hGap
        let perWeek = Self.cellSize + Self.cellGap
        let weeks = Int((available + Self.cellGap) / perWeek)
        model.setWeekCount(min(53, max(8, weeks)))
    }

    private var heatmap: some View {
        HStack(alignment: .top, spacing: Self.cellGap) {
            ForEach(Array(model.snapshot.heatmapWeeks.enumerated()), id: \.offset) { col, week in
                VStack(spacing: Self.cellGap) {
                    ForEach(Array(week.enumerated()), id: \.element.date) { row, cell in
                        heatCell(cell)
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

    private static let levelOpacity: [Double] = [0, 0.22, 0.45, 0.70, 1.0]

    private static let minMonthLabelCols = 3

    private var monthMarkers: [MonthMark] {
        let calendar = Calendar.current
        var raw: [(col: Int, text: String)] = []
        var lastMonth = -1
        for (i, week) in model.snapshot.heatmapWeeks.enumerated() {
            guard let first = week.first?.date else { continue }
            let month = calendar.component(.month, from: first)
            if month != lastMonth {
                raw.append((i, first.formatted(.dateTime.month(.abbreviated))))
                lastMonth = month
            }
        }
        var marks: [MonthMark] = []
        for (idx, mark) in raw.enumerated() {
            if idx == 0, raw.count > 1, raw[1].col - mark.col < Self.minMonthLabelCols {
                continue
            }
            if let last = marks.last, mark.col - last.col < Self.minMonthLabelCols {
                continue
            }
            marks.append(MonthMark(col: mark.col, text: mark.text))
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

    private func cellHelp(_ cell: InsightsMath.HeatCell) -> String {
        let day = cell.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let heading = day + (cell.isToday ? " · Today" : "")
        guard cell.words > 0 else { return "\(heading)\nNo dictation" }
        let unit = cell.dictations == 1 ? "dictation" : "dictations"
        return "\(heading)\n\(cell.words.formatted()) words · \(cell.dictations) \(unit)"
    }

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

private struct HBar: View {
    let label: String
    let fraction: Double
    let value: String
    var ghost = false
    var icon: Image?
    var iconIsSymbol = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconIsSymbol ? 15 : 20, height: iconIsSymbol ? 15 : 20)
                    .foregroundStyle(Color.inkFaint)
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
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.top, 10)
    }
}

private struct WordsCard: View {
    let snapshot: InsightsModel.Snapshot

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
                EmptyPane(icon: "text.alignleft",
                          headline: "No words yet",
                          message: "Your most-said words show up here.")
            }
        }
    }
}

private struct EmptyPane: View {
    let icon: String
    let headline: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))  // ds-allow: icon
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Text(headline)
                .font(.inkCalloutEmphasized)
                .foregroundStyle(Color.inkText)
            Text(message)
                .font(.inkCallout)
                .foregroundStyle(Color.inkSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 150)
        .padding(.top, 8)
    }
}

private struct WhereCard: View {
    let snapshot: InsightsModel.Snapshot

    var body: some View {
        InsightsCard(title: "Where you dictate") {
            if !snapshot.appShare.isEmpty {
                let top = Double(snapshot.appShare.map(\.words).max() ?? 1)
                ForEach(snapshot.appShare, id: \.name) { share in
                    let mark = Self.appIcon(bundleID: share.bundleID)
                    HBar(label: share.name,
                         fraction: Double(share.words) / max(top, 1),
                         value: "\(share.percent)%",
                         icon: mark.image,
                         iconIsSymbol: mark.isSymbol)
                }
            } else {
                EmptyPane(icon: "square.grid.2x2",
                          headline: "No apps yet",
                          message: "The apps you dictate into show up here.")
            }
        }
    }

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
}

private struct WhenCard: View {
    let snapshot: InsightsModel.Snapshot

    @State private var hoverHour: Int?

    private static let minDictationsForHours = 5
    private static let chartHeight: CGFloat = 150
    private static let tooltipReserve: CGFloat = 58

    private var hasHourData: Bool {
        snapshot.windowDictations >= Self.minDictationsForHours
    }

    var body: some View {
        InsightsCard(title: "When you speak") {
            if hasHourData {
                chart
                    .padding(.top, 4)
                hourLabels
                    .padding(.top, 8)
            } else {
                EmptyPane(icon: "clock",
                          headline: "No hours yet",
                          message: "Your busiest dictation hours show up here.")
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let bins = snapshot.hourWords
        let maxVal = CGFloat(max(bins.max() ?? 1, 1))
        let lastIndex = CGFloat(max(bins.count - 1, 1))
        let top = min(Self.tooltipReserve, size.height)
        let span = size.height - top
        return bins.enumerated().map { i, value in
            CGPoint(x: size.width * CGFloat(i) / lastIndex,
                    y: top + span * (1 - CGFloat(value) / maxVal))
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var path = linePath(pts)
        guard let first = pts.first, let last = pts.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }

    private var chart: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack(alignment: .topLeading) {
                areaPath(pts, height: geo.size.height)
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                linePath(pts)
                    .stroke(Color.accentColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let h = hoverHour, pts.indices.contains(h) {
                    let p = pts[h]
                    Path {
                        $0.move(to: CGPoint(x: p.x, y: 0))
                        $0.addLine(to: CGPoint(x: p.x, y: geo.size.height))
                    }
                    .stroke(Color.line, lineWidth: 1)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .position(p)
                    tooltip(hour: h)
                        .allowsHitTesting(false)
                        .fixedSize()
                        .position(x: min(max(p.x, 56), geo.size.width - 56),
                                  y: max(p.y - 34, 4))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let lastIndex = max(snapshot.hourWords.count - 1, 1)
                    let ratio = location.x / max(geo.size.width, 1)
                    hoverHour = min(max(Int((ratio * CGFloat(lastIndex)).rounded()), 0), lastIndex)
                case .ended:
                    hoverHour = nil
                }
            }
        }
        .frame(height: Self.chartHeight)
    }

    private func tooltip(hour: Int) -> some View {
        let words = snapshot.hourWords[hour]
        return VStack(alignment: .leading, spacing: 2) {
            Text(Self.hourLabel(hour))
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
            Text("\(words.formatted()) \(words == 1 ? "word" : "words")")
                .font(.inkCalloutEmphasized)
                .foregroundStyle(words > 0 ? Color.inkText : Color.inkFaint)
        }
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

    private static func hourLabel(_ hour24: Int) -> String {
        let start = clockLabel(hour24)
        let end = clockLabel((hour24 + 1) % 24)
        return start.meridiem == end.meridiem
            ? "\(start.hour)\u{2013}\(end.hour) \(end.meridiem)"
            : "\(start.hour) \(start.meridiem) \u{2013} \(end.hour) \(end.meridiem)"
    }

    private static func clockLabel(_ hour24: Int) -> (hour: Int, meridiem: String) {
        let meridiem = hour24 < 12 ? "AM" : "PM"
        let h = hour24 % 12
        return (h == 0 ? 12 : h, meridiem)
    }

    private var hourLabels: some View {
        HStack {
            Text("12 AM")
            Spacer()
            Text("6 AM")
            Spacer()
            Text("noon")
            Spacer()
            Text("6 PM")
            Spacer()
            Text("11 PM")
        }
        .font(.inkCaption)
        .foregroundStyle(Color.inkFaint)
    }
}

