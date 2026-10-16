import Foundation
import AudioToolbox

final class ClipRecorder {
    private let lock = NSLock()
    private var buffer = Data()
    private var overflowed = false

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !overflowed else { return }
        if buffer.count + chunk.count > ClipStore.maxReportableBytes {
            overflowed = true
            buffer = Data()
        } else {
            buffer.append(chunk)
        }
    }

    func take() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !overflowed, !buffer.isEmpty else { return nil }
        let data = buffer
        buffer = Data()
        return data
    }
}

enum ClipStoreError: Error {
    case missingClip
    case encodeFailed(OSStatus)
}

enum ClipStore {
    static let keepCount = 50
    static let sampleRate = 16_000
    static let uploadLimitBytes = 4 * 1024 * 1024
    static let maxReportableMs = 180_000
    static let maxReportableBytes = maxReportableMs * sampleRate * 2 / 1000
    static let minReportableMs = 250
    static let maxAge: TimeInterval = 7 * 86_400 - 3_600

    private static let headerSize = 44
    private static let queue = DispatchQueue(label: "inkit.clips", qos: .utility)

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("InkIt/clips", isDirectory: true)
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).wav")
    }

    static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    static func durationMs(bytes: Int) -> Int {
        bytes * 1000 / (sampleRate * 2)
    }

    static func retainedIDs(_ entries: [TranscriptHistoryStore.Entry], now: Date = Date()) -> Set<UUID> {
        let cutoff = now.addingTimeInterval(-maxAge)
        return Set(entries.prefix(keepCount)
            .filter { ($0.diagnostics?.startedAt ?? $0.timestamp) > cutoff }
            .map(\.id))
    }

    static func reportableIDs(_ entries: [TranscriptHistoryStore.Entry], now: Date = Date()) -> Set<UUID> {
        let retained = retainedIDs(entries, now: now)
        return Set(entries.prefix(keepCount).filter { entry in
            guard retained.contains(entry.id), let ms = entry.diagnostics?.clipMs else { return false }
            return ms >= minReportableMs
        }.map(\.id))
    }

    static func save(pcm: Data, for id: UUID, keeping ids: Set<UUID>) {
        guard !pcm.isEmpty else { return }
        queue.async {
            do {
                try write(pcm: pcm, for: id)
                removeClips(notIn: ids)
            } catch {
                DebugLog.error("ClipStore: save failed — \(error)")
            }
        }
    }

    static func write(pcm: Data, for id: UUID) throws {
        try prepareDirectory()
        var file = wavHeader(dataBytes: pcm.count)
        file.append(pcm)
        try file.write(to: url(for: id), options: .atomic)
    }

    static func prune(keeping ids: Set<UUID>) {
        queue.async { removeClips(notIn: ids) }
    }

    static func deleteAll() {
        queue.async {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func samples(for id: UUID) -> [Int16] {
        guard let data = try? Data(contentsOf: url(for: id)), data.count > headerSize else { return [] }
        let body = data.dropFirst(headerSize)
        var samples = [Int16](repeating: 0, count: body.count / 2)
        _ = samples.withUnsafeMutableBytes { body.copyBytes(to: $0) }
        return samples
    }

    static func waveform(for id: UUID, bars: Int) -> [Float] {
        let samples = samples(for: id)
        guard !samples.isEmpty, bars > 0 else { return Array(repeating: 0.1, count: bars) }
        let per = max(1, samples.count / bars)
        var levels: [Float] = []
        levels.reserveCapacity(bars)
        for b in 0..<bars {
            let start = b * per
            guard start < samples.count else { levels.append(0); continue }
            let end = min(samples.count, start + per)
            var peak: Int32 = 0
            for i in start..<end { peak = max(peak, abs(Int32(samples[i]))) }
            levels.append(Float(peak) / Float(Int16.max))
        }
        let top = max(levels.max() ?? 1, 0.0001)
        return levels.map { max(0.08, $0 / top) }
    }

    static func encodeFLAC(for id: UUID) throws -> URL {
        let pcm = samples(for: id)
        guard !pcm.isEmpty else { throw ClipStoreError.missingClip }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).flac")

        var flac = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatFLAC,
            mFormatFlags: kAppleLosslessFormatFlag_16BitSourceData,
            mBytesPerPacket: 0, mFramesPerPacket: 0, mBytesPerFrame: 0,
            mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        var ext: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(out as CFURL, kAudioFileFLACType, &flac, nil,
                                               AudioFileFlags.eraseFile.rawValue, &ext)
        guard status == noErr, let ext else { throw ClipStoreError.encodeFailed(status) }
        defer { ExtAudioFileDispose(ext) }

        var client = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        status = ExtAudioFileSetProperty(ext, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
        guard status == noErr else { throw ClipStoreError.encodeFailed(status) }

        var copy = pcm
        status = copy.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            return ExtAudioFileWrite(ext, UInt32(pcm.count), &list)
        }
        guard status == noErr else { throw ClipStoreError.encodeFailed(status) }
        return out
    }

    private static func prepareDirectory() throws {
        var dir = directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }

    private static func removeClips(notIn ids: Set<UUID>) {
        let names = Set(ids.map { "\($0.uuidString).wav" })
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func wavHeader(dataBytes: Int) -> Data {
        var h = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 2)) }
        h.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataBytes))
        h.append(contentsOf: Array("WAVE".utf8))
        h.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        h.append(contentsOf: Array("data".utf8)); u32(UInt32(dataBytes))
        return h
    }
}
