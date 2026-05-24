import Foundation
import AppKit

/// Reads the user's most recently active Cursor agent transcript and returns
/// its prose content as a single string. Bypasses the AX wall that hides
/// Chromium-rendered content from native accessibility queries.
///
/// Cursor writes each agent session as line-delimited JSON at:
///   ~/.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>.jsonl
///
/// Each line is an Anthropic-Messages-API-shaped message:
///   {"role":"user","message":{"content":[{"type":"text","text":"..."}, ...]}}
///   {"role":"assistant","message":{"content":[{"type":"text","text":"..."},{"type":"tool_use",...}]}}
///
/// We extract every `type:"text"` block, drop the `<user_query>` framing tags,
/// and concatenate. Tool calls and tool results are ignored — they're mostly
/// noise (paths, JSON blobs) and inflate token count.
final class CursorTranscriptProvider: ContextProvider {
    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    /// ~32k chars ≈ 8k tokens — leaves plenty of headroom in the LLM prompt.
    private let maxChars = 32_000

    func captureContext(for app: NSRunningApplication?) async -> String? {
        guard isCursor(app: app) else { return nil }
        return await Task.detached(priority: .userInitiated) { [maxChars] in
            Self.readNewestTranscript(maxChars: maxChars)
        }.value
    }

    private func isCursor(app: NSRunningApplication?) -> Bool {
        if let bid = app?.bundleIdentifier {
            return bid == Self.cursorBundleID
        }
        // No explicit target: only attempt this provider if Cursor is running
        // and likely visible. The AppCoordinator already resolved the target,
        // so a nil here usually means "InkIt was frontmost" — accept Cursor
        // if it's any of the running apps.
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.cursorBundleID && !$0.isTerminated
        }
    }

    private static func readNewestTranscript(maxChars: Int) -> String? {
        let cursorRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: cursorRoot.path) else {
            DebugLog.info("CursorTranscriptProvider: ~/.cursor/projects missing")
            return nil
        }

        guard let url = newestTranscriptURL(under: cursorRoot) else {
            DebugLog.info("CursorTranscriptProvider: no transcript jsonl found")
            return nil
        }
        DebugLog.info("CursorTranscriptProvider: reading \(url.lastPathComponent)")

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            DebugLog.info("CursorTranscriptProvider: read failed for \(url.path)")
            return nil
        }
        // Read a generous tail so we capture only recent turns. Doubling the
        // char budget here is fine because most lines drop large tool_use /
        // tool_result blocks during parse.
        let tailSize = min(data.count, max(16_000, maxChars * 3))
        let tail = data.suffix(tailSize)
        guard let raw = String(data: tail, encoding: .utf8) else { return nil }

        // If we sliced into the middle of a line, drop the leading partial
        // line so JSON parsing starts on a clean boundary.
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if tail.count < data.count, lines.count > 1 {
            lines.removeFirst()
        }

        var pieces: [String] = []
        var total = 0
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let role = json["role"] as? String,
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { continue }

            for block in content {
                guard (block["type"] as? String) == "text",
                      let text = block["text"] as? String
                else { continue }
                let cleaned = stripUserQueryTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty { continue }
                pieces.append("\(role.uppercased()): \(cleaned)")
                total += cleaned.count + role.count + 3
                if total >= maxChars { break }
            }
            if total >= maxChars { break }
        }
        guard !pieces.isEmpty else { return nil }
        let joined = pieces.joined(separator: "\n\n")
        return joined.count > maxChars ? String(joined.suffix(maxChars)) : joined
    }

    /// Find the .jsonl with the freshest mtime under any agent-transcripts/
    /// directory. The freshest file = the session the user is actively in.
    private static func newestTranscriptURL(under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var best: (URL, Date)? = nil
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            // Only consider files under .../agent-transcripts/...
            guard url.pathComponents.contains("agent-transcripts") else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let mtime = values?.contentModificationDate ?? .distantPast
            if let (_, current) = best, current >= mtime { continue }
            best = (url, mtime)
        }
        return best?.0
    }

    private static func stripUserQueryTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<user_query>", with: "")
            .replacingOccurrences(of: "</user_query>", with: "")
    }
}
