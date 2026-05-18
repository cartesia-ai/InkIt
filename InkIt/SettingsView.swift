import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var permissions = PermissionsService.shared
    @State private var showAPIKey = false

    var body: some View {
        Form {
            Section("Cartesia") {
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $settings.cartesiaAPIKey)
                    } else {
                        SecureField("API Key", text: $settings.cartesiaAPIKey)
                    }
                    Button(showAPIKey ? "Hide" : "Show") { showAPIKey.toggle() }
                }
                Text("Model: ink-2 (English preview)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                HotkeyRecorder()
                    .environmentObject(settings)
                    .environmentObject(coordinator)
                Text("Hold the hotkey to dictate. Release to paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Play sound on press and release", isOn: $settings.playFeedbackSounds)
                if case .fn = settings.hotkey {
                    Text("Fn caveat: macOS reserves 🌐 by default for dictation/emoji. " +
                         "Set System Settings → Keyboard → Press 🌐 key to → Do Nothing.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Permissions") {
                PermissionRow(label: "Microphone", granted: permissions.hasMicrophone) {
                    permissions.requestMicrophone { _ in }
                }
                Text("Status: \(permissions.microphoneStatusString)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                PermissionRow(label: "Accessibility", granted: permissions.hasAccessibility) {
                    permissions.requestAccessibility()
                }
                if !permissions.hasAccessibility {
                    Button("I granted Accessibility") {
                        permissions.confirmAccessibilityGrant()
                    }
                    Text("Grant access to: \(permissions.appIdentityDescription)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Status") {
                HStack {
                    Circle().fill(coordinator.statusColor).frame(width: 10, height: 10)
                    Text(coordinator.statusText)
                    Spacer()
                }
                if let err = coordinator.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }
}

struct PermissionRow: View {
    let label: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Text(label)
            Spacer()
            Button(granted ? "Granted" : "Request") { action() }
                .disabled(granted)
        }
    }
}

/// Records a hotkey. Two paths:
///
/// - Carbon combo: first qualifying key-down event (must include a modifier)
///   wins.
/// - Fn-only: detected via `.flagsChanged` events where `function` is the only
///   active modifier.
struct HotkeyRecorder: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var recording = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?

    var body: some View {
        HStack {
            Text("Shortcut")
            Spacer()
            Button(recording ? "Press keys…" : settings.hotkeyDisplayString) {
                toggleRecording()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func toggleRecording() {
        if recording {
            stop()
            return
        }
        recording = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let carbonMods = HotkeyConversion.carbonModifiers(from: event.modifierFlags)
            if carbonMods == 0 { return event }
            settings.hotkey = .carbon(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
            coordinator.registerHotkey()
            stop()
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            // Fn pressed with no other modifier → treat as Fn-only binding.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let onlyFn = flags == .function
            if onlyFn {
                settings.hotkey = .fn
                coordinator.registerHotkey()
                stop()
                return nil
            }
            return event
        }
    }

    private func stop() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        recording = false
    }
}
