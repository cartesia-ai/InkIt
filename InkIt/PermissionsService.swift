import Foundation
import AVFoundation
import AppKit
import ApplicationServices
import Combine

/// Tri-state for a single permission, used to drive the onboarding card UI.
///
/// `needsManual` is the important one: macOS shows its TCC prompt only once per
/// decision, so after a denial — or after we've already fired the prompt — a
/// second "Enable" tap silently no-ops (just re-opening Settings). That's the
/// "bubble keeps popping" loop. In `needsManual` the card stops offering a
/// re-prompt and instead walks the user to the manual toggle.
enum PermissionState: Equatable {
    case granted
    case notRequested
    case needsManual
}

/// Observable permission status with periodic polling. macOS gives no
/// notification when the user toggles Accessibility in System Settings, so
/// polling is the pragmatic option.
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
        // Use .common modes so the timer keeps firing across runloop modes
        // (notably when our app is backgrounded while the user is in System
        // Settings granting permissions).
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        // Permission polling is shared by onboarding, settings, and the
        // coordinator. Keep it alive for the process lifetime so one surface
        // disappearing cannot make another surface show stale permission state.
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
        // macOS exposes no "denied" status for Accessibility — AXIsProcessTrusted
        // is just false either way. But once we've fired the prompt, re-firing it
        // is a no-op, so the only way forward is a manual toggle. The resume flag
        // persists this across the AX relaunch so the manual state survives it.
        let prompted = axRequestedAt != nil
            || UserDefaults.standard.bool(forKey: resumeOnboardingKey)
        return prompted ? .needsManual : .notRequested
    }

    var microphoneStatusString: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return "Not determined"
        case .denied:        return "Denied"
        case .restricted:    return "Restricted"
        case .authorized:    return "Authorized"
        @unknown default:    return "Unknown"
        }
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
            // Also kick the audio engine — AVCaptureDevice.requestAccess
            // doesn't always surface a prompt on its own with hardened runtime;
            // touching AVAudioEngine.start forces TCC to evaluate.
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

    var appIdentityDescription: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "InkIt"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown bundle id"
        return "\(name) • \(bundleID)\n\(Bundle.main.bundlePath)"
    }

    /// Fires the system TCC prompt and opens System Settings → Privacy &
    /// Security → Accessibility.
    ///
    /// `AXIsProcessTrustedWithOptions(prompt: true)` is the only API that
    /// pre-adds InkIt to the Accessibility list (disabled), so the user can
    /// just flip the toggle instead of hunting for the "+" button. macOS only
    /// shows the dialog once per decision, so calling this again after a Deny
    /// silently no-ops and just re-opens Settings.
    ///
    /// Only call this from an explicit user action (the onboarding/Settings
    /// "Enable" button) — never from the dictation hot path, or repeated key
    /// presses would keep re-popping the dialog. Polling (`refresh`) detects
    /// the grant live once the user flips the toggle.
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        axRequestedAt = Date()
        UserDefaults.standard.set(true, forKey: resumeOnboardingKey)
        openAccessibilitySettings()
    }

    /// Lets the UI explicitly re-check after the user returns from System
    /// Settings. If Accessibility is still stale in-process, fall back to the
    /// relaunch path so a new process can read the fresh trust bit.
    func confirmAccessibilityGrant() {
        refresh()
        if hasAccessibility {
            axRequestedAt = nil
            UserDefaults.standard.removeObject(forKey: resumeOnboardingKey)
            return
        }
        guard let requestedAt = axRequestedAt else {
            // After a relaunch or manual restart we no longer know whether the
            // user has already been sent to System Settings. Don't let the
            // confirmation button become a no-op; prompt again.
            openAccessibilitySettings()
            return
        }
        // Give the user a beat to finish the Settings interaction before we
        // decide the process-local trust bit is stale.
        guard Date().timeIntervalSince(requestedAt) > 1.0 else {
            openAccessibilitySettings()
            return
        }
        relaunch()
    }

    private func relaunch() {
        UserDefaults.standard.set(true, forKey: resumeOnboardingKey)
        let appURL = Bundle.main.bundleURL

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error != nil {
                    self.openAccessibilitySettings()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
