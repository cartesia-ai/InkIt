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
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiKey = "cartesiaAPIKey"
        static let hotkeyKind = "hotkeyKind"           // "carbon" | "fn"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let notchHorizontalPosition = "notchHorizontalPosition"
        static let playFeedbackSounds = "playFeedbackSounds"
    }

    @Published var cartesiaAPIKey: String {
        didSet { defaults.set(cartesiaAPIKey, forKey: Keys.apiKey) }
    }

    @Published var hotkey: HotkeyBinding {
        didSet { saveHotkey() }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
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
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
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
            self.hotkey = .carbon(
                keyCode: UInt32(storedKey ?? kVK_Space),
                modifiers: UInt32(storedMods ?? (controlKey | optionKey))
            )
        default:
            // Default to the Fn / 🌐 key — claimed via a CGEventTap that
            // suppresses the system Globe action while InkIt is running.
            self.hotkey = .fn
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
