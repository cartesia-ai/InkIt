import Foundation
import AppKit
import ApplicationServices

/// Captures on-screen text from another app so we can extract a glossary of
/// identifiers the user might be dictating about. Used by the optional AI
/// correction pass to repair ASR mistakes on proper nouns.
protocol ContextProvider {
    func captureContext(for target: TargetAppSnapshot, runID: String) async -> ContextSnapshot
}

/// Cheap title-only AX read for an arbitrary app's focused window. Used to
/// confirm the focused window hasn't changed between capture start and the
/// full tree walk, without paying for the walk twice.
enum FocusedWindowTitle {
    static func read(for app: NSRunningApplication?) -> String? {
        guard let app, app.processIdentifier > 0 else { return nil }
        return read(pid: app.processIdentifier)
    }

    static func read(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
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
    private let walkBudget: TimeInterval = 0.25
    /// Cap children pushed per parent. A 339-row Notes sidebar would
    /// otherwise consume the entire budget before the walk could reach
    /// other panes. 30 children is plenty of breadth for any realistic
    /// content view.
    private let maxChildrenPerParent = 30
    /// Minimum characters captured from genuine *content* roles (text areas,
    /// static text, web content — not window titles, tabs, or buttons) for a
    /// capture to count as usable context. Terminal apps (Claude Code, vim,
    /// tmux) expose only window/tab chrome through AX; that chrome is noise the
    /// rewriter shouldn't be anchored to, so below this we send no context.
    private let minContentChars = 24

    func captureContext(for target: TargetAppSnapshot, runID: String) async -> ContextSnapshot {
        let pid = target.processIdentifier
        guard pid > 0 else {
            DebugLog.info("[\(runID)] AX capture: invalid target PID")
            return .unavailable(target: target, reason: "invalid target pid")
        }
        let currentTitle = FocusedWindowTitle.read(pid: pid)
        guard currentTitle == target.focusedWindowTitle else {
            return ContextSnapshot(
                source: .accessibility,
                confidence: .low,
                target: target,
                payload: "",
                evidence: [
                    "startTitle": target.focusedWindowTitle ?? "nil",
                    "currentTitle": currentTitle ?? "nil",
                    "pid": "\(pid)"
                ],
                rejectionReason: "AX target window title changed"
            )
        }

        DebugLog.info("[\(runID)] AX capture: walking pid=\(pid) app=\(target.localizedName) title=\(currentTitle ?? "nil")")

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
        let maxChildren = self.maxChildrenPerParent
        let result = await Task.detached(priority: .userInitiated) {
            Self.walk(pid: pid, maxDepth: maxDepth, maxNodes: maxNodes, maxChars: maxChars, maxChildren: maxChildren, deadline: deadline)
        }.value
        guard let result, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ContextSnapshot(
                source: .accessibility,
                confidence: .none,
                target: target,
                payload: "",
                evidence: [
                    "pid": "\(pid)",
                    "title": currentTitle ?? "nil"
                ],
                rejectionReason: "AX capture returned empty payload"
            )
        }
        // A capture that's all window/tab/button chrome (e.g. a terminal) gives
        // the rewriter no real subject matter — sending it only risks anchoring
        // corrections to noise. Treat it as unusable so we fall back to a
        // context-free polish instead.
        guard result.contentChars >= minContentChars else {
            DebugLog.info("[\(runID)] AX capture: chrome-only (contentChars=\(result.contentChars), total=\(result.text.count)) — skipping context")
            return ContextSnapshot(
                source: .accessibility,
                confidence: .low,
                target: target,
                payload: "",
                evidence: [
                    "pid": "\(pid)",
                    "title": currentTitle ?? "nil",
                    "chars": "\(result.text.count)",
                    "contentChars": "\(result.contentChars)"
                ],
                rejectionReason: "chrome-only context (\(result.contentChars) content chars)"
            )
        }
        return ContextSnapshot(
            source: .accessibility,
            confidence: .high,
            target: target,
            payload: result.text,
            evidence: [
                "pid": "\(pid)",
                "title": currentTitle ?? "nil",
                "chars": "\(result.text.count)",
                "contentChars": "\(result.contentChars)"
            ],
            rejectionReason: nil
        )
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

    /// Captured text plus how much of it came from genuine content roles (vs.
    /// chrome like window titles, tabs, and buttons).
    private struct WalkResult {
        let text: String
        let contentChars: Int
    }

    private static func walk(pid: pid_t,
                             maxDepth: Int,
                             maxNodes: Int,
                             maxChars: Int,
                             maxChildren: Int,
                             deadline: Date) -> WalkResult? {
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
        var contentChars = 0
        var nodes = 0
        // Breadth-first walk: visit all siblings at each depth before going
        // deeper. With DFS, a wide-but-shallow node like the Notes sidebar
        // (AXTable with 339 rows) starves the rest of the tree because its
        // children are popped before any of its siblings' subtrees are
        // visited. BFS plus a per-parent child cap keeps the walk balanced.
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        let started = Date()
        var hitDeadline = false

        while !queue.isEmpty {
            if Date() >= deadline {
                hitDeadline = true
                break
            }
            if nodes >= maxNodes || collected.count >= maxChars { break }
            let (element, depth) = queue.removeFirst()
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
            // Read the role only when this node contributed text (for chrome
            // classification) or while we're still tracing — one AX IPC call.
            var role: String? = nil
            if captured > 0 {
                role = readString(element, attr: kAXRoleAttribute as CFString) ?? "?"
                if let role, !chromeRoles.contains(role) {
                    contentChars += captured
                }
            }
            let children = readChildren(of: element)
            let pushedChildren = min(children.count, maxChildren)

            if traceCount < traceLimit {
                let roleForTrace = role ?? readString(element, attr: kAXRoleAttribute as CFString) ?? "?"
                let attrPart = firstAttrPreview.map { " first=\($0.name)(\($0.length)c)" } ?? ""
                let capNote = pushedChildren < children.count ? " (capped from \(children.count))" : ""
                DebugLog.info("AX node[\(nodes)] role=\(roleForTrace) depth=\(depth) kids=\(children.count)\(capNote) captured=\(captured)c\(attrPart)")
                traceCount += 1
            }

            if depth >= maxDepth { continue }
            // Append at the queue tail (BFS) and cap so any single
            // long-listing node can't starve its siblings' subtrees.
            for child in children.prefix(maxChildren) {
                queue.append((child, depth + 1))
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
        return WalkResult(text: collected, contentChars: contentChars)
    }

    /// Roles whose text is window/app chrome, not document content: window
    /// titles, tab strips, buttons, menus, toolbars. A capture made up only of
    /// these (the typical terminal-emulator AX tree) carries no subject matter
    /// for the rewriter, so it doesn't count toward usable content.
    private static let chromeRoles: Set<String> = [
        "AXWindow", "AXButton", "AXRadioButton", "AXTabGroup",
        "AXToolbar", "AXMenuBar", "AXMenuBarItem", "AXMenu",
        "AXMenuItem", "AXMenuButton", "AXPopUpButton", "AXCheckBox",
        "AXImage", "AXSplitter", "AXDisclosureTriangle"
    ]

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
        kAXSelectedTextAttribute as CFString
        // kAXHelpAttribute deliberately omitted: in Notes (and many other
        // list-bearing apps) every row carries identical UI-affordance help
        // text like "Perform press or select Return to open note." which
        // floods the capture with noise the LLM has to wade through.
    ]
}
