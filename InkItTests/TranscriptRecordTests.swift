import XCTest
import SwiftData
@testable import InkIt

/// Locks the SwiftData persistence contract for transcript rows: the `Entry`
/// value type the UI consumes maps 1:1 to the on-disk `TranscriptRecord`, and
/// every field — including the `Codable` nested value types (`Latency`,
/// `PolishOutcome`, `PolishFailure`) SwiftData stores as composite attributes —
/// survives an insert/fetch round trip unchanged. That round trip is the
/// migration's riskiest assumption, so it is pinned here against an in-memory
/// store (no disk, no singleton, no global state).
@MainActor
final class TranscriptRecordTests: XCTestCase {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([TranscriptRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testPolishedRecordRoundTripsAllFields() throws {
        let context = try makeInMemoryContext()
        let entry = TranscriptHistoryStore.Entry(
            text: "hello world",
            timestamp: Date(timeIntervalSince1970: 1_699_000_000),
            latency: .init(transcribeMs: 120, polishMs: 80, pasteMs: 30),
            original: "helo world",
            polish: .polished,
            failure: nil
        )
        context.insert(TranscriptRecord(entry: entry))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TranscriptRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.toEntry(), entry,
                       "every field must survive the SwiftData round trip unchanged")
    }

    func testFailedRecordRoundTripsFailureDetails() throws {
        let context = try makeInMemoryContext()
        let entry = TranscriptHistoryStore.Entry(
            text: "raw words",
            timestamp: Date(timeIntervalSince1970: 1_699_500_000),
            latency: .init(transcribeMs: 200, polishMs: 0, pasteMs: 10),
            original: nil,
            polish: .failed,
            failure: .init(reason: .rateLimited, provider: "Groq",
                           retryAt: Date(timeIntervalSince1970: 1_700_000_000))
        )
        context.insert(TranscriptRecord(entry: entry))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TranscriptRecord>()).first
        XCTAssertEqual(fetched?.toEntry(), entry)
        XCTAssertEqual(fetched?.failure?.reason, .rateLimited,
                       "the Codable failure enum must persist as a composite attribute")
    }

    /// Legacy entries carry no latency/polish/failure; nil-valued optionals must
    /// round-trip too (the v1 decode path produces these).
    func testMinimalRecordRoundTrips() throws {
        let context = try makeInMemoryContext()
        let entry = TranscriptHistoryStore.Entry(
            text: "just text",
            timestamp: Date(timeIntervalSince1970: 1_698_000_000),
            latency: nil, original: nil, polish: nil, failure: nil
        )
        context.insert(TranscriptRecord(entry: entry))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<TranscriptRecord>()).first?.toEntry(), entry)
    }

    func testIDIsPreservedThroughMapping() {
        let entry = TranscriptHistoryStore.Entry(
            text: "keep my id",
            timestamp: Date(),
            latency: nil, original: nil, polish: .off, failure: nil
        )
        let record = TranscriptRecord(entry: entry)
        XCTAssertEqual(record.id, entry.id)
        XCTAssertEqual(record.toEntry().id, entry.id,
                       "id must be stable through Entry -> record -> Entry")
    }

    func testFetchSortsNewestFirst() throws {
        let context = try makeInMemoryContext()
        let older = TranscriptHistoryStore.Entry(
            text: "older", timestamp: Date(timeIntervalSince1970: 1_000),
            latency: nil, original: nil, polish: nil, failure: nil
        )
        let newer = TranscriptHistoryStore.Entry(
            text: "newer", timestamp: Date(timeIntervalSince1970: 2_000),
            latency: nil, original: nil, polish: nil, failure: nil
        )
        context.insert(TranscriptRecord(entry: older))
        context.insert(TranscriptRecord(entry: newer))
        try context.save()

        let descriptor = FetchDescriptor<TranscriptRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        XCTAssertEqual(try context.fetch(descriptor).map(\.text), ["newer", "older"])
    }
}
