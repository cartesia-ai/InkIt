import Foundation
import AVFoundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var converter: AudioPCMConverter?
    private var onChunk: ((Data) -> Void)?
    /// Called on the main queue with a normalized 0…1 input level (peak-ish, eased).
    var onLevel: ((Float) -> Void)?
    private let queue = DispatchQueue(label: "inkit.audio", qos: .userInitiated)
    private var isRunning = false

    /// UID of the user's pinned input device, or nil/empty to follow the macOS
    /// default. Set before `start()`. When set but the device is unplugged we
    /// fall back to the system default rather than failing — see `start()`.
    var preferredDeviceUID: String?

    func start(onChunk: @escaping (Data) -> Void) throws {
        guard !isRunning else { return }
        self.onChunk = onChunk

        let input = engine.inputNode

        // Pin the user's chosen input device, or reset to the system default.
        // This must happen while the engine is stopped and BEFORE we read the
        // input format (which is the active device's format). If the pinned
        // device is gone, `deviceID(forUID:)` returns nil and we route to the
        // current default — the graceful AirPods-unplugged fallback. We also
        // reset to default when unpinned, since the engine instance is reused
        // across takes and would otherwise keep a previously pinned device.
        let pinnedID = preferredDeviceUID.flatMap { AudioDevices.deviceID(forUID: $0) }
        if let deviceID = pinnedID ?? AudioDevices.defaultInputDeviceID() {
            try? input.auAudioUnit.setDeviceID(deviceID)
        }

        let inputFormat = input.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "InkIt", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to build target audio format"])
        }
        converter = AudioPCMConverter(input: inputFormat, output: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.peakLevel(buffer)
            DispatchQueue.main.async { self.onLevel?(level) }
            self.queue.async {
                guard let data = self.converter?.convert(buffer: buffer) else { return }
                if !data.isEmpty {
                    self.onChunk?(data)
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Drain conversions still queued from the final tap callbacks before we
        // tear down the converter/callback. Without this barrier, an in-flight
        // buffer finds `converter`/`onChunk` already nil and is silently dropped
        // — losing the tail of the last word. The server transcribes all audio
        // we manage to send before `close`, so anything not flushed here is gone.
        queue.sync { }
        converter = nil
        onChunk = nil
        isRunning = false
        DispatchQueue.main.async { [weak self] in self?.onLevel?(0) }
    }

    /// Compute a normalized 0…1 level from a float input buffer. We take the
    /// peak sample, log-compress (-50 dB floor) so quiet speech isn't invisible.
    private static func peakLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if frames == 0 { return 0 }
        var peak: Float = 0
        for ch in 0..<channelCount {
            let samples = channelData[ch]
            for i in 0..<frames {
                let v = abs(samples[i])
                if v > peak { peak = v }
            }
        }
        if peak <= 0 { return 0 }
        let db = 20 * log10f(peak)        // typically -∞ … 0
        let floor: Float = -50
        let norm = max(0, min(1, (db - floor) / -floor))
        return norm
    }
}
