import Foundation
import AVFoundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var converter: AudioPCMConverter?
    private var onChunk: ((Data) -> Void)?
    private let queue = DispatchQueue(label: "inksper.audio", qos: .userInitiated)
    private var isRunning = false

    func start(onChunk: @escaping (Data) -> Void) throws {
        guard !isRunning else { return }
        self.onChunk = onChunk

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "Inksper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to build target audio format"])
        }
        converter = AudioPCMConverter(input: inputFormat, output: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
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
        converter = nil
        onChunk = nil
        isRunning = false
    }
}
