import Foundation
import Combine

/// Assembles everything the Insights view renders, from the two stores'
/// published value mirrors. Recomputed only while the tab is visible (the
/// view calls `refresh` on appear and when history changes) — never on Home
/// search keystrokes or other unrelated UI work. All the math is
/// `InsightsMath`'s pure functions over value types, so moving it off the
/// main actor later is an implementation detail, not a redesign.
@MainActor
final class InsightsModel: ObservableObject {

    /// One immutable computation result — the view reads only this.
    struct Snapshot: Equatable {
        var totalWords = 0
        var totalFixes = 0
        var bestDayWords: Int?
        var longestDictationMs: Int?
        var fastestWpm: Int?
        var heatmapWeeks: [[InsightsMath.HeatCell]] = []
        var currentStreak = 0
        var longestStreak = 0
        var activeDays = 0
        var activeDaysSpan = 0
        var topWords: [InsightsMath.WordCount] = []
        var monthTokens = 0
        var appShare: [InsightsMath.AppShare] = []
        var hourBins: [Int] = Array(repeating: 0, count: 12)
        var windowDictations = 0
        var hasAnyActivity = false
        /// Activity heatmap paging — nonzero only when history runs deeper than
        /// the visible window (so `canPageBack || canPageForward` gates the
        /// control). `windowRange` labels the months on screen.
        var canPageBack = false
        var canPageForward = false
        var windowRange = ""
    }

    @Published private(set) var snapshot = Snapshot()

    /// Columns the Activity card asked for last layout pass — the heatmap is
    /// adaptive so it always fills its row without overflowing (risk: 40 weeks
    /// doesn't fit at the window's minimum width).
    private(set) var weekCount = 40

    /// Days the heatmap window is slid back from today (0 = ends today).
    /// Paged a full window at a time; re-clamped whenever the width (and so
    /// `weekCount`) changes so a wider window can't strand the offset past the
    /// oldest activity.
    private(set) var dayOffset = 0

    private let history: TranscriptHistoryStore
    private let aggregates: UsageAggregateStore

    // The `.shared` fallbacks resolve inside the (MainActor-isolated) init
    // body — as default-argument expressions they'd be evaluated in the
    // caller's nonisolated context, a Swift 6 error.
    init(history: TranscriptHistoryStore? = nil,
         aggregates: UsageAggregateStore? = nil) {
        self.history = history ?? .shared
        self.aggregates = aggregates ?? .shared
    }

    func setWeekCount(_ count: Int) {
        guard count != weekCount, count > 0 else { return }
        weekCount = count
        refresh()
    }

    /// Slide the window one full window older / newer. `refresh` clamps the
    /// new offset to the available history, so calling at an edge is a no-op.
    func pageBack() {
        dayOffset += weekCount * 7
        refresh()
    }

    func pageForward() {
        dayOffset = max(0, dayOffset - weekCount * 7)
        refresh()
    }

    /// Farthest the window can slide back: the span from the first active day
    /// to today, less one window, so the oldest page lands the first day at the
    /// left edge (never scrolling into all-empty prehistory). 0 when history
    /// fits in a single window.
    private static func maxDayOffset(days: [UsageAggregateStore.Day], weekCount: Int,
                                     today: Date, calendar: Calendar) -> Int {
        guard let first = days.lazy.filter({ $0.words > 0 }).map(\.day).min() else { return 0 }
        let span = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: first),
                                           to: calendar.startOfDay(for: today)).day ?? 0
        return max(0, span - (weekCount * 7 - 1))
    }

    /// "Sep 2025 – Apr 2026" for the paging control — collapses the year when
    /// the window sits within one.
    private static func rangeLabel(weeks: [[InsightsMath.HeatCell]], calendar: Calendar) -> String {
        guard let start = weeks.first?.first?.date, let end = weeks.last?.last?.date else { return "" }
        let endLabel = end.formatted(.dateTime.month(.abbreviated).year())
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let startLabel = sameYear
            ? start.formatted(.dateTime.month(.abbreviated))
            : start.formatted(.dateTime.month(.abbreviated).year())
        return "\(startLabel) – \(endLabel)"
    }

    func refresh(now: Date = Date()) {
        let days = aggregates.days
        let entries = history.entries
        let calendar = Calendar.current

        var s = Snapshot()

        // Headline totals + Activity + records — from durable counters that
        // survive Delete All, so the hero always has its numbers. "Words
        // dictated" reads the monotonic lifetime counter (not the seeded day
        // aggregates): it's the number the user watched climb before this
        // release, it counts every word ever dictated — including takes since
        // deleted — and it never dips on upgrade.
        s.totalWords = history.lifetimeWords
        s.totalFixes = InsightsMath.totalFillersRemoved(days: days)
        s.bestDayWords = InsightsMath.bestDayWords(days: days)
        s.longestDictationMs = InsightsMath.longestDictationMs(days: days)
        s.fastestWpm = InsightsMath.fastestDayWordsPerMinute(days: days)
        // Paging window. The oldest day the user can reach is their first
        // active day; from there the offset can slide back until that day sits
        // at the window's left edge. Re-clamp here so a resize (new weekCount)
        // never leaves the offset pointing past the oldest activity.
        let maxOffset = Self.maxDayOffset(days: days, weekCount: weekCount,
                                          today: now, calendar: calendar)
        dayOffset = min(dayOffset, maxOffset)
        s.heatmapWeeks = InsightsMath.heatmapWeeks(days: days, now: now, weekCount: weekCount,
                                                   dayOffset: dayOffset, calendar: calendar)
        s.canPageBack = dayOffset < maxOffset
        s.canPageForward = dayOffset > 0
        s.windowRange = Self.rangeLabel(weeks: s.heatmapWeeks, calendar: calendar)
        s.currentStreak = InsightsMath.currentStreak(days: days, today: now, calendar: calendar)
        s.longestStreak = InsightsMath.longestStreak(days: days, calendar: calendar)
        let summary = InsightsMath.activeDaysSummary(days: days, today: now, calendar: calendar)
        s.activeDays = summary.active
        s.activeDaysSpan = summary.of
        s.hasAnyActivity = days.contains { $0.words > 0 }

        // Word cards — from transcript text, this calendar month (these do
        // empty out on Delete All; the copy says "this month").
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let monthTexts = entries.filter { $0.timestamp >= monthStart }.map(\.text)
        s.monthTokens = monthTexts.reduce(0) { $0 + TranscriptHistoryStore.wordCount($1) }
        s.topWords = InsightsMath.topWords(texts: monthTexts,
                                           stopwords: InsightsResources.stopwords, limit: 5)

        // App + hour cards — all-time, like the hero stats above.
        s.windowDictations = entries.count
        s.appShare = InsightsMath.appShare(entries: entries, limit: 4)
        s.hourBins = InsightsMath.hourHistogram(entries: entries, calendar: calendar)

        snapshot = s
    }
}

/// The bundled stopword list, parsed once and cached on first Insights visit
/// — dictation startup never pays for it.
enum InsightsResources {
    /// Common-English filter for the "Your words" card (~300 words).
    static let stopwords: Set<String> = {
        guard let text = load("stopwords-en") else { return [] }
        return Set(text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }()

    private static func load(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            DebugLog.error("InsightsResources: missing bundled resource \(name).txt")
            return nil
        }
        return text
    }
}
