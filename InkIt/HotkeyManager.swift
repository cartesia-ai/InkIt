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
    // The tap callback runs on its own thread/run loop, not the main one. An
    // *active* `flagsChanged` tap blocks every modifier-key press until its
    // callback returns; servicing it on the main run loop means any main-thread
    // stall (a slow AX walk, heavy SwiftUI work) freezes Cmd/Shift/… system-wide
    // until the tap times out. A dedicated thread decouples modifier delivery
    // from the main thread entirely.
    private var fnTapThread: Thread?
    private var fnTapRunLoop: CFRunLoop?

    // Fn path — passive fallback
    private var fnGlobalMonitor: Any?
    private var fnLocalMonitor: Any?

    // Modifier path — a bare ⌘/⌥/⌃/⇧ (left or right) used on its own. Same
    // dedicated-thread tap as Fn, but listen-only: the modifier must keep
    // working for normal combos, so we observe its press/release and never
    // suppress it. `modKeyCode` is the physical key we react to; `modMask` is
    // the device-independent flag that tells press from release.
    private var modEventTap: CFMachPort?
    private var modRunLoopSource: CFRunLoopSource?
    private var modTapThread: Thread?
    private var modTapRunLoop: CFRunLoop?
    private var modGlobalMonitor: Any?
    private var modLocalMonitor: Any?
    private var modIsDown = false
    private var modKeyCode: Int64 = 0
    private var modMask: CGEventFlags = []

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
        case .modifierKey(let keyCode):
            registerModifier(keyCode: keyCode)
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let tap = fnEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Tear the source out of the dedicated tap thread's run loop and stop
            // that run loop so the thread returns from CFRunLoopRun and exits.
            if let runLoop = fnTapRunLoop {
                if let src = fnRunLoopSource {
                    CFRunLoopRemoveSource(runLoop, src, .commonModes)
                }
                CFRunLoopStop(runLoop)
            }
            fnEventTap = nil
            fnRunLoopSource = nil
            fnTapRunLoop = nil
            fnTapThread = nil
        }
        if let m = fnGlobalMonitor { NSEvent.removeMonitor(m); fnGlobalMonitor = nil }
        if let m = fnLocalMonitor { NSEvent.removeMonitor(m); fnLocalMonitor = nil }
        fnIsDown = false
        if let tap = modEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoop = modTapRunLoop {
                if let src = modRunLoopSource { CFRunLoopRemoveSource(runLoop, src, .commonModes) }
                CFRunLoopStop(runLoop)
            }
            modEventTap = nil
            modRunLoopSource = nil
            modTapRunLoop = nil
            modTapThread = nil
        }
        if let m = modGlobalMonitor { NSEvent.removeMonitor(m); modGlobalMonitor = nil }
        if let m = modLocalMonitor { NSEvent.removeMonitor(m); modLocalMonitor = nil }
        modIsDown = false
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

            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Function) else {
                return Unmanaged.passUnretained(event)
            }

            let fnDown = event.flags.contains(.maskSecondaryFn)
            // Only react (and consume) when this event actually toggles Fn.
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
        fnEventTap = tap
        fnRunLoopSource = source

        // Service the tap on a dedicated thread rather than the main run loop, so
        // a busy main thread can never stall modifier-key delivery (see the
        // `fnTapThread` note above). The callback only does a tiny async hop to
        // main, so this thread stays responsive regardless of app workload. The
        // source keeps the run loop alive; `unregister()` stops it so the thread
        // exits. `fnTapRunLoop` is written once here at thread start and read
        // later on `unregister` (a user action, well separated in time).
        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.fnTapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.cartesia.InkIt.FnEventTap"
        thread.qualityOfService = .userInteractive
        fnTapThread = thread
        thread.start()
        return true
    }

    private func installFnPassiveMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == UInt16(kVK_Function) else { return }
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

    // MARK: - Modifier path

    private func registerModifier(keyCode: UInt32) {
        modKeyCode = Int64(keyCode)
        modMask = Self.cgFlag(forModifierKeyCode: keyCode)
        modIsDown = false
        if installModifierEventTap() { return }
        installModifierPassiveMonitor()
    }

    private func installModifierEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.modEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }

            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

            // React only to our specific physical key; the mask tells down from
            // up. Everything passes through untouched.
            if event.getIntegerValueField(.keyboardEventKeycode) == manager.modKeyCode {
                let isDown = event.flags.contains(manager.modMask)
                if isDown != manager.modIsDown {
                    manager.modIsDown = isDown
                    if isDown {
                        DispatchQueue.main.async { manager.onPress?() }
                    } else {
                        DispatchQueue.main.async { manager.onRelease?() }
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Listen-only: a bare modifier must keep functioning for normal combos,
        // so unlike the Fn tap we never return nil to swallow the event.
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        modEventTap = tap
        modRunLoopSource = source

        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.modTapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.cartesia.InkIt.ModifierEventTap"
        thread.qualityOfService = .userInteractive
        modTapThread = thread
        thread.start()
        return true
    }

    private func installModifierPassiveMonitor() {
        let nsMask = HotkeyConversion.nsModifierFlag(for: UInt32(modKeyCode))
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == UInt16(self.modKeyCode) else { return }
            let isDown = event.modifierFlags.contains(nsMask)
            if isDown != self.modIsDown {
                self.modIsDown = isDown
                if isDown {
                    DispatchQueue.main.async { self.onPress?() }
                } else {
                    DispatchQueue.main.async { self.onRelease?() }
                }
            }
        }
        modGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handler($0) }
        modLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    private static func cgFlag(forModifierKeyCode keyCode: UInt32) -> CGEventFlags {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return .maskCommand
        case kVK_Option, kVK_RightOption:   return .maskAlternate
        case kVK_Control, kVK_RightControl: return .maskControl
        case kVK_Shift, kVK_RightShift:     return .maskShift
        default:                            return []
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

    /// The eight bare modifier keys allowed as standalone hotkeys, by physical
    /// keyCode. Left and right are distinct so the recorder can show the side.
    static let modifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command), UInt32(kVK_RightCommand),
        UInt32(kVK_Option),  UInt32(kVK_RightOption),
        UInt32(kVK_Control), UInt32(kVK_RightControl),
        UInt32(kVK_Shift),   UInt32(kVK_RightShift)
    ]

    static func isModifierKeyCode(_ keyCode: UInt32) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    /// The AppKit flag a given modifier keyCode toggles — lets the recorder tell
    /// a press from a release on a flagsChanged event.
    static func nsModifierFlag(for keyCode: UInt32) -> NSEvent.ModifierFlags {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return .command
        case kVK_Option, kVK_RightOption:   return .option
        case kVK_Control, kVK_RightControl: return .control
        case kVK_Shift, kVK_RightShift:     return .shift
        default:                            return []
        }
    }

    /// Glyph + label for a bare modifier hotkey, e.g. "⌥ Opt →". Right-hand keys
    /// get a trailing arrow; left-hand keys are shown plain.
    static func modifierLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Command:      return "⌘ Cmd"
        case kVK_RightCommand: return "⌘ Cmd →"
        case kVK_Option:       return "⌥ Opt"
        case kVK_RightOption:  return "⌥ Opt →"
        case kVK_Control:      return "⌃ Ctrl"
        case kVK_RightControl: return "⌃ Ctrl →"
        case kVK_Shift:        return "⇧ Shift"
        case kVK_RightShift:   return "⇧ Shift →"
        default:               return "Key \(keyCode)"
        }
    }

    private static let functionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
        UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19)
    ]

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeyCodes.contains(UInt32(keyCode))
    }

    /// One display token per key, e.g. ["⌃ Ctrl", "⌥ Opt", "S"] — rendered as a
    /// keycap each, joined by "+". A single letter is uppercased to match how
    /// keys are labelled on a physical keyboard.
    static func displayTokens(for binding: HotkeyBinding) -> [String] {
        switch binding {
        case .fn:
            return ["🌐 fn"]
        case .modifierKey(let keyCode):
            return [modifierLabel(for: keyCode)]
        case .carbon(let keyCode, let modifiers):
            var tokens: [String] = []
            if modifiers & UInt32(controlKey) != 0 { tokens.append("⌃ Ctrl") }
            if modifiers & UInt32(optionKey) != 0 { tokens.append("⌥ Opt") }
            if modifiers & UInt32(shiftKey) != 0 { tokens.append("⇧ Shift") }
            if modifiers & UInt32(cmdKey) != 0 { tokens.append("⌘ Cmd") }
            tokens.append(tokenName(for: keyCode))
            return tokens
        }
    }

    private static func tokenName(for keyCode: UInt32) -> String {
        let name = keyName(for: keyCode)
        if name.count == 1, name.rangeOfCharacter(from: .letters) != nil {
            return name.uppercased()
        }
        return name
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
