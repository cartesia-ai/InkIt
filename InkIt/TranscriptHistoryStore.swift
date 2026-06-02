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
    }

    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [Entry] = []
    private let limit = 50
    private let defaults = UserDefaults.standard
    private let storageKey = "transcriptHistory.v1"

    private init() {
        load()
    }

    func add(_ text: String, original: String? = nil, latency: Latency? = nil, polish: PolishOutcome? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(Entry(text: trimmed, timestamp: Date(), latency: latency, original: original, polish: polish), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
