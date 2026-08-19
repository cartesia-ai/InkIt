import Foundation
import Combine
import SwiftData

@MainActor
final class MeetingNotesStore: ObservableObject {
    struct Speaker: Identifiable, Equatable, Codable {
        var id = UUID()
        var label: String
        var displayName: String?

        var displayLabel: String { displayName ?? label }

        static let unknownID = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!
    }

    struct TranscriptLine: Identifiable, Equatable, Codable {
        var id = UUID()
        var speakerID: UUID
        var text: String
        var legacyLabel: String?

        init(id: UUID = UUID(), speakerID: UUID, text: String) {
            self.id = id
            self.speakerID = speakerID
            self.text = text
            self.legacyLabel = nil
        }

        private enum CodingKeys: String, CodingKey {
            case id, speakerID, text, speaker
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            text = try container.decode(String.self, forKey: .text)
            if let speakerID = try container.decodeIfPresent(UUID.self, forKey: .speakerID) {
                self.speakerID = speakerID
                legacyLabel = nil
            } else {
                legacyLabel = try container.decode(String.self, forKey: .speaker)
                speakerID = UUID()
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(speakerID, forKey: .speakerID)
            try container.encode(text, forKey: .text)
        }
    }

    struct SummaryLine: Identifiable, Equatable, Codable {
        var id = UUID()
        var text: String
        var isActionItem: Bool
    }

    struct Note: Identifiable, Equatable, Codable {
        var id = UUID()
        var title: String
        let createdAt: Date
        var summary: String?
        var summaryLines: [SummaryLine] = []
        var transcript: String?
        var lines: [TranscriptLine] = []
        var speakers: [Speaker] = []

        func displayName(for speakerID: UUID) -> String {
            if speakerID == Speaker.unknownID { return "Unknown" }
            return speakers.first(where: { $0.id == speakerID })?.displayLabel ?? "Unknown"
        }

        mutating func promotingLegacySpeakersIfNeeded() {
            guard speakers.isEmpty, lines.contains(where: { $0.legacyLabel != nil }) else { return }
            var idByLabel: [String: UUID] = [:]
            var derived: [Speaker] = []
            for index in lines.indices {
                guard let label = lines[index].legacyLabel else { continue }
                let speakerID = idByLabel[label] ?? {
                    let newID = UUID()
                    idByLabel[label] = newID
                    derived.append(Speaker(id: newID, label: label, displayName: nil))
                    return newID
                }()
                lines[index].speakerID = speakerID
                lines[index].legacyLabel = nil
            }
            speakers = derived
        }
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
                configurations: ModelConfiguration(schema: schema, url: storeURL())
            )
            return (container, true)
        } catch {
            let container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            return (container, false)
        }
    }

    private static func storeURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.cartesia.InkIt"
        guard bundleID != "ai.cartesia.InkIt" else {
            return appSupport.appendingPathComponent("default.store")
        }
        let scopedDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: scopedDir, withIntermediateDirectories: true)
        return scopedDir.appendingPathComponent("MeetingNotes.store")
    }

    private func loadNotes() {
        let descriptor = FetchDescriptor<MeetingNoteRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            notes = try context.fetch(descriptor).map {
                var note = $0.toNote()
                note.promotingLegacySpeakersIfNeeded()
                return note
            }
        } catch {
            notes = []
        }
    }

    @discardableResult
    func createNote(transcript: String, lines: [TranscriptLine] = [], speakers: [Speaker] = [],
                    summary: String? = nil, summaryLines: [SummaryLine] = [], title: String? = nil) -> Note {
        let note = Note(title: title ?? Self.defaultTitle(),
                        createdAt: Date(),
                        summary: summary,
                        summaryLines: summaryLines,
                        transcript: transcript,
                        lines: lines,
                        speakers: speakers)
        context.insert(MeetingNoteRecord(note: note))
        saveContext()
        notes.insert(note, at: 0)
        return note
    }

    func updateSummary(id: UUID, summary: String, summaryLines: [SummaryLine] = []) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].summary = summary
        notes[index].summaryLines = summaryLines
        guard let record = record(id: id) else { return }
        record.summary = summary
        record.summaryLines = summaryLines
        saveContext()
    }

    func updateTitle(id: UUID, title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].title = title
        let descriptor = FetchDescriptor<MeetingNoteRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first else { return }
        record.title = title
        saveContext()
    }

    func updateSummaryLine(noteID: UUID, lineID: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }),
              let lineIndex = notes[index].summaryLines.firstIndex(where: { $0.id == lineID }) else { return }
        notes[index].summaryLines[lineIndex].text = text
        guard let record = record(id: noteID) else { return }
        record.summaryLines = notes[index].summaryLines
        saveContext()
    }

    func updateLineText(noteID: UUID, lineID: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }),
              let lineIndex = notes[index].lines.firstIndex(where: { $0.id == lineID }) else { return }
        notes[index].lines[lineIndex].text = text
        guard let record = record(id: noteID) else { return }
        record.lines = notes[index].lines
        saveContext()
    }

    @discardableResult
    func deleteSummaryLine(noteID: UUID, lineID: UUID) -> (line: SummaryLine, index: Int)? {
        guard let index = notes.firstIndex(where: { $0.id == noteID }),
              let lineIndex = notes[index].summaryLines.firstIndex(where: { $0.id == lineID }) else { return nil }
        let line = notes[index].summaryLines.remove(at: lineIndex)
        guard let record = record(id: noteID) else { return (line, lineIndex) }
        record.summaryLines = notes[index].summaryLines
        saveContext()
        return (line, lineIndex)
    }

    func insertSummaryLine(noteID: UUID, line: SummaryLine, at index: Int) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let clamped = min(index, notes[noteIndex].summaryLines.count)
        notes[noteIndex].summaryLines.insert(line, at: clamped)
        guard let record = record(id: noteID) else { return }
        record.summaryLines = notes[noteIndex].summaryLines
        saveContext()
    }

    @discardableResult
    func deleteTranscriptLine(noteID: UUID, lineID: UUID) -> (line: TranscriptLine, index: Int)? {
        guard let index = notes.firstIndex(where: { $0.id == noteID }),
              let lineIndex = notes[index].lines.firstIndex(where: { $0.id == lineID }) else { return nil }
        let line = notes[index].lines.remove(at: lineIndex)
        guard let record = record(id: noteID) else { return (line, lineIndex) }
        record.lines = notes[index].lines
        saveContext()
        return (line, lineIndex)
    }

    func insertTranscriptLine(noteID: UUID, line: TranscriptLine, at index: Int) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let clamped = min(index, notes[noteIndex].lines.count)
        notes[noteIndex].lines.insert(line, at: clamped)
        guard let record = record(id: noteID) else { return }
        record.lines = notes[noteIndex].lines
        saveContext()
    }

    func reassignLine(noteID: UUID, lineID: UUID, speakerID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }),
              let lineIndex = notes[index].lines.firstIndex(where: { $0.id == lineID }) else { return }
        notes[index].lines[lineIndex].speakerID = speakerID
        guard let record = record(id: noteID) else { return }
        record.lines = notes[index].lines
        saveContext()
    }

    @discardableResult
    func addSpeaker(noteID: UUID, label: String) -> Speaker {
        let speaker = Speaker(label: label, displayName: nil)
        insertSpeaker(noteID: noteID, speaker: speaker)
        return speaker
    }

    func insertSpeaker(noteID: UUID, speaker: Speaker) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].speakers.append(speaker)
        guard let record = record(id: noteID) else { return }
        record.speakers = notes[index].speakers
        saveContext()
    }

    func renameSpeaker(noteID: UUID, speakerID: UUID, displayName: String?) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }),
              let speakerIndex = notes[index].speakers.firstIndex(where: { $0.id == speakerID }) else { return }
        notes[index].speakers[speakerIndex].displayName = displayName
        guard let record = record(id: noteID) else { return }
        record.speakers = notes[index].speakers
        saveContext()
    }

    @discardableResult
    func removeSpeaker(noteID: UUID, speakerID: UUID) -> [(lineID: UUID, previousSpeakerID: UUID)] {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return [] }
        var affected: [(lineID: UUID, previousSpeakerID: UUID)] = []
        for lineIndex in notes[index].lines.indices where notes[index].lines[lineIndex].speakerID == speakerID {
            affected.append((notes[index].lines[lineIndex].id, speakerID))
            notes[index].lines[lineIndex].speakerID = Speaker.unknownID
        }
        notes[index].speakers.removeAll { $0.id == speakerID }
        guard let record = record(id: noteID) else { return affected }
        record.lines = notes[index].lines
        record.speakers = notes[index].speakers
        saveContext()
        return affected
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        let descriptor = FetchDescriptor<MeetingNoteRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first else { return }
        context.delete(record)
        saveContext()
    }

    private func record(id: UUID) -> MeetingNoteRecord? {
        let descriptor = FetchDescriptor<MeetingNoteRecord>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func saveContext() {
        try? context.save()
    }

    private static let defaultTitleFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private static func defaultTitle() -> String {
        "Meeting, \(defaultTitleFmt.string(from: Date()))"
    }
}

@Model
final class MeetingNoteRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var summary: String?
    var summaryLines: [MeetingNotesStore.SummaryLine] = []
    var transcript: String?
    var lines: [MeetingNotesStore.TranscriptLine] = []
    var speakers: [MeetingNotesStore.Speaker] = []

    init(id: UUID, title: String, createdAt: Date, summary: String?, transcript: String?,
         summaryLines: [MeetingNotesStore.SummaryLine] = [],
         lines: [MeetingNotesStore.TranscriptLine] = [], speakers: [MeetingNotesStore.Speaker] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.summary = summary
        self.summaryLines = summaryLines
        self.transcript = transcript
        self.lines = lines
        self.speakers = speakers
    }

    convenience init(note: MeetingNotesStore.Note) {
        self.init(id: note.id, title: note.title, createdAt: note.createdAt,
                  summary: note.summary, transcript: note.transcript, summaryLines: note.summaryLines,
                  lines: note.lines, speakers: note.speakers)
    }

    func toNote() -> MeetingNotesStore.Note {
        MeetingNotesStore.Note(id: id, title: title, createdAt: createdAt,
                               summary: summary, summaryLines: summaryLines, transcript: transcript,
                               lines: lines, speakers: speakers)
    }
}
