import Foundation
import Combine
import SwiftData

@MainActor
final class TranscriptHistoryStore: ObservableObject {
    struct Latency: Equatable, Codable {
        let transcribeMs: Int
        let polishMs: Int
        let pasteMs: Int
        var totalMs: Int { transcribeMs + polishMs }
    }

    /// Whether AI correction ran for a transcript, and how it turned out.
    /// Persisted so the history row can show the right indicator. `nil` on
    /// entries written before this was tracked; the UI then falls back to
    /// `original != nil` to decide whether to show the polished mark.
    enum PolishOutcome: String, Codable {
        case off       // correction disabled, no key, or skipped — no indicator
        case polished  // ran and succeeded (text may or may not have changed)
        case failed    // ran but errored (e.g. rate limit) — raw text pasted
    }

    /// Why a `.failed` polish failed, so the history row can show a concise,
    /// actionable reason instead of a generic warning.
    enum PolishFailureReason: String, Codable {
        case rateLimited   // provider 429
        case offline       // no network / can't reach host
        case timedOut      // request exceeded the rewrite timeout
        case invalidKey    // 401/403 or missing key
        case outOfCredits  // provider 402 / billing limit reached
        case serverError   // provider 5xx
        case unknown       // parse error, sanity reject, anything else
    }

    /// Details attached to a `.failed` outcome, used to build the warning
    /// tooltip. Optional on the entry so older entries still decode.
    struct PolishFailure: Equatable, Codable {
        let reason: PolishFailureReason
        /// Display name of the provider that failed (e.g. "Groq").
        let provider: String
        /// For rate limits: the absolute time after which a retry is sensible
        /// (from the Retry-After header). nil when not applicable/known.
        var retryAt: Date?
    }

    struct Entry: Identifiable, Equatable, Codable {
        var id = UUID()
        let text: String
        let timestamp: Date
        var latency: Latency?
        var original: String?
        var polish: PolishOutcome?
        var failure: PolishFailure?
        var appName: String?
        var appBundleID: String?
        var wordCount: Int?
        var recordingMs: Int?
    }

    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var lifetimeWords: Int = 0

    let modelContainer: ModelContainer
    private var context: ModelContext { modelContainer.mainContext }
    let isPersistent: Bool

    private let defaults = UserDefaults.standard
    private let legacyStorageKey = "transcriptHistory.v1"
    private let lifetimeWordsKey = "transcriptHistory.lifetimeWords.v1"

    private init() {
        let store = Self.makeContainer()
        modelContainer = store.container
        isPersistent = store.isPersistent
        migrateLegacyHistoryIfNeeded()
        loadEntries()
        loadLifetimeWords()
    }

    func add(_ text: String, original: String? = nil, latency: Latency? = nil,
             polish: PolishOutcome? = nil, failure: PolishFailure? = nil,
             appName: String? = nil, appBundleID: String? = nil,
             recordingMs: Int? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = Entry(text: trimmed, timestamp: Date(), latency: latency,
                          original: original, polish: polish, failure: failure,
                          appName: appName, appBundleID: appBundleID,
                          wordCount: Self.wordCount(trimmed), recordingMs: recordingMs)
        context.insert(TranscriptRecord(entry: entry))
        let saved = saveContext()
        entries.insert(entry, at: 0)
        if isPersistent && saved {
            lifetimeWords += Self.wordCount(trimmed)
            persistLifetimeWords()
            let fillers = (polish == .polished && original != nil)
                ? InsightsMath.fillersRemoved(original: original ?? "", polished: trimmed)
                : 0
            UsageAggregateStore.shared.record(words: entry.wordCount ?? 0,
                                              recordingMs: recordingMs,
                                              fillersRemoved: fillers,
                                              on: entry.timestamp)
        }
    }

    nonisolated static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    func clear() {
        do {
            try context.delete(model: TranscriptRecord.self)
        } catch {
            DebugLog.error("TranscriptHistoryStore: clear failed — \(error)")
            return
        }
        guard saveContext() else { return }
        entries.removeAll()
    }

    private static func makeContainer() -> (container: ModelContainer, isPersistent: Bool) {
        let schema = Schema([TranscriptRecord.self, DailyUsageRecord.self])
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
            return (container, true)
        } catch {
            DebugLog.error("TranscriptHistoryStore: on-disk SwiftData store unavailable (\(error)); using a non-persisting in-memory store for this session")
            let container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            return (container, false)
        }
    }

    private func loadEntries() {
        let descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            entries = try context.fetch(descriptor).map { $0.toEntry() }
        } catch {
            DebugLog.error("TranscriptHistoryStore: loading transcripts failed — \(error)")
            entries = []
        }
    }

    @discardableResult
    private func saveContext() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            DebugLog.error("TranscriptHistoryStore: save failed — \(error)")
            return false
        }
    }

    private func migrateLegacyHistoryIfNeeded() {
        guard isPersistent else { return }
        guard let data = defaults.data(forKey: legacyStorageKey) else { return }
        guard let legacy = try? JSONDecoder().decode([Entry].self, from: data) else {
            DebugLog.error("TranscriptHistoryStore: legacy history present but could not be decoded; left in place")
            return
        }
        let existingIDs: Set<UUID>
        do {
            existingIDs = Set(try context.fetch(FetchDescriptor<TranscriptRecord>()).map(\.id))
        } catch {
            DebugLog.error("TranscriptHistoryStore: could not read existing rows for migration (\(error)); leaving legacy blob in place")
            return
        }
        let missing = legacy.filter { !existingIDs.contains($0.id) }
        for entry in missing {
            context.insert(TranscriptRecord(entry: entry))
        }
        guard saveContext() else {
            DebugLog.error("TranscriptHistoryStore: legacy migration save failed; leaving the UserDefaults blob in place to retry next launch")
            return
        }
        defaults.removeObject(forKey: legacyStorageKey)
        if !missing.isEmpty {
            DebugLog.info("TranscriptHistoryStore: migrated \(missing.count) transcript(s) from UserDefaults to SwiftData")
        }
    }

    private func loadLifetimeWords() {
        if defaults.object(forKey: lifetimeWordsKey) != nil {
            lifetimeWords = defaults.integer(forKey: lifetimeWordsKey)
            return
        }
        lifetimeWords = entries.reduce(0) { $0 + Self.wordCount($1.text) }
        if isPersistent && defaults.data(forKey: legacyStorageKey) == nil {
            defaults.set(lifetimeWords, forKey: lifetimeWordsKey)
        }
    }

    private func persistLifetimeWords() {
        defaults.set(lifetimeWords, forKey: lifetimeWordsKey)
    }
}

@Model
final class TranscriptRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var timestamp: Date
    var latency: TranscriptHistoryStore.Latency?
    var original: String?
    var polish: TranscriptHistoryStore.PolishOutcome?
    var failure: TranscriptHistoryStore.PolishFailure?
    var appName: String?
    var appBundleID: String?
    var wordCount: Int?
    var recordingMs: Int?

    init(id: UUID,
         text: String,
         timestamp: Date,
         latency: TranscriptHistoryStore.Latency?,
         original: String?,
         polish: TranscriptHistoryStore.PolishOutcome?,
         failure: TranscriptHistoryStore.PolishFailure?,
         appName: String? = nil,
         appBundleID: String? = nil,
         wordCount: Int? = nil,
         recordingMs: Int? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.latency = latency
        self.original = original
        self.polish = polish
        self.failure = failure
        self.appName = appName
        self.appBundleID = appBundleID
        self.wordCount = wordCount
        self.recordingMs = recordingMs
    }

    convenience init(entry: TranscriptHistoryStore.Entry) {
        self.init(id: entry.id, text: entry.text, timestamp: entry.timestamp,
                  latency: entry.latency, original: entry.original,
                  polish: entry.polish, failure: entry.failure,
                  appName: entry.appName, appBundleID: entry.appBundleID,
                  wordCount: entry.wordCount, recordingMs: entry.recordingMs)
    }

    func toEntry() -> TranscriptHistoryStore.Entry {
        TranscriptHistoryStore.Entry(id: id, text: text, timestamp: timestamp,
                                     latency: latency, original: original,
                                     polish: polish, failure: failure,
                                     appName: appName, appBundleID: appBundleID,
                                     wordCount: wordCount, recordingMs: recordingMs)
    }
}
