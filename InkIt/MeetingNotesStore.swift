import Foundation
import Combine
import SwiftData

@MainActor
final class MeetingNotesStore: ObservableObject {
    struct Note: Identifiable, Equatable, Codable {
        var id = UUID()
        var title: String
        let createdAt: Date
        var summary: String?
        var transcript: String?
    }

    static let shared = MeetingNotesStore()

    @Published private(set) var notes: [Note] = []

    let modelContainer: ModelContainer
    private var context: ModelContext { modelContainer.mainContext }
    let isPersistent: Bool

    private init() {
        let store = Self.makeContainer()
        modelContainer = store.container
        isPersistent = store.isPersistent
        loadNotes()
    }

    private static func makeContainer() -> (container: ModelContainer, isPersistent: Bool) {
        let schema = Schema([MeetingNoteRecord.self])
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
            return (container, true)
        } catch {
            DebugLog.error("MeetingNotesStore: on-disk SwiftData store unavailable (\(error)); using a non-persisting in-memory store for this session")
            let container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            return (container, false)
        }
    }

    private func loadNotes() {
        let descriptor = FetchDescriptor<MeetingNoteRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            notes = try context.fetch(descriptor).map { $0.toNote() }
        } catch {
            DebugLog.error("MeetingNotesStore: loading notes failed — \(error)")
            notes = []
        }
    }
}

@Model
final class MeetingNoteRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var summary: String?
    var transcript: String?

    init(id: UUID, title: String, createdAt: Date, summary: String?, transcript: String?) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.summary = summary
        self.transcript = transcript
    }

    convenience init(note: MeetingNotesStore.Note) {
        self.init(id: note.id, title: note.title, createdAt: note.createdAt,
                  summary: note.summary, transcript: note.transcript)
    }

    func toNote() -> MeetingNotesStore.Note {
        MeetingNotesStore.Note(id: id, title: title, createdAt: createdAt,
                               summary: summary, transcript: transcript)
    }
}
