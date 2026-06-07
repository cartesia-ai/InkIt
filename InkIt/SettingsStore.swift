import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox
import Security
import ServiceManagement

/// The kind of hotkey binding currently in use.
///
/// The Fn key is special on macOS: it isn't a standard modifier in the Carbon
/// `RegisterEventHotKey` API. We detect it via `NSEvent.flagsChanged` instead.
enum HotkeyBinding: Equatable {
    case carbon(keyCode: UInt32, modifiers: UInt32)
    case fn

    var validationMessage: String? {
        guard case .carbon(let keyCode, let modifiers) = self else { return nil }
        let usesCommand = modifiers & UInt32(cmdKey) != 0
        let usesControl = modifiers & UInt32(controlKey) != 0
        let usesOption = modifiers & UInt32(optionKey) != 0
        let usesShift = modifiers & UInt32(shiftKey) != 0
        let nonCommandModifiers = modifiers & ~UInt32(cmdKey)

        if usesCommand && !usesControl && !usesOption && !usesShift && Self.commonCommandKeys.contains(keyCode) {
            let name = HotkeyConversion.displayString(keyCode: keyCode, modifiers: modifiers)
            return "\(name) is a common app shortcut. Choose a shortcut with Control or Option."
        }

        if usesCommand && !usesControl && !usesOption && !usesShift && keyCode == UInt32(kVK_Space) {
            return "Command-Space is reserved for Spotlight. Choose a different shortcut."
        }

        if usesControl && !usesCommand && !usesOption && !usesShift && keyCode == UInt32(kVK_Space) {
            return "Control-Space is commonly used by input methods and editors. Choose a different shortcut."
        }

        if usesCommand && usesOption && !usesControl && !usesShift && keyCode == UInt32(kVK_Escape) {
            return "Command-Option-Escape is reserved for Force Quit. Choose a different shortcut."
        }

        if usesCommand && usesControl && !usesOption && !usesShift && keyCode == UInt32(kVK_ANSI_Q) {
            return "Control-Command-Q is reserved for Lock Screen. Choose a different shortcut."
        }

        if usesCommand && usesShift && !usesControl && !usesOption && Self.screenshotKeys.contains(keyCode) {
            return "Command-Shift-\(HotkeyConversion.keyName(for: keyCode)) is reserved for screenshots. Choose a different shortcut."
        }

        if usesCommand && nonCommandModifiers == 0 && keyCode == UInt32(kVK_Tab) {
            return "Command-Tab is reserved for switching apps. Choose a different shortcut."
        }

        return nil
    }

    var isValidShortcut: Bool { validationMessage == nil }

    private static let commonCommandKeys: Set<UInt32> = [
        UInt32(kVK_ANSI_A),
        UInt32(kVK_ANSI_C),
        UInt32(kVK_ANSI_F),
        UInt32(kVK_ANSI_L),
        UInt32(kVK_ANSI_N),
        UInt32(kVK_ANSI_O),
        UInt32(kVK_ANSI_P),
        UInt32(kVK_ANSI_Q),
        UInt32(kVK_ANSI_R),
        UInt32(kVK_ANSI_S),
        UInt32(kVK_ANSI_T),
        UInt32(kVK_ANSI_V),
        UInt32(kVK_ANSI_W),
        UInt32(kVK_ANSI_X),
        UInt32(kVK_ANSI_Z)
    ]

    private static let screenshotKeys: Set<UInt32> = [
        UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4),
        UInt32(kVK_ANSI_5)
    ]
}

/// User's appearance choice. `.system` follows the OS setting; the other two
/// pin the app. Applied app-wide via `NSApp.appearance` (the always-dark notch
/// HUD ignores it — see DESIGN_SYSTEM.md).
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

/// How the dictation hotkey behaves. `.hold` is press-and-hold — release to
/// paste, the original (and default) behavior. `.toggle` is hands-free: one
/// press starts, the next press stops and pastes, for dictating longer
/// passages without holding the key. See AppCoordinator's hotkey handlers.
enum DictationMode: String, CaseIterable, Identifiable {
    case hold, toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold:   return "Hold to talk"
        case .toggle: return "Hands-free"
        }
    }

    /// One-line gesture description shown beneath the label in the picker.
    /// Kept strictly parallel so the two modes read as a clean contrast.
    var detail: String {
        switch self {
        case .hold:   return "Hold while you speak, release to paste."
        case .toggle: return "Press once to start, press again to paste."
        }
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiKey = "cartesiaAPIKey"
        static let appearance = "appearancePreference"
        static let hotkeyKind = "hotkeyKind"           // "carbon" | "fn"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let dictationMode = "dictationMode"     // "hold" | "toggle"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let notchHorizontalPosition = "notchHorizontalPosition"
        static let playFeedbackSounds = "playFeedbackSounds"
        static let correctionEnabled = "correctionEnabled"
        static let polishNudgeDismissed = "polishNudgeDismissed"
        static let screenContextEnabled = "screenContextEnabled"
        static let preferredInputDeviceUID = "preferredInputDeviceUID"
        static let polishKeyInvalid = "polishKeyInvalid"
        static let polishOutOfCredits = "polishOutOfCredits"
        static let cartesiaKeyInvalid = "cartesiaKeyInvalid"
        static let cartesiaOutOfCredits = "cartesiaOutOfCredits"
        static let anthropicAPIKey = "anthropicAPIKey"   // legacy; migrated into llmKeys
        static let rewriteProvider = "rewriteProvider"
        static let rewriteModel = "rewriteModel"
        static let llmKeys = "llmAPIKeys"
        static let debugLogging = DebugLog.isEnabledKey
    }

    /// API keys live in the macOS Keychain, never in UserDefaults (which is a
    /// plaintext plist on disk). Accounts under one service, keyed by name.
    private enum KeychainAccount {
        static let cartesia = "cartesiaAPIKey"
        static func llm(_ provider: LLMProvider) -> String { "llm." + provider.rawValue }
    }

    @Published var cartesiaAPIKey: String {
        didSet { Keychain.set(cartesiaAPIKey, for: KeychainAccount.cartesia) }
    }

    /// Light / Dark / follow-System. Persisted and applied on change.
    @Published var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    /// Pushes the current `appearance` onto the running app. Safe to call from
    /// any point after the app is up; no-op for `.system` beyond clearing any
    /// previous override.
    func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    @Published var correctionEnabled: Bool {
        didSet { defaults.set(correctionEnabled, forKey: Keys.correctionEnabled) }
    }

    /// Whether the user has dismissed the Home "Polish your dictation" nudge.
    /// Sticky so a dismissed nudge stays gone across launches. The nudge only
    /// shows when polish is off anyway, so enabling polish also hides it.
    @Published var polishNudgeDismissed: Bool {
        didSet { defaults.set(polishNudgeDismissed, forKey: Keys.polishNudgeDismissed) }
    }

    /// Whether AI correction may read on-screen context (the focused app's
    /// visible text via Accessibility) to repair proper nouns and identifiers.
    /// When off, correction still runs but only cleans up the transcript
    /// itself — no screen is read.
    @Published var screenContextEnabled: Bool {
        didSet { defaults.set(screenContextEnabled, forKey: Keys.screenContextEnabled) }
    }

    /// UID of the input device the user pinned for dictation, or "" to follow
    /// the macOS default. Pinning decouples "what I dictate into" from whatever
    /// macOS routes to (e.g. AirPods hijacking the mic). The capture service
    /// falls back to the system default when the pinned device is unplugged, so
    /// a stale UID is always safe. Persisted by UID (stable across replug), not
    /// by the transient AudioDeviceID.
    @Published var preferredInputDeviceUID: String {
        didSet { defaults.set(preferredInputDeviceUID, forKey: Keys.preferredInputDeviceUID) }
    }

    /// True when a polish rewrite last failed because the provider rejected the
    /// key (401/403) — the key "stopped working." Persisted so Settings can show
    /// the honest "paused — re-enter a key" state even after a relaunch, instead
    /// of silently pasting raw. Cleared when a key validates, the provider
    /// changes, or polish is (re)enabled. See AppCoordinator.correctedTranscript.
    @Published var polishKeyInvalid: Bool {
        didSet { defaults.set(polishKeyInvalid, forKey: Keys.polishKeyInvalid) }
    }

    /// True when a polish rewrite last failed because the provider rejected the
    /// request for billing reasons (402). Drives the "Polish is paused — out of
    /// credits" home card. Cleared when a rewrite succeeds or the provider changes.
    @Published var polishOutOfCredits: Bool {
        didSet { defaults.set(polishOutOfCredits, forKey: Keys.polishOutOfCredits) }
    }

    /// True when an STT session last failed on an invalid/expired Cartesia key
    /// (401/403). Drives the "Transcription is paused — invalid key" home card.
    /// Cleared on the next successful transcription. See AppCoordinator.
    @Published var cartesiaKeyInvalid: Bool {
        didSet { defaults.set(cartesiaKeyInvalid, forKey: Keys.cartesiaKeyInvalid) }
    }

    /// True when an STT session last failed because Cartesia credits are used up
    /// (402 / quota_exceeded / plan_upgrade_required). Drives the "Transcription
    /// is paused — out of credits" home card. Cleared on the next success.
    @Published var cartesiaOutOfCredits: Bool {
        didSet { defaults.set(cartesiaOutOfCredits, forKey: Keys.cartesiaOutOfCredits) }
    }

    /// Selected LLM provider + model for the rewrite ("Polish transcripts").
    @Published var rewriteProvider: LLMProvider {
        didSet {
            defaults.set(rewriteProvider.rawValue, forKey: Keys.rewriteProvider)
            // A broken-key / out-of-credits verdict belongs to the old provider;
            // clear both so the newly selected provider starts from a clean slate.
            polishKeyInvalid = false
            polishOutOfCredits = false
        }
    }

    @Published var rewriteModel: String {
        didSet { defaults.set(rewriteModel, forKey: Keys.rewriteModel) }
    }

    /// Per-provider API keys, keyed by `LLMProvider.rawValue`. Persisted to the
    /// Keychain, one item per provider; an empty value removes that item.
    @Published var llmAPIKeys: [String: String] {
        didSet {
            for provider in LLMProvider.allCases {
                Keychain.set(llmAPIKeys[provider.rawValue] ?? "", for: KeychainAccount.llm(provider))
            }
        }
    }

    func apiKey(for provider: LLMProvider) -> String { llmAPIKeys[provider.rawValue] ?? "" }
    func setAPIKey(_ key: String, for provider: LLMProvider) {
        llmAPIKeys[provider.rawValue] = key
    }

    /// Whether the currently selected rewrite provider has a key on file.
    var hasRewriteKey: Bool {
        !apiKey(for: rewriteProvider).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The Polish settings pane's state, derived from whether a key exists,
    /// whether polish is enabled, and whether the key last failed auth. The key
    /// is the switch: no key → setup. See PolishSettingsView.
    enum PolishUIState { case setup, on, paused, keyBroken }
    var polishUIState: PolishUIState {
        guard hasRewriteKey else { return .setup }
        guard correctionEnabled else { return .paused }
        return polishKeyInvalid ? .keyBroken : .on
    }

    /// A persistent, user-fixable problem with one of the two services, surfaced
    /// as a calm card in the Home rail. Only config/account problems that won't
    /// fix themselves — never transient blips (offline, 5xx, rate limit), which
    /// live in the moment (notch) and the history log.
    enum ServiceIssue: Equatable { case keyInvalid, outOfCredits }

    /// Transcription (Cartesia) problem to surface on Home, or nil when healthy.
    /// Suppressed when no key is set yet — that's onboarding/setup, not a fault.
    var transcriptionIssue: ServiceIssue? {
        guard !cartesiaAPIKey.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if cartesiaKeyInvalid { return .keyInvalid }
        if cartesiaOutOfCredits { return .outOfCredits }
        return nil
    }

    /// Polish (LLM provider) problem to surface on Home, or nil. Suppressed when
    /// Polish is off or has no key — there's nothing paused to fix in that case.
    var polishIssue: ServiceIssue? {
        guard correctionEnabled, hasRewriteKey else { return nil }
        if polishKeyInvalid { return .keyInvalid }
        if polishOutOfCredits { return .outOfCredits }
        return nil
    }

    /// Turn on the LLM "Polish transcripts" rewrite for `provider`, keeping the
    /// selected model valid. Centralizes the provider/model/enabled trio so the
    /// Polish settings pane stays consistent.
    func enablePolish(provider: LLMProvider) {
        rewriteProvider = provider
        if !provider.models.contains(rewriteModel) {
            rewriteModel = provider.defaultModel
        }
        polishKeyInvalid = false
        polishOutOfCredits = false
        correctionEnabled = true
    }

    /// Pause polish without forgetting the key (the master toggle's off state).
    func pausePolish() { correctionEnabled = false }

    @Published var hotkey: HotkeyBinding {
        didSet { saveHotkey() }
    }

    /// Hold-to-talk vs tap-to-toggle. Persisted; read by AppCoordinator's
    /// hotkey handlers to decide whether release stops dictation (`.hold`) or
    /// a second press does (`.toggle`).
    @Published var dictationMode: DictationMode {
        didSet { defaults.set(dictationMode.rawValue, forKey: Keys.dictationMode) }
    }

    /// Whether InkIt opens automatically at login. The system (`SMAppService`)
    /// is the source of truth, so this mirrors the real registration status
    /// rather than a separately-persisted flag — flipping it registers or
    /// unregisters the login item, and `syncLaunchAtLoginFromSystem()`
    /// reconciles it (the user can change Login Items in System Settings).
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }
    /// Set while mirroring the system status into `launchAtLogin` so the didSet
    /// doesn't bounce back into another register/unregister.
    private var isSyncingLaunchAtLogin = false

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            NSLog("InkIt: launch-at-login %@ failed: %@",
                  launchAtLogin ? "register" : "unregister", error.localizedDescription)
            syncLaunchAtLoginFromSystem()   // fall back to the real state
        }
    }

    /// Re-reads the actual login-item registration and mirrors it into the
    /// toggle without re-triggering registration. Call when Settings appears.
    func syncLaunchAtLoginFromSystem() {
        let enabled = SMAppService.mainApp.status == .enabled
        guard launchAtLogin != enabled else { return }
        isSyncingLaunchAtLogin = true
        launchAtLogin = enabled
        isSyncingLaunchAtLogin = false
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Developer trace logging to `~/Library/Logs/InkIt-debug.log`. Off by
    /// default because traces include raw transcripts and on-screen context.
    /// See `DebugLog`.
    @Published var debugLoggingEnabled: Bool {
        didSet { defaults.set(debugLoggingEnabled, forKey: Keys.debugLogging) }
    }

    /// Horizontal position of the notch HUD on the active screen, normalized
    /// from 0.0 (left edge) to 1.0 (right edge). Defaults slightly left of
    /// center so it does not sit directly below the camera notch.
    @Published var playFeedbackSounds: Bool {
        didSet { defaults.set(playFeedbackSounds, forKey: Keys.playFeedbackSounds) }
    }

    @Published var notchHorizontalPosition: Double {
        didSet {
            let clamped = Self.clampedNotchPosition(notchHorizontalPosition)
            if notchHorizontalPosition != clamped {
                notchHorizontalPosition = clamped
                return
            }
            defaults.set(notchHorizontalPosition, forKey: Keys.notchHorizontalPosition)
        }
    }

    var hotkeyDisplayString: String {
        switch hotkey {
        case .carbon(let kc, let mods):
            return HotkeyConversion.displayString(keyCode: kc, modifiers: mods)
        case .fn:
            return "🌐 fn"
        }
    }

    private init() {
        // --- Secrets live in the Keychain. Read them there, migrating any
        // plaintext keys written by older builds, then scrub the plaintext. ---
        if let stored = Keychain.string(for: KeychainAccount.cartesia) {
            self.cartesiaAPIKey = stored
        } else {
            let legacy = defaults.string(forKey: Keys.apiKey) ?? ""
            self.cartesiaAPIKey = legacy
            if !legacy.isEmpty { Keychain.set(legacy, for: KeychainAccount.cartesia) }
        }
        defaults.removeObject(forKey: Keys.apiKey)
        // Default to Light so first-run onboarding is light; users can switch
        // to Dark or System in Settings (applied instantly). See DESIGN_SYSTEM.md.
        self.appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppearancePreference.init(rawValue:)) ?? .light
        self.correctionEnabled = defaults.bool(forKey: Keys.correctionEnabled)
        self.polishNudgeDismissed = defaults.bool(forKey: Keys.polishNudgeDismissed)
        self.polishKeyInvalid = defaults.bool(forKey: Keys.polishKeyInvalid)
        self.polishOutOfCredits = defaults.bool(forKey: Keys.polishOutOfCredits)
        self.cartesiaKeyInvalid = defaults.bool(forKey: Keys.cartesiaKeyInvalid)
        self.cartesiaOutOfCredits = defaults.bool(forKey: Keys.cartesiaOutOfCredits)
        // Default on so existing users keep the context-aware behavior they
        // already had before this toggle existed.
        if defaults.object(forKey: Keys.screenContextEnabled) == nil {
            self.screenContextEnabled = true
        } else {
            self.screenContextEnabled = defaults.bool(forKey: Keys.screenContextEnabled)
        }
        self.preferredInputDeviceUID = defaults.string(forKey: Keys.preferredInputDeviceUID) ?? ""
        self.rewriteProvider = defaults.string(forKey: Keys.rewriteProvider)
            .flatMap(LLMProvider.init(rawValue:)) ?? .groq
        self.rewriteModel = defaults.string(forKey: Keys.rewriteModel) ?? LLMProvider.groq.defaultModel
        // Per-provider LLM keys: Keychain first, migrating from the legacy
        // UserDefaults map (and the even older standalone Anthropic key).
        let legacyLLMKeys = (defaults.dictionary(forKey: Keys.llmKeys) as? [String: String]) ?? [:]
        let legacyAnthropic = defaults.string(forKey: Keys.anthropicAPIKey) ?? ""
        var loadedLLMKeys: [String: String] = [:]
        for provider in LLMProvider.allCases {
            let account = KeychainAccount.llm(provider)
            if let stored = Keychain.string(for: account), !stored.isEmpty {
                loadedLLMKeys[provider.rawValue] = stored
            } else if let legacy = legacyLLMKeys[provider.rawValue], !legacy.isEmpty {
                loadedLLMKeys[provider.rawValue] = legacy
                Keychain.set(legacy, for: account)
            }
        }
        if loadedLLMKeys[LLMProvider.anthropic.rawValue] == nil, !legacyAnthropic.isEmpty {
            loadedLLMKeys[LLMProvider.anthropic.rawValue] = legacyAnthropic
            Keychain.set(legacyAnthropic, for: KeychainAccount.llm(.anthropic))
        }
        self.llmAPIKeys = loadedLLMKeys
        defaults.removeObject(forKey: Keys.llmKeys)
        defaults.removeObject(forKey: Keys.anthropicAPIKey)
        self.dictationMode = defaults.string(forKey: Keys.dictationMode)
            .flatMap(DictationMode.init(rawValue:)) ?? .hold
        // Mirror the real login-item status. didSet does not fire for this
        // initial assignment, so reading the system here never re-registers.
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.debugLoggingEnabled = defaults.bool(forKey: Keys.debugLogging)
        if defaults.object(forKey: Keys.playFeedbackSounds) == nil {
            self.playFeedbackSounds = true
        } else {
            self.playFeedbackSounds = defaults.bool(forKey: Keys.playFeedbackSounds)
        }
        if defaults.object(forKey: Keys.notchHorizontalPosition) == nil {
            self.notchHorizontalPosition = 0.38
        } else {
            self.notchHorizontalPosition = Self.clampedNotchPosition(defaults.double(forKey: Keys.notchHorizontalPosition))
        }
        switch defaults.string(forKey: Keys.hotkeyKind) {
        case "carbon":
            let storedKey = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
            let storedMods = defaults.object(forKey: Keys.hotkeyModifiers) as? Int
            let storedHotkey = HotkeyBinding.carbon(
                keyCode: UInt32(storedKey ?? kVK_Space),
                modifiers: UInt32(storedMods ?? (controlKey | optionKey))
            )
            self.hotkey = storedHotkey.isValidShortcut ? storedHotkey : .fn
        default:
            // Default to the Fn / 🌐 key — claimed via a CGEventTap that
            // suppresses the system Globe action while InkIt is running.
            self.hotkey = .fn
        }

        // Keep model valid for the selected provider.
        if !rewriteProvider.models.contains(rewriteModel) {
            rewriteModel = rewriteProvider.defaultModel
        }
    }

    private func saveHotkey() {
        switch hotkey {
        case .fn:
            defaults.set("fn", forKey: Keys.hotkeyKind)
        case .carbon(let kc, let mods):
            defaults.set("carbon", forKey: Keys.hotkeyKind)
            defaults.set(Int(kc), forKey: Keys.hotkeyKeyCode)
            defaults.set(Int(mods), forKey: Keys.hotkeyModifiers)
        }
    }

    private static func clampedNotchPosition(_ value: Double) -> Double {
        min(0.96, max(0.04, value))
    }
}

/// Thin wrapper over the macOS Keychain for InkIt's API keys. Secrets are stored
/// as generic-password items under one service so they never touch UserDefaults
/// (a plaintext plist). Calls are synchronous and best-effort: a Keychain miss
/// or error degrades to an absent value rather than crashing.
///
/// Keychain items are bound to the app's code signature, so they only survive a
/// rebuild when the signature is stable. Signed release builds qualify; ad-hoc
/// "Sign to Run Locally" builds (what a contributor without a Developer ID gets)
/// re-sign each build, which would orphan the items. For those builds only we
/// fall back to a namespaced UserDefaults key — friendlier for contributors,
/// while shipped builds keep secrets out of plaintext. (VoiceInk does the same.)
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "InkIt"
    /// Distinct from any legacy `Keys` so the migration's plaintext-scrub can't
    /// delete a value we just wrote here.
    private static let fallbackPrefix = "secretFallback."

    /// True when the running build is signed with a stable identity (not ad-hoc
    /// or unsigned), so Keychain items persist across rebuilds. Computed once.
    static let usesKeychain: Bool = isStablySigned()

    static func string(for account: String) -> String? {
        guard usesKeychain else {
            return UserDefaults.standard.string(forKey: fallbackPrefix + account)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Stores `value` for `account`. An empty value removes the item, so the
    /// store never holds a blank secret.
    static func set(_ value: String, for account: String) {
        guard !value.isEmpty else {
            remove(account)
            return
        }
        guard usesKeychain else {
            UserDefaults.standard.set(value, forKey: fallbackPrefix + account)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // Readable while locked so dictation works without an unlock prompt;
            // still excluded from iCloud/backup sync.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
    }

    static func remove(_ account: String) {
        guard usesKeychain else {
            UserDefaults.standard.removeObject(forKey: fallbackPrefix + account)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Inspects the running binary's code signature. Returns true only when it
    /// carries a signing identifier and is not ad-hoc — i.e. the signature is
    /// stable enough for Keychain items to survive a rebuild.
    private static func isStablySigned() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return false }
        var infoCF: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any],
              info[kSecCodeInfoIdentifier as String] != nil else {
            return false  // unsigned
        }
        let signatureFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adhoc: UInt32 = 0x2  // kSecCodeSignatureAdhoc
        return (signatureFlags & adhoc) == 0
    }
}
