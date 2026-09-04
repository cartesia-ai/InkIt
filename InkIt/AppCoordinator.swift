import Foundation
import AppKit
import Combine

enum RecordingMode: Equatable {
    case held
    case handsFree
}

enum DictationState: Equatable {
    case idle
    case recording(RecordingMode)
    case finalizing
    case rewriting
    case pasting
    case heldInHistory
    case error(String)
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var audioReady: Bool = false

    private let audio = AudioCaptureService()
    private let paste = PasteService()
    let permissions = PermissionsService.shared
    private let fnKey = FnKeyManager()
    private let hotkey: HotkeyManager
    private var client: CartesiaStreamingClient?
    let settings = SettingsStore.shared
    let history = TranscriptHistoryStore.shared
    private var hud: NotchHUDController?
    private var cancellables = Set<AnyCancellable>()
    private var hadAccessibility = false
    private var isHotkeyRegistered = false
    private var lastAccessibilityPrompt: Date?
    private let accessibilityPromptThrottle: TimeInterval = 10
    private var lastExternalApp: NSRunningApplication?
    private var pasteTargetApp: NSRunningApplication?
    private var contextTargetSnapshot: TargetAppSnapshot?
    private var routesFinalTranscriptToOnboarding = false
    private(set) var lastTrialLatency: TranscriptHistoryStore.Latency?
    private(set) var lastTrialRecordingMs: Int?
    private var releaseTime: DispatchTime?
    private var recordingStartTime: DispatchTime?
    private var warmRewriter: TranscriptRewriter?

    #if DEBUG
    private let mainThreadWatchdog = MainThreadWatchdog()
    #endif

    init() {
        self.hotkey = HotkeyManager(fnKey: fnKey)
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
        hotkey.onHandsFreePress = { [weak self] in
            Task { @MainActor in self?.handleHandsFreeToggle() }
        }
        audio.onLevel = { [weak self] level in
            Task { @MainActor in self?.inputLevel = level }
        }
        audio.onReady = { [weak self] in
            Task { @MainActor in self?.audioReady = true }
        }
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
                    if self.isHotkeyRegistered { self.registerHotkey() }
                }
            }
            .store(in: &cancellables)
    }

    func registerHotkey() {
        isHotkeyRegistered = true
        hotkey.register(hotkey: settings.hotkey, handsFree: settings.handsFreeHotkey)
        syncFnKey()
    }

    func unregisterHotkey() {
        guard isHotkeyRegistered else { return }
        hotkey.unregister()
        isHotkeyRegistered = false
        syncFnKey()
    }

    private func syncFnKey() {
        let needed = isHotkeyRegistered && (settings.hotkey == .fn || settings.handsFreeHotkey == .fn)
        if needed {
            fnKey.start()
        } else {
            fnKey.stop()
        }
    }

    private func ensureHotkeyRegistration() {
        guard !isHotkeyRegistered else { return }
        registerHotkey()
    }

    func beginOnboardingTrial() {
        routesFinalTranscriptToOnboarding = true
        lastTrialLatency = nil
        lastTrialRecordingMs = nil
        liveTranscript = ""
        ensureHotkeyRegistration()
        if hud == nil {
            hud = NotchHUDController(coordinator: self)
        }
    }

    func endOnboardingTrial() {
        routesFinalTranscriptToOnboarding = false
        if !settings.hasCompletedOnboarding {
            unregisterHotkey()
            hud?.dismiss()
            hud = nil
        }
    }

    private func handleHotkeyPress() {
        if case .recording(.handsFree) = state {
            stopDictation()
            return
        }
        isHotkeyHeld = true
        startDictation(mode: .held)
    }

    private func handleHotkeyRelease() {
        isHotkeyHeld = false
        if case .error = state {
            armErrorDismiss()
            return
        }
        stopDictation()
    }

    private func handleHandsFreeToggle() {
        if case .recording(.handsFree) = state {
            stopDictation()
            return
        }
        startDictation(mode: .handsFree)
    }

    func startDictation(mode: RecordingMode) {
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

        state = .recording(mode)
        recordingStartTime = .now()
        audioReady = false
        lastError = nil
        liveTranscript = ""
        if settings.playFeedbackSounds { FeedbackSoundPlayer.shared.playStart() }
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let ownBundleID = Bundle.main.bundleIdentifier
        let routeToOnboardingBox = routesFinalTranscriptToOnboarding
            && frontmostApp?.bundleIdentifier == ownBundleID
        let suppressLivePreview = routesFinalTranscriptToOnboarding
        pasteTargetApp = {
            if let frontmostApp, frontmostApp.bundleIdentifier != ownBundleID {
                return frontmostApp
            }
            return lastExternalApp
        }()
        contextTargetSnapshot = TargetAppSnapshot.capture(from: pasteTargetApp)
        DebugLog.info("startDictation: frontmost=\(frontmostApp?.bundleIdentifier ?? "nil") lastExternal=\(lastExternalApp?.bundleIdentifier ?? "nil") resolvedTarget=\(pasteTargetApp?.bundleIdentifier ?? "nil") targetSnapshot=\(contextTargetSnapshot?.logDescription ?? "nil")")

        if let targetPid = pasteTargetApp?.processIdentifier {
            FocusedEditable.enableWebAccessibility(pid: targetPid)
        }

        let capturedTargetApp = pasteTargetApp
        let capturedSnapshot = contextTargetSnapshot
        let capturedRecordingStart = recordingStartTime

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

        let client = CartesiaStreamingClient(apiKey: settings.cartesiaAPIKey,
                                             keyterms: settings.validatedDictionaryTerms)
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
        client.onClosed = { [weak self, capturedTargetApp, capturedSnapshot, capturedRecordingStart, routeToOnboardingBox] finalText in
            Task { @MainActor in
                guard let self else { return }
                let transcriptArrived = DispatchTime.now()
                let release = self.releaseTime
                let recordingMs: Int? = {
                    guard let start = capturedRecordingStart, let end = release else { return nil }
                    return Self.elapsedMs(start, end)
                }()
                let raw = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    self.state = .idle
                    return
                }
                self.settings.cartesiaKeyInvalid = false
                self.settings.cartesiaOutOfCredits = false
                if routeToOnboardingBox {
                    self.pasteTargetApp = nil
                    self.contextTargetSnapshot = nil
                    self.liveTranscript = raw
                    self.lastTrialLatency = release.map { start in
                        TranscriptHistoryStore.Latency(
                            transcribeMs: Self.elapsedMs(start, transcriptArrived),
                            polishMs: 0,
                            pasteMs: 0
                        )
                    }
                    self.lastTrialRecordingMs = recordingMs
                    self.state = .idle
                    return
                }

                let correction = await self.correctedTranscript(
                    raw: raw,
                    targetSnapshot: capturedSnapshot
                )
                if correction.outcome == .polished {
                    self.settings.polishKeyInvalid = false
                    self.settings.polishOutOfCredits = false
                } else if correction.outcome == .failed, let reason = correction.failure?.reason {
                    if reason == .invalidKey { self.settings.polishKeyInvalid = true }
                    else if reason == .outOfCredits { self.settings.polishOutOfCredits = true }
                }
                let polishFinished = DispatchTime.now()

                let focus = await FocusedEditable.current()
                let pasteTargetApp: NSRunningApplication?
                if focus.isEditable {
                    pasteTargetApp = focus.app ?? capturedTargetApp
                } else if focus.allowsKeyboardPasteFallback(to: capturedTargetApp) {
                    pasteTargetApp = capturedTargetApp
                    DebugLog.info("onClosed: no AX-editable focus but target app still frontmost — pasting via Cmd+V")
                } else {
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
                        failure: correction.failure,
                        appName: capturedSnapshot?.localizedName,
                        appBundleID: capturedSnapshot?.bundleIdentifier,
                        recordingMs: recordingMs
                    )
                    DebugLog.info("onClosed: no editable field focused at release — held in History instead of pasting")
                    self.showHeldInHistoryNotice()
                    return
                }

                self.state = .pasting
                self.paste.paste(text: correction.text, targetApp: pasteTargetApp) { ok in
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
                                failure: correction.failure,
                                appName: capturedSnapshot?.localizedName,
                                appBundleID: capturedSnapshot?.bundleIdentifier,
                                recordingMs: recordingMs
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

    private struct Correction {
        let text: String
        let outcome: TranscriptHistoryStore.PolishOutcome
        let original: String?
        var failure: TranscriptHistoryStore.PolishFailure?
    }

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

    private func correctedTranscript(
        raw: String,
        targetSnapshot: TargetAppSnapshot?
    ) async -> Correction {
        let runID = Self.makeCorrectionRunID()
        let enabled = settings.correctionEnabled
        let hasKey = !settings.apiKey(for: settings.rewriteProvider).isEmpty
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
        let rewriter = warmRewriter ?? TranscriptRewriter(provider: provider, model: settings.rewriteModel, apiKey: apiKey)
        warmRewriter = nil

        DebugLog.info("[\(runID)] CTX \(appTag) provider=\(provider.rawValue)/\(settings.rewriteModel) outcome=polish")
        state = .rewriting
        let result = await rewriter.rewriteWithoutContext(transcript: raw, runID: runID)
        return Self.polishResult(raw: raw, result: result, provider: provider)
    }

    private func showHeldInHistoryNotice() {
        state = .heldInHistory
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            Task { @MainActor in
                if case .heldInHistory = self?.state { self?.state = .idle }
            }
        }
    }

    private var isHotkeyHeld = false

    private var errorDismissWork: DispatchWorkItem?

    private func handleSTTFailure(_ failure: STTFailure) {
        switch failure {
        case .invalidKey:   settings.cartesiaKeyInvalid = true
        case .outOfCredits: settings.cartesiaOutOfCredits = true
        default: break
        }
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

    private func armErrorDismiss() {
        errorDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .error = self.state else { return }
            if self.isHotkeyHeld {
                self.armErrorDismiss()
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

    private static func elapsedMs(_ start: DispatchTime, _ end: DispatchTime) -> Int {
        guard end.uptimeNanoseconds > start.uptimeNanoseconds else { return 0 }
        return Int((end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}

#if DEBUG
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
                self.scheduleNextPing()
            }
        }
    }
}
#endif
