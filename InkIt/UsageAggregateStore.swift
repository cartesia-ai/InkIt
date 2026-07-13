import Foundation
import Combine
import SwiftData

/// One calendar day of dictation usage, kept as a durable aggregate for
/// Insights. Separate from `TranscriptRecord` on purpose: "Delete All" wipes
/// transcript *content* (typed `context.delete(model: TranscriptRecord.self)`)
/// while these content-free counters survive — the same contract as the
/// `lifetimeWords` UserDefaults counter, so the Activity heatmap, streaks, and
/// Records don't reset when the user clears their words.
@Model
final class DailyUsageRecord {
    /// Local-calendar day key, e.g. "2026-07-11". A string (not a `Date`) so
    /// the unique constraint can't be undermined by sub-day timestamps or
    /// timezone drift in `Date` equality. A timezone change mid-travel can
    /// split a "day" across two keys — acceptable for a usage stat.
    @Attribute(.unique) var dayKey: String
    /// Start-of-day in the local calendar at write time, for range math.
    var day: Date
    /// Words dictated that day (whitespace count, frozen per entry at save).
    var words: Int
    /// Number of dictations that day.
    var dictations: Int
    /// The longest single dictation (press → release) that day, in ms.
    var longestDictationMs: Int
    /// Filler words Polish removed that day (see `InsightsMath.fillersRemoved`).
    var fillerWordsRemoved: Int
    /// Total speaking time that day (sum of press → release), for day-level
    /// words-per-minute. Optional: added after the first aggregate release,
    /// so pre-existing rows read back `nil` (treated as 0 / unknown).
    var speakingMs: Int?

    init(dayKey: String, day: Date, words: Int = 0, dictations: Int = 0,
         longestDictationMs: Int = 0, fillerWordsRemoved: Int = 0, speakingMs: Int = 0) {
        self.dayKey = dayKey
        self.day = day
        self.words = words
        self.dictations = dictations
        self.longestDictationMs = longestDictationMs
        self.fillerWordsRemoved = fillerWordsRemoved
        self.speakingMs = speakingMs
    }
}

/// Owner of the daily usage aggregates. Writes ride the same SwiftData
/// container as the transcripts (one store, one lightweight migration, one
/// in-memory fallback story); the UI reads the published `days` value mirror,
/// exactly like `TranscriptHistoryStore.entries`.
@MainActor
final class UsageAggregateStore: ObservableObject {
    /// A day's aggregates as a plain value for the UI / analytics math.
    struct Day: Equatable, Identifiable {
        var id: String { dayKey }
        let dayKey: String
        let day: Date
        var words: Int
        var dictations: Int
        var longestDictationMs: Int
        var fillerWordsRemoved: Int
        var speakingMs: Int
    }

    /// Instantiated at app launch (InkItApp holds it), *before* any dictation
    /// can call `record` — seeding reads the persisted transcript rows, so a
    /// first-touch inside `TranscriptHistoryStore.add` would double-count the
    /// row that triggered it.
    static let shared = UsageAggregateStore(
        container: TranscriptHistoryStore.shared.modelContainer,
        isPersistent: TranscriptHistoryStore.shared.isPersistent
    )

    /// Every recorded day, oldest first. Rebuilt from storage on launch and
    /// kept in step by `record`.
    @Published private(set) var days: [Day] = []

    private let container: ModelContainer
    /// Mirrors `TranscriptHistoryStore.isPersistent` — durable side effects
    /// (the seeded flag) only land against a store that survives a relaunch.
    private let isPersistent: Bool
    private var context: ModelContext { container.mainContext }
    private let defaults: UserDefaults
    private let seededKey = "usageAggregates.seeded.v1"
    /// Legacy pre-SwiftData history blob — while it exists, the transcript
    /// table may not yet reflect all history, so seeding must wait (mirrors
    /// `loadLifetimeWords`'s gating).
    private let legacyHistoryKey = "transcriptHistory.v1"

    init(container: ModelContainer, isPersistent: Bool, defaults: UserDefaults = .standard) {
        self.container = container
        self.isPersistent = isPersistent
        self.defaults = defaults
        seedFromHistoryIfNeeded()
        loadDays()
    }

    // MARK: - Public API

    /// Folds one dictation into its local-calendar day. Called by
    /// `TranscriptHistoryStore.add` after the transcript row durably saved, so
    /// aggregates never outrun the history they summarize.
    func record(words: Int, recordingMs: Int?, fillersRemoved: Int, on date: Date = Date()) {
        let record = fetchOrCreate(for: date)
        record.words += words
        record.dictations += 1
        record.longestDictationMs = max(record.longestDictationMs, recordingMs ?? 0)
        record.fillerWordsRemoved += fillersRemoved
        record.speakingMs = (record.speakingMs ?? 0) + (recordingMs ?? 0)
        guard saveContext() else { return }
        upsertMirror(Day(dayKey: record.dayKey, day: record.day, words: record.words,
                         dictations: record.dictations,
                         longestDictationMs: record.longestDictationMs,
                         fillerWordsRemoved: record.fillerWordsRemoved,
                         speakingMs: record.speakingMs ?? 0))
    }

    // MARK: - Seeding

    /// One-time backfill from existing transcripts, so the heatmap and records
    /// aren't empty for long-time users on first launch after the upgrade.
    /// Reads the persisted rows (not the published mirror) and follows the
    /// `loadLifetimeWords` gating: only against a durable store, only once the
    /// legacy blob has fully migrated, and the "done" flag lands only after a
    /// successful save — otherwise a later healthy launch retries.
    private func seedFromHistoryIfNeeded() {
        guard isPersistent else { return }
        guard defaults.object(forKey: seededKey) == nil else { return }
        guard defaults.data(forKey: legacyHistoryKey) == nil else { return }

        let entries: [TranscriptHistoryStore.Entry]
        do {
            entries = try context.fetch(FetchDescriptor<TranscriptRecord>()).map { $0.toEntry() }
        } catch {
            DebugLog.error("UsageAggregateStore: seed fetch failed — \(error); retrying next launch")
            return
        }

        for entry in entries {
            let record = fetchOrCreate(for: entry.timestamp)
            record.words += entry.wordCount ?? TranscriptHistoryStore.wordCount(entry.text)
            record.dictations += 1
            record.longestDictationMs = max(record.longestDictationMs, entry.recordingMs ?? 0)
            record.speakingMs = (record.speakingMs ?? 0) + (entry.recordingMs ?? 0)
            // Retroactive filler credit where a before→after pair survives.
            if entry.polish == .polished, let original = entry.original {
                record.fillerWordsRemoved += InsightsMath.fillersRemoved(original: original,
                                                                         polished: entry.text)
            }
        }

        guard saveContext() else {
            DebugLog.error("UsageAggregateStore: seed save failed; leaving unseeded to retry next launch")
            return
        }
        defaults.set(true, forKey: seededKey)
        if !entries.isEmpty {
            DebugLog.info("UsageAggregateStore: seeded daily aggregates from \(entries.count) transcript(s)")
        }
    }

    // MARK: - SwiftData plumbing

    private func fetchOrCreate(for date: Date) -> DailyUsageRecord {
        let key = Self.dayKey(for: date)
        var descriptor = FetchDescriptor<DailyUsageRecord>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let record = DailyUsageRecord(dayKey: key,
                                      day: Calendar.current.startOfDay(for: date))
        context.insert(record)
        return record
    }

    private func loadDays() {
        let descriptor = FetchDescriptor<DailyUsageRecord>(
            sortBy: [SortDescriptor(\.day, order: .forward)]
        )
        do {
            days = try context.fetch(descriptor).map {
                Day(dayKey: $0.dayKey, day: $0.day, words: $0.words,
                    dictations: $0.dictations,
                    longestDictationMs: $0.longestDictationMs,
                    fillerWordsRemoved: $0.fillerWordsRemoved,
                    speakingMs: $0.speakingMs ?? 0)
            }
        } catch {
            DebugLog.error("UsageAggregateStore: loading day aggregates failed — \(error)")
            days = []
        }
    }

    private func upsertMirror(_ day: Day) {
        if let i = days.firstIndex(where: { $0.dayKey == day.dayKey }) {
            days[i] = day
        } else {
            days.append(day)
            days.sort { $0.day < $1.day }
        }
    }

    @discardableResult
    private func saveContext() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            DebugLog.error("UsageAggregateStore: save failed — \(error)")
            return false
        }
    }

    // MARK: - Day keys

    /// Nonisolated (lives in `InsightsMath`) so the pure analytics functions
    /// can key days without hopping onto the main actor.
    static func dayKey(for date: Date) -> String {
        InsightsMath.dayKey(for: date)
    }
}
