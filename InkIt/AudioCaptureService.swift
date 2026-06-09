import Foundation
import AVFoundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var converter: AudioPCMConverter?
    private var onChunk: ((Data) -> Void)?
    /// Called on the main queue with a normalized 0…1 input level (peak-ish, eased).
    var onLevel: ((Float) -> Void)?
    /// Called on the main queue exactly once per take, when the input device is
    /// actually producing audio — used to flip the HUD from "preparing" to the
    /// live waveform so the user knows when to start speaking. With a Bluetooth
    /// mic this fires ~200–500ms after `start()`: the device spends that long
    /// switching from its output (A2DP) profile into the mic (HFP) profile, and
    /// until then it emits digital silence, so words spoken in that window are
    /// lost at the hardware level. The cue exists to keep the user from talking
    /// into that dead gap.
    var onReady: (() -> Void)?
    private let queue = DispatchQueue(label: "inkit.audio", qos: .userInitiated)
    private var isRunning = false

    /// Whether `onReady` has fired for the current take. Only read/written on
    /// the main queue (the tap routes its readiness check there, as does the
    /// fallback below), so it needs no extra locking.
    private var hasSignaledReady = false
    private var readyFallback: DispatchWorkItem?
    /// Normalized input level above which we treat the device as genuinely
    /// delivering audio, vs the digital silence a Bluetooth mic emits while it
    /// switches into its input profile. Sits just above the meter's noise floor.
    private static let readyLevelThreshold: Float = 0.03
    /// Safety net: if no real audio is seen this soon after `start()` (e.g. a
    /// genuinely silent room), signal ready anyway so the HUD never stays stuck
    /// on the "preparing" cue. Sized to cover the worst-case Bluetooth switch.
    private let readyFallbackDelay: TimeInterval = 0.6

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
            DispatchQueue.main.async {
                self.onLevel?(level)
                // First buffer carrying real signal means the device is live —
                // tell the HUD it's safe to start speaking.
                if level > Self.readyLevelThreshold { self.signalReadyIfNeeded() }
            }
            self.queue.async {
                guard let data = self.converter?.convert(buffer: buffer) else { return }
                if !data.isEmpty {
                    self.onChunk?(data)
                }
            }
        }

        hasSignaledReady = false
        engine.prepare()
        try engine.start()
        isRunning = true

        // Backstop the signal-based readiness cue: in a silent room no buffer
        // ever crosses the threshold, so flip to "ready" on a timer once the
        // device has had time to come up (incl. the Bluetooth profile switch).
        let fallback = DispatchWorkItem { [weak self] in self?.signalReadyIfNeeded() }
        readyFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + readyFallbackDelay, execute: fallback)
    }

    /// Fire `onReady` once per take. Always called on the main queue.
    private func signalReadyIfNeeded() {
        guard !hasSignaledReady else { return }
        hasSignaledReady = true
        readyFallback?.cancel()
        readyFallback = nil
        onReady?()
    }

    func stop() {
        guard isRunning else { return }
        readyFallback?.cancel()
        readyFallback = nil
        hasSignaledReady = false
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
