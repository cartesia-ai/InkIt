import Foundation
import Combine
import SwiftData

@MainActor
final class TranscriptHistoryStore: ObservableObject {
    /// Per-stage wall-clock latency for a single dictation, measured from the
    /// moment the user releases the hotkey. `transcribe` is release → final
    /// transcript, `polish` is the AI rewrite (≈0 when correction is off), and
    /// `paste` is insertion into the target app.
    ///
    /// `paste` is still recorded (for diagnostics) but deliberately left out of
    /// `totalMs` and the user-facing breakdown: it's a near-constant fixed floor
    /// the user can't influence, so surfacing it only added noise. The total the
    /// user sees reflects the two stages that actually vary — transcribe + polish.
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
        // Optional so v1 entries persisted before latency tracking still decode.
        var latency: Latency?
        // The raw pre-rewrite transcript, kept whenever AI correction ran
        // successfully so the UI can show a before/after diff — identical to
        // `text` when the rewrite was a no-op. `nil` when correction didn't run
        // (off) or failed.
        var original: String?
        // Outcome of AI correction; drives the row indicator. `nil` on legacy
        // entries (see PolishOutcome).
        var polish: PolishOutcome?
        // Why polish failed, when `polish == .failed`. `nil` for success/off and
        // for entries written before failure reasons were tracked.
        var failure: PolishFailure?
    }

    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [Entry] = []
    /// Running total of every word ever dictated. Kept as its own counter so the
    /// Home stats ("words dictated", "time saved") reflect lifetime usage even
    /// after the user clears their history — Delete All wipes the rows but not
    /// this. Seeded once from existing history, then incremented per dictation.
    @Published private(set) var lifetimeWords: Int = 0

    /// SwiftData container backing the transcript rows. Exposed so the app can
    /// inject it into the SwiftUI environment (`.modelContainer`), keeping a
    /// single container available for any future `@Query`-based reads, while the
    /// store itself drives all writes through `context` below.
    let modelContainer: ModelContainer
    private var context: ModelContext { modelContainer.mainContext }
    /// Whether `modelContainer` writes to disk. `false` means we fell back to a
    /// non-persisting in-memory store (the on-disk one couldn't be opened), so
    /// nothing saved this session survives a relaunch. Durable side effects that
    /// must stay in lockstep with stored rows — dropping the legacy migration
    /// blob, advancing the persisted lifetime counter — are gated on this so they
    /// never outrun the transcripts that actually survive a quit.
    private let isPersistent: Bool

    private let defaults = UserDefaults.standard
    /// Legacy UserDefaults blob that held the entire `[Entry]` array as one JSON
    /// value, re-encoded on every write. Migrated into SwiftData once and then
    /// removed. See `migrateLegacyHistoryIfNeeded`.
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

    // MARK: - Public API

    func add(_ text: String, original: String? = nil, latency: Latency? = nil, polish: PolishOutcome? = nil, failure: PolishFailure? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // One row inserted, one row persisted — no cap, and no re-encoding the
        // whole history on every dictation (the UserDefaults bottleneck this
        // replaced). The freshly stamped entry is the newest, so it leads.
        let entry = Entry(text: trimmed, timestamp: Date(), latency: latency,
                          original: original, polish: polish, failure: failure)
        context.insert(TranscriptRecord(entry: entry))
        let saved = saveContext()
        // Reflect the entry in the session's published mirror regardless — that
        // array is rebuilt from storage on every launch, so showing a row that
        // didn't persist only affects this session. The lifetime counter is
        // different: it's written to UserDefaults and read back across launches,
        // so it may only advance when the row durably persisted, otherwise the
        // Home stats would outgrow the transcripts that survive a relaunch.
        entries.insert(entry, at: 0)
        if isPersistent && saved {
            lifetimeWords += Self.wordCount(trimmed)
            persistLifetimeWords()
        }
    }

    /// Whitespace-delimited word count. Good enough for a usage stat — not a
    /// linguistic tokenizer.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    func clear() {
        do {
            try context.delete(model: TranscriptRecord.self)
        } catch {
            DebugLog.error("TranscriptHistoryStore: clear failed — \(error)")
            return
        }
        // Only mirror the wipe in the published array once the deletion is
        // durably persisted. If the save fails the rows remain on disk and would
        // reappear next launch, so leaving the UI populated keeps it honest about
        // what "Delete All" actually removed rather than implying a wipe that
        // didn't stick.
        guard saveContext() else { return }
        entries.removeAll()
        // `lifetimeWords` intentionally survives Delete All.
    }

    // MARK: - SwiftData

    /// Builds the on-disk SwiftData container, falling back to a non-persisting
    /// in-memory store if the on-disk one can't be opened. The fallback keeps
    /// dictation working (and gives the SwiftUI environment a valid container)
    /// for the session rather than crashing or losing the app; an in-memory
    /// store has no disk dependency that can fail.
    private static func makeContainer() -> (container: ModelContainer, isPersistent: Bool) {
        let schema = Schema([TranscriptRecord.self])
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

    /// Loads every stored transcript, newest first, into the published mirror
    /// the UI reads. Sorting in the fetch keeps the in-memory array ordered the
    /// same way `add` maintains it (newest at index 0).
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

    /// Persists pending changes, reporting whether the store is now durable.
    /// Returns `true` when there was nothing to save or the save succeeded;
    /// `false` when SwiftData rejected the write (e.g. a unique-`id` collision).
    /// Callers use the result to gate irreversible follow-ups — dropping the
    /// legacy blob, advancing the lifetime counter — so those never run against
    /// rows that didn't actually land on disk.
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

    /// One-time move of the legacy UserDefaults JSON blob into SwiftData. Merges
    /// by `id` — it imports only the legacy entries SwiftData doesn't already
    /// hold — rather than assuming an empty store means "not yet migrated". A
    /// non-empty store does not prove the blob was imported (new dictations can
    /// persist while an earlier migration save failed), so a blanket "rows exist
    /// ⇒ blob is stale" deletion would drop unmigrated history. The blob is
    /// removed only once every entry it holds is confirmed present in SwiftData.
    /// Deliberately kept for future versions so any upgrade path — including
    /// jumping straight from a pre-SwiftData build — still migrates rather than
    /// silently losing history.
    private func migrateLegacyHistoryIfNeeded() {
        // Never migrate into the non-persisting fallback store: copying the blob
        // into a session-only store and then dropping the UserDefaults key would
        // lose the history on quit. Leaving the key untouched lets the next launch
        // with a healthy on-disk store migrate it for real.
        guard isPersistent else { return }
        guard let data = defaults.data(forKey: legacyStorageKey) else { return }
        guard let legacy = try? JSONDecoder().decode([Entry].self, from: data) else {
            // Unreadable blob: leave it in place rather than discard data we
            // can't parse. Migration simply no-ops until it can be read.
            DebugLog.error("TranscriptHistoryStore: legacy history present but could not be decoded; left in place")
            return
        }
        let existingIDs: Set<UUID>
        do {
            existingIDs = Set(try context.fetch(FetchDescriptor<TranscriptRecord>()).map(\.id))
        } catch {
            // Can't tell what's already stored, so importing risks duplicate-`id`
            // collisions. Leave the blob untouched and retry next launch.
            DebugLog.error("TranscriptHistoryStore: could not read existing rows for migration (\(error)); leaving legacy blob in place")
            return
        }
        let missing = legacy.filter { !existingIDs.contains($0.id) }
        for entry in missing {
            context.insert(TranscriptRecord(entry: entry))
        }
        // Drop the source blob only once everything it held is confirmed present
        // in SwiftData (saved). A failed save keeps the blob for a retry next
        // launch rather than losing the history outright.
        guard saveContext() else {
            DebugLog.error("TranscriptHistoryStore: legacy migration save failed; leaving the UserDefaults blob in place to retry next launch")
            return
        }
        defaults.removeObject(forKey: legacyStorageKey)
        if !missing.isEmpty {
            DebugLog.info("TranscriptHistoryStore: migrated \(missing.count) transcript(s) from UserDefaults to SwiftData")
        }
    }

    /// Seeds the lifetime word counter once from existing history (post-migration),
    /// then treats the stored value as authoritative — it only grows via `add`.
    private func loadLifetimeWords() {
        if defaults.object(forKey: lifetimeWordsKey) == nil {
            lifetimeWords = entries.reduce(0) { $0 + Self.wordCount($1.text) }
            defaults.set(lifetimeWords, forKey: lifetimeWordsKey)
        } else {
            lifetimeWords = defaults.integer(forKey: lifetimeWordsKey)
        }
    }

    private func persistLifetimeWords() {
        defaults.set(lifetimeWords, forKey: lifetimeWordsKey)
    }
}

/// SwiftData persistence record for a single transcript. Kept distinct from the
/// `Entry` value type the UI consumes: `Entry` stays a lightweight
/// `Codable`/`Equatable` struct (so the Home view's grouping/search/sort and the
/// `history.add(...)` callers are unchanged), while this is the durable on-disk
/// shape. The two map 1:1, preserving `id`.
///
/// The nested value types (`Latency`, `PolishOutcome`, `PolishFailure`) are
/// `Codable`, which SwiftData stores as composite attributes — so they are
/// reused verbatim rather than flattened into separate columns.
@Model
final class TranscriptRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var timestamp: Date
    var latency: TranscriptHistoryStore.Latency?
    var original: String?
    var polish: TranscriptHistoryStore.PolishOutcome?
    var failure: TranscriptHistoryStore.PolishFailure?

    init(id: UUID,
         text: String,
         timestamp: Date,
         latency: TranscriptHistoryStore.Latency?,
         original: String?,
         polish: TranscriptHistoryStore.PolishOutcome?,
         failure: TranscriptHistoryStore.PolishFailure?) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.latency = latency
        self.original = original
        self.polish = polish
        self.failure = failure
    }

    convenience init(entry: TranscriptHistoryStore.Entry) {
        self.init(id: entry.id, text: entry.text, timestamp: entry.timestamp,
                  latency: entry.latency, original: entry.original,
                  polish: entry.polish, failure: entry.failure)
    }

    func toEntry() -> TranscriptHistoryStore.Entry {
        TranscriptHistoryStore.Entry(id: id, text: text, timestamp: timestamp,
                                     latency: latency, original: original,
                                     polish: polish, failure: failure)
    }
}
