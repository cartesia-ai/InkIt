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

    var isSessionActive: Bool { state != .idle }

    private let settings = SettingsStore.shared
    private let meetingNotes = MeetingNotesStore.shared

    private let micAudio = AudioCaptureService()
    private let systemAudio = ProcessTapAudioService()
    private var micClient: CartesiaStreamingClient?
    private var systemClient: CartesiaStreamingClient?
    private var micClosed = false
    private var systemClosed = false

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
        if PermissionsService.shared.systemAudioCaptureState == .needsManual {
            PermissionsService.shared.requestSystemAudioCapture()
            return
        }

        state = .recording
        segments = []
        elapsedSeconds = 0
        startedAt = Date()
        micClosed = false
        systemClosed = false
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
            Task { @MainActor in self?.appendSegment(speaker: "Speaker 1 (You)", text: text, timestamp: timestamp) }
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
            Task { @MainActor in self?.appendSegment(speaker: "Speaker 2", text: text, timestamp: timestamp) }
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

    private func appendSegment(speaker: String, text: String, timestamp: Date) {
        let segment = Segment(speakerLabel: speaker, text: text, timestamp: timestamp)
        if let insertIndex = segments.firstIndex(where: { $0.timestamp > timestamp }) {
            segments.insert(segment, at: insertIndex)
        } else {
            segments.append(segment)
        }
    }

    private func channelClosed(mic: Bool) {
        if mic { micClosed = true } else { systemClosed = true }
        guard micClosed, systemClosed else { return }

        micClient = nil
        systemClient = nil
        let transcript = segments
            .map { "\($0.speakerLabel): \($0.text)" }
            .joined(separator: "\n")
        if !transcript.isEmpty {
            meetingNotes.createNote(transcript: transcript)
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
