import Foundation

/// Persisted summary of one Cursor agent session, used as a stable
/// cache-control'd prefix when calling the rewriter. Stored as plain JSON
/// at `~/Library/Application Support/InkIt/sessions/<uuid>.json`.
struct SessionSummary: Codable {
    let sessionUUID: String
    let summary: String
    /// Number of messages in the JSONL at the time we generated the summary.
    /// Used to decide when the conversation has grown enough to merit a
    /// fresh summary.
    let summarizedUpToMessageCount: Int
    let summaryLastUpdated: Date
    let cursorTranscriptPath: String
}

enum SessionSummaryStore {
    /// Regenerate the summary once new messages exceed this many turns
    /// since the last summary. Below this, the cached summary is reused.
    static let resummarizeAfterNewMessages = 10
    /// Below this total message count we don't bother summarizing — raw
    /// recent turns fit comfortably in the prompt.
    static let minMessagesForSummary = 12

    private static var directory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("InkIt", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(forUUID uuid: String) -> URL {
        directory.appendingPathComponent("\(uuid).json")
    }

    static func load(uuid: String) -> SessionSummary? {
        let url = fileURL(forUUID: uuid)
        guard let data = try? Data(contentsOf: url),
              let summary = try? JSONDecoder.iso.decode(SessionSummary.self, from: data)
        else { return nil }
        return summary
    }

    static func save(_ summary: SessionSummary) {
        guard let data = try? JSONEncoder.iso.encode(summary) else { return }
        try? data.write(to: fileURL(forUUID: summary.sessionUUID), options: [.atomic])
        pruneIfNeeded(keep: 50)
    }

    /// True when the conversation has either never been summarized OR
    /// grown by `resummarizeAfterNewMessages` since the last summary.
    /// Returns false for short conversations — caller should send raw
    /// recent turns instead.
    static func needsRefresh(uuid: String, messageCount: Int) -> Bool {
        guard messageCount >= minMessagesForSummary else { return false }
        guard let cached = load(uuid: uuid) else { return true }
        return messageCount - cached.summarizedUpToMessageCount >= resummarizeAfterNewMessages
    }

    private static func pruneIfNeeded(keep: Int) {
        let dir = directory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                                         options: [.skipsHiddenFiles]) else { return }
        guard entries.count > keep else { return }
        let sorted = entries.sorted { a, b in
            let am = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bm = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return am > bm
        }
        for stale in sorted.dropFirst(keep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
