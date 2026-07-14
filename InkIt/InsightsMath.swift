import Foundation

/// Pure analytics behind the Insights tab. Every function is static and
/// side-effect-free — inputs in, values out — so each card's math is unit-
/// testable without a store or a view. All of it is plain arithmetic over
/// local data: no model, nothing leaves the Mac (the tab says so).
enum InsightsMath {

    // MARK: - Day keys

    /// Local-calendar day key, e.g. "2026-07-11" — the identity both the
    /// aggregate store's unique constraint and the streak/heatmap math key on.
    /// Local timezone on purpose: a "day" is the user's day.
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    // MARK: - Filler counting (Polish before → after)

    /// Filler tokens Polish typically strips. Unigrams are matched per token;
    /// the bigrams are matched on adjacent token pairs.
    private static let fillerUnigrams: Set<String> = [
        "um", "uh", "uhm", "erm", "er", "ah", "hmm", "mmm", "like", "yeah",
    ]
    private static let fillerBigrams: [(String, String)] = [
        ("you", "know"), ("i", "mean"), ("sort", "of"), ("kind", "of"),
    ]

    /// How many filler words the polish pass removed: filler occurrences in
    /// the raw transcript minus those still present in the polished text,
    /// clamped at zero per filler (a rewrite can also *add* words; that never
    /// counts negative). Bigrams count both words, matching how they read.
    static func fillersRemoved(original: String, polished: String) -> Int {
        let before = fillerCounts(in: tokenize(original).map(\.normalized))
        let after = fillerCounts(in: tokenize(polished).map(\.normalized))
        var removed = 0
        for (token, count) in before {
            removed += max(0, count - (after[token] ?? 0))
        }
        return removed
    }

    /// Occurrences of each filler (unigrams keyed by the word, bigrams keyed
    /// "a b" and weighted ×2 — two words removed).
    private static func fillerCounts(in tokens: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in tokens where fillerUnigrams.contains(token) {
            counts[token, default: 0] += 1
        }
        if tokens.count >= 2 {
            for i in 0..<(tokens.count - 1) {
                for (a, b) in fillerBigrams where tokens[i] == a && tokens[i + 1] == b {
                    counts["\(a) \(b)", default: 0] += 2
                }
            }
        }
        // "like"/"yeah" as unigram fillers is deliberately loose; polished text
        // that keeps a legitimate "like" simply cancels it in the subtraction.
        return counts
    }

    // MARK: - Tokenizing

    /// One word occurrence: the normalized form used for counting/lookup
    /// (lowercased, apostrophes dropped — matching the frequency table's
    /// tokenization) plus the surface form as spoken, for display casing.
    struct Token: Equatable {
        let normalized: String
        let surface: String
    }

    /// Splits text into word tokens: letters/digits stay, an apostrophe stays
    /// *inside* a word ("don't"), everything else separates. Normalization
    /// lowercases and drops apostrophes ("don't" → "dont") so lookups line up
    /// with the bundled corpus.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            // A trailing apostrophe is punctuation, not part of the word.
            let surface = current.hasSuffix("'") ? String(current.dropLast()) : current
            if !surface.isEmpty {
                let normalized = surface.lowercased().replacingOccurrences(of: "'", with: "")
                if !normalized.isEmpty {
                    tokens.append(Token(normalized: normalized, surface: surface))
                }
            }
            current = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if ch == "'" || ch == "’" {
                if current.isEmpty { continue }  // leading apostrophe = quote
                current.append("'")
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    // MARK: - Your words (top words this month)

    struct WordCount: Equatable {
        /// Display form — the most frequent surface casing ("Cartesia", not
        /// "cartesia").
        let word: String
        let count: Int
    }

    /// The most-said interesting words across `texts`: stopwords, short words
    /// (< 3 letters), and pure numbers filtered out; top `limit` by count.
    static func topWords(texts: [String], stopwords: Set<String>, limit: Int) -> [WordCount] {
        let counted = countWords(texts: texts, stopwords: stopwords)
        return counted
            .sorted { $0.value.total == $1.value.total
                        ? $0.key < $1.key
                        : $0.value.total > $1.value.total }
            .prefix(limit)
            .map { WordCount(word: $0.value.displayForm, count: $0.value.total) }
    }

    /// Shared counting for the words card: normalized word → total count +
    /// most frequent surface casing.
    private struct SurfaceCount {
        var total = 0
        var surfaces: [String: Int] = [:]
        var displayForm: String {
            surfaces.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? ""
        }
    }

    private static func countWords(texts: [String], stopwords: Set<String>) -> [String: SurfaceCount] {
        var counts: [String: SurfaceCount] = [:]
        for text in texts {
            for token in tokenize(text) {
                let word = token.normalized
                guard word.count >= 3,
                      !stopwords.contains(word),
                      !word.allSatisfy({ $0.isNumber }) else { continue }
                counts[word, default: SurfaceCount()].total += 1
                counts[word, default: SurfaceCount()].surfaces[token.surface, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Activity heatmap

    struct HeatCell: Equatable {
        let date: Date
        let words: Int
        /// Dictations that day — the second half of the hover tooltip.
        let dictations: Int
        /// 0 (no activity) … 4 (a top day), scaled to the user's own history.
        let level: Int
        let isToday: Bool
    }

    /// `weekCount` columns × 7 rows of days, oldest first — the prototype's
    /// flow, not GitHub's weekday-aligned columns, so there are never leading
    /// ghost days. The window's newest day is `dayOffset` days before today
    /// (0 = ends today); paging slides it back a full window at a time.
    /// Levels are quartiles of the user's own nonzero days: "deeper ink, more
    /// words" relative to *their* usage, so light dictators still see range.
    static func heatmapWeeks(days: [UsageAggregateStore.Day],
                             now: Date,
                             weekCount: Int,
                             dayOffset: Int = 0,
                             calendar: Calendar = .current) -> [[HeatCell]] {
        guard weekCount > 0 else { return [] }
        let wordsByKey = Dictionary(days.map { ($0.dayKey, $0.words) },
                                    uniquingKeysWith: { a, _ in a })
        let dictationsByKey = Dictionary(days.map { ($0.dayKey, $0.dictations) },
                                         uniquingKeysWith: { a, _ in a })
        let thresholds = levelThresholds(days: days)
        let today = calendar.startOfDay(for: now)
        let totalDays = weekCount * 7
        let base = max(0, dayOffset)

        var cells: [HeatCell] = []
        cells.reserveCapacity(totalDays)
        for offset in stride(from: totalDays - 1 + base, through: base, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayKey(for: date)
            let words = wordsByKey[key] ?? 0
            cells.append(HeatCell(date: date,
                                  words: words,
                                  dictations: dictationsByKey[key] ?? 0,
                                  level: level(for: words, thresholds: thresholds),
                                  isToday: offset == 0))
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    /// Quartile boundaries of the user's nonzero day totals.
    private static func levelThresholds(days: [UsageAggregateStore.Day]) -> [Int] {
        let nonzero = days.map(\.words).filter { $0 > 0 }.sorted()
        guard !nonzero.isEmpty else { return [] }
        func q(_ f: Double) -> Int { nonzero[min(nonzero.count - 1, Int(Double(nonzero.count) * f))] }
        return [q(0.25), q(0.5), q(0.75)]
    }

    private static func level(for words: Int, thresholds: [Int]) -> Int {
        guard words > 0 else { return 0 }
        guard thresholds.count == 3 else { return 4 }
        // Boundaries round *up* so a flat history (every threshold equal — a
        // brand-new or one-speed user) inks its active days fully, not faintly.
        if words >= thresholds[2] { return 4 }
        if words >= thresholds[1] { return 3 }
        if words >= thresholds[0] { return 2 }
        return 1
    }

    // MARK: - Streaks

    /// Consecutive active days ending today — or ending *yesterday* when today
    /// has no dictation yet: the streak is "safe until midnight", not broken
    /// at breakfast.
    static func currentStreak(days: [UsageAggregateStore.Day],
                              today: Date,
                              calendar: Calendar = .current) -> Int {
        let active = activeDayKeys(days)
        var date = calendar.startOfDay(for: today)
        if !active.contains(dayKey(for: date)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }
        var streak = 0
        while active.contains(dayKey(for: date)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return streak
    }

    /// The longest run of consecutive active days anywhere in history.
    static func longestStreak(days: [UsageAggregateStore.Day],
                              calendar: Calendar = .current) -> Int {
        let activeDates = days.filter { $0.words > 0 }
            .map { calendar.startOfDay(for: $0.day) }
            .sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for date in activeDates {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == date {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = date
        }
        return longest
    }

    /// "234 active days of 280": days with any dictation, over the span from
    /// the first recorded day through today (inclusive).
    static func activeDaysSummary(days: [UsageAggregateStore.Day],
                                  today: Date,
                                  calendar: Calendar = .current) -> (active: Int, of: Int) {
        let active = days.filter { $0.words > 0 }.count
        guard let first = days.map(\.day).min() else { return (0, 0) }
        let span = (calendar.dateComponents([.day],
                                            from: calendar.startOfDay(for: first),
                                            to: calendar.startOfDay(for: today)).day ?? 0) + 1
        return (active, max(span, active))
    }

    private static func activeDayKeys(_ days: [UsageAggregateStore.Day]) -> Set<String> {
        Set(days.filter { $0.words > 0 }.map(\.dayKey))
    }

    // MARK: - Where you dictate

    struct AppShare: Equatable {
        let name: String
        /// Bundle ID for icon lookup; nil for the rolled-up "Other" bucket.
        let bundleID: String?
        let count: Int
        /// Integer percent; a set of shares sums to 100 (largest remainder).
        let percent: Int
    }

    /// Share of dictations by target app over `entries` (pass a pre-filtered
    /// window). Entries with no app captured (pre-upgrade rows, practice
    /// takes) are excluded entirely. Top `limit` apps plus an "Other" bucket
    /// when more remain.
    static func appShare(entries: [TranscriptHistoryStore.Entry], limit: Int) -> [AppShare] {
        var countsByKey: [String: (name: String, bundleID: String?, count: Int)] = [:]
        for entry in entries {
            guard let name = entry.appName else { continue }
            let key = entry.appBundleID ?? name
            var slot = countsByKey[key] ?? (name, entry.appBundleID, 0)
            slot.count += 1
            slot.name = name  // latest display name wins (apps rarely rename)
            countsByKey[key] = slot
        }
        let ranked = countsByKey.values.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        guard !ranked.isEmpty else { return [] }

        var shares = ranked.prefix(limit).map { (name: $0.name, bundleID: $0.bundleID, count: $0.count) }
        let otherCount = ranked.dropFirst(limit).reduce(0) { $0 + $1.count }
        if otherCount > 0 { shares.append((name: "Other", bundleID: nil, count: otherCount)) }

        let total = shares.reduce(0) { $0 + $1.count }
        let percents = wholePercents(of: shares.map(\.count), total: total)
        return zip(shares, percents).map {
            AppShare(name: $0.name, bundleID: $0.bundleID, count: $0.count, percent: $1)
        }
    }

    /// Integer percentages that sum to exactly 100 (largest-remainder method).
    static func wholePercents(of counts: [Int], total: Int) -> [Int] {
        guard total > 0, !counts.isEmpty else { return counts.map { _ in 0 } }
        let exact = counts.map { Double($0) * 100 / Double(total) }
        var floors = exact.map { Int($0) }
        var remainder = 100 - floors.reduce(0, +)
        // Hand the leftover points to the largest fractional parts.
        let order = exact.enumerated()
            .sorted { ($0.element - $0.element.rounded(.down)) > ($1.element - $1.element.rounded(.down)) }
            .map(\.offset)
        var i = 0
        while remainder > 0 && !order.isEmpty {
            floors[order[i % order.count]] += 1
            remainder -= 1
            i += 1
        }
        return floors
    }

    // MARK: - When you speak

    /// Dictation counts in 12 two-hour bins over the day (00–02 … 22–24),
    /// local time. Pass a pre-filtered window of entries.
    static func hourHistogram(entries: [TranscriptHistoryStore.Entry],
                              calendar: Calendar = .current) -> [Int] {
        var bins = [Int](repeating: 0, count: 12)
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.timestamp)
            bins[min(hour / 2, 11)] += 1
        }
        return bins
    }

    // MARK: - Headline totals

    /// Every word ever dictated, across the whole aggregate history — the
    /// proud lifetime number the hero leads with.
    static func totalWords(days: [UsageAggregateStore.Day]) -> Int {
        days.reduce(0) { $0 + $1.words }
    }

    /// Every filler word Polish has cleaned up for the user, lifetime — the
    /// one headline figure that is the app working *for* you, not you working.
    static func totalFillersRemoved(days: [UsageAggregateStore.Day]) -> Int {
        days.reduce(0) { $0 + $1.fillerWordsRemoved }
    }

    /// Lifetime mean speaking pace — the single source of truth both Home and
    /// Insights render, so the two surfaces can never disagree. Pairs each
    /// dictation's own word count with its own press→release duration (only
    /// entries that recorded both) and divides the totals. Computed straight
    /// from the transcript entries, deliberately *not* the day aggregates:
    /// aggregates sum words and speaking time as separate counters, which can
    /// fall out of lockstep (e.g. across a schema change) and skew the ratio;
    /// the per-entry pairing here can't. Stays nil under a minute of timed
    /// speech — a tiny sample posts a jumpy, meaningless number.
    static func averageWordsPerMinute(entries: [TranscriptHistoryStore.Entry],
                                      minSpeakingMs: Int = 60_000) -> Int? {
        var totalWords = 0
        var totalMs = 0
        for entry in entries {
            guard let words = entry.wordCount, let ms = entry.recordingMs,
                  words > 0, ms > 0 else { continue }
            totalWords += words
            totalMs += ms
        }
        guard totalMs >= minSpeakingMs, totalWords > 0 else { return nil }
        return Int((Double(totalWords) * 60_000 / Double(totalMs)).rounded())
    }

    // MARK: - Records

    /// Most words in a single day.
    static func bestDayWords(days: [UsageAggregateStore.Day]) -> Int? {
        days.map(\.words).max().flatMap { $0 > 0 ? $0 : nil }
    }

    /// The single longest dictation (press → release) on record.
    static func longestDictationMs(days: [UsageAggregateStore.Day]) -> Int? {
        days.map(\.longestDictationMs).max().flatMap { $0 > 0 ? $0 : nil }
    }

    /// The user's fastest day, in words per minute of actual speaking time.
    /// Day-level on purpose (total words ÷ total press→release time) so one
    /// two-second blurt can't set an absurd record; days with under a minute
    /// of speech carry too little signal and are skipped.
    static func fastestDayWordsPerMinute(days: [UsageAggregateStore.Day],
                                         minSpeakingMs: Int = 60_000) -> Int? {
        days.filter { $0.speakingMs >= minSpeakingMs && $0.spokenWords > 0 }
            .map { Int((Double($0.spokenWords) * 60_000 / Double($0.speakingMs)).rounded()) }
            .max()
    }

    /// "3m 12s" / "48s" — duration formatting for the records tiles.
    static func formatDuration(ms: Int) -> String {
        let seconds = (ms + 500) / 1000
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
