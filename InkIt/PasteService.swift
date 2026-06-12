import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// Pastes a string into the frontmost application by swapping the pasteboard
/// and synthesizing Cmd+V, then restoring the previous clipboard contents.
final class PasteService {
    /// Time for a synchronous `setString` to propagate before the target reads
    /// it on Cmd+V. Peer dictation apps (VoiceInk 100ms, Handy 60ms, Whispering
    /// 50ms) all use a fixed settle like this — none poll.
    private let clipboardSettleDelay: TimeInterval = 0.08
    /// Extra margin after `activate()` for the focus change to land before we
    /// post Cmd+V. Only paid when the target wasn't already frontmost —
    /// `activate()` is async with no "now focused" callback, so this is the
    /// blind wait covering that gap. Skipped entirely in the common case.
    private let activationFocusDelay: TimeInterval = 0.12
    /// Cleanup happens off the critical path; still delayed so Cmd+V has
    /// definitely been processed before we touch the pasteboard again.
    private let clipboardRestoreDelay: TimeInterval = 0.4

    /// Private pasteboard type carrying a per-paste UUID, so before restoring we
    /// can confirm we still own the clipboard and didn't race a clipboard
    /// manager or a fast manual copy. Borrowed from VoiceInk.
    private static let sessionType = NSPasteboard.PasteboardType("com.cartesia.InkIt.PasteSession")
    /// Convention type that tells clipboard-history apps to ignore an entry, so
    /// the dictated text doesn't pollute the user's clipboard history.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func paste(text: String, targetApp: NSRunningApplication?, completion: @escaping (Bool) -> Void) {
        let pb = NSPasteboard.general
        // Snapshot existing items so non-string content is preserved when possible.
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
        // Tag the write so the restore step can verify ownership, and mark it
        // transient so clipboard managers skip the dictated text.
        pb.setString(sessionID, forType: Self.sessionType)
        pb.setString("1", forType: Self.transientType)

        // Only bring the target forward if it isn't already frontmost. Our
        // recorder is a non-activating panel, so the target normally never lost
        // focus — `activate()` + its focus wait are pure overhead in that case.
        // A nil target means "paste into whatever is frontmost", also no-wait.
        let alreadyFront = targetApp.map { $0.isActive } ?? true
        if !alreadyFront, let targetApp, !targetApp.isTerminated {
            targetApp.activate()
        }

        let preDelay = alreadyFront ? clipboardSettleDelay : clipboardSettleDelay + activationFocusDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + preDelay) {
            self.synthesizeCmdV()
            // The text is now visible to the user, so this is the end of
            // perceived paste latency — report completion immediately.
            completion(true)

            // Restoring the previous clipboard is cleanup that happens after the
            // user already sees their text, so it runs off the critical path.
            DispatchQueue.main.asyncAfter(deadline: .now() + self.clipboardRestoreDelay) {
                // Only restore if our write is still on the clipboard. If another
                // app (or the user) wrote to it in the interim, leave theirs be.
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

/// Runs a synchronous Accessibility traversal off the main thread, bounded by a
/// wall-clock deadline the closure must check inside its own loops.
///
/// AX attribute reads are blocking IPC into the target app; a huge or slow tree
/// can take seconds. On the main thread that stalls the UI *and* the Fn event
/// tap, freezing modifier keys system-wide. And a `Task`/timeout race can't
/// preempt synchronous AX code already running — so we hand the work a
/// `deadline` and make it responsible for returning whatever it has when the
/// clock runs out, on a detached thread. Every AX walk in the app routes through
/// here; nothing should hand-roll synchronous-AX-on-main again.
enum AX {
    static func run<T>(budget: TimeInterval, _ work: @escaping @Sendable (_ deadline: Date) -> T) async -> T {
        let deadline = Date().addingTimeInterval(budget)
        return await Task.detached(priority: .userInitiated) {
            work(deadline)
        }.value
    }
}

/// Answers one question at hotkey *release*: is an editable control focused
/// right now? InkIt resolves a paste target app at hotkey press, but by the time
/// the transcript is ready that app may have no focused text field — the user
/// clicked a non-editable surface, or focus moved during dictation. Firing Cmd+V
/// then lands the words in the wrong app (the one that *was* focused) or silently
/// nowhere. We re-check the system-wide focused element at release and only paste
/// when something can actually receive the text.
enum FocusedEditable {
    struct Result {
        /// Whether an editable control is focused right now.
        let isEditable: Bool
        /// The app owning the focused element — the *verified* paste target,
        /// resolved at release rather than the (possibly stale) press-time app.
        let app: NSRunningApplication?
    }

    static func current() async -> Result {
        // No Accessibility → we can't tell where text would land, so treat it as
        // "no editable focus" and hold the transcript in History rather than
        // gamble a Cmd+V. (Dictation already requires AX to start, so this is the
        // revoked-mid-session edge, not the common path.) Cheap and main-safe, so
        // it stays here rather than going off-thread.
        guard AXIsProcessTrusted() else { return Result(isEditable: false, app: nil) }

        // The probe is a chain of synchronous AX IPCs plus, for Chromium/Electron,
        // a bounded subtree scan. Run it off the main thread under a wall-clock
        // budget so a slow or huge tree can neither hitch the UI nor stall the Fn
        // event tap (which would freeze modifier keys). The budget is generous —
        // real apps resolve in well under it — so it never turns a would-be paste
        // into a held-in-History.
        let outcome = await AX.run(budget: 1.5) { deadline in resolve(deadline: deadline) }
        let app = outcome.pid > 0 ? NSRunningApplication(processIdentifier: outcome.pid) : nil
        return Result(isEditable: outcome.isEditable, app: app)
    }

    /// The pure, off-main editability probe: returns whether an editable control
    /// is focused right now and the owning pid (resolved back to an
    /// `NSRunningApplication` by the caller). Every traversal honors `deadline`
    /// so an outsized tree returns promptly instead of burning the whole budget.
    private static func resolve(deadline: Date) -> (isEditable: Bool, pid: pid_t) {
        let system = AXUIElementCreateSystemWide()
        guard let focused = copyElement(system, kAXFocusedUIElementAttribute as CFString) else {
            return (false, 0)
        }

        var pid: pid_t = 0
        AXUIElementGetPid(focused, &pid)

        // Fast path: the system-wide focused element is itself editable — true
        // for native fields and most Electron inputs.
        if isEditable(focused) {
            return (true, pid)
        }

        // Chromium/Electron fallback. For web-rendered content the system-wide
        // query frequently stops at the enclosing web area/group rather than
        // descending to the focused textbox, so the fast path sees a
        // non-editable container and we would wrongly hold the transcript in
        // History (observed with Antigravity, and the same risk for VS Code,
        // Slack, etc.). Re-resolve through the application element then follow
        // kAXFocusedUIElementAttribute down to the focused node.
        if pid > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            // Chromium builds its accessible tree lazily; until a client marks
            // the process accessibility-active it exposes only the web-area
            // shell and the focused textbox is invisible. We normally enable
            // this at hotkey press (see enableWebAccessibility), but re-assert
            // here for the focus-moved-mid-dictation case.
            enableWebAccessibility(appElement)

            if let appFocused = copyElement(appElement, kAXFocusedUIElementAttribute as CFString),
               descendToEditable(from: appFocused, deadline: deadline) {
                DebugLog.info("FocusedEditable: resolved editable via app-element descent (system-wide query saw a container)")
                return (true, pid)
            }
            // The focus chain can dead-end at a web area that never names its
            // focused child (Slack's Lexical composer does this). Scan the
            // focused window's subtree for the node Chromium flags AXFocused —
            // that's the field the caret is actually in — and accept it if it's
            // editable. Bounded so a deep tree can't stall the paste.
            if let window = copyElement(appElement, kAXFocusedWindowAttribute as CFString),
               focusedEditableInSubtree(window, deadline: deadline) {
                DebugLog.info("FocusedEditable: resolved editable via AXFocused subtree scan")
                return (true, pid)
            }
        }
        // Last resort: descend from the system-wide container itself.
        if descendToEditable(from: focused, deadline: deadline) {
            DebugLog.info("FocusedEditable: resolved editable via system-wide container descent")
            return (true, pid)
        }

        DebugLog.info("FocusedEditable: no editable focus — \(describe(focused, label: "system-wide"))")
        return (false, pid)
    }

    /// Marks a Chromium/Electron process as accessibility-active so it builds
    /// the full accessible tree (exposing focused web textboxes). Setting these
    /// attributes is idempotent and simply fails — harmlessly — on native apps
    /// that don't recognize them, so we attempt both unconditionally. Call this
    /// at hotkey press against the resolved target so the tree is ready by
    /// release rather than racing it.
    static func enableWebAccessibility(pid: pid_t) {
        guard AXIsProcessTrusted(), pid > 0 else { return }
        // Setting these attributes is blocking IPC into the target app; do it off
        // the main thread so it can't contribute to a main-thread stall.
        Task.detached(priority: .userInitiated) {
            enableWebAccessibility(AXUIElementCreateApplication(pid))
        }
    }

    private static func enableWebAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// Breadth-first scan for the editable element Chromium flags as focused.
    /// `kAXFocusedAttribute` is the per-element "caret is here" bit, so this
    /// pinpoints the real input even when no parent names it via
    /// `kAXFocusedUIElementAttribute`. Bounded in node count against deep DOMs.
    private static func focusedEditableInSubtree(_ root: AXUIElement, deadline: Date, maxNodes: Int = 1500) -> Bool {
        var queue = [root]
        var visited = 0
        while !queue.isEmpty, visited < maxNodes {
            // Time budget is the primary bound; the node cap is a backstop.
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

    /// One-line role/subrole/settable summary for trace logging when a paste is
    /// about to be held — so the failing AX shape is visible without a rebuild.
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
        // Primary signal: the element exposes a *settable* value. That's what an
        // editable field looks like to the accessibility layer — native text
        // fields/areas, search fields, and most web/Electron inputs all qualify,
        // without us enumerating every role.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        // Fallback: some controls don't report AXValue settable until first
        // edited, so trust a known editable role too.
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            return role == kAXTextFieldRole
                || role == kAXTextAreaRole
                || role == kAXComboBoxRole
        }
        return false
    }

    /// Follows `kAXFocusedUIElementAttribute` from `element` down through web
    /// container nodes looking for an editable element. Chromium exposes the
    /// focused web node this way even when the system-wide focus query stops at
    /// the enclosing web area. Bounded in depth and guarded against self-cycles.
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

    /// Copies an AXUIElement-valued attribute, returning nil unless the value is
    /// actually an AXUIElement.
    private static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }
}
