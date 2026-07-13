import XCTest
import SwiftData
@testable import InkIt

/// Pins the durable daily-aggregate contract: per-day upserts, local-day
/// keying, the one-time seed from existing history, and — the product
/// promise — that a typed Delete All on transcripts leaves the aggregates
/// standing. In-memory containers and an ephemeral defaults suite; no
/// singletons, no disk.
@MainActor
final class UsageAggregateStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "UsageAggregateStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TranscriptRecord.self, DailyUsageRecord.self])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func at(hour: Int, minute: Int = 0, day: Int = 11) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day,
                                                   hour: hour, minute: minute))!
    }

    // MARK: Upserts

    func testSameDayRecordsUpsertIntoOneRow() throws {
        let store = UsageAggregateStore(container: try makeContainer(),
                                        isPersistent: true, defaults: defaults)
        store.record(words: 100, recordingMs: 30_000, fillersRemoved: 2, on: at(hour: 9))
        store.record(words: 50, recordingMs: 90_000, fillersRemoved: 1, on: at(hour: 17))

        XCTAssertEqual(store.days.count, 1)
        let day = try XCTUnwrap(store.days.first)
        XCTAssertEqual(day.words, 150)
        XCTAssertEqual(day.dictations, 2)
        XCTAssertEqual(day.longestDictationMs, 90_000, "longest keeps the max, not the sum")
        XCTAssertEqual(day.fillerWordsRemoved, 3)
        XCTAssertEqual(day.speakingMs, 120_000, "speaking time sums for day-level WPM")
    }

    func testMidnightBoundarySplitsDays() throws {
        let store = UsageAggregateStore(container: try makeContainer(),
                                        isPersistent: true, defaults: defaults)
        store.record(words: 10, recordingMs: nil, fillersRemoved: 0,
                     on: at(hour: 23, minute: 59, day: 10))
        store.record(words: 20, recordingMs: nil, fillersRemoved: 0,
                     on: at(hour: 0, minute: 1, day: 11))

        XCTAssertEqual(store.days.count, 2, "23:59 and 00:01 are different local days")
        XCTAssertEqual(store.days.map(\.words), [10, 20], "days mirror stays oldest-first")
    }

    // MARK: Delete All survival

    func testTranscriptDeleteAllLeavesAggregates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TranscriptRecord(entry: .init(text: "hello there world",
                                                     timestamp: at(hour: 9),
                                                     latency: nil, original: nil,
                                                     polish: nil, failure: nil)))
        try context.save()

        let store = UsageAggregateStore(container: container,
                                        isPersistent: true, defaults: defaults)
        XCTAssertEqual(store.days.first?.words, 3, "seeded from the existing row")

        // The exact wipe TranscriptHistoryStore.clear() performs.
        try context.delete(model: TranscriptRecord.self)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<TranscriptRecord>()).isEmpty)
        let survivors = try context.fetch(FetchDescriptor<DailyUsageRecord>())
        XCTAssertEqual(survivors.count, 1,
                       "the typed delete must not touch DailyUsageRecord — Insights survives Delete All")
        XCTAssertEqual(survivors.first?.words, 3)
    }

    // MARK: Seeding

    func testSeedFoldsHistoryIntoDays() throws {
        let container = try makeContainer()
        let context = container.mainContext
        // A legacy row (no wordCount → counted from text) and a new-style row.
        context.insert(TranscriptRecord(entry: .init(text: "one two three",
                                                     timestamp: at(hour: 9, day: 10),
                                                     latency: nil, original: nil,
                                                     polish: nil, failure: nil)))
        context.insert(TranscriptRecord(entry: .init(text: "um the plan",
                                                     timestamp: at(hour: 15, day: 11),
                                                     latency: nil,
                                                     original: "um so um the plan",
                                                     polish: .polished, failure: nil,
                                                     appName: "Slack", appBundleID: "com.slack",
                                                     wordCount: 3, recordingMs: 42_000)))
        try context.save()

        let store = UsageAggregateStore(container: container,
                                        isPersistent: true, defaults: defaults)
        XCTAssertEqual(store.days.count, 2)
        XCTAssertEqual(store.days.map(\.words), [3, 3])
        XCTAssertEqual(store.days.last?.longestDictationMs, 42_000)
        XCTAssertEqual(store.days.last?.speakingMs, 42_000, "seed backfills speaking time too")
        XCTAssertEqual(store.days.last?.fillerWordsRemoved, 1,
                       "seed retro-computes fillers from the surviving before→after pair (2 um → 1 um)")
    }

    func testSeedIsIdempotentAcrossLaunches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TranscriptRecord(entry: .init(text: "one two", timestamp: at(hour: 9),
                                                     latency: nil, original: nil,
                                                     polish: nil, failure: nil)))
        try context.save()

        let first = UsageAggregateStore(container: container,
                                        isPersistent: true, defaults: defaults)
        XCTAssertEqual(first.days.first?.words, 2)

        // "Second launch" against the same container + defaults: the seeded
        // flag must prevent double-counting.
        let second = UsageAggregateStore(container: container,
                                         isPersistent: true, defaults: defaults)
        XCTAssertEqual(second.days.count, 1)
        XCTAssertEqual(second.days.first?.words, 2, "re-seeding would have doubled this")
    }

    func testSeedWaitsForLegacyBlobMigration() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TranscriptRecord(entry: .init(text: "one two", timestamp: at(hour: 9),
                                                     latency: nil, original: nil,
                                                     polish: nil, failure: nil)))
        try context.save()
        // Un-migrated legacy blob still present → seeding must hold off.
        defaults.set(Data("[]".utf8), forKey: "transcriptHistory.v1")

        let store = UsageAggregateStore(container: container,
                                        isPersistent: true, defaults: defaults)
        XCTAssertTrue(store.days.isEmpty, "seeding while the blob exists would undercount")
        XCTAssertNil(defaults.object(forKey: "usageAggregates.seeded.v1"),
                     "the flag must stay unset so a later launch seeds for real")
    }

    func testSeedSkippedOnNonPersistentStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TranscriptRecord(entry: .init(text: "one two", timestamp: at(hour: 9),
                                                     latency: nil, original: nil,
                                                     polish: nil, failure: nil)))
        try context.save()

        _ = UsageAggregateStore(container: container, isPersistent: false, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "usageAggregates.seeded.v1"),
                     "a session-only store must never mark seeding done")
    }
}
