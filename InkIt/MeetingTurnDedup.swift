import Foundation

@MainActor
final class MeetingTurnDedup {
    private struct Turn {
        let tag: String
        let segmentID: UUID
        let isMic: Bool
        let speaker: String
        let text: String
        let timestamp: Date
    }

    private static let bufferWindow: TimeInterval = 6
    private static let debounceInterval: TimeInterval = 1.5
    private static let maxWaitInterval: TimeInterval = 3.0

    private let rewriter: TranscriptRewriter
    private let onDropMicSegment: (UUID) -> Void

    private var micBuffer: [Turn] = []
    private var systemBuffer: [Turn] = []
    private var lastFlushedMic: Turn?
    private var lastFlushedSystem: Turn?
    private var flushTask: Task<Void, Never>?
    private var oldestPendingArrival: Date?
    private var tagCounter = 0

    init(rewriter: TranscriptRewriter, onDropMicSegment: @escaping (UUID) -> Void) {
        self.rewriter = rewriter
        self.onDropMicSegment = onDropMicSegment
    }

    func recordMicTurn(segmentID: UUID, text: String, timestamp: Date) {
        tagCounter += 1
        micBuffer.append(Turn(tag: "M\(tagCounter)", segmentID: segmentID, isMic: true,
                              speaker: "You", text: text, timestamp: timestamp))
        if oldestPendingArrival == nil { oldestPendingArrival = Date() }
        pruneExpired()
        scheduleFlush()
    }

    func recordSystemTurn(segmentID: UUID, speaker: String, text: String, timestamp: Date) {
        tagCounter += 1
        systemBuffer.append(Turn(tag: "S\(tagCounter)", segmentID: segmentID, isMic: false,
                                 speaker: speaker, text: text, timestamp: timestamp))
        pruneExpired()
        scheduleFlush()
    }

    func flushImmediately() {
        flushTask?.cancel()
        flushTask = nil
        Task { await flush() }
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-Self.bufferWindow)
        micBuffer.removeAll { $0.timestamp < cutoff }
        systemBuffer.removeAll { $0.timestamp < cutoff }
    }

    private func scheduleFlush() {
        let now = Date()
        let debounceDeadline = now.addingTimeInterval(Self.debounceInterval)
        let deadline = oldestPendingArrival.map { min(debounceDeadline, $0.addingTimeInterval(Self.maxWaitInterval)) }
            ?? debounceDeadline
        let delay = max(0, deadline.timeIntervalSince(now))

        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() async {
        pruneExpired()
        guard !micBuffer.isEmpty, !systemBuffer.isEmpty || lastFlushedSystem != nil else { return }

        var batch = micBuffer + systemBuffer
        if let lastMic = lastFlushedMic, !batch.contains(where: { $0.segmentID == lastMic.segmentID }) {
            batch.append(lastMic)
        }
        if let lastSystem = lastFlushedSystem, !batch.contains(where: { $0.segmentID == lastSystem.segmentID }) {
            batch.append(lastSystem)
        }
        batch.sort { $0.timestamp < $1.timestamp }

        let flushedMic = micBuffer
        let flushedSystem = systemBuffer
        micBuffer.removeAll()
        systemBuffer.removeAll()
        oldestPendingArrival = nil

        let turnsText = batch
            .map { "[\($0.tag)] \($0.speaker) @ t=\(String(format: "%.3f", $0.timestamp.timeIntervalSince1970)): \($0.text)" }
            .joined(separator: "\n")
        DebugLog.info("meeting dedup batch tags=\(batch.map(\.tag).joined(separator: ",")) mic=\(flushedMic.count) system=\(flushedSystem.count)")

        let dropTags: Set<String>
        switch await rewriter.detectCrossChannelDuplicates(turnsText: turnsText) {
        case .success(let tags):
            dropTags = Set(tags)
            DebugLog.info("meeting dedup verdict drop=[\(tags.joined(separator: ","))]")
        case .failure(let failure):
            dropTags = []
            DebugLog.error("meeting dedup call failed: \(failure)")
        }

        for turn in batch where turn.isMic && dropTags.contains(turn.tag) {
            DebugLog.info("meeting dedup dropping mic segment tag=\(turn.tag) id=\(turn.segmentID) text=\(turn.text.prefix(80))")
            onDropMicSegment(turn.segmentID)
        }

        lastFlushedMic = flushedMic.last ?? lastFlushedMic
        lastFlushedSystem = flushedSystem.last ?? lastFlushedSystem
    }
}
