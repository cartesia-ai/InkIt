import Foundation
import AVFoundation

/// Converts arbitrary microphone input buffers to mono pcm_s16le @ 16 kHz,
/// returning the raw little-endian byte payload Cartesia expects.
final class AudioPCMConverter {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat

    init?(input: AVAudioFormat, output: AVAudioFormat) {
        guard let c = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = c
        self.output = output
    }

    func convert(buffer: AVAudioPCMBuffer) -> Data {
        // Estimate output capacity based on sample-rate ratio.
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
            return Data()
        }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil { return Data() }
        guard let int16 = outBuffer.int16ChannelData else { return Data() }
        let frames = Int(outBuffer.frameLength)
        if frames == 0 { return Data() }
        return Data(bytes: int16[0], count: frames * MemoryLayout<Int16>.size)
    }
}
