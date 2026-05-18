import Foundation
import SwiftUI
import AppKit
import Combine

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
    @Published private(set) var inputLevel: Float = 0

    private let audio = AudioCaptureService()
    private let paste = PasteService()
    let permissions = PermissionsService.shared
    private let hotkey = HotkeyManager()
    private var client: CartesiaStreamingClient?
    let settings = SettingsStore.shared
    let history = TranscriptHistoryStore.shared
    private var hud: NotchHUDController?
    private var cancellables = Set<AnyCancellable>()
    private var hadAccessibility = false
    private var isHotkeyRegistered = false
    private var lastExternalApp: NSRunningApplication?
    private var pasteTargetApp: NSRunningApplication?
    private var routesFinalTranscriptToOnboarding = false

    init() {
        detectDuplicateRunningCopies()
        startTrackingActiveApps()
        hotkey.onPress = { [weak self] in
            Task { @MainActor in self?.startDictation() }
        }
        hotkey.onRelease = { [weak self] in
            Task { @MainActor in self?.stopDictation() }
        }
        audio.onLevel = { [weak self] level in
            Task { @MainActor in self?.inputLevel = level }
        }
        // Show the notch HUD only after the user has completed onboarding,
        // so it doesn't compete with the first-launch window.
        refreshHUD()
        settings.$hasCompletedOnboarding
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshHUD() }
            }
            .store(in: &cancellables)
    }

    private func startTrackingActiveApps() {
        let ownBundleID = Bundle.main.bundleIdentifier
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard
                    let self,
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.bundleIdentifier != ownBundleID
                else { return }
                self.lastExternalApp = app
            }
            .store(in: &cancellables)
    }

    private func detectDuplicateRunningCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier == bundleID && app.processIdentifier != currentPID
        }
        guard !others.isEmpty else { return }

        let currentPath = Bundle.main.bundlePath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let otherPaths = others.compactMap(\.bundleURL?.path)
            .map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
            .joined(separator: ", ")
        lastError = "Multiple InkIt copies are running. Current: \(currentPath). Also running: \(otherPaths). Quit the duplicate copy and grant Accessibility to only one app bundle."
    }

    private func refreshHUD() {
        if settings.hasCompletedOnboarding {
            if hud == nil {
                hud = NotchHUDController(coordinator: self, history: history)
            }
            ensureHotkeyRegistration()
        } else {
            hud?.dismiss()
            hud = nil
            unregisterHotkey()
        }
        permissions.startPolling()
        hadAccessibility = permissions.hasAccessibility
        // When Accessibility flips on, re-register so the Fn binding can
        // upgrade from the passive monitor to the suppressing event tap.
        permissions.$hasAccessibility
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasAX in
                guard let self else { return }
                if hasAX && !self.hadAccessibility {
                    self.hadAccessibility = true
                    self.registerHotkey()
                } else if !hasAX {
                    self.hadAccessibility = false
                }
            }
            .store(in: &cancellables)
    }

    func registerHotkey() {
        isHotkeyRegistered = true
        hotkey.register(binding: settings.hotkey)
    }

    func unregisterHotkey() {
        guard isHotkeyRegistered else { return }
        hotkey.unregister()
        isHotkeyRegistered = false
    }

    private func ensureHotkeyRegistration() {
        guard !isHotkeyRegistered else { return }
        registerHotkey()
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

    func beginOnboardingTrial() {
        routesFinalTranscriptToOnboarding = true
        liveTranscript = ""
    }

    func endOnboardingTrial() {
        routesFinalTranscriptToOnboarding = false
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
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let ownBundleID = Bundle.main.bundleIdentifier
        pasteTargetApp = {
            if let frontmostApp, frontmostApp.bundleIdentifier != ownBundleID {
                return frontmostApp
            }
            return lastExternalApp
        }()

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
                    self.pasteTargetApp = nil
                    self.state = .idle
                    return
                }
                if self.routesFinalTranscriptToOnboarding {
                    self.pasteTargetApp = nil
                    self.liveTranscript = final
                    self.state = .idle
                    return
                }
                self.state = .pasting
                self.paste.paste(text: final, targetApp: self.pasteTargetApp) { ok in
                    Task { @MainActor in
                        self.pasteTargetApp = nil
                        if !ok {
                            self.setError("Paste failed.")
                        } else {
                            self.history.add(final)
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
        pasteTargetApp = nil
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
