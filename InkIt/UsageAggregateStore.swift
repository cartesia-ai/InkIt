import Foundation
import Combine
import SwiftData

@Model
final class DailyUsageRecord {
    @Attribute(.unique) var dayKey: String
    var day: Date
    var words: Int
    var dictations: Int
    var longestDictationMs: Int
    var fillerWordsRemoved: Int
    var speakingMs: Int?
    var spokenWords: Int?

    init(dayKey: String, day: Date, words: Int = 0, dictations: Int = 0,
         longestDictationMs: Int = 0, fillerWordsRemoved: Int = 0,
         speakingMs: Int = 0, spokenWords: Int = 0) {
        self.dayKey = dayKey
        self.day = day
        self.words = words
        self.dictations = dictations
        self.longestDictationMs = longestDictationMs
        self.fillerWordsRemoved = fillerWordsRemoved
        self.speakingMs = speakingMs
        self.spokenWords = spokenWords
    }
}

@MainActor
final class UsageAggregateStore: ObservableObject {
    struct Day: Equatable, Identifiable {
        var id: String { dayKey }
        let dayKey: String
        let day: Date
        var words: Int
        var dictations: Int
        var longestDictationMs: Int
        var fillerWordsRemoved: Int
        var speakingMs: Int
        var spokenWords: Int
    }

    static let shared = UsageAggregateStore(
        container: TranscriptHistoryStore.shared.modelContainer,
        isPersistent: TranscriptHistoryStore.shared.isPersistent
    )

    @Published private(set) var days: [Day] = []

    private let container: ModelContainer
    private let isPersistent: Bool
    private var context: ModelContext { container.mainContext }
    private let defaults: UserDefaults
    private let seededKey = "usageAggregates.seeded.v1"
    private let legacyHistoryKey = "transcriptHistory.v1"

    init(container: ModelContainer, isPersistent: Bool, defaults: UserDefaults = .standard) {
        self.container = container
        self.isPersistent = isPersistent
        self.defaults = defaults
        seedFromHistoryIfNeeded()
        loadDays()
    }

    func record(words: Int, recordingMs: Int?, fillersRemoved: Int, on date: Date = Date()) {
        let record = fetchOrCreate(for: date)
        record.words += words
        record.dictations += 1
        record.longestDictationMs = max(record.longestDictationMs, recordingMs ?? 0)
        record.fillerWordsRemoved += fillersRemoved
        record.speakingMs = (record.speakingMs ?? 0) + (recordingMs ?? 0)
        if let ms = recordingMs, ms > 0 {
            record.spokenWords = (record.spokenWords ?? 0) + words
        }
        guard saveContext() else { return }
        upsertMirror(Day(dayKey: record.dayKey, day: record.day, words: record.words,
                         dictations: record.dictations,
                         longestDictationMs: record.longestDictationMs,
                         fillerWordsRemoved: record.fillerWordsRemoved,
                         speakingMs: record.speakingMs ?? 0,
                         spokenWords: record.spokenWords ?? 0))
    }

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
            let words = entry.wordCount ?? TranscriptHistoryStore.wordCount(entry.text)
            record.words += words
            record.dictations += 1
            record.longestDictationMs = max(record.longestDictationMs, entry.recordingMs ?? 0)
            record.speakingMs = (record.speakingMs ?? 0) + (entry.recordingMs ?? 0)
            if let ms = entry.recordingMs, ms > 0 {
                record.spokenWords = (record.spokenWords ?? 0) + words
            }
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
                    speakingMs: $0.speakingMs ?? 0,
                    spokenWords: $0.spokenWords ?? 0)
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

    static func dayKey(for date: Date) -> String {
        InsightsMath.dayKey(for: date)
    }
}
