import Foundation
import AppKit
import ApplicationServices

/// Debug-only deep walker. Triggered from the Diagnostics panel in Settings,
/// after a 2-second delay so the user can switch focus to the target app.
/// Writes a structured dump of every node to `~/Library/Logs/InkIt-debug.log`.
///
/// A general-purpose Accessibility-tree inspector: the dump reveals what
/// attributes each role actually exposes for a given app, which is handy when
/// diagnosing why an app's AX tree looks the way it does.
enum AXTreeDumper {
    static let nodeLimit = 5000
    static let wallClockLimit: TimeInterval = 5.0
    /// Strings longer than this get summarised as `<N chars>` in the dump.
    static let inlineStringMax = 200

    /// Reads commonly-useful attributes regardless of role. The walker also
    /// asks each element for its *full* attribute name list and reports any
    /// names not in this set so we discover new ones.
    private static let knownAttributes: [CFString] = [
        kAXRoleAttribute as CFString,
        kAXSubroleAttribute as CFString,
        kAXRoleDescriptionAttribute as CFString,
        kAXTitleAttribute as CFString,
        kAXValueAttribute as CFString,
        kAXDescriptionAttribute as CFString,
        kAXHelpAttribute as CFString,
        kAXSelectedTextAttribute as CFString,
        kAXIdentifierAttribute as CFString,
        kAXPlaceholderValueAttribute as CFString,
        kAXNumberOfCharactersAttribute as CFString
    ]

    /// Dumps the AX tree of the user's currently-focused app to the debug
    /// log. Resolves the target the same way the regular AX provider does
    /// (frontmost-non-InkIt → first regular non-InkIt running app) so it
    /// can be triggered from InkIt's own Settings window.
    static func dumpFocusedApp() {
        let ownBundleID = Bundle.main.bundleIdentifier
        let resolved: NSRunningApplication? = {
            if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != ownBundleID {
                return front
            }
            return NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID && !$0.isTerminated
            }
        }()
        guard let app = resolved, app.processIdentifier > 0 else {
            DebugLog.info("AXTreeDumper: no resolvable non-InkIt frontmost")
            return
        }
        let pid = app.processIdentifier
        let name = app.localizedName ?? "<pid:\(pid)>"
        DebugLog.info("AXTreeDumper: ── BEGIN dump for pid=\(pid) app=\(name) bundle=\(app.bundleIdentifier ?? "?") ──")

        Task.detached(priority: .userInitiated) {
            walk(pid: pid)
            DebugLog.info("AXTreeDumper: ── END dump for pid=\(pid) ──")
        }
    }

    private static func walk(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        guard let root = focusedOrMainWindow(of: appElement) else {
            DebugLog.info("AXTreeDumper: no focused/main/first window for pid=\(pid)")
            return
        }

        var stack: [(AXUIElement, Int, String)] = [(root, 0, "0")]
        var nodes = 0
        let started = Date()

        while let (element, depth, path) = stack.popLast() {
            if nodes >= nodeLimit { DebugLog.info("AXTreeDumper: node limit hit at \(nodes)"); break }
            if Date().timeIntervalSince(started) > wallClockLimit {
                DebugLog.info("AXTreeDumper: wall-clock limit hit at \(nodes) nodes")
                break
            }
            nodes += 1

            dumpElement(element, path: path, depth: depth)

            let children = readChildren(of: element)
            for (i, child) in children.enumerated().reversed() {
                stack.append((child, depth + 1, "\(path).\(i)"))
            }
        }
        let elapsed = String(format: "%.3fs", Date().timeIntervalSince(started))
        DebugLog.info("AXTreeDumper: visited \(nodes) nodes in \(elapsed)")
    }

    private static func dumpElement(_ element: AXUIElement, path: String, depth: Int) {
        var pieces: [String] = []
        var captured = Set<String>()
        for attr in knownAttributes {
            if let line = formatAttribute(element, attr: attr) {
                pieces.append(line)
                captured.insert(attr as String)
            }
        }
        // Discover any attributes we don't know about and report their names.
        var namesRef: CFArray?
        if AXUIElementCopyAttributeNames(element, &namesRef) == .success,
           let names = namesRef as? [String] {
            let extras = names.filter { !captured.contains($0) && !$0.hasPrefix("AXChildren") && !$0.hasPrefix("AXParent") && !$0.hasPrefix("AXWindow") && !$0.hasPrefix("AXTopLevel") }
            if !extras.isEmpty {
                pieces.append("otherAttrs=\(extras.joined(separator: ","))")
            }
        }
        let line = "[\(path)] d=\(depth) " + pieces.joined(separator: " ")
        DebugLog.info("AXTreeDumper: \(line)")
    }

    private static func formatAttribute(_ element: AXUIElement, attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success, let value = ref else {
            return nil
        }
        let name = (attr as String).replacingOccurrences(of: "AX", with: "")
        if let str = value as? String {
            if str.isEmpty { return nil }
            if str.count > inlineStringMax {
                return "\(name)=<\(str.count) chars: \(str.prefix(inlineStringMax))…>"
            }
            return "\(name)=\"\(str)\""
        }
        if let num = value as? Int {
            return "\(name)=\(num)"
        }
        if let bool = value as? Bool {
            return "\(name)=\(bool)"
        }
        // Unknown CFType — print its type name so we can decide whether to
        // care.
        let typeID = CFGetTypeID(value)
        let typeName = CFCopyTypeIDDescription(typeID) as String? ?? "?"
        return "\(name)=<\(typeName)>"
    }

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

    private static func focusedOrMainWindow(of appElement: AXUIElement) -> AXUIElement? {
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] as [CFString] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, attr, &ref) == .success,
               let v = ref, CFGetTypeID(v) == AXUIElementGetTypeID() {
                return (v as! AXUIElement)
            }
        }
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref) == .success,
           let arr = ref as? [AXUIElement], let first = arr.first {
            return first
        }
        return nil
    }
}
