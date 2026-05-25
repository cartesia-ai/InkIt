import Foundation
import AppKit
import ApplicationServices

/// Captures on-screen text from another app so we can extract a glossary of
/// identifiers the user might be dictating about. Used by the optional AI
/// correction pass to repair ASR mistakes on proper nouns.
protocol ContextProvider {
    func captureContext(for app: NSRunningApplication?) async -> String?
}

/// Cheap title-only AX read for an arbitrary app's focused window. Used by
/// `SessionLocator` to disambiguate which Cursor session is active without
/// paying for a full tree walk.
enum FocusedWindowTitle {
    static func read(for app: NSRunningApplication?) -> String? {
        let ownBundleID = Bundle.main.bundleIdentifier
        let resolvedPid: pid_t? = {
            if let app, app.bundleIdentifier != ownBundleID { return app.processIdentifier }
            if let front = NSWorkspace.shared.frontmostApplication,
               front.bundleIdentifier != ownBundleID { return front.processIdentifier }
            return NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID && !$0.isTerminated
            }?.processIdentifier
        }()
        guard let pid = resolvedPid, pid > 0 else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let value = ref,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = value as! AXUIElement
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String,
              !title.isEmpty
        else { return nil }
        return title
    }
}

/// Walks the focused app's Accessibility tree and concatenates visible text.
///
/// The AX tree on a busy app (Cursor, Xcode, a browser) can be huge — we cap
/// depth, node count, and total characters so a slow read never blocks the
/// paste. Anything past those budgets is dropped silently; a partial glossary
/// is fine.
final class FocusedWindowAXProvider: ContextProvider {
    private let maxDepth = 8
    private let maxNodes = 1200
    private let maxChars = 20_000
    private let walkBudget: TimeInterval = 0.5

    func captureContext(for app: NSRunningApplication?) async -> String? {
        let ownBundleID = Bundle.main.bundleIdentifier
        // Resolve the target PID. Prefer the explicit app, otherwise the
        // frontmost — but never InkIt itself. If InkIt is frontmost (e.g. the
        // user clicked our window before Fn-press), fall back to whatever the
        // first non-InkIt running app is.
        let resolvedApp: NSRunningApplication? = {
            if let app, app.bundleIdentifier != ownBundleID { return app }
            if let front = NSWorkspace.shared.frontmostApplication,
               front.bundleIdentifier != ownBundleID {
                return front
            }
            return NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID && !$0.isTerminated
            }
        }()
        guard let pid = resolvedApp?.processIdentifier, pid > 0 else {
            DebugLog.info("AX capture: could not resolve a non-InkIt PID")
            return nil
        }
        let name = resolvedApp?.localizedName ?? "<pid:\(pid)>"
        DebugLog.info("AX capture: walking pid=\(pid) app=\(name)")

        // Run the synchronous AX walk on a dedicated thread (Task.detached) and
        // bound it by a wall-clock deadline checked inside the walk loop. The
        // previous withTaskGroup race didn't actually preempt — `group.cancelAll`
        // can't interrupt synchronous AX IPC, so withTaskGroup waited for the
        // walk to finish AND threw away its result. The internal deadline
        // approach always returns whatever the walk had collected when the
        // budget expired.
        let deadline = Date().addingTimeInterval(walkBudget)
        let maxDepth = self.maxDepth
        let maxNodes = self.maxNodes
        let maxChars = self.maxChars
        return await Task.detached(priority: .userInitiated) {
            Self.walk(pid: pid, maxDepth: maxDepth, maxNodes: maxNodes, maxChars: maxChars, deadline: deadline)
        }.value
    }

    /// Returns the focused window for the app, or the main window, or the
    /// first window we can find. The menu bar — which would otherwise consume
    /// most of the tree-walk budget on a complex app — is intentionally skipped.
    private static func rootWindow(forApp appElement: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &ref) == .success,
           let value = ref,
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            return (value as! AXUIElement)
        }
        ref = nil
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &ref) == .success,
           let value = ref,
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            return (value as! AXUIElement)
        }
        ref = nil
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref) == .success,
           let windows = ref as? [AXUIElement], let first = windows.first {
            return first
        }
        return nil
    }

    private static func walk(pid: pid_t,
                             maxDepth: Int,
                             maxNodes: Int,
                             maxChars: Int,
                             deadline: Date) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let root = rootWindow(forApp: appElement) else {
            DebugLog.info("AX capture: no focused/main/first window for pid=\(pid)")
            return nil
        }

        var windowTitleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXTitleAttribute as CFString, &windowTitleRef) == .success,
           let title = windowTitleRef as? String {
            DebugLog.info("AX capture: root window title=\"\(title)\"")
        }

        let traceLimit = 60
        var traceCount = 0
        var collected = ""
        var nodes = 0
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        let started = Date()
        var hitDeadline = false

        while let (element, depth) = stack.popLast() {
            if Date() >= deadline {
                hitDeadline = true
                break
            }
            if nodes >= maxNodes || collected.count >= maxChars { break }
            nodes += 1

            let beforeCollectedCount = collected.count
            var firstAttrPreview: (name: String, length: Int)? = nil

            for attr in textAttributes {
                if collected.count >= maxChars { break }
                var value: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, attr, &value)
                guard status == .success, let str = value as? String, !str.isEmpty else { continue }
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2, trimmed.count <= 4_000 else { continue }
                if !collected.isEmpty { collected.append(" ") }
                collected.append(trimmed)
                if firstAttrPreview == nil {
                    firstAttrPreview = (attr as String, trimmed.count)
                }
            }

            let captured = collected.count - beforeCollectedCount
            let children = readChildren(of: element)

            if traceCount < traceLimit {
                let role = readString(element, attr: kAXRoleAttribute as CFString) ?? "?"
                let attrPart = firstAttrPreview.map { " first=\($0.name)(\($0.length)c)" } ?? ""
                DebugLog.info("AX node[\(nodes)] role=\(role) depth=\(depth) kids=\(children.count) captured=\(captured)c\(attrPart)")
                traceCount += 1
            }

            if depth >= maxDepth { continue }
            // Push in reverse so depth-first visits the first child next.
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }

        let elapsed = String(format: "%.3fs", Date().timeIntervalSince(started))
        if hitDeadline {
            DebugLog.info("AX walk hit deadline at \(elapsed) — visited \(nodes) nodes, \(collected.count) chars captured")
        } else {
            DebugLog.info("AX walk finished in \(elapsed) — visited \(nodes) nodes, \(collected.count) chars captured")
        }

        if collected.isEmpty { return nil }
        if collected.count > maxChars {
            collected = String(collected.prefix(maxChars))
        }
        return collected
    }

    /// Some apps populate only `kAXChildrenAttribute`; others use
    /// `kAXVisibleChildrenAttribute` (e.g. virtualized scroll content).
    /// Try the regular list first; fall back to the visible list when empty.
    private static func readChildren(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
           let arr = ref as? [AXUIElement], !arr.isEmpty {
            return arr
        }
        ref = nil
        if AXUIElementCopyAttributeValue(element, kAXVisibleChildrenAttribute as CFString, &ref) == .success,
           let arr = ref as? [AXUIElement], !arr.isEmpty {
            return arr
        }
        return []
    }

    private static func readString(_ element: AXUIElement, attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success,
              let s = ref as? String else { return nil }
        return s
    }

    private static let textAttributes: [CFString] = [
        kAXValueAttribute as CFString,
        kAXTitleAttribute as CFString,
        kAXDescriptionAttribute as CFString,
        kAXSelectedTextAttribute as CFString,
        kAXHelpAttribute as CFString
    ]
}
