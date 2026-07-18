import Foundation
import Combine

@MainActor
final class InsightsModel: ObservableObject {

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
        var hourWords: [Int] = Array(repeating: 0, count: 24)
        var windowDictations = 0
        var hasAnyActivity = false
        var canPageBack = false
        var canPageForward = false
        var windowRange = ""
    }

    @Published private(set) var snapshot = Snapshot()

    private(set) var weekCount = 40

    private(set) var dayOffset = 0

    private let history: TranscriptHistoryStore
    private let aggregates: UsageAggregateStore

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

    func pageBack() {
        dayOffset += weekCount * 7
        refresh()
    }

    func pageForward() {
        dayOffset = max(0, dayOffset - weekCount * 7)
        refresh()
    }

    private static func maxDayOffset(days: [UsageAggregateStore.Day], weekCount: Int,
                                     today: Date, calendar: Calendar) -> Int {
        guard let first = days.lazy.filter({ $0.words > 0 }).map(\.day).min() else { return 0 }
        let span = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: first),
                                           to: calendar.startOfDay(for: today)).day ?? 0
        return max(0, span - (weekCount * 7 - 1))
    }

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

        s.totalWords = history.lifetimeWords
        s.totalFixes = InsightsMath.totalFillersRemoved(days: days)
        s.bestDayWords = InsightsMath.bestDayWords(days: days)
        s.longestDictationMs = InsightsMath.longestDictationMs(days: days)
        s.fastestWpm = InsightsMath.fastestDayWordsPerMinute(days: days)
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

        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let monthTexts = entries.filter { $0.timestamp >= monthStart }.map(\.text)
        s.monthTokens = monthTexts.reduce(0) { $0 + TranscriptHistoryStore.wordCount($1) }
        s.topWords = InsightsMath.topWords(texts: monthTexts,
                                           stopwords: InsightsResources.stopwords, limit: 5)

        s.windowDictations = entries.count
        s.appShare = InsightsMath.appShare(entries: entries, limit: 4)
        s.hourWords = InsightsMath.hourWords(entries: entries, calendar: calendar)

        snapshot = s
    }
}

enum InsightsResources {
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
