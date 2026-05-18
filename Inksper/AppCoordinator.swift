import Foundation
import SwiftUI
import AppKit

enum DictationState: Equatable {
    case idle
    case recording
    case finalizing
    case pasting
    case error(String)
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var liveTranscript: String = ""

    private let audio = AudioCaptureService()
    private let paste = PasteService()
    private let permissions = PermissionsService.shared
    private let hotkey = HotkeyManager()
    private var client: CartesiaStreamingClient?
    private let settings = SettingsStore.shared

    init() {
        hotkey.onPress = { [weak self] in
            Task { @MainActor in self?.startDictation() }
        }
        hotkey.onRelease = { [weak self] in
            Task { @MainActor in self?.stopDictation() }
        }
        registerHotkey()
    }

    func registerHotkey() {
        hotkey.register(binding: settings.hotkey)
    }

    var statusText: String {
        switch state {
        case .idle: return "Idle"
        case .recording: return "Recording…"
        case .finalizing: return "Finalizing…"
        case .pasting: return "Pasting…"
        case .error(let m): return "Error: \(m)"
        }
    }

    var statusColor: Color {
        switch state {
        case .idle: return .secondary
        case .recording: return .red
        case .finalizing, .pasting: return .orange
        case .error: return .red
        }
    }

    var menuBarIconName: String {
        switch state {
        case .recording: return "waveform.circle.fill"
        case .finalizing, .pasting: return "waveform.circle"
        case .error: return "exclamationmark.circle"
        case .idle: return "mic"
        }
    }

    /// Short text shown in the menu bar (more visible than an SF Symbol on
    /// some systems). Keep it tight — the menu bar is precious real estate.
    var menuBarLabel: String {
        switch state {
        case .recording: return "● Ink"
        case .finalizing: return "… Ink"
        case .pasting: return "↩ Ink"
        case .error: return "⚠ Ink"
        case .idle: return "Ink"
        }
    }

    func startDictation() {
        guard case .idle = state else { return }

        guard !settings.cartesiaAPIKey.isEmpty else {
            setError("Missing Cartesia API key. Open Settings.")
            return
        }
        permissions.refresh()
        guard permissions.hasMicrophone else {
            setError("Microphone permission required.")
            permissions.requestMicrophone { _ in }
            return
        }
        guard permissions.hasAccessibility else {
            setError("Accessibility permission required.")
            permissions.requestAccessibility()
            return
        }

        state = .recording
        lastError = nil
        liveTranscript = ""

        let client = CartesiaStreamingClient(apiKey: settings.cartesiaAPIKey)
        self.client = client

        client.onTranscriptUpdate = { [weak self] text in
            Task { @MainActor in self?.liveTranscript = text }
        }
        client.onError = { [weak self] message in
            Task { @MainActor in self?.setError(message) }
        }
        client.onClosed = { [weak self] finalText in
            Task { @MainActor in
                guard let self else { return }
                let final = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if final.isEmpty {
                    self.state = .idle
                    return
                }
                self.state = .pasting
                self.paste.paste(text: final) { ok in
                    Task { @MainActor in
                        if !ok {
                            self.setError("Paste failed.")
                        } else {
                            self.state = .idle
                        }
                    }
                }
            }
        }

        client.connect()

        do {
            try audio.start { [weak self] data in
                self?.client?.sendAudio(data)
            }
        } catch {
            setError("Audio start failed: \(error.localizedDescription)")
            client.cancel()
            self.client = nil
        }
    }

    func stopDictation() {
        guard case .recording = state else { return }
        state = .finalizing
        audio.stop()
        client?.finalizeAndClose()
    }

    private func setError(_ message: String) {
        lastError = message
        state = .error(message)
        audio.stop()
        client?.cancel()
        client = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            Task { @MainActor in
                if case .error = self?.state { self?.state = .idle }
            }
        }
    }
}
