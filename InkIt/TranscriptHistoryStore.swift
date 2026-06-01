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

    struct Entry: Identifiable, Equatable, Codable {
        var id = UUID()
        let text: String
        let timestamp: Date
        // Optional so v1 entries persisted before latency tracking still decode.
        var latency: Latency?
        // The raw pre-rewrite transcript. Set only when AI correction was
        // enabled and actually changed the text, so the UI can show a
        // before/after diff. `nil` means no rewrite was applied (or it was a
        // no-op), and there's nothing to compare.
        var original: String?
    }

    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [Entry] = []
    private let limit = 50
    private let defaults = UserDefaults.standard
    private let storageKey = "transcriptHistory.v1"

    private init() {
        load()
    }

    func add(_ text: String, original: String? = nil, latency: Latency? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(Entry(text: trimmed, timestamp: Date(), latency: latency, original: original), at: 0)
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
