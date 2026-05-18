import Foundation
import Combine

@MainActor
final class TranscriptHistoryStore: ObservableObject {
    struct Entry: Identifiable, Equatable, Codable {
        var id = UUID()
        let text: String
        let timestamp: Date
    }

    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [Entry] = []
    private let limit = 50
    private let defaults = UserDefaults.standard
    private let storageKey = "transcriptHistory.v1"

    private init() {
        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(Entry(text: trimmed, timestamp: Date()), at: 0)
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
