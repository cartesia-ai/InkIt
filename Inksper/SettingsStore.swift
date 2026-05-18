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
    }

    @Published var cartesiaAPIKey: String {
        didSet { defaults.set(cartesiaAPIKey, forKey: Keys.apiKey) }
    }

    @Published var hotkey: HotkeyBinding {
        didSet { saveHotkey() }
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
        switch defaults.string(forKey: Keys.hotkeyKind) {
        case "fn":
            self.hotkey = .fn
        default:
            let storedKey = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
            let storedMods = defaults.object(forKey: Keys.hotkeyModifiers) as? Int
            // Default: ⌃⌥ Space
            self.hotkey = .carbon(
                keyCode: UInt32(storedKey ?? kVK_Space),
                modifiers: UInt32(storedMods ?? (controlKey | optionKey))
            )
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
}
