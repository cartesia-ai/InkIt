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
    private let contextResolver = ContextResolver()
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
    /// When a take is routed to an in-app box (see `routeToOnboardingBox`), should
    /// it also be saved to history? The onboarding Try-it step keeps this off and
    /// logs once on send; the Home empty-state try box turns it on so the very
    /// first take both lands in the box and persists — instantly replacing the
    /// empty state with a real transcript row.
    var logTrialTakesToHistory = false
    /// Monotonic timestamp of the most recent hotkey release, used as the
    /// anchor for per-dictation latency measurements.
    private var releaseTime: DispatchTime?
    /// Polish pipeline warmed at key-press so its setup overlaps the time the
    /// user spends speaking, instead of landing on the critical path after
    /// release. `warmRewriter` holds an already-connected LLM session;
    /// `pendingContextTask` is the in-flight screen-context capture (its log
    /// runID is `pendingContextRunID`). All three are consumed once in
    /// `correctedTranscript` and reset on every `startDictation`.
    private var warmRewriter: TranscriptRewriter?
    private var pendingContextTask: Task<ContextSnapshot, Never>?
    private var pendingContextRunID: String?

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
                hud = NotchHUDController(coordinator: self)
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
                } else if !hasAX && self.hadAccessibility {
                    self.hadAccessibility = false
                    // Accessibility was revoked mid-session, which kills the Fn
                    // CGEventTap. Re-register so the binding downgrades to the
                    // passive monitor instead of leaving a dead tap that silently
                    // swallows key presses. When AX is restored the branch above
                    // upgrades back to the suppressing tap.
                    if self.isHotkeyRegistered { self.registerHotkey() }
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
        // Surface the real Notch HUD during the trial so the "Try it" step
        // mimics actual use — the recording island and live waveform appear up
        // by the notch, exactly as they will every day after onboarding.
        if hud == nil {
            hud = NotchHUDController(coordinator: self)
        }
    }

    func endOnboardingTrial() {
        routesFinalTranscriptToOnboarding = false
        if !settings.hasCompletedOnboarding {
            unregisterHotkey()
            // Tear the HUD back down so it doesn't linger over the remaining
            // onboarding steps; refreshHUD re-creates it once onboarding completes.
            hud?.dismiss()
            hud = nil
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
            // Mirror the microphone-denied experience: surface the HUD error and
            // route the user to fix it. requestAccessibility fires the system
            // "InkIt would like to control this computer" prompt (first press
            // after a revoke) and opens the Accessibility pane; later presses
            // just re-open Settings, the same way a denied mic re-opens its pane.
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
        // The onboarding trial box should only capture dictation when InkIt
        // itself is frontmost — i.e. the user is actually looking at the box.
        // If they've clicked into another app, behave like normal dictation
        // and paste at their real cursor; otherwise the box silently swallows
        // text meant for whatever they were focused on.
        let routeToOnboardingBox = routesFinalTranscriptToOnboarding
            && frontmostApp?.bundleIdentifier == ownBundleID
        // The trial box never shows interim transcript. While dictating into
        // another app the box must stay empty (the final text pastes at the real
        // cursor, and the preview must not leak into a box they aren't looking
        // at). And even when routed to the box itself, we deliberately hold the
        // words back until release — they land all at once when the final
        // transcript arrives in onClosed, rather than flickering in word-by-word.
        // That makes the reveal feel like a result, not a live caption.
        let suppressLivePreview = routesFinalTranscriptToOnboarding
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

        // Pre-warm the polish pipeline at key-press so its cost overlaps the
        // time the user is still speaking rather than landing on the critical
        // path after release. Two independent warmups, skipped for the
        // onboarding/Home try box (which never polishes):
        //   1. Open the LLM connection (DNS+TCP+TLS) so the polish POST reuses it.
        //   2. Capture screen context now — it depends on the focused window,
        //      not the transcript text, so there's no reason to wait for the
        //      final turn. `correctedTranscript` awaits this task instead of
        //      starting capture from scratch.
        warmRewriter = nil
        pendingContextTask = nil
        pendingContextRunID = nil
        if !routeToOnboardingBox,
           settings.correctionEnabled,
           !settings.apiKey(for: settings.rewriteProvider).isEmpty {
            let provider = settings.rewriteProvider
            let rewriter = TranscriptRewriter(provider: provider,
                                              model: settings.rewriteModel,
                                              apiKey: settings.apiKey(for: provider))
            rewriter.prewarm()
            warmRewriter = rewriter

            if settings.screenContextEnabled, permissions.hasAccessibility, capturedSnapshot != nil {
                let runID = Self.makeCorrectionRunID()
                pendingContextRunID = runID
                let resolver = contextResolver
                DebugLog.info("[\(runID)] prewarm: capturing context at key-press target=\(capturedSnapshot?.logDescription ?? "nil")")
                pendingContextTask = Task { await resolver.captureContext(target: capturedSnapshot, runID: runID) }
            }
        }

        let client = CartesiaStreamingClient(apiKey: settings.cartesiaAPIKey)
        self.client = client

        client.onTranscriptUpdate = { [weak self, suppressLivePreview] text in
            Task { @MainActor in
                guard let self, !suppressLivePreview else { return }
                self.liveTranscript = text
            }
        }
        client.onError = { [weak self] message in
            Task { @MainActor in self?.setError(message) }
        }
        client.onClosed = { [weak self, capturedTargetApp, capturedSnapshot, routeToOnboardingBox] finalText in
            Task { @MainActor in
                guard let self else { return }
                let transcriptArrived = DispatchTime.now()
                let release = self.releaseTime
                let raw = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    self.state = .idle
                    return
                }
                if routeToOnboardingBox {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    self.liveTranscript = raw
                    // The trial is verbatim — no polish ran — so log it as an
                    // `.off` entry with no latency/diff. Only the Home try box
                    // opts into this; onboarding logs on send instead.
                    if self.logTrialTakesToHistory {
                        self.history.add(raw, polish: .off)
                    }
                    self.state = .idle
                    return
                }

                let correction = await self.correctedTranscript(
                    raw: raw,
                    targetSnapshot: capturedSnapshot
                )
                // Keep the persisted "key stopped working" state honest: a clean
                // rewrite clears it; an auth rejection (401/403) sets it so the
                // Polish settings pane shows the paused/re-enter state instead of
                // silently pasting raw.
                if correction.outcome == .polished {
                    self.settings.polishKeyInvalid = false
                } else if correction.outcome == .failed, correction.failure?.reason == .invalidKey {
                    self.settings.polishKeyInvalid = true
                }
                let polishFinished = DispatchTime.now()

                self.state = .pasting
                self.paste.paste(text: correction.text, targetApp: capturedTargetApp) { ok in
                    Task { @MainActor in
                        self.pasteTargetApp = nil
                        self.contextTargetSnapshot = nil
                        if !ok {
                            self.setError("Paste failed.")
                        } else {
                            let pasteFinished = DispatchTime.now()
                            let latency = release.map { start in
                                TranscriptHistoryStore.Latency(
                                    transcribeMs: Self.elapsedMs(start, transcriptArrived),
                                    polishMs: Self.elapsedMs(transcriptArrived, polishFinished),
                                    pasteMs: Self.elapsedMs(polishFinished, pasteFinished)
                                )
                            }
                            self.history.add(
                                correction.text,
                                original: correction.original,
                                latency: latency,
                                polish: correction.outcome,
                                failure: correction.failure
                            )
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
        releaseTime = .now()
        state = .finalizing
        if settings.playFeedbackSounds { FeedbackSoundPlayer.shared.playStop() }
        audio.stop()
        client?.finalizeAndClose()
    }

    /// Result of the optional AI-correction pass: the text to paste plus how
    /// correction turned out, so history can show the right indicator.
    private struct Correction {
        let text: String
        let outcome: TranscriptHistoryStore.PolishOutcome
        let original: String?
        var failure: TranscriptHistoryStore.PolishFailure?
    }

    /// Maps a rewriter result to a `Correction`. `.success` keeps the raw text
    /// alongside for diffing (even when unchanged); `.failure` falls back to raw
    /// and records why, so the history row can explain it.
    private static func polishResult(raw: String,
                                     result: Result<String, RewriteFailure>,
                                     provider: LLMProvider) -> Correction {
        switch result {
        case .success(let rewritten):
            return Correction(text: rewritten, outcome: .polished, original: raw)
        case .failure(let failure):
            let reason: TranscriptHistoryStore.PolishFailureReason
            var retryAt: Date?
            switch failure {
            case .rateLimited(let at): reason = .rateLimited; retryAt = at
            case .offline:             reason = .offline
            case .timedOut:            reason = .timedOut
            case .invalidKey:          reason = .invalidKey
            case .serverError:         reason = .serverError
            case .unknown:             reason = .unknown
            }
            let polishFailure = TranscriptHistoryStore.PolishFailure(
                reason: reason,
                provider: provider.displayName,
                retryAt: retryAt
            )
            return Correction(text: raw, outcome: .failed, original: nil, failure: polishFailure)
        }
    }

    /// Optionally runs the raw transcript through the AI correction pipeline.
    /// Returns the corrected text and outcome on success, or `raw`/`.off` if
    /// correction is disabled or skipped, or `raw`/`.failed` if the rewrite
    /// errored. Never throws — the user must always get at least the raw
    /// transcript pasted.
    private func correctedTranscript(
        raw: String,
        targetSnapshot: TargetAppSnapshot?
    ) async -> Correction {
        // Reuse the runID minted when context capture was kicked off at
        // key-press so its logs correlate; fall back to a fresh one when no
        // capture was prelaunched (context disabled, or polish off at press).
        let runID = pendingContextRunID ?? Self.makeCorrectionRunID()
        let enabled = settings.correctionEnabled
        let hasKey = !settings.apiKey(for: settings.rewriteProvider).isEmpty
        let hasAX = permissions.hasAccessibility
        let screenContext = settings.screenContextEnabled
        // Single grep-able marker for per-app context diagnosis. One CTX line is
        // emitted on every terminal branch below — `grep CTX ~/Library/Logs/InkIt-debug.log`
        // gives one row per dictation: which app, confidence, content chars, and
        // what we actually did with it.
        let appTag: String = {
            guard let s = targetSnapshot else { return "app=nil bundle=nil" }
            return "app=\(s.localizedName) bundle=\(s.bundleIdentifier ?? "nil")"
        }()
        DebugLog.info("[\(runID)] correctedTranscript: raw=\"\(raw)\" enabled=\(enabled) hasKey=\(hasKey) hasAX=\(hasAX) screenContext=\(screenContext)")
        guard enabled, hasKey else {
            DebugLog.info("[\(runID)] correctedTranscript: skipping (enabled=\(enabled) hasKey=\(hasKey))")
            DebugLog.info("[\(runID)] CTX \(appTag) screenContext=\(screenContext) confidence=n/a contentChars=0 outcome=off reason=\(!enabled ? "correction-off" : "no-api-key")")
            return Correction(text: raw, outcome: .off, original: nil)
        }

        let provider = settings.rewriteProvider
        let apiKey = settings.apiKey(for: provider)
        // Prefer the connection-warmed rewriter opened at key-press; build a
        // fresh one only if prewarm was skipped (e.g. settings changed mid-hold).
        let rewriter = warmRewriter ?? TranscriptRewriter(provider: provider, model: settings.rewriteModel, apiKey: apiKey)
        warmRewriter = nil

        // The user opted out of screen context: polish the transcript on its
        // own (filler/homophone cleanup) without reading any on-screen text.
        guard screenContext else {
            DebugLog.info("[\(runID)] correctedTranscript: screen context disabled — context-free polish")
            DebugLog.info("[\(runID)] CTX \(appTag) screenContext=false confidence=n/a contentChars=0 outcome=context-free reason=screen-context-off")
            state = .rewriting
            let result = await rewriter.rewriteWithoutContext(transcript: raw, runID: runID)
            return Self.polishResult(raw: raw, result: result, provider: provider)
        }

        let targetDesc: String = {
            guard let snapshot = targetSnapshot else { return "nil(no-target-snapshot)" }
            return snapshot.logDescription
        }()
        DebugLog.info("[\(runID)] correctedTranscript: target=\(targetDesc) provider=\(provider.rawValue)/\(settings.rewriteModel) key=set(\(apiKey.count)c)")

        guard hasAX, targetSnapshot != nil else {
            DebugLog.info("[\(runID)] correctedTranscript: raw fallback reason=\(!hasAX ? "missing accessibility" : "missing target snapshot")")
            DebugLog.info("[\(runID)] CTX \(appTag) screenContext=true confidence=n/a contentChars=0 outcome=raw reason=\(!hasAX ? "missing-accessibility" : "missing-target-snapshot")")
            return Correction(text: raw, outcome: .off, original: nil)
        }

        // Await the capture started at key-press; only start one here if that
        // prewarm didn't run (its conditions are a subset of this path's).
        let snapshot: ContextSnapshot
        if let task = pendingContextTask {
            pendingContextTask = nil
            snapshot = await task.value
        } else {
            snapshot = await contextResolver.captureContext(target: targetSnapshot, runID: runID)
        }
        DebugLog.info("[\(runID)] selected context: \(snapshot.logSummary)")
        DebugLog.infoBlock(title: "[\(runID)] selected context payload", text: snapshot.payload)

        switch ContextCorrectionGate.decision(for: snapshot) {
        case .pasteRaw(let reason):
            // Context was unusable (chrome-only, empty, or the window changed
            // mid-capture). Don't feed junk to the model — degrade to a
            // context-free polish so filler/homophone cleanup still happens.
            DebugLog.info("[\(runID)] correctedTranscript: context unusable (\(reason)) — context-free polish")
            DebugLog.info("[\(runID)] CTX \(appTag) screenContext=true confidence=\(snapshot.confidence) contentChars=\(snapshot.evidence["contentChars"] ?? "0") outcome=context-free reason=\(reason)")
            state = .rewriting
            let result = await rewriter.rewriteWithoutContext(transcript: raw, runID: runID)
            return Self.polishResult(raw: raw, result: result, provider: provider)
        case .rewrite(let snapshot):
            DebugLog.info("[\(runID)] CTX \(appTag) screenContext=true confidence=\(snapshot.confidence) contentChars=\(snapshot.evidence["contentChars"] ?? "?") payloadChars=\(snapshot.payload.count) outcome=rewrite-with-context")
            state = .rewriting
            let result = await rewriter.rewriteWithRawContext(
                transcript: raw,
                context: snapshot.payload,
                runID: runID
            )
            return Self.polishResult(raw: raw, result: result, provider: provider)
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

    /// Whole milliseconds between two monotonic timestamps, clamped at 0.
    private static func elapsedMs(_ start: DispatchTime, _ end: DispatchTime) -> Int {
        guard end.uptimeNanoseconds > start.uptimeNanoseconds else { return 0 }
        return Int((end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}
