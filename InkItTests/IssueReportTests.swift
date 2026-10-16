import XCTest
import SwiftData
@testable import InkIt

@MainActor
final class IssueReportTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(ageDays: Double, clipMs: Int?) -> TranscriptHistoryStore.Entry {
        let at = now.addingTimeInterval(-ageDays * 86_400)
        var entry = TranscriptHistoryStore.Entry(text: "hello", timestamp: at)
        entry.diagnostics = DictationDiagnostics(model: "ink-2", rawText: "hello", keyterms: [],
                                                 startedAt: at, clipMs: clipMs)
        return entry
    }

    func testReportableExcludesOldShortAndClipless() {
        let fresh = entry(ageDays: 1, clipMs: 4_000)
        let stale = entry(ageDays: 7, clipMs: 4_000)
        let tooShort = entry(ageDays: 1, clipMs: 100)
        let noClip = entry(ageDays: 1, clipMs: nil)
        let ids = ClipStore.reportableIDs([fresh, stale, tooShort, noClip], now: now)
        XCTAssertEqual(ids, [fresh.id])
    }

    func testRetentionCapsAtKeepCount() {
        let entries = (0..<(ClipStore.keepCount + 5)).map { _ in entry(ageDays: 0.1, clipMs: 1_000) }
        let retained = ClipStore.retainedIDs(entries, now: now)
        XCTAssertEqual(retained, Set(entries.prefix(ClipStore.keepCount).map(\.id)))
    }

    func testDiagnosticsRoundTripThroughSwiftData() throws {
        let schema = Schema([TranscriptRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        var original = entry(ageDays: 0, clipMs: 2_500)
        original.diagnostics?.keyterms = ["Cartesia", "InkIt"]
        original.diagnostics?.requestID = "req_123"
        original.diagnostics?.micTransport = "bluetooth"
        original.reportedAt = now
        context.insert(TranscriptRecord(entry: original))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TranscriptRecord>())
        XCTAssertEqual(fetched.first?.toEntry(), original)
    }

    func testPayloadUsesSnakeCaseAndOmitsEmptyFeedback() throws {
        var source = entry(ageDays: 0, clipMs: 2_000)
        source.diagnostics?.requestID = "req_abc"
        let payload = IssueReportPayload(entry: source,
                                         categories: [.other, .wrongWords],
                                         editedText: "   ")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.json()) as? [String: Any])
        XCTAssertEqual(json["request_id"] as? String, "req_abc")
        XCTAssertEqual(json["categories"] as? [String], ["wrong_words", "other"])
        XCTAssertEqual(json["raw_text"] as? String, "hello")
        XCTAssertNil(json["user_feedback"] as? String)
        XCTAssertNil(json["polished_text"] as? String)
    }

    func testEncodesSavedClipToFLAC() throws {
        let id = UUID()
        defer { try? FileManager.default.removeItem(at: ClipStore.url(for: id)) }
        let samples: [Int16] = (0..<16_000).map { Int16(sin(Double($0) / 8) * 8_000) }
        let pcm = samples.withUnsafeBytes { Data($0) }
        try ClipStore.write(pcm: pcm, for: id)

        XCTAssertEqual(ClipStore.samples(for: id), samples)
        let flac = try ClipStore.encodeFLAC(for: id)
        defer { try? FileManager.default.removeItem(at: flac) }
        let data = try Data(contentsOf: flac)
        XCTAssertEqual(data.prefix(4), Data("fLaC".utf8))
        XCTAssertLessThan(data.count, pcm.count)
    }
}
