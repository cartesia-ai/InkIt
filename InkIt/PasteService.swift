import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices

final class PasteService {
    private let clipboardSettleDelay: TimeInterval = 0.08
    private let activationFocusDelay: TimeInterval = 0.12
    private let clipboardRestoreDelay: TimeInterval = 0.4

    private static let sessionType = NSPasteboard.PasteboardType("com.cartesia.InkIt.PasteSession")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func paste(text: String, targetApp: NSRunningApplication?, completion: @escaping (Bool) -> Void) {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict.isEmpty ? nil : dict
        } ?? []

        let sessionID = UUID().uuidString
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        if !ok {
            completion(false)
            return
        }
        pb.setString(sessionID, forType: Self.sessionType)
        pb.setString("1", forType: Self.transientType)

        let alreadyFront = targetApp.map { $0.isActive } ?? true
        if !alreadyFront, let targetApp, !targetApp.isTerminated {
            targetApp.activate()
        }

        let preDelay = alreadyFront ? clipboardSettleDelay : clipboardSettleDelay + activationFocusDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + preDelay) {
            self.synthesizeCmdV()
            completion(true)

            DispatchQueue.main.asyncAfter(deadline: .now() + self.clipboardRestoreDelay) {
                let stillOurs = pb.string(forType: .string) == text
                    && pb.string(forType: Self.sessionType) == sessionID
                guard stillOurs else { return }

                pb.clearContents()
                if !saved.isEmpty {
                    let restored = saved.map { dict -> NSPasteboardItem in
                        let item = NSPasteboardItem()
                        for (type, data) in dict { item.setData(data, forType: type) }
                        return item
                    }
                    pb.writeObjects(restored)
                }
            }
        }
    }

    private func synthesizeCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

enum AX {
    static func run<T>(budget: TimeInterval, _ work: @escaping @Sendable (_ deadline: Date) -> T) async -> T {
        let deadline = Date().addingTimeInterval(budget)
        return await Task.detached(priority: .userInitiated) {
            work(deadline)
        }.value
    }
}

enum FocusedEditable {
    struct Result {
        let isEditable: Bool
        let app: NSRunningApplication?
        let focusedPID: pid_t

        /// True when AX did not find an editable field but the dictation target is
        /// still frontmost, so Cmd+V is likely to land in the right place anyway.
        /// GPU terminals and native agent UIs (Conductor, super.engineering, …)
        /// often accept keyboard paste without exposing AXTextArea.
        func allowsKeyboardPasteFallback(to target: NSRunningApplication?) -> Bool {
            guard !isEditable else { return false }
            guard let target, !target.isTerminated, target.isActive else { return false }
            if focusedPID <= 0 { return true }
            return focusedPID == target.processIdentifier
        }
    }

    static func current() async -> Result {
        guard AXIsProcessTrusted() else {
            return Result(isEditable: false, app: nil, focusedPID: 0)
        }

        let outcome = await AX.run(budget: 1.5) { deadline in resolve(deadline: deadline) }
        let app = outcome.pid > 0 ? NSRunningApplication(processIdentifier: outcome.pid) : nil
        return Result(isEditable: outcome.isEditable, app: app, focusedPID: outcome.pid)
    }

    private static func resolve(deadline: Date) -> (isEditable: Bool, pid: pid_t) {
        let system = AXUIElementCreateSystemWide()
        guard let focused = copyElement(system, kAXFocusedUIElementAttribute as CFString) else {
            return (false, 0)
        }

        var pid: pid_t = 0
        AXUIElementGetPid(focused, &pid)

        if isEditable(focused) {
            return (true, pid)
        }

        if pid > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            enableWebAccessibility(appElement)

            if let appFocused = copyElement(appElement, kAXFocusedUIElementAttribute as CFString),
               descendToEditable(from: appFocused, deadline: deadline) {
                DebugLog.info("FocusedEditable: resolved editable via app-element descent (system-wide query saw a container)")
                return (true, pid)
            }
            if let window = copyElement(appElement, kAXFocusedWindowAttribute as CFString),
               focusedEditableInSubtree(window, deadline: deadline) {
                DebugLog.info("FocusedEditable: resolved editable via AXFocused subtree scan")
                return (true, pid)
            }
        }
        if descendToEditable(from: focused, deadline: deadline) {
            DebugLog.info("FocusedEditable: resolved editable via system-wide container descent")
            return (true, pid)
        }

        DebugLog.info("FocusedEditable: no editable focus — \(describe(focused, label: "system-wide"))")
        return (false, pid)
    }

    static func enableWebAccessibility(pid: pid_t) {
        guard AXIsProcessTrusted(), pid > 0 else { return }
        Task.detached(priority: .userInitiated) {
            enableWebAccessibility(AXUIElementCreateApplication(pid))
        }
    }

    private static func enableWebAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func focusedEditableInSubtree(_ root: AXUIElement, deadline: Date, maxNodes: Int = 1500) -> Bool {
        var queue = [root]
        var visited = 0
        while !queue.isEmpty, visited < maxNodes {
            if Date() >= deadline { return false }
            let element = queue.removeFirst()
            visited += 1
            if isFocused(element), isEditable(element) { return true }
            queue.append(contentsOf: children(of: element))
        }
        return false
    }

    private static func isFocused(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let array = ref as? [AXUIElement] else {
            return []
        }
        return array
    }

    private static func describe(_ element: AXUIElement, label: String) -> String {
        func attr(_ name: CFString) -> String {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name, &ref) == .success,
                  let value = ref as? String else { return "nil" }
            return value
        }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return "\(label) role=\(attr(kAXRoleAttribute as CFString)) subrole=\(attr(kAXSubroleAttribute as CFString)) valueSettable=\(settable.boolValue)"
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            return role == kAXTextFieldRole
                || role == kAXTextAreaRole
                || role == kAXComboBoxRole
        }
        return false
    }

    private static func descendToEditable(from element: AXUIElement, deadline: Date, maxHops: Int = 6) -> Bool {
        var current = element
        for _ in 0..<maxHops {
            if Date() >= deadline { return false }
            if isEditable(current) { return true }
            guard let next = copyElement(current, kAXFocusedUIElementAttribute as CFString),
                  !CFEqual(current, next) else { return false }
            current = next
        }
        return isEditable(current)
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }
}
