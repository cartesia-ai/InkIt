import XCTest
@testable import InkIt

final class InsightsMathTests: XCTestCase {

    private let calendar = Calendar.current
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
    }

    private func day(_ offset: Int, words: Int,
                     longestMs: Int = 0, fillers: Int = 0,
                     speakingMs: Int = 0, spokenWords: Int? = nil) -> UsageAggregateStore.Day {
        let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: today)!)
        return UsageAggregateStore.Day(dayKey: InsightsMath.dayKey(for: date), day: date,
                                       words: words, dictations: 1,
                                       longestDictationMs: longestMs,
                                       fillerWordsRemoved: fillers,
                                       speakingMs: speakingMs,
                                       spokenWords: spokenWords ?? words)
    }

    private func entry(_ text: String, hoursAgo: Int = 0,
                       appName: String? = nil, appBundleID: String? = nil,
                       wordCount: Int? = nil, recordingMs: Int? = nil) -> TranscriptHistoryStore.Entry {
        TranscriptHistoryStore.Entry(
            text: text,
            timestamp: calendar.date(byAdding: .hour, value: -hoursAgo, to: today)!,
            latency: nil, original: nil, polish: nil, failure: nil,
            appName: appName, appBundleID: appBundleID,
            wordCount: wordCount, recordingMs: recordingMs
        )
    }

    func testCurrentStreakEmptyHistoryIsZero() {
        XCTAssertEqual(InsightsMath.currentStreak(days: [], today: today), 0)
    }

    func testCurrentStreakCountsRunEndingToday() {
        let days = [day(0, words: 10), day(1, words: 5), day(2, words: 7), day(4, words: 9)]
        XCTAssertEqual(InsightsMath.currentStreak(days: days, today: today), 3,
                       "the gap at offset 3 ends the run")
    }

    func testCurrentStreakSurvivesQuietToday() {
        let days = [day(1, words: 5), day(2, words: 7)]
        XCTAssertEqual(InsightsMath.currentStreak(days: days, today: today), 2)
    }

    func testCurrentStreakZeroAfterFullDayGap() {
        let days = [day(2, words: 7), day(3, words: 3)]
        XCTAssertEqual(InsightsMath.currentStreak(days: days, today: today), 0)
    }

    func testCurrentStreakIgnoresZeroWordDays() {
        let days = [day(0, words: 0), day(1, words: 5)]
        XCTAssertEqual(InsightsMath.currentStreak(days: days, today: today), 1,
                       "a zero-word aggregate row is not an active day")
    }

    func testLongestStreakFindsHistoricRun() {
        let days = [day(0, words: 1),
                    day(10, words: 1), day(11, words: 1), day(12, words: 1), day(13, words: 1),
                    day(20, words: 1)]
        XCTAssertEqual(InsightsMath.longestStreak(days: days), 4)
    }

    func testActiveDaysSummarySpansFirstRecordToToday() {
        let days = [day(9, words: 1), day(0, words: 1)]
        let summary = InsightsMath.activeDaysSummary(days: days, today: today)
        XCTAssertEqual(summary.active, 2)
        XCTAssertEqual(summary.of, 10, "span is inclusive of both endpoints")
    }

    func testHeatmapShapeAndTodayMarker() {
        let weeks = InsightsMath.heatmapWeeks(days: [day(0, words: 100)], now: today, weekCount: 4)
        XCTAssertEqual(weeks.count, 4)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        let cells = weeks.flatMap { $0 }
        XCTAssertEqual(cells.filter(\.isToday).count, 1)
        XCTAssertTrue(cells.last!.isToday, "today is the last cell of the last column")
        XCTAssertEqual(cells.last!.words, 100)
    }

    func testHeatmapDayOffsetSlidesWindowBack() {
        let offset = 28
        let weeks = InsightsMath.heatmapWeeks(days: [day(offset, words: 100)],
                                              now: today, weekCount: 4, dayOffset: offset)
        let cells = weeks.flatMap { $0 }
        XCTAssertEqual(cells.count, 28)
        XCTAssertFalse(cells.contains(where: \.isToday), "an offset window never contains today")
        XCTAssertEqual(cells.last?.words, 100, "the day 28 days back is the window's newest cell")
        let expectedNewest = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: today)!)
        XCTAssertEqual(cells.last.map { calendar.startOfDay(for: $0.date) }, expectedNewest)
    }

    func testHeatmapSingleSpeedHistoryInksFully() {
        let weeks = InsightsMath.heatmapWeeks(days: [day(0, words: 50), day(1, words: 50)],
                                              now: today, weekCount: 2)
        let active = weeks.flatMap { $0 }.filter { $0.words > 0 }
        XCTAssertEqual(active.map(\.level), [4, 4])
    }

    func testHeatmapLevelsScaleToOwnHistory() {
        let days = (1...100).map { day($0, words: $0 * 10) }
        let weeks = InsightsMath.heatmapWeeks(days: days, now: today, weekCount: 15)
        let cells = weeks.flatMap { $0 }
        XCTAssertEqual(cells.first(where: { $0.words == 10 })?.level, 1)
        XCTAssertEqual(cells.first(where: { $0.words == 1000 })?.level, 4)
        let levels = Set(cells.map(\.level))
        XCTAssertTrue(levels.isSuperset(of: [1, 2, 3, 4]), "a spread history uses the full ramp, got \(levels)")
    }

    func testHeatmapEmptyHistoryIsAllZeroLevels() {
        let weeks = InsightsMath.heatmapWeeks(days: [], now: today, weekCount: 3)
        XCTAssertTrue(weeks.flatMap { $0 }.allSatisfy { $0.level == 0 })
    }

    func testHeatmapCarriesDictationCountForTooltip() {
        var d = day(0, words: 100)
        d.dictations = 6
        let cells = InsightsMath.heatmapWeeks(days: [d], now: today, weekCount: 2).flatMap { $0 }
        XCTAssertEqual(cells.last?.dictations, 6, "today's cell carries its dictation count")
        XCTAssertTrue(cells.dropLast().allSatisfy { $0.dictations == 0 }, "empty days report zero dictations")
    }

    func testHeadlineTotalsSumAcrossHistory() {
        let days = [day(0, words: 100, fillers: 12, speakingMs: 40_000),
                    day(1, words: 300, fillers: 8, speakingMs: 80_000)]
        XCTAssertEqual(InsightsMath.totalWords(days: days), 400)
        XCTAssertEqual(InsightsMath.totalFillersRemoved(days: days), 20)
    }

    func testAverageWpmPairsEachEntrysWordsWithItsDuration() {
        let entries = [entry("a", wordCount: 100, recordingMs: 40_000),
                       entry("b", wordCount: 300, recordingMs: 80_000)]
        XCTAssertEqual(InsightsMath.averageWordsPerMinute(entries: entries), 200)
    }

    func testAverageWpmNilUntilAMinuteOfSpeech() {
        XCTAssertNil(InsightsMath.averageWordsPerMinute(entries: [entry("a", wordCount: 50, recordingMs: 10_000)]),
                     "under the one-minute floor there is no meaningful average yet")
        XCTAssertNil(InsightsMath.averageWordsPerMinute(entries: []))
    }

    func testAverageWpmSkipsUntimedEntries() {
        let entries = [entry("timed", wordCount: 150, recordingMs: 60_000),
                       entry("untimed", wordCount: 5_000, recordingMs: nil)]
        XCTAssertEqual(InsightsMath.averageWordsPerMinute(entries: entries), 150)
    }

    func testAverageWpmNilWithoutAnyTimedEntries() {
        let entries = [entry("a", wordCount: 5_000, recordingMs: nil)]
        XCTAssertNil(InsightsMath.averageWordsPerMinute(entries: entries))
    }

    func testTokenizeStripsPunctuationAndNormalizesApostrophes() {
        let tokens = InsightsMath.tokenize("Don't ship it, twice — \"don't\"!")
        XCTAssertEqual(tokens.map(\.normalized), ["dont", "ship", "it", "twice", "dont"])
        XCTAssertEqual(tokens.first?.surface, "Don't")
    }

    func testTopWordsFiltersStopwordsShortsAndNumbers() {
        let texts = Array(repeating: "the latency of 42 latency is ok latency deploy deploy", count: 3)
        let top = InsightsMath.topWords(texts: texts, stopwords: ["the", "of", "is"], limit: 5)
        XCTAssertEqual(top.first, InsightsMath.WordCount(word: "latency", count: 9))
        XCTAssertEqual(top.dropFirst().first, InsightsMath.WordCount(word: "deploy", count: 6))
        XCTAssertFalse(top.contains { $0.word == "42" }, "pure numbers are filtered")
        XCTAssertFalse(top.contains { $0.word == "ok" }, "words under 3 letters are filtered")
    }

    func testTopWordsPicksDominantCasing() {
        let texts = ["Cartesia cartesia Cartesia Cartesia streaming"]
        let top = InsightsMath.topWords(texts: texts, stopwords: [], limit: 1)
        XCTAssertEqual(top.first?.word, "Cartesia")
    }

    func testFillersRemovedCountsUnigramsAndBigrams() {
        let removed = InsightsMath.fillersRemoved(
            original: "um so like the uh plan you know",
            polished: "so the plan"
        )
        XCTAssertEqual(removed, 5)
    }

    func testFillersRemovedClampsWhenPolishKeepsThem() {
        XCTAssertEqual(InsightsMath.fillersRemoved(original: "um the plan",
                                                   polished: "um um the plan"), 0,
                       "polish adding fillers never counts negative")
    }

    func testFillersRemovedNoFillersIsZero() {
        XCTAssertEqual(InsightsMath.fillersRemoved(original: "ship it thursday",
                                                   polished: "Ship it Thursday."), 0)
    }

    func testAppShareRanksByWordsAndBucketsOther() {
        var entries: [TranscriptHistoryStore.Entry] = []
        entries += (0..<6).map { _ in entry("hi", appName: "Slack", appBundleID: "com.slack", wordCount: 10) }
        entries += (0..<3).map { _ in entry("hi", appName: "Mail", appBundleID: "com.mail", wordCount: 5) }
        entries += [entry("hi", appName: "Notes", appBundleID: "com.notes", wordCount: 2),
                    entry("hi", appName: "Cursor", appBundleID: "com.cursor", wordCount: 2),
                    entry("hi", appName: "Xcode", appBundleID: "com.xcode", wordCount: 2),
                    entry("hi", wordCount: 99)]
        let shares = InsightsMath.appShare(entries: entries, limit: 3)
        XCTAssertEqual(shares.map(\.name), ["Slack", "Mail", "Cursor", "Other"])
        XCTAssertEqual(shares.map(\.percent).reduce(0, +), 100)
        XCTAssertEqual(shares.first?.words, 60, "words sum across an app's dictations")
        XCTAssertEqual(shares.last?.words, 4, "the two apps past the limit roll up by words")
    }

    func testAppShareEmptyWithoutAppData() {
        XCTAssertTrue(InsightsMath.appShare(entries: [entry("hi"), entry("there")], limit: 4).isEmpty)
    }

    func testWholePercentsSumToExactlyOneHundred() {
        XCTAssertEqual(InsightsMath.wholePercents(of: [1, 1, 1], total: 3).reduce(0, +), 100)
        XCTAssertEqual(InsightsMath.wholePercents(of: [6, 3, 1, 1, 1], total: 12).reduce(0, +), 100)
        XCTAssertEqual(InsightsMath.wholePercents(of: [12], total: 12), [100])
    }

    func testHourWordsBinsByHour() {
        let e1 = TranscriptHistoryStore.Entry(
            text: "a", timestamp: calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 0, minute: 5))!,
            latency: nil, original: nil, polish: nil, failure: nil, wordCount: 5)
        let e2 = TranscriptHistoryStore.Entry(
            text: "b", timestamp: calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 23, minute: 59))!,
            latency: nil, original: nil, polish: nil, failure: nil, wordCount: 8)
        let e3 = TranscriptHistoryStore.Entry(
            text: "c", timestamp: calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 14))!,
            latency: nil, original: nil, polish: nil, failure: nil, wordCount: 3)
        let bins = InsightsMath.hourWords(entries: [e1, e2, e3])
        XCTAssertEqual(bins.count, 24)
        XCTAssertEqual(bins[0], 5)
        XCTAssertEqual(bins[23], 8)
        XCTAssertEqual(bins[14], 3)
        XCTAssertEqual(bins.reduce(0, +), 16)
    }

    func testRecordsFromAggregates() {
        let days = [day(0, words: 100, longestMs: 45_000),
                    day(1, words: 900, longestMs: 192_000),
                    day(30, words: 500, longestMs: 10_000)]
        XCTAssertEqual(InsightsMath.bestDayWords(days: days), 900)
        XCTAssertEqual(InsightsMath.longestDictationMs(days: days), 192_000)
    }

    func testFastestDayPicksBestWPM() {
        let days = [day(0, words: 300, speakingMs: 120_000),
                    day(1, words: 500, speakingMs: 300_000)]
        XCTAssertEqual(InsightsMath.fastestDayWordsPerMinute(days: days), 150)
    }

    func testFastestDaySkipsThinDays() {
        let days = [day(0, words: 50, speakingMs: 10_000)]
        XCTAssertNil(InsightsMath.fastestDayWordsPerMinute(days: days))
        XCTAssertNil(InsightsMath.fastestDayWordsPerMinute(days: []))
    }

    func testRecordsNilOnEmptyHistory() {
        XCTAssertNil(InsightsMath.bestDayWords(days: []))
        XCTAssertNil(InsightsMath.longestDictationMs(days: [day(0, words: 5)]),
                     "no recorded duration yet → no record, not 0s")
    }

    func testFormatDuration() {
        XCTAssertEqual(InsightsMath.formatDuration(ms: 48_200), "48s")
        XCTAssertEqual(InsightsMath.formatDuration(ms: 192_000), "3m 12s")
    }

    func testDayKeyBoundaries() {
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 23, minute: 59))!
        let justAfterMidnight = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 0, minute: 1))!
        XCTAssertEqual(InsightsMath.dayKey(for: lateNight), "2026-07-10")
        XCTAssertEqual(InsightsMath.dayKey(for: justAfterMidnight), "2026-07-11")
    }
}
