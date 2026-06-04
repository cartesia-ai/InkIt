import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox

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

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiKey = "cartesiaAPIKey"
        static let appearance = "appearancePreference"
        static let hotkeyKind = "hotkeyKind"           // "carbon" | "fn"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let notchHorizontalPosition = "notchHorizontalPosition"
        static let playFeedbackSounds = "playFeedbackSounds"
        static let correctionEnabled = "correctionEnabled"
        static let screenContextEnabled = "screenContextEnabled"
        static let anthropicAPIKey = "anthropicAPIKey"   // legacy; migrated into llmKeys
        static let rewriteProvider = "rewriteProvider"
        static let rewriteModel = "rewriteModel"
        static let llmKeys = "llmAPIKeys"
        static let debugLogging = DebugLog.isEnabledKey
    }

    @Published var cartesiaAPIKey: String {
        didSet { defaults.set(cartesiaAPIKey, forKey: Keys.apiKey) }
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

    /// Whether AI correction may read on-screen context (the focused app's
    /// visible text via Accessibility) to repair proper nouns and identifiers.
    /// When off, correction still runs but only cleans up the transcript
    /// itself — no screen is read.
    @Published var screenContextEnabled: Bool {
        didSet { defaults.set(screenContextEnabled, forKey: Keys.screenContextEnabled) }
    }

    @Published var anthropicAPIKey: String {
        didSet { defaults.set(anthropicAPIKey, forKey: Keys.anthropicAPIKey) }
    }

    /// Selected LLM provider + model for the rewrite ("Polish transcripts").
    @Published var rewriteProvider: LLMProvider {
        didSet { defaults.set(rewriteProvider.rawValue, forKey: Keys.rewriteProvider) }
    }

    @Published var rewriteModel: String {
        didSet { defaults.set(rewriteModel, forKey: Keys.rewriteModel) }
    }

    /// Per-provider API keys, keyed by `LLMProvider.rawValue`.
    @Published var llmAPIKeys: [String: String] {
        didSet { defaults.set(llmAPIKeys, forKey: Keys.llmKeys) }
    }

    func apiKey(for provider: LLMProvider) -> String { llmAPIKeys[provider.rawValue] ?? "" }
    func setAPIKey(_ key: String, for provider: LLMProvider) { llmAPIKeys[provider.rawValue] = key }

    @Published var hotkey: HotkeyBinding {
        didSet { saveHotkey() }
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
        self.cartesiaAPIKey = defaults.string(forKey: Keys.apiKey) ?? ""
        // Default to Light so first-run onboarding is light; users can switch
        // to Dark or System in Settings (applied instantly). See DESIGN_SYSTEM.md.
        self.appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppearancePreference.init(rawValue:)) ?? .light
        self.correctionEnabled = defaults.bool(forKey: Keys.correctionEnabled)
        // Default on so existing users keep the context-aware behavior they
        // already had before this toggle existed.
        if defaults.object(forKey: Keys.screenContextEnabled) == nil {
            self.screenContextEnabled = true
        } else {
            self.screenContextEnabled = defaults.bool(forKey: Keys.screenContextEnabled)
        }
        self.anthropicAPIKey = defaults.string(forKey: Keys.anthropicAPIKey) ?? ""
        self.rewriteProvider = defaults.string(forKey: Keys.rewriteProvider)
            .flatMap(LLMProvider.init(rawValue:)) ?? .groq
        self.rewriteModel = defaults.string(forKey: Keys.rewriteModel) ?? LLMProvider.groq.defaultModel
        self.llmAPIKeys = (defaults.dictionary(forKey: Keys.llmKeys) as? [String: String]) ?? [:]
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

        // Migrate the legacy standalone Anthropic key into the per-provider map.
        if !anthropicAPIKey.isEmpty, (llmAPIKeys[LLMProvider.anthropic.rawValue] ?? "").isEmpty {
            llmAPIKeys[LLMProvider.anthropic.rawValue] = anthropicAPIKey
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
