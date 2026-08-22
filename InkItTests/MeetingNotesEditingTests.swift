import XCTest
import SwiftData
@testable import InkIt

@MainActor
final class MeetingNotesEditingTests: XCTestCase {

    // MARK: - EditCoordinator: exactly one field editable at a time

    func testRequestEditSavesPreviousFieldBeforeActivatingNew() {
        let coordinator = EditCoordinator()
        let fieldA = UUID()
        let fieldB = UUID()
        var savedA = false

        coordinator.requestEdit(fieldA, saveAndClose: { savedA = true })
        XCTAssertEqual(coordinator.activeFieldID, fieldA)
        XCTAssertFalse(savedA)

        coordinator.requestEdit(fieldB, saveAndClose: {})
        XCTAssertTrue(savedA, "activating a second field must save-and-close the first")
        XCTAssertEqual(coordinator.activeFieldID, fieldB)
    }

    func testRequestEditOnSameFieldDoesNotResave() {
        let coordinator = EditCoordinator()
        let field = UUID()
        var saveCount = 0

        coordinator.requestEdit(field, saveAndClose: { saveCount += 1 })
        coordinator.requestEdit(field, saveAndClose: { saveCount += 1 })
        XCTAssertEqual(saveCount, 0, "re-requesting the already-active field must not trigger its own save")
    }

    func testResignEditOnlyClearsMatchingField() {
        let coordinator = EditCoordinator()
        let fieldA = UUID()
        coordinator.requestEdit(fieldA, saveAndClose: {})

        coordinator.resignEdit(UUID())
        XCTAssertEqual(coordinator.activeFieldID, fieldA, "resigning a different id must be a no-op")

        coordinator.resignEdit(fieldA)
        XCTAssertNil(coordinator.activeFieldID)
    }

    // MARK: - SwiftData persistence: summaryLines round trip + backward compatibility

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([MeetingNoteRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testSummaryLinesRoundTripThroughSwiftData() throws {
        let context = try makeInMemoryContext()
        let overview = MeetingNotesStore.SummaryLine(text: "Discussed Q3 roadmap", isActionItem: false)
        let actionItem = MeetingNotesStore.SummaryLine(text: "Jan: send the deck", isActionItem: true)
        let note = MeetingNotesStore.Note(title: "Planning sync", createdAt: Date(),
                                          summary: "Discussed Q3 roadmap", summaryLines: [overview, actionItem],
                                          transcript: "Jan: let's plan Q3", lines: [], speakers: [])
        context.insert(MeetingNoteRecord(note: note))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MeetingNoteRecord>()).first
        XCTAssertEqual(fetched?.toNote().summaryLines, [overview, actionItem])
    }

    func testOldShapeRecordWithoutSummaryLinesFallsBackToFlatSummary() throws {
        let context = try makeInMemoryContext()
        let legacyRecord = MeetingNoteRecord(id: UUID(), title: "Old meeting", createdAt: Date(),
                                             summary: "Plain markdown summary text", transcript: "Me: hello")
        context.insert(legacyRecord)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MeetingNoteRecord>()).first?.toNote()
        XCTAssertEqual(fetched?.summary, "Plain markdown summary text")
        XCTAssertEqual(fetched?.summaryLines, [],
                       "an old-shape note must decode with empty summaryLines so the detail view falls back to read-only rendering")
    }

    // MARK: - Multi-level undo/redo via UndoManager's recursive re-registration idiom
    private final class Counter {
        let undoManager = UndoManager()
        private(set) var value: Int

        init(_ value: Int) {
            self.value = value
            undoManager.groupsByEvent = false
        }

        func set(_ newValue: Int, previous: Int) {
            guard newValue != previous else { return }
            value = newValue
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self) { $0.set(previous, previous: newValue) }
            undoManager.endUndoGrouping()
        }
    }

    func testUndoManagerRecursivePatternSupportsMultiLevelUndoAndRedo() {
        let counter = Counter(0)
        counter.set(1, previous: 0)
        counter.set(2, previous: 1)
        counter.set(3, previous: 2)
        XCTAssertEqual(counter.value, 3)

        counter.undoManager.undo()
        XCTAssertEqual(counter.value, 2)
        counter.undoManager.undo()
        XCTAssertEqual(counter.value, 1)
        counter.undoManager.undo()
        XCTAssertEqual(counter.value, 0)
        XCTAssertFalse(counter.undoManager.canUndo)

        counter.undoManager.redo()
        XCTAssertEqual(counter.value, 1)
        counter.undoManager.redo()
        XCTAssertEqual(counter.value, 2)

        counter.set(9, previous: 2)
        XCTAssertEqual(counter.value, 9)
        counter.undoManager.undo()
        XCTAssertEqual(counter.value, 2)
    }
}
