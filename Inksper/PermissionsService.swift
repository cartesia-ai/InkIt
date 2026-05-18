import Foundation
import AVFoundation
import AppKit
import ApplicationServices
import Combine

/// Observable permission status with periodic polling. macOS gives no
/// notification when the user toggles Accessibility in System Settings, so
/// polling is the pragmatic option.
@MainActor
final class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    @Published private(set) var hasMicrophone: Bool = false
    @Published private(set) var hasAccessibility: Bool = false

    private var timer: Timer?
    private var axRequestedAt: Date?
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
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ax = AXIsProcessTrusted()
        if mic != hasMicrophone { hasMicrophone = mic }
        if ax != hasAccessibility { hasAccessibility = ax }
    }

    func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.refresh()
                completion(granted)
            }
        }
    }

    var appIdentityDescription: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Inksper"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown bundle id"
        return "\(name) • \(bundleID)\n\(Bundle.main.bundlePath)"
    }

    /// Triggers the system Accessibility prompt and opens the Privacy pane.
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        axRequestedAt = Date()
        openAccessibilitySettings()
    }

    /// Lets the UI explicitly re-check after the user returns from System
    /// Settings. If Accessibility is still stale in-process, fall back to the
    /// relaunch path so a new process can read the fresh trust bit.
    func confirmAccessibilityGrant() {
        refresh()
        if hasAccessibility {
            axRequestedAt = nil
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
        openAccessibilitySettings()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
