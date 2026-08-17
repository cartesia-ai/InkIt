import Foundation
import CoreAudio

// Uses a Core Audio Process Tap rather than ScreenCaptureKit: it's gated by the
// narrower "System Audio Recording Only" permission bucket instead of full Screen Recording.
final class ProcessTapAudioService {
    private var tapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var capture: AudioCaptureService?

    func start(onChunk: @escaping (Data) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    try startSync(onChunk: onChunk)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startSync(onChunk: @escaping (Data) -> Void) throws {
        let tapUUID = UUID()
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.uuid = tapUUID
        description.muteBehavior = .unmuted

        var tapID: AudioObjectID = .unknown
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw ProcessTapError.tapCreationFailed(status)
        }
        self.tapID = tapID

        let aggregateUID = UUID().uuidString
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "InkIt Meeting Audio Tap",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUUID.uuidString]
            ]
        ]

        var aggregateDeviceID: AudioObjectID = .unknown
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            self.tapID = .unknown
            throw ProcessTapError.aggregateDeviceCreationFailed(status)
        }
        self.aggregateDeviceID = aggregateDeviceID

        let capture = AudioCaptureService()
        capture.preferredDeviceID = aggregateDeviceID
        self.capture = capture
        try capture.start(onChunk: onChunk)
    }

    func stop() {
        capture?.stop()
        capture = nil

        if aggregateDeviceID != .unknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    static func probeAccess() -> Bool {
        let probe = ProcessTapAudioService()
        do {
            try probe.startSync(onChunk: { _ in })
            probe.stop()
            return true
        } catch {
            return false
        }
    }
}

enum ProcessTapError: Error {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
}

private extension AudioObjectID {
    static let unknown = kAudioObjectUnknown
}
