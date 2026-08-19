import Foundation

enum MeetingSessionState: Equatable {
    case idle
    case recording
    case ending
}

@MainActor
final class MeetingSessionCoordinator: ObservableObject {
    struct Segment: Identifiable, Equatable {
        let id = UUID()
        let speakerLabel: String
        let text: String
        let timestamp: Date
    }

    enum StartGate {
        case ready
        case needsAPIKey
    }

    @Published private(set) var state: MeetingSessionState = .idle
    @Published private(set) var segments: [Segment] = []
    @Published private(set) var elapsedSeconds: Int = 0
    @Published var showStopConfirm = false
    @Published var pendingNavigateToMeetingNotes = false

    var isSessionActive: Bool { state != .idle }

    private let settings = SettingsStore.shared
    private let meetingNotes = MeetingNotesStore.shared

    private let micAudio = AudioCaptureService()
    private let systemAudio = ProcessTapAudioService()
    private var micClient: CartesiaStreamingClient?
    private var systemClient: CartesiaStreamingClient?
    private var micClosed = false
    private var systemClosed = false
    private var rewriter: TranscriptRewriter?
    private var systemChannelHistory: [(speaker: String, text: String)] = []
    private var pendingPolishCount = 0
    private static let maxSystemHistoryTurns = 6

    private var timer: Timer?
    private var startedAt: Date?

    func checkGate() -> StartGate {
        settings.apiKey(for: settings.rewriteProvider).isEmpty ? .needsAPIKey : .ready
    }

    func start() {
        guard state == .idle else { return }
        PermissionsService.shared.refresh()
        guard PermissionsService.shared.hasMicrophone else {
            PermissionsService.shared.requestMicrophone { _ in }
            return
        }
        guard PermissionsService.shared.hasSystemAudioCapture else {
            PermissionsService.shared.requestSystemAudioCapture()
            return
        }

        state = .recording
        segments = []
        elapsedSeconds = 0
        startedAt = Date()
        micClosed = false
        systemClosed = false
        systemChannelHistory = []
        pendingPolishCount = 0
        rewriter = TranscriptRewriter(provider: settings.rewriteProvider,
                                      model: settings.rewriteModel,
                                      apiKey: settings.apiKey(for: settings.rewriteProvider))
        startTimer()

        startMicChannel()
        startSystemChannel()
    }

    func requestStop() {
        guard state == .recording else { return }
        showStopConfirm = true
    }

    func cancelStopRequest() {
        showStopConfirm = false
    }

    func confirmStop() {
        showStopConfirm = false
        endMeeting()
    }

    func endMeeting() {
        guard state == .recording else { return }
        state = .ending
        stopTimer()
        micAudio.stop()
        systemAudio.stop()
        micClient?.finalizeAndClose()
        systemClient?.finalizeAndClose()
    }

    private func startMicChannel() {
        let client = CartesiaStreamingClient(apiKey: settings.cartesiaAPIKey,
                                             keyterms: settings.validatedDictionaryTerms)
        micClient = client
        client.onTurnFinal = { [weak self] text, timestamp in
            Task { @MainActor in
                guard let self else { return }
                self.pendingPolishCount += 1
                let cleaned = await self.polishMicTurn(text)
                self.appendSegment(speaker: "You", text: cleaned, timestamp: timestamp)
                self.pendingPolishCount -= 1
                self.finalizeIfReady()
            }
        }
        client.onClosed = { [weak self] _ in
            Task { @MainActor in self?.channelClosed(mic: true) }
        }
        client.connect()

        micAudio.preferredDeviceUID = settings.preferredInputDeviceUID
        try? micAudio.start { [weak self] data in
            self?.micClient?.sendAudio(data)
        }
    }

    private func startSystemChannel() {
        let client = CartesiaStreamingClient(apiKey: settings.cartesiaAPIKey)
        systemClient = client
        client.onTurnFinal = { [weak self] text, timestamp in
            Task { @MainActor in
                guard let self else { return }
                self.pendingPolishCount += 1
                let labeled = await self.labelSystemTurn(text)
                self.appendSegment(speaker: labeled.speaker, text: labeled.text, timestamp: timestamp)
                self.pendingPolishCount -= 1
                self.finalizeIfReady()
            }
        }
        client.onClosed = { [weak self] _ in
            Task { @MainActor in self?.channelClosed(mic: false) }
        }
        client.connect()

        Task {
            do {
                try await systemAudio.start { [weak self] data in
                    self?.systemClient?.sendAudio(data)
                }
                PermissionsService.shared.recordSystemAudioCaptureResult(granted: true)
            } catch {
                PermissionsService.shared.recordSystemAudioCaptureResult(granted: false)
            }
        }
    }

    private func polishMicTurn(_ raw: String) async -> String {
        guard let rewriter else { return raw }
        switch await rewriter.rewriteWithoutContext(transcript: raw) {
        case .success(let cleaned): return cleaned
        case .failure: return raw
        }
    }

    private func labelSystemTurn(_ raw: String) async -> (speaker: String, text: String) {
        guard let rewriter else { return (systemChannelHistory.last?.speaker ?? "Speaker 1", raw) }
        let result = await rewriter.rewriteMeetingTurn(transcript: raw, priorTurns: systemChannelHistory)
        let labeled: (speaker: String, text: String)
        switch result {
        case .success(let value): labeled = value
        case .failure: labeled = (systemChannelHistory.last?.speaker ?? "Speaker 1", raw)
        }
        systemChannelHistory.append(labeled)
        if systemChannelHistory.count > Self.maxSystemHistoryTurns {
            systemChannelHistory.removeFirst(systemChannelHistory.count - Self.maxSystemHistoryTurns)
        }
        return labeled
    }

    private func appendSegment(speaker: String, text: String, timestamp: Date) {
        DebugLog.info("meeting segment speaker=\(speaker) ts=\(timestamp.timeIntervalSince1970) text=\(text.prefix(80))")
        let segment = Segment(speakerLabel: speaker, text: text, timestamp: timestamp)
        if let insertIndex = segments.firstIndex(where: { $0.timestamp > timestamp }) {
            segments.insert(segment, at: insertIndex)
        } else {
            segments.append(segment)
        }
    }

    private func channelClosed(mic: Bool) {
        if mic { micClosed = true } else { systemClosed = true }
        finalizeIfReady()
    }

    private func summarize(transcript: String, noteID: UUID) {
        guard let rewriter else { return }
        Task { @MainActor in
            if case .success(let result) = await rewriter.summarizeMeeting(transcript: transcript) {
                if !result.title.isEmpty {
                    self.meetingNotes.updateTitle(id: noteID, title: result.title)
                }
                let summaryLines = result.overview.map { MeetingNotesStore.SummaryLine(text: $0, isActionItem: false) }
                    + result.actionItems.map { MeetingNotesStore.SummaryLine(text: $0, isActionItem: true) }
                let flatSummary = Self.flattenSummary(overview: result.overview, actionItems: result.actionItems)
                self.meetingNotes.updateSummary(id: noteID, summary: flatSummary, summaryLines: summaryLines, icon: result.icon)
            }
        }
    }

    private static func flattenSummary(overview: [String], actionItems: [String]) -> String {
        var parts = overview
        if !actionItems.isEmpty {
            parts.append("")
            parts.append("**Action Items**")
            parts.append(contentsOf: actionItems.map { "- \($0)" })
        }
        return parts.joined(separator: "\n")
    }

    private func finalizeIfReady() {
        guard micClosed, systemClosed, pendingPolishCount == 0 else { return }

        micClient = nil
        systemClient = nil
        let transcript = segments
            .map { "\($0.speakerLabel): \($0.text)" }
            .joined(separator: "\n")
        var speakerIDByLabel: [String: UUID] = [:]
        var speakers: [MeetingNotesStore.Speaker] = []
        let lines = segments.map { segment -> MeetingNotesStore.TranscriptLine in
            let speakerID = speakerIDByLabel[segment.speakerLabel] ?? {
                let speaker = MeetingNotesStore.Speaker(label: segment.speakerLabel, displayName: nil)
                speakerIDByLabel[segment.speakerLabel] = speaker.id
                speakers.append(speaker)
                return speaker.id
            }()
            return MeetingNotesStore.TranscriptLine(speakerID: speakerID, text: segment.text)
        }
        if !transcript.isEmpty {
            let note = meetingNotes.createNote(transcript: transcript, lines: lines, speakers: speakers)
            pendingNavigateToMeetingNotes = true
            summarize(transcript: transcript, noteID: note.id)
        }
        state = .idle
        segments = []
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
