import Foundation
import Combine

@MainActor
final class TranscriptHistoryStore: ObservableObject {
    /// Per-stage wall-clock latency for a single dictation, measured from the
    /// moment the user releases the hotkey. `transcribe` is release → final
    /// transcript, `polish` is the AI rewrite (≈0 when correction is off), and
    /// `paste` is insertion into the target app.
    struct Latency: Equatable, Codable {
        let transcribeMs: Int
        let polishMs: Int
        let pasteMs: Int
        var totalMs: Int { transcribeMs + polishMs + pasteMs }
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
    /// Running total of every word ever dictated — survives the 100-entry history
    /// cap so the Home stats ("words dictated", "time saved") reflect lifetime
    /// usage rather than just the last 100 takes. Seeded from existing history on
    /// first run after this shipped, then incremented per dictation.
    @Published private(set) var lifetimeWords: Int = 0
    private let limit = 100
    private let defaults = UserDefaults.standard
    private let storageKey = "transcriptHistory.v1"
    private let lifetimeWordsKey = "transcriptHistory.lifetimeWords.v1"

    private init() {
        load()
    }

    func add(_ text: String, original: String? = nil, latency: Latency? = nil, polish: PolishOutcome? = nil, failure: PolishFailure? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(Entry(text: trimmed, timestamp: Date(), latency: latency, original: original, polish: polish, failure: failure), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        lifetimeWords += Self.wordCount(trimmed)
        persist()
    }

    /// Whitespace-delimited word count. Good enough for a usage stat — not a
    /// linguistic tokenizer.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        // Seed the lifetime counter once: if it has never been written, estimate
        // it from whatever history we still have on disk. After that the stored
        // value is authoritative and only grows via `add`.
        if defaults.object(forKey: lifetimeWordsKey) == nil {
            lifetimeWords = entries.reduce(0) { $0 + Self.wordCount($1.text) }
            defaults.set(lifetimeWords, forKey: lifetimeWordsKey)
        } else {
            lifetimeWords = defaults.integer(forKey: lifetimeWordsKey)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
        defaults.set(lifetimeWords, forKey: lifetimeWordsKey)
    }
}
