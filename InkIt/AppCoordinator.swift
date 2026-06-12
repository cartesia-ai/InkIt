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
    /// No editable field was focused at release, so the transcript was kept in
    /// History instead of pasted. A brief, self-clearing confirmation state.
    case heldInHistory
    case error(String)
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var inputLevel: Float = 0
    /// Whether the input device is actually capturing yet. False for the brief
    /// window after the hotkey while the mic comes up (notably the Bluetooth
    /// A2DP→HFP profile switch, ~200–500ms). The HUD shows a "preparing" cue
    /// until this flips true, so the user doesn't speak into the dead gap and
    /// lose their first words. See `AudioCaptureService.onReady`.
    @Published private(set) var audioReady: Bool = false

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
    /// When the dictation hot path last routed the user to Accessibility
    /// Settings. Mashing the key — or pressing again after clicking Deny —
    /// must not yank System Settings to the front on every press, so we
    /// re-open it at most once per `accessibilityPromptThrottle`. The HUD
    /// error still shows every time.
    private var lastAccessibilityPrompt: Date?
    private let accessibilityPromptThrottle: TimeInterval = 10
    private var lastExternalApp: NSRunningApplication?
    private var pasteTargetApp: NSRunningApplication?
    private var contextTargetSnapshot: TargetAppSnapshot?
    private var routesFinalTranscriptToOnboarding = false
    /// Transcribe latency of the most recent trial take (the trial neither
    /// polishes nor pastes, so transcribe is the whole story). Captured so the
    /// onboarding Try-it step can persist it alongside the saved transcript,
    /// letting Home's "avg time to text" show a real number on first landing.
    private(set) var lastTrialLatency: TranscriptHistoryStore.Latency?
    /// Monotonic timestamp of the most recent hotkey release, used as the
    /// anchor for per-dictation latency measurements.
    private var releaseTime: DispatchTime?
    /// LLM session connection-warmed at key-press so its TLS/TCP setup overlaps
    /// the time the user spends speaking, instead of landing on the critical
    /// path after release. Consumed once in `correctedTranscript` and reset on
    /// every `startDictation`.
    private var warmRewriter: TranscriptRewriter?

    #if DEBUG
    private let mainThreadWatchdog = MainThreadWatchdog()
    #endif

    init() {
        #if DEBUG
        mainThreadWatchdog.start()
        #endif
        detectDuplicateRunningCopies()
        startTrackingActiveApps()
        seedLastExternalApp()
        hotkey.onPress = { [weak self] in
            Task { @MainActor in self?.handleHotkeyPress() }
        }
        hotkey.onRelease = { [weak self] in
            Task { @MainActor in self?.handleHotkeyRelease() }
        }
        audio.onLevel = { [weak self] level in
            Task { @MainActor in self?.inputLevel = level }
        }
        audio.onReady = { [weak self] in
            Task { @MainActor in self?.audioReady = true }
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
                    self.lastAccessibilityPrompt = nil
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
        case .recording: return "Live"
        case .finalizing: return "Finalizing…"
        case .rewriting: return "Polishing…"
        case .pasting: return "Pasting…"
        case .heldInHistory: return "Saved to History"
        case .error(let m): return "Error: \(m)"
        }
    }

    var statusColor: Color {
        switch state {
        case .idle: return .secondary
        case .recording: return Color(nsColor: .systemOrange)
        case .finalizing, .rewriting, .pasting: return .orange
        case .heldInHistory: return .secondary
        case .error: return .red
        }
    }

    var menuBarIconName: String {
        switch state {
        case .recording: return "waveform.circle.fill"
        case .finalizing, .rewriting, .pasting: return "waveform.circle"
        case .heldInHistory: return "tray.and.arrow.down"
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
        case .heldInHistory: return "⬇ Ink"
        case .error: return "⚠ Ink"
        case .idle: return "Ink"
        }
    }

    func beginOnboardingTrial() {
        routesFinalTranscriptToOnboarding = true
        lastTrialLatency = nil
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

    /// Hotkey press. In hold mode this starts dictation (release stops it). In
    /// hands-free mode a press flips recording on or off, so the next press is
    /// what stops and pastes — just like releasing the key in hold mode.
    private func handleHotkeyPress() {
        switch settings.dictationMode {
        case .hold:
            isHotkeyHeld = true
            startDictation()
        case .toggle:
            if case .recording = state {
                stopDictation()
            } else {
                startDictation()
            }
        }
    }

    /// Hotkey release. Only hold mode acts on release; in hands-free mode the
    /// next press is what stops recording, so a release is ignored.
    private func handleHotkeyRelease() {
        guard settings.dictationMode == .hold else { return }
        isHotkeyHeld = false
        // An error shown during the hold has been held on screen; now that the
        // user has finished, give it a clean dwell from release, then it clears.
        if case .error = state {
            armErrorDismiss()
            return
        }
        stopDictation()
    }

    func startDictation() {
        // Start not just from idle but from the brief unhappy-path notices
        // (held-in-history, error): pressing the hotkey during one of those
        // clearly means "let me dictate again," so don't block it (which also
        // stopped the dead key-press from triggering the system error beep). A
        // dictation actually in flight still guards against a double-start.
        switch state {
        case .idle, .heldInHistory, .error: break
        default: return
        }
        errorDismissWork?.cancel()

        guard !settings.cartesiaAPIKey.isEmpty else {
            setError("Add your API key")
            return
        }
        permissions.refresh()
        guard permissions.hasMicrophone else {
            setError("Mic access needed")
            permissions.requestMicrophone { _ in }
            return
        }
        guard permissions.hasAccessibility else {
            // Mirror the microphone-denied experience: surface the HUD error and
            // route the user to fix it. requestAccessibility fires the system
            // "InkIt would like to control this computer" prompt and opens the
            // Accessibility pane. Throttle the Settings re-open so mashing the
            // key (or pressing again after Deny) doesn't yank it to the front
            // on every press — the HUD error below still nudges every time.
            setError("Accessibility needed")
            let now = Date()
            let shouldPrompt = lastAccessibilityPrompt
                .map { now.timeIntervalSince($0) > accessibilityPromptThrottle } ?? true
            if shouldPrompt {
                lastAccessibilityPrompt = now
                permissions.requestAccessibility()
            }
            return
        }

        state = .recording
        audioReady = false
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

        // Nudge a Chromium/Electron target (Slack, VS Code, etc.) into building
        // its full accessible tree now, at press, so its focused textbox is
        // visible by the time we re-check editability at release. Done lazily by
        // Chromium otherwise, which makes the release-time check race the tree
        // and wrongly hold the transcript in History. No-op for native apps.
        if let targetPid = pasteTargetApp?.processIdentifier {
            FocusedEditable.enableWebAccessibility(pid: targetPid)
        }

        // Capture the resolved target and snapshot into the onClosed closure.
        // Instance state (pasteTargetApp / contextTargetSnapshot) can be wiped
        // mid-flight by setError or a stale paste callback, which would cause
        // correctedTranscript to fall back to raw paste even though we had a
        // perfectly good target at recording start.
        let capturedTargetApp = pasteTargetApp
        let capturedSnapshot = contextTargetSnapshot

        // Pre-warm the polish LLM connection (DNS+TCP+TLS) at key-press so its
        // setup overlaps the time the user is still speaking rather than landing
        // on the critical path after release. Skipped for the onboarding/Home
        // try box (which never polishes).
        warmRewriter = nil
        if !routeToOnboardingBox,
           settings.correctionEnabled,
           !settings.apiKey(for: settings.rewriteProvider).isEmpty {
            let provider = settings.rewriteProvider
            let rewriter = TranscriptRewriter(provider: provider,
                                              model: settings.rewriteModel,
                                              apiKey: settings.apiKey(for: provider))
            rewriter.prewarm()
            warmRewriter = rewriter
        }

        let client = CartesiaStreamingClient(apiKey: settings.cartesiaAPIKey)
        self.client = client

        client.onTranscriptUpdate = { [weak self, suppressLivePreview] text in
            Task { @MainActor in
                guard let self, !suppressLivePreview else { return }
                self.liveTranscript = text
            }
        }
        client.onError = { [weak self] failure in
            Task { @MainActor in self?.handleSTTFailure(failure) }
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
                // A real transcript came back, so the Cartesia key works and
                // credits are available: clear any persisted "transcription paused"
                // state driving the Home card.
                self.settings.cartesiaKeyInvalid = false
                self.settings.cartesiaOutOfCredits = false
                if routeToOnboardingBox {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    self.liveTranscript = raw
                    // The trial is verbatim — no polish, no paste — so the only
                    // latency that applies is transcribe (release → final text).
                    // Capture it so the practice card can persist it alongside the
                    // saved transcript; the card logs the take to history itself on
                    // send (as `.off`, no diff).
                    self.lastTrialLatency = release.map { start in
                        TranscriptHistoryStore.Latency(
                            transcribeMs: Self.elapsedMs(start, transcriptArrived),
                            polishMs: 0,
                            pasteMs: 0
                        )
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
                    self.settings.polishOutOfCredits = false
                } else if correction.outcome == .failed, let reason = correction.failure?.reason {
                    if reason == .invalidKey { self.settings.polishKeyInvalid = true }
                    else if reason == .outOfCredits { self.settings.polishOutOfCredits = true }
                }
                let polishFinished = DispatchTime.now()

                // Re-check at release whether an editable field is actually
                // focused. The target app was resolved at hotkey press; if the
                // user clicked a surface with no text field (or focus moved
                // during dictation), pasting now would fire Cmd+V into the wrong
                // app or nowhere. In that case hold the transcript in History —
                // it's still saved and copyable — rather than guess.
                let focus = await FocusedEditable.current()
                guard focus.isEditable else {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    let latency = release.map { start in
                        TranscriptHistoryStore.Latency(
                            transcribeMs: Self.elapsedMs(start, transcriptArrived),
                            polishMs: Self.elapsedMs(transcriptArrived, polishFinished),
                            pasteMs: 0
                        )
                    }
                    self.history.add(
                        correction.text,
                        original: correction.original,
                        latency: latency,
                        polish: correction.outcome,
                        failure: correction.failure
                    )
                    DebugLog.info("onClosed: no editable field focused at release — held in History instead of pasting")
                    self.showHeldInHistoryNotice()
                    return
                }

                self.state = .pasting
                // Paste into the verified, currently-focused app rather than the
                // (possibly stale) press-time target.
                self.paste.paste(text: correction.text, targetApp: focus.app ?? capturedTargetApp) { ok in
                    Task { @MainActor in
                        self.pasteTargetApp = nil
                        self.contextTargetSnapshot = nil
                        if !ok {
                            self.setError("Paste failed")
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
            audio.preferredDeviceUID = settings.preferredInputDeviceUID
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
            case .outOfCredits:        reason = .outOfCredits
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
        let runID = Self.makeCorrectionRunID()
        let enabled = settings.correctionEnabled
        let hasKey = !settings.apiKey(for: settings.rewriteProvider).isEmpty
        // Single grep-able marker, one row per dictation: which app + outcome.
        let appTag: String = {
            guard let s = targetSnapshot else { return "app=nil bundle=nil" }
            return "app=\(s.localizedName) bundle=\(s.bundleIdentifier ?? "nil")"
        }()
        DebugLog.info("[\(runID)] correctedTranscript: raw=\"\(raw)\" enabled=\(enabled) hasKey=\(hasKey)")
        guard enabled, hasKey else {
            DebugLog.info("[\(runID)] correctedTranscript: skipping (enabled=\(enabled) hasKey=\(hasKey))")
            DebugLog.info("[\(runID)] CTX \(appTag) outcome=off reason=\(!enabled ? "correction-off" : "no-api-key")")
            return Correction(text: raw, outcome: .off, original: nil)
        }

        let provider = settings.rewriteProvider
        let apiKey = settings.apiKey(for: provider)
        // Prefer the connection-warmed rewriter opened at key-press; build a
        // fresh one only if prewarm was skipped (e.g. settings changed mid-hold).
        let rewriter = warmRewriter ?? TranscriptRewriter(provider: provider, model: settings.rewriteModel, apiKey: apiKey)
        warmRewriter = nil

        DebugLog.info("[\(runID)] CTX \(appTag) provider=\(provider.rawValue)/\(settings.rewriteModel) outcome=polish")
        state = .rewriting
        let result = await rewriter.rewriteWithoutContext(transcript: raw, runID: runID)
        return Self.polishResult(raw: raw, result: result, provider: provider)
    }

    /// Briefly surface "Saved to History" (notch + menu bar), then fall back to
    /// idle. Mirrors `setError`'s self-clearing timer but isn't an error state.
    private func showHeldInHistoryNotice() {
        state = .heldInHistory
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            Task { @MainActor in
                if case .heldInHistory = self?.state { self?.state = .idle }
            }
        }
    }

    /// Surface a classified STT failure. Every cause gets a brief notch flash
    /// (via setError → the `.error` notice, self-clearing after 2.5s). The two
    /// persistent, user-fixable causes also set a flag that drives the Home
    /// "Transcription is paused" card until the next successful dictation.
    /// True while the dictation hotkey is physically held (hold mode). Keeps an
    /// error notice up for the whole press rather than letting it flash by.
    private var isHotkeyHeld = false

    /// The pending `.error` self-clear, cancelable so a release (or a new error)
    /// can re-arm a fresh dwell. See `armErrorDismiss`.
    private var errorDismissWork: DispatchWorkItem?

    private func handleSTTFailure(_ failure: STTFailure) {
        switch failure {
        case .invalidKey:   settings.cartesiaKeyInvalid = true
        case .outOfCredits: settings.cartesiaOutOfCredits = true
        default: break
        }
        // Show the error right away — even mid-hold — so the user finds out
        // promptly instead of talking into a dead session until they release.
        // setError's dwell keeps it up while the key is held and clears after
        // release, so it neither flashes past nor persists.
        setError(failure.notchMessage)
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
        armErrorDismiss()
    }

    /// Self-clear the `.error` notice after a brief dwell — but keep it up while
    /// the hotkey is still held, so an error that fires mid-hold stays visible
    /// for the whole press (the user keeps seeing it instead of it flashing by)
    /// and only clears after they release. Re-armed on release for a clean
    /// post-release dwell. A cancelable work item so re-arming supersedes.
    ///
    /// 1.5s: the message is 2–3 words and usually already seen during the hold,
    /// so the post-release window is a confirmation tail — long enough to read
    /// cold, short enough not to feel stuck.
    private func armErrorDismiss() {
        errorDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .error = self.state else { return }
            if self.isHotkeyHeld {
                self.armErrorDismiss()   // still holding — keep showing, re-check
            } else {
                self.state = .idle
            }
        }
        errorDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
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

#if DEBUG
/// Debug-only tripwire for a blocked main run loop. A blocked main thread is the
/// precondition for the bug class this guards: historically the Fn event tap ran
/// on the main run loop, so any main-thread stall froze modifier keys; the tap
/// now runs off-main, but heavy synchronous work on main (a hand-rolled AX walk,
/// say) is still the thing that reintroduces UI hangs. This pings main on a
/// cadence and logs loudly when a round-trip exceeds the threshold — coverage
/// that event taps and AX traversal can't get from unit tests, firing the moment
/// anyone reintroduces blocking-on-main in *any* module. Never compiled into
/// release builds.
final class MainThreadWatchdog {
    private let queue = DispatchQueue(label: "com.cartesia.InkIt.MainThreadWatchdog", qos: .utility)
    private let pingInterval: TimeInterval
    private let stallThreshold: TimeInterval
    private var running = false

    init(pingInterval: TimeInterval = 0.25, stallThreshold: TimeInterval = 0.2) {
        self.pingInterval = pingInterval
        self.stallThreshold = stallThreshold
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.scheduleNextPing()
        }
    }

    func stop() {
        queue.async { [weak self] in self?.running = false }
    }

    private func scheduleNextPing() {
        queue.asyncAfter(deadline: .now() + pingInterval) { [weak self] in
            guard let self, self.running else { return }
            let sent = Date()
            DispatchQueue.main.async {
                let waited = Date().timeIntervalSince(sent)
                if waited > self.stallThreshold {
                    DebugLog.info(String(format: "MainThreadWatchdog: main run loop blocked %.0fms (threshold %.0fms)",
                                         waited * 1000, self.stallThreshold * 1000))
                }
                // Re-arm from the worker queue regardless of how long main took.
                self.scheduleNextPing()
            }
        }
    }
}
#endif
