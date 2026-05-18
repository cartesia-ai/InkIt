import Foundation
import AppKit
import Carbon.HIToolbox

/// Global hotkey with two backends:
///
/// - `.carbon`: Carbon `RegisterEventHotKey` for normal keyCode + modifier
///   combinations. Press and release events arrive without key repeat, even
///   when another app is frontmost.
///
/// - `.fn`: The Fn / 🌐 key isn't a real modifier in Carbon. We install a
///   `CGEventTap` at `cghidEventTap` with active suppression: when Fn
///   transitions, the callback returns `nil` and the event never reaches the
///   OS Globe handler (so Emoji / Dictation don't fire). This requires
///   Accessibility permission. If the tap can't be created we fall back to a
///   passive `NSEvent` monitor that observes Fn but can't suppress it.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    // Carbon path
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x494E4B53 /* "INKS" */), id: 1)

    // Fn path — event tap
    private var fnEventTap: CFMachPort?
    private var fnRunLoopSource: CFRunLoopSource?
    private var fnIsDown = false

    // Fn path — passive fallback
    private var fnGlobalMonitor: Any?
    private var fnLocalMonitor: Any?

    init() {
        installCarbonHandler()
    }

    deinit {
        unregister()
        if let h = eventHandler { RemoveEventHandler(h) }
    }

    func register(binding: HotkeyBinding) {
        unregister()
        switch binding {
        case .carbon(let keyCode, let modifiers):
            registerCarbon(keyCode: keyCode, modifiers: modifiers)
        case .fn:
            registerFn()
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let tap = fnEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = fnRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            fnEventTap = nil
            fnRunLoopSource = nil
        }
        if let m = fnGlobalMonitor { NSEvent.removeMonitor(m); fnGlobalMonitor = nil }
        if let m = fnLocalMonitor { NSEvent.removeMonitor(m); fnLocalMonitor = nil }
        fnIsDown = false
    }

    // MARK: - Carbon path

    private func registerCarbon(keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("InkIt: RegisterEventHotKey failed (%d)", status)
        }
    }

    private func installCarbonHandler() {
        var spec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(eventRef)
            if kind == UInt32(kEventHotKeyPressed) {
                DispatchQueue.main.async { manager.onPress?() }
            } else if kind == UInt32(kEventHotKeyReleased) {
                DispatchQueue.main.async { manager.onRelease?() }
            }
            return noErr
        }, 2, &spec, selfPtr, &eventHandler)
    }

    // MARK: - Fn path

    /// Try the suppressing CGEventTap first; if that fails (no Accessibility
    /// permission yet, or otherwise), fall back to a passive NSEvent monitor.
    private func registerFn() {
        if installFnEventTap() { return }
        installFnPassiveMonitor()
    }

    private func installFnEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

            // System may disable the tap (timeout, user input excess). Re-enable.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.fnEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }

            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

            let fnDown = event.flags.contains(.maskSecondaryFn)
            // Only react (and consume) when this event actually toggles Fn —
            // other flag-change events (Cmd, Shift, …) must pass through.
            if fnDown != manager.fnIsDown {
                manager.fnIsDown = fnDown
                if fnDown {
                    DispatchQueue.main.async { manager.onPress?() }
                } else {
                    DispatchQueue.main.async { manager.onRelease?() }
                }
                // Swallow the event so macOS doesn't fire Globe / Dictation / Emoji.
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        fnEventTap = tap
        fnRunLoopSource = source
        return true
    }

    private func installFnPassiveMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let fnDown = event.modifierFlags.contains(.function)
            if fnDown && !self.fnIsDown {
                self.fnIsDown = true
                DispatchQueue.main.async { self.onPress?() }
            } else if !fnDown && self.fnIsDown {
                self.fnIsDown = false
                DispatchQueue.main.async { self.onRelease?() }
            }
        }
        fnGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handler($0) }
        fnLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }
}

/// Helpers for converting between AppKit modifier flags and Carbon modifier masks.
enum HotkeyConversion {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_ANSI_Grave: return "`"
        default:
            if let s = literalKey(for: keyCode) { return s }
            return "Key \(keyCode)"
        }
    }

    private static func literalKey(for keyCode: UInt32) -> String? {
        let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutPtr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = unsafeBitCast(layoutPtr, to: CFData.self) as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var realLen = 0
        var dead: UInt32 = 0
        let status = layoutData.withUnsafeBytes { ptr -> OSStatus in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(base,
                                  UInt16(keyCode),
                                  UInt16(kUCKeyActionDisplay),
                                  0,
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &dead,
                                  4,
                                  &realLen,
                                  &chars)
        }
        if status != noErr || realLen == 0 { return nil }
        return String(utf16CodeUnits: chars, count: realLen).uppercased()
    }
}
