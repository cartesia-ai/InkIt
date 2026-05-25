import Foundation
import SwiftUI
import AppKit
import Combine

enum DictationState: Equatable {
    case idle
    case recording
    case finalizing
    case rewriting
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
    private static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    private let contextResolver = ContextResolver(cursorBundleID: AppCoordinator.cursorBundleID)
    let settings = SettingsStore.shared
    let history = TranscriptHistoryStore.shared
    private var hud: NotchHUDController?
    private var cancellables = Set<AnyCancellable>()
    private var hadAccessibility = false
    private var isHotkeyRegistered = false
    private var lastExternalApp: NSRunningApplication?
    private var pasteTargetApp: NSRunningApplication?
    private var contextTargetSnapshot: TargetAppSnapshot?
    private var routesFinalTranscriptToOnboarding = false

    init() {
        detectDuplicateRunningCopies()
        startTrackingActiveApps()
        seedLastExternalApp()
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

    /// `didActivateApplicationNotification` fires only on app transitions. If
    /// the user holds Fn while InkIt is frontmost before ever Cmd-Tabbing
    /// away, `lastExternalApp` stays nil and `pasteTargetApp` resolves to
    /// nil. Seed from the current frontmost (if non-InkIt) or the first
    /// non-InkIt regular running app so the fallback chain always has
    /// something usable.
    private func seedLastExternalApp() {
        let ownBundleID = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != ownBundleID {
            lastExternalApp = front
            return
        }
        lastExternalApp = NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != ownBundleID
                && !$0.isTerminated
                && $0.isFinishedLaunching
        }
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
        case .rewriting: return "Polishing…"
        case .pasting: return "Pasting…"
        case .error(let m): return "Error: \(m)"
        }
    }

    var statusColor: Color {
        switch state {
        case .idle: return .secondary
        case .recording: return .red
        case .finalizing, .rewriting, .pasting: return .orange
        case .error: return .red
        }
    }

    var menuBarIconName: String {
        switch state {
        case .recording: return "waveform.circle.fill"
        case .finalizing, .rewriting, .pasting: return "waveform.circle"
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
        case .rewriting: return "✎ Ink"
        case .pasting: return "↩ Ink"
        case .error: return "⚠ Ink"
        case .idle: return "Ink"
        }
    }

    func beginOnboardingTrial() {
        routesFinalTranscriptToOnboarding = true
        liveTranscript = ""
        ensureHotkeyRegistration()
    }

    func endOnboardingTrial() {
        routesFinalTranscriptToOnboarding = false
        if !settings.hasCompletedOnboarding {
            unregisterHotkey()
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
        if settings.playFeedbackSounds { FeedbackSoundPlayer.shared.playStart() }
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let ownBundleID = Bundle.main.bundleIdentifier
        pasteTargetApp = {
            if let frontmostApp, frontmostApp.bundleIdentifier != ownBundleID {
                return frontmostApp
            }
            return lastExternalApp
        }()
        contextTargetSnapshot = TargetAppSnapshot.capture(from: pasteTargetApp)
        DebugLog.info("startDictation: frontmost=\(frontmostApp?.bundleIdentifier ?? "nil") lastExternal=\(lastExternalApp?.bundleIdentifier ?? "nil") resolvedTarget=\(pasteTargetApp?.bundleIdentifier ?? "nil") targetSnapshot=\(contextTargetSnapshot?.logDescription ?? "nil")")

        // Capture the resolved target and snapshot into the onClosed closure.
        // Instance state (pasteTargetApp / contextTargetSnapshot) can be wiped
        // mid-flight by setError or a stale paste callback, which would cause
        // correctedTranscript to fall back to raw paste even though we had a
        // perfectly good target at recording start.
        let capturedTargetApp = pasteTargetApp
        let capturedSnapshot = contextTargetSnapshot

        let client = CartesiaStreamingClient(apiKey: settings.cartesiaAPIKey)
        self.client = client

        client.onTranscriptUpdate = { [weak self] text in
            Task { @MainActor in self?.liveTranscript = text }
        }
        client.onError = { [weak self] message in
            Task { @MainActor in self?.setError(message) }
        }
        client.onClosed = { [weak self, capturedTargetApp, capturedSnapshot] finalText in
            Task { @MainActor in
                guard let self else { return }
                let raw = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    self.state = .idle
                    return
                }
                if self.routesFinalTranscriptToOnboarding {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    self.liveTranscript = raw
                    self.state = .idle
                    return
                }

                let corrected = await self.correctedTranscript(
                    raw: raw,
                    targetApp: capturedTargetApp,
                    targetSnapshot: capturedSnapshot
                )

                self.state = .pasting
                self.paste.paste(text: corrected, targetApp: capturedTargetApp) { ok in
                    Task { @MainActor in
                        self.pasteTargetApp = nil
                        self.contextTargetSnapshot = nil
                        if !ok {
                            self.setError("Paste failed.")
                        } else {
                            self.history.add(corrected)
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
        if settings.playFeedbackSounds { FeedbackSoundPlayer.shared.playStop() }
        audio.stop()
        client?.finalizeAndClose()
    }

    /// Optionally runs the raw transcript through the AI correction pipeline.
    /// Returns the corrected text on success, or `raw` if correction is
    /// disabled or anything fails. Never throws — the user must always get
    /// at least the raw transcript pasted.
    private func correctedTranscript(
        raw: String,
        targetApp: NSRunningApplication?,
        targetSnapshot: TargetAppSnapshot?
    ) async -> String {
        let runID = Self.makeCorrectionRunID()
        let enabled = settings.correctionEnabled
        let hasKey = !settings.anthropicAPIKey.isEmpty
        let hasAX = permissions.hasAccessibility
        DebugLog.info("[\(runID)] correctedTranscript: raw=\"\(raw)\" enabled=\(enabled) hasKey=\(hasKey) hasAX=\(hasAX)")
        guard enabled, hasKey else {
            DebugLog.info("[\(runID)] correctedTranscript: skipping (enabled=\(enabled) hasKey=\(hasKey))")
            return raw
        }

        let apiKey = settings.anthropicAPIKey
        let rewriter = TranscriptRewriter(apiKey: apiKey)

        let targetDesc: String = {
            guard let snapshot = targetSnapshot else { return "nil(no-target-snapshot)" }
            return snapshot.logDescription
        }()
        DebugLog.info("[\(runID)] correctedTranscript: target=\(targetDesc) anthropicKey=set(\(apiKey.count)c)")

        guard hasAX, targetSnapshot != nil else {
            DebugLog.info("[\(runID)] correctedTranscript: raw fallback reason=\(!hasAX ? "missing accessibility" : "missing target snapshot")")
            return raw
        }

        let snapshot = await contextResolver.captureContext(target: targetSnapshot, app: targetApp, runID: runID)
        DebugLog.info("[\(runID)] selected context: \(snapshot.logSummary)")
        DebugLog.infoBlock(title: "[\(runID)] selected context payload", text: snapshot.payload)

        switch ContextCorrectionGate.decision(for: snapshot) {
        case .pasteRaw(let reason):
            DebugLog.info("[\(runID)] correctedTranscript: raw fallback reason=\(reason)")
            return raw
        case .rewrite(let snapshot):
            state = .rewriting
            if snapshot.source == .cursorSession {
                guard let transcriptPath = snapshot.evidence["transcriptPath"],
                      let uuid = snapshot.evidence["sessionUUID"] else {
                    DebugLog.info("[\(runID)] correctedTranscript: cursor raw fallback reason=missing transcript evidence")
                    return raw
                }
                let url = URL(fileURLWithPath: transcriptPath)
                let messages = ConversationLoader.load(from: url)
                guard !messages.isEmpty else {
                    DebugLog.info("[\(runID)] correctedTranscript: cursor raw fallback reason=empty parsed messages")
                    return raw
                }
                let summary: String? = await {
                    let fresh = await SessionSummarizer.ensureFresh(
                        uuid: uuid,
                        transcriptPath: transcriptPath,
                        messages: messages,
                        apiKey: apiKey
                    )
                    return fresh?.summary
                }()
                let rewritten = await rewriter.rewriteWithCursorSession(
                    transcript: raw,
                    summary: summary,
                    recentTurns: snapshot.payload,
                    runID: runID
                )
                return rewritten ?? raw
            }

            let rewritten = await rewriter.rewriteWithRawContext(
                transcript: raw,
                context: snapshot.payload,
                runID: runID
            )
            return rewritten ?? raw
        }
    }

    private func setError(_ message: String) {
        DebugLog.info("setError: \(message)")
        pasteTargetApp = nil
        contextTargetSnapshot = nil
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

    private static func makeCorrectionRunID() -> String {
        String(UUID().uuidString.prefix(8))
    }
}
