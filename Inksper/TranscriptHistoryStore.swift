import Foundation
import Combine

@MainActor
final class TranscriptHistoryStore: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let timestamp: Date
    }

    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [Entry] = []
    private let limit = 20

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(Entry(text: trimmed, timestamp: Date()), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    func clear() { entries.removeAll() }
}
