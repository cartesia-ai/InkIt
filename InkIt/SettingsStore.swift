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
        if onlyCommand && keyCode == UInt32(kVK_Space) { return false }
        if usesControl && !usesCommand && !usesOption && !usesShift
            && keyCode == UInt32(kVK_Space) { return false }
        if usesCommand && usesOption && !usesControl && !usesShift
            && keyCode == UInt32(kVK_Escape) { return false }
        if usesCommand && usesControl && !usesOption && !usesShift
            && keyCode == UInt32(kVK_ANSI_Q) { return false }
        if usesCommand && usesShift && !usesControl && !usesOption
            && Self.screenshotKeys.contains(keyCode) { return false }
        if usesCommand && nonCommandModifiers == 0 && keyCode == UInt32(kVK_Tab) { return false }
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

    func conflicts(with other: HotkeyBinding) -> Bool {
        if self == other { return true }
        switch (self, other) {
        case (.modifierKey(let code), .carbon(_, let modifiers)),
             (.carbon(_, let modifiers), .modifierKey(let code)):
            return Self.carbonModifierBit(forModifierKeyCode: code) & modifiers != 0
        default:
            return false
        }
    }

    private static func carbonModifierBit(forModifierKeyCode keyCode: UInt32) -> UInt32 {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return UInt32(cmdKey)
        case kVK_Option, kVK_RightOption:   return UInt32(optionKey)
        case kVK_Control, kVK_RightControl: return UInt32(controlKey)
        case kVK_Shift, kVK_RightShift:     return UInt32(shiftKey)
        default: return 0
        }
    }
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

enum DictionaryLimits {
    static let maxTerms = 100
    static let maxCharacters = 1200
    static let approachingTerms = 85
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiKey = "cartesiaAPIKey"
        static let appearance = "appearancePreference"
        static let hotkeyKind = "hotkeyKind"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let handsFreeHotkeyKind = "handsFreeHotkeyKind"
        static let handsFreeHotkeyKeyCode = "handsFreeHotkeyKeyCode"
        static let handsFreeHotkeyModifiers = "handsFreeHotkeyModifiers"
        static let dictationMode = "dictationMode"
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
        static let anthropicAPIKey = "anthropicAPIKey"
        static let rewriteProvider = "rewriteProvider"
        static let rewriteModel = "rewriteModel"
        static let llmKeys = "llmAPIKeys"
        static let dictionaryTerms = "dictionaryTerms"
        static let debugLogging = DebugLog.isEnabledKey
    }

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

    func pausePolish() { correctionEnabled = false }

    @Published var dictionaryTerms: [String] {
        didSet { defaults.set(dictionaryTerms, forKey: Keys.dictionaryTerms) }
    }

    var validatedDictionaryTerms: [String] {
        Self.validatedDictionaryTerms(dictionaryTerms)
    }

    static func normalizedDictionaryTerm(_ raw: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet.controlCharacters)
        let collapsed = raw.components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func validatedDictionaryTerms(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        var characters = 0
        for term in raw {
            guard let clean = normalizedDictionaryTerm(term) else { continue }
            if result.count >= DictionaryLimits.maxTerms { break }
            if !seen.insert(clean).inserted { continue }
            if characters + clean.count > DictionaryLimits.maxCharacters { continue }
            result.append(clean)
            characters += clean.count
        }
        return result
    }

    @Published var hotkey: HotkeyBinding {
        didSet {
            Self.persist(hotkey, kind: Keys.hotkeyKind, keyCode: Keys.hotkeyKeyCode,
                        modifiers: Keys.hotkeyModifiers, in: defaults)
        }
    }

    @Published var handsFreeHotkey: HotkeyBinding {
        didSet {
            Self.persist(handsFreeHotkey, kind: Keys.handsFreeHotkeyKind, keyCode: Keys.handsFreeHotkeyKeyCode,
                        modifiers: Keys.handsFreeHotkeyModifiers, in: defaults)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }
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
            syncLaunchAtLoginFromSystem()
        }
    }

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
        self.dictionaryTerms = defaults.array(forKey: Keys.dictionaryTerms) as? [String] ?? []
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
        Self.migrateDictationModeIfNeeded(in: defaults)
        self.hotkey = Self.loadBinding(kind: Keys.hotkeyKind, keyCode: Keys.hotkeyKeyCode,
                                      modifiers: Keys.hotkeyModifiers, fallback: .fn, in: defaults)
        self.handsFreeHotkey = Self.loadBinding(kind: Keys.handsFreeHotkeyKind, keyCode: Keys.handsFreeHotkeyKeyCode,
                                                modifiers: Keys.handsFreeHotkeyModifiers,
                                                fallback: .modifierKey(keyCode: UInt32(kVK_RightCommand)), in: defaults)

        if !rewriteProvider.models.contains(rewriteModel) {
            rewriteModel = rewriteProvider.defaultModel
        }
    }

    private static func migrateDictationModeIfNeeded(in defaults: UserDefaults) {
        guard let dictationMode = defaults.string(forKey: Keys.dictationMode) else { return }
        defer { defaults.removeObject(forKey: Keys.dictationMode) }

        let existingHotkey = loadBinding(kind: Keys.hotkeyKind, keyCode: Keys.hotkeyKeyCode,
                                         modifiers: Keys.hotkeyModifiers, fallback: .fn, in: defaults)

        if dictationMode == "toggle" {
            persist(existingHotkey, kind: Keys.handsFreeHotkeyKind, keyCode: Keys.handsFreeHotkeyKeyCode,
                   modifiers: Keys.handsFreeHotkeyModifiers, in: defaults)
            let defaultHoldToTalk: HotkeyBinding = existingHotkey == .fn
                ? .modifierKey(keyCode: UInt32(kVK_RightCommand))
                : .fn
            persist(defaultHoldToTalk, kind: Keys.hotkeyKind, keyCode: Keys.hotkeyKeyCode,
                   modifiers: Keys.hotkeyModifiers, in: defaults)
        } else {
            let defaultHandsFree: HotkeyBinding = existingHotkey.conflicts(with: .modifierKey(keyCode: UInt32(kVK_RightCommand)))
                ? .modifierKey(keyCode: UInt32(kVK_RightOption))
                : .modifierKey(keyCode: UInt32(kVK_RightCommand))
            persist(defaultHandsFree, kind: Keys.handsFreeHotkeyKind, keyCode: Keys.handsFreeHotkeyKeyCode,
                   modifiers: Keys.handsFreeHotkeyModifiers, in: defaults)
        }
    }

    private static func loadBinding(kind: String, keyCode: String, modifiers: String,
                                    fallback: HotkeyBinding, in defaults: UserDefaults) -> HotkeyBinding {
        switch defaults.string(forKey: kind) {
        case "carbon":
            let storedKey = defaults.object(forKey: keyCode) as? Int
            let storedMods = defaults.object(forKey: modifiers) as? Int
            let candidate = HotkeyBinding.carbon(
                keyCode: UInt32(storedKey ?? kVK_Space),
                modifiers: UInt32(storedMods ?? (controlKey | optionKey))
            )
            return candidate.isValidShortcut ? candidate : fallback
        case "modifier":
            let storedKey = defaults.object(forKey: keyCode) as? Int
            return .modifierKey(keyCode: UInt32(storedKey ?? kVK_Control))
        case "fn":
            return .fn
        default:
            return fallback
        }
    }

    private static func persist(_ binding: HotkeyBinding, kind: String, keyCode: String,
                                modifiers: String, in defaults: UserDefaults) {
        switch binding {
        case .fn:
            defaults.set("fn", forKey: kind)
        case .carbon(let kc, let mods):
            defaults.set("carbon", forKey: kind)
            defaults.set(Int(kc), forKey: keyCode)
            defaults.set(Int(mods), forKey: modifiers)
        case .modifierKey(let kc):
            defaults.set("modifier", forKey: kind)
            defaults.set(Int(kc), forKey: keyCode)
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
            return false
        }
        let signatureFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adhoc: UInt32 = 0x2
        return (signatureFlags & adhoc) == 0
    }
}
