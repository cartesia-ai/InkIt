import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox
import Security
import ServiceManagement

enum HotkeyBinding: Equatable {
    case carbon(keyCode: UInt32, modifiers: UInt32)
    case fn
    case modifierKey(keyCode: UInt32)

    var isValidShortcut: Bool {
        guard case .carbon(let keyCode, let modifiers) = self else { return true }
        let usesCommand = modifiers & UInt32(cmdKey) != 0
        let usesControl = modifiers & UInt32(controlKey) != 0
        let usesOption = modifiers & UInt32(optionKey) != 0
        let usesShift = modifiers & UInt32(shiftKey) != 0
        let nonCommandModifiers = modifiers & ~UInt32(cmdKey)
        let onlyCommand = usesCommand && !usesControl && !usesOption && !usesShift

        if onlyCommand && Self.commonCommandKeys.contains(keyCode) { return false }
        if onlyCommand && keyCode == UInt32(kVK_Space) { return false }            // Spotlight
        if usesControl && !usesCommand && !usesOption && !usesShift
            && keyCode == UInt32(kVK_Space) { return false }                        // input methods
        if usesCommand && usesOption && !usesControl && !usesShift
            && keyCode == UInt32(kVK_Escape) { return false }                       // Force Quit
        if usesCommand && usesControl && !usesOption && !usesShift
            && keyCode == UInt32(kVK_ANSI_Q) { return false }                       // Lock Screen
        if usesCommand && usesShift && !usesControl && !usesOption
            && Self.screenshotKeys.contains(keyCode) { return false }               // screenshots
        if usesCommand && nonCommandModifiers == 0 && keyCode == UInt32(kVK_Tab) { return false } // app switch
        return true
    }

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

enum DictationMode: String, CaseIterable, Identifiable {
    case hold, toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold:   return "Hold to talk"
        case .toggle: return "Hands-free"
        }
    }

    var detail: String {
        switch self {
        case .hold:   return "Hold your shortcut while you speak, release to paste."
        case .toggle: return "Press your shortcut once to start, again to paste."
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

    @Published var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    @Published var correctionEnabled: Bool {
        didSet { defaults.set(correctionEnabled, forKey: Keys.correctionEnabled) }
    }

    @Published var polishNudgeDismissed: Bool {
        didSet { defaults.set(polishNudgeDismissed, forKey: Keys.polishNudgeDismissed) }
    }

    @Published var preferredInputDeviceUID: String {
        didSet { defaults.set(preferredInputDeviceUID, forKey: Keys.preferredInputDeviceUID) }
    }

    @Published var polishKeyInvalid: Bool {
        didSet { defaults.set(polishKeyInvalid, forKey: Keys.polishKeyInvalid) }
    }

    @Published var polishOutOfCredits: Bool {
        didSet { defaults.set(polishOutOfCredits, forKey: Keys.polishOutOfCredits) }
    }

    @Published var cartesiaKeyInvalid: Bool {
        didSet { defaults.set(cartesiaKeyInvalid, forKey: Keys.cartesiaKeyInvalid) }
    }

    @Published var cartesiaOutOfCredits: Bool {
        didSet { defaults.set(cartesiaOutOfCredits, forKey: Keys.cartesiaOutOfCredits) }
    }

    @Published var rewriteProvider: LLMProvider {
        didSet {
            defaults.set(rewriteProvider.rawValue, forKey: Keys.rewriteProvider)
            polishKeyInvalid = false
            polishOutOfCredits = false
        }
    }

    @Published var rewriteModel: String {
        didSet { defaults.set(rewriteModel, forKey: Keys.rewriteModel) }
    }

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

    var hasRewriteKey: Bool {
        !apiKey(for: rewriteProvider).trimmingCharacters(in: .whitespaces).isEmpty
    }

    enum PolishUIState { case setup, on, paused, keyBroken }
    var polishUIState: PolishUIState {
        guard hasRewriteKey else { return .setup }
        guard correctionEnabled else { return .paused }
        return polishKeyInvalid ? .keyBroken : .on
    }

    enum ServiceIssue: Equatable { case keyInvalid, outOfCredits }

    var transcriptionIssue: ServiceIssue? {
        guard !cartesiaAPIKey.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if cartesiaKeyInvalid { return .keyInvalid }
        if cartesiaOutOfCredits { return .outOfCredits }
        return nil
    }

    var polishIssue: ServiceIssue? {
        guard correctionEnabled, hasRewriteKey else { return nil }
        if polishKeyInvalid { return .keyInvalid }
        if polishOutOfCredits { return .outOfCredits }
        return nil
    }

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

    @Published var debugLoggingEnabled: Bool {
        didSet { defaults.set(debugLoggingEnabled, forKey: Keys.debugLogging) }
    }

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
        case .modifierKey(let kc):
            return HotkeyConversion.modifierLabel(for: kc)
        }
    }

    var dictationModeVerb: String {
        dictationMode == .toggle ? "Press" : "Hold"
    }

    private init() {
        if let stored = Keychain.string(for: KeychainAccount.cartesia) {
            self.cartesiaAPIKey = stored
        } else {
            let legacy = defaults.string(forKey: Keys.apiKey) ?? ""
            self.cartesiaAPIKey = legacy
            if !legacy.isEmpty { Keychain.set(legacy, for: KeychainAccount.cartesia) }
        }
        defaults.removeObject(forKey: Keys.apiKey)
        self.appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppearancePreference.init(rawValue:)) ?? .light
        self.correctionEnabled = defaults.bool(forKey: Keys.correctionEnabled)
        self.polishNudgeDismissed = defaults.bool(forKey: Keys.polishNudgeDismissed)
        self.polishKeyInvalid = defaults.bool(forKey: Keys.polishKeyInvalid)
        self.polishOutOfCredits = defaults.bool(forKey: Keys.polishOutOfCredits)
        self.cartesiaKeyInvalid = defaults.bool(forKey: Keys.cartesiaKeyInvalid)
        self.cartesiaOutOfCredits = defaults.bool(forKey: Keys.cartesiaOutOfCredits)
        self.preferredInputDeviceUID = defaults.string(forKey: Keys.preferredInputDeviceUID) ?? ""
        self.rewriteProvider = defaults.string(forKey: Keys.rewriteProvider)
            .flatMap(LLMProvider.init(rawValue:)) ?? .groq
        self.rewriteModel = defaults.string(forKey: Keys.rewriteModel) ?? LLMProvider.groq.defaultModel
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
        case "modifier":
            let storedKey = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
            self.hotkey = .modifierKey(keyCode: UInt32(storedKey ?? kVK_Control))
        default:
            self.hotkey = .fn
        }

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
        case .modifierKey(let kc):
            defaults.set("modifier", forKey: Keys.hotkeyKind)
            defaults.set(Int(kc), forKey: Keys.hotkeyKeyCode)
        }
    }

    private static func clampedNotchPosition(_ value: Double) -> Double {
        min(0.96, max(0.04, value))
    }
}

enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "InkIt"
    private static let fallbackPrefix = "secretFallback."

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
