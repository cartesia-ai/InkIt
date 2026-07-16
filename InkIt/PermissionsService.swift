import Foundation
import AVFoundation
import AppKit
import ApplicationServices
import Combine

enum PermissionState: Equatable {
    case granted
    case notRequested
    case needsManual
}

@MainActor
final class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    @Published private(set) var hasMicrophone: Bool = false
    @Published private(set) var hasAccessibility: Bool = false
    @Published private(set) var microphoneState: PermissionState = .notRequested
    @Published private(set) var accessibilityState: PermissionState = .notRequested

    private var timer: Timer?
    private var axRequestedAt: Date?
    private let resumeOnboardingKey = "resumeOnboardingAtPermissions"
    private var becameActiveObserver: Any?

    private init() {
        refresh()
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func startPolling() {
        guard timer == nil else {
            refresh()
            return
        }
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        refresh()
    }

    func refresh() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ax = AXIsProcessTrusted()
        if mic != hasMicrophone { hasMicrophone = mic }
        if ax != hasAccessibility { hasAccessibility = ax }

        let micState = currentMicrophoneState()
        if micState != microphoneState { microphoneState = micState }
        let axState = currentAccessibilityState(trusted: ax)
        if axState != accessibilityState { accessibilityState = axState }
    }

    private func currentMicrophoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:          return .granted
        case .notDetermined:       return .notRequested
        case .denied, .restricted: return .needsManual
        @unknown default:          return .needsManual
        }
    }

    private func currentAccessibilityState(trusted: Bool) -> PermissionState {
        if trusted { return .granted }
        let prompted = axRequestedAt != nil
            || UserDefaults.standard.bool(forKey: resumeOnboardingKey)
        return prompted ? .needsManual : .notRequested
    }

    func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .denied, .restricted:
            openMicrophoneSettings()
            completion(false)
        case .authorized:
            refresh()
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.refresh()
                    completion(granted)
                }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let engine = AVAudioEngine()
                _ = engine.inputNode.inputFormat(forBus: 0)
                try? engine.start()
                engine.stop()
            }
        @unknown default:
            openMicrophoneSettings()
            completion(false)
        }
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func requestAccessibility() {
        let alreadyPrompted = axRequestedAt != nil
            || UserDefaults.standard.bool(forKey: resumeOnboardingKey)
        if !alreadyPrompted {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            axRequestedAt = Date()
            UserDefaults.standard.set(true, forKey: resumeOnboardingKey)
        }
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
