import Foundation
import AVFoundation

final class AudioCaptureService {
    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var converter: AudioPCMConverter?
    private var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onReady: (() -> Void)?
    private let queue = DispatchQueue(label: "inkit.audio", qos: .userInitiated)
    private var isRunning = false

    private var hasSignaledReady = false
    private var readyFallback: DispatchWorkItem?
    private static let readyLevelThreshold: Float = 0.03
    private let readyFallbackDelay: TimeInterval = 0.6

    var preferredDeviceUID: String?

    func start(onChunk: @escaping (Data) -> Void) throws {
        guard !isRunning, engine == nil else { return }
        self.onChunk = onChunk

        let engine = AVAudioEngine()
        let input = engine.inputNode
        self.engine = engine
        inputNode = input

        let pinnedID = preferredDeviceUID.flatMap { AudioDevices.deviceID(forUID: $0) }
        if let deviceID = pinnedID ?? AudioDevices.defaultInputDeviceID() {
            do {
                try input.auAudioUnit.setDeviceID(deviceID)
            } catch {
                DebugLog.error("AudioCapture: device selection failed id=\(deviceID) error=\(error.localizedDescription)")
            }
        }

        let inputFormat = input.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            tearDownEngine()
            throw NSError(domain: "InkIt", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to build target audio format"])
        }
        guard let converter = AudioPCMConverter(input: inputFormat, output: targetFormat) else {
            tearDownEngine()
            throw NSError(domain: "InkIt", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to build audio converter"])
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.peakLevel(buffer)
            DispatchQueue.main.async {
                self.onLevel?(level)
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
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            DebugLog.info(
                "AudioCapture: started source=\(pinnedID == nil ? "default" : "pinned") "
                + "device=\((pinnedID ?? AudioDevices.defaultInputDeviceID()).map(String.init) ?? "unknown") "
                + "inputRate=\(Int(inputFormat.sampleRate)) inputChannels=\(inputFormat.channelCount)"
            )
        } catch {
            tearDownEngine()
            throw error
        }

        let fallback = DispatchWorkItem { [weak self] in self?.signalReadyIfNeeded() }
        readyFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + readyFallbackDelay, execute: fallback)
    }

    private func signalReadyIfNeeded() {
        guard !hasSignaledReady else { return }
        hasSignaledReady = true
        readyFallback?.cancel()
        readyFallback = nil
        onReady?()
    }

    func stop() {
        guard engine != nil else { return }
        readyFallback?.cancel()
        readyFallback = nil
        hasSignaledReady = false
        tearDownEngine()
        DispatchQueue.main.async { [weak self] in self?.onLevel?(0) }
    }

    private func tearDownEngine() {
        let engine = engine
        let input = inputNode
        isRunning = false

        input?.removeTap(onBus: 0)
        engine?.stop()
        engine?.reset()

        queue.sync { }
        converter = nil
        onChunk = nil
        inputNode = nil
        self.engine = nil

        DebugLog.info("AudioCapture: stopped and released engine")
    }

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
        let db = 20 * log10f(peak)
        let floor: Float = -50
        let norm = max(0, min(1, (db - floor) / -floor))
        return norm
    }
}
