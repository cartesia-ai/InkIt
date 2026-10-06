import Foundation
import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio

enum AudioCaptureError: LocalizedError {
    case alreadyRunning
    case noInputDevice
    case coreAudio(step: String, status: OSStatus)
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Mic was already recording"
        case .noInputDevice: return "No microphone found"
        case .coreAudio(let step, let status): return "Mic \(step) failed (\(status))"
        case .converterUnavailable: return "Mic format unsupported"
        }
    }
}

final class AudioCaptureService {
    private final class InputUnit {
        let unit: AudioUnit
        let deviceID: AudioDeviceID
        let format: AVAudioFormat
        let onBuffer: (AVAudioPCMBuffer) -> Void

        init(unit: AudioUnit, deviceID: AudioDeviceID, format: AVAudioFormat,
             onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
            self.unit = unit
            self.deviceID = deviceID
            self.format = format
            self.onBuffer = onBuffer
        }

        func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                    timestamp: UnsafePointer<AudioTimeStamp>,
                    bus: UInt32,
                    frames: UInt32) -> OSStatus {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                return noErr
            }
            buffer.frameLength = frames
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for i in buffers.indices {
                buffers[i].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
            }
            let status = AudioUnitRender(unit, flags, timestamp, bus, frames, buffer.mutableAudioBufferList)
            guard status == noErr else { return status }
            onBuffer(buffer)
            return noErr
        }
    }

    private var inputUnit: InputUnit?
    private var converter: AudioPCMConverter?
    private var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onReady: (() -> Void)?
    private let queue = DispatchQueue(label: "inkit.audio", qos: .userInitiated)
    private var isRunning = false
    private var needsRebuild = false

    private var hasSignaledReady = false
    private var readyFallback: DispatchWorkItem?
    private static let readyLevelThreshold: Float = 0.03
    private let readyFallbackDelay: TimeInterval = 0.6

    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []

    var preferredDeviceUID: String? {
        didSet {
            guard preferredDeviceUID != oldValue else { return }
            prepare()
        }
    }

    init() {
        startObservingSystem()
    }

    deinit {
        stopObservingSystem()
        dispose()
    }

    func prepare() {
        guard !isRunning else {
            needsRebuild = true
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        do {
            try configureIfNeeded()
        } catch {
            DebugLog.error("AudioCapture: prepare failed \(error.localizedDescription)")
        }
    }

    func start(onChunk: @escaping (Data) -> Void) throws {
        guard !isRunning else { throw AudioCaptureError.alreadyRunning }

        try configureIfNeeded()
        guard let inputUnit else { throw AudioCaptureError.noInputDevice }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let converter = AudioPCMConverter(input: inputUnit.format, output: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }

        queue.sync {
            self.converter = converter
            self.onChunk = onChunk
        }

        hasSignaledReady = false
        let status = AudioOutputUnitStart(inputUnit.unit)
        guard status == noErr else {
            queue.sync {
                self.converter = nil
                self.onChunk = nil
            }
            dispose()
            throw AudioCaptureError.coreAudio(step: "start", status: status)
        }
        isRunning = true
        DebugLog.info(
            "AudioCapture: started device=\(inputUnit.deviceID) "
            + "rate=\(Int(inputUnit.format.sampleRate)) channels=\(inputUnit.format.channelCount)"
        )

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
        guard isRunning else { return }
        readyFallback?.cancel()
        readyFallback = nil
        hasSignaledReady = false
        if let unit = inputUnit?.unit {
            let status = AudioOutputUnitStop(unit)
            if status != noErr {
                DebugLog.error("AudioCapture: stop failed status=\(status)")
            }
        }
        isRunning = false
        queue.sync {
            converter = nil
            onChunk = nil
        }
        DispatchQueue.main.async { [weak self] in self?.onLevel?(0) }

        if needsRebuild {
            needsRebuild = false
            rebuild()
        }
    }

    private func rebuild() {
        guard !isRunning else {
            needsRebuild = true
            return
        }
        dispose()
        prepare()
    }

    private func targetDeviceID() -> AudioDeviceID? {
        let pinnedID = preferredDeviceUID.flatMap { AudioDevices.deviceID(forUID: $0) }
        return pinnedID ?? AudioDevices.defaultInputDeviceID()
    }

    private func configureIfNeeded() throws {
        guard let deviceID = targetDeviceID() else {
            dispose()
            throw AudioCaptureError.noInputDevice
        }
        if let inputUnit, inputUnit.deviceID == deviceID,
           let current = try? Self.hardwareFormat(inputUnit.unit),
           current.mSampleRate == inputUnit.format.sampleRate,
           current.mChannelsPerFrame == inputUnit.format.channelCount {
            return
        }
        dispose()
        inputUnit = try makeInputUnit(deviceID: deviceID)
        DebugLog.info("AudioCapture: configured device=\(deviceID)")
    }

    private func makeInputUnit(deviceID: AudioDeviceID) throws -> InputUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioCaptureError.coreAudio(step: "lookup", status: kAudioUnitErr_FailedInitialization)
        }
        var newUnit: AudioUnit?
        try Self.check("create", AudioComponentInstanceNew(component, &newUnit))
        guard let unit = newUnit else {
            throw AudioCaptureError.coreAudio(step: "create", status: kAudioUnitErr_FailedInitialization)
        }

        do {
            var enable: UInt32 = 1
            var disable: UInt32 = 0
            try Self.check("enable input", AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                &enable, UInt32(MemoryLayout<UInt32>.size)))
            try Self.check("disable output", AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                &disable, UInt32(MemoryLayout<UInt32>.size)))

            var device = deviceID
            try Self.check("select device", AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &device, UInt32(MemoryLayout<AudioDeviceID>.size)))

            let hardware = try Self.hardwareFormat(unit)
            guard hardware.mSampleRate > 0, hardware.mChannelsPerFrame > 0,
                  let format = AVAudioFormat(standardFormatWithSampleRate: hardware.mSampleRate,
                                             channels: hardware.mChannelsPerFrame) else {
                throw AudioCaptureError.converterUnavailable
            }
            var clientFormat = format.streamDescription.pointee
            try Self.check("set format", AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                &clientFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))

            let input = InputUnit(unit: unit, deviceID: deviceID, format: format) { [weak self] buffer in
                self?.handle(buffer)
            }
            var callback = AURenderCallbackStruct(
                inputProc: Self.inputCallback,
                inputProcRefCon: Unmanaged.passUnretained(input).toOpaque()
            )
            try Self.check("set callback", AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))

            try Self.check("initialize", AudioUnitInitialize(unit))
            return input
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    private func dispose() {
        guard let inputUnit else { return }
        if isRunning {
            AudioOutputUnitStop(inputUnit.unit)
            isRunning = false
        }
        AudioUnitUninitialize(inputUnit.unit)
        AudioComponentInstanceDispose(inputUnit.unit)
        self.inputUnit = nil
    }

    private static let inputCallback: AURenderCallback = { refCon, flags, timestamp, bus, frames, _ in
        Unmanaged<InputUnit>.fromOpaque(refCon).takeUnretainedValue()
            .render(flags: flags, timestamp: timestamp, bus: bus, frames: frames)
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, let converter = self.converter else { return }
            let level = Self.peakLevel(buffer)
            DispatchQueue.main.async {
                self.onLevel?(level)
                if level > Self.readyLevelThreshold { self.signalReadyIfNeeded() }
            }
            let data = converter.convert(buffer: buffer)
            if !data.isEmpty {
                self.onChunk?(data)
            }
        }
    }

    private static func hardwareFormat(_ unit: AudioUnit) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check("read format", AudioUnitGetProperty(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &format, &size))
        return format
    }

    private static func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw AudioCaptureError.coreAudio(step: step, status: status) }
    }

    private func startObservingSystem() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.prepare()
        }
        deviceListener = listener
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        }

        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        })
        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dispose()
        })
    }

    private func stopObservingSystem() {
        if let listener = deviceListener {
            for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
            }
        }
        deviceListener = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.removeAll()
        appObservers.removeAll()
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
