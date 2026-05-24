import Foundation

/// One turn from a Cursor agent transcript, flattened to plain text.
struct ConversationMessage: Equatable {
    enum Role: String { case user, assistant, other }
    let role: Role
    /// All `type:"text"` content blocks for this message, joined with " ".
    let text: String
}

/// Parses Cursor's per-session `.jsonl` files into an ordered array of
/// messages. Each line is an Anthropic-Messages-API-shaped envelope:
///   {"role":"user|assistant","message":{"content":[{"type":"text","text":"…"}, …]}}
/// Tool calls and tool results are dropped — they're mostly noise and we
/// only want prose the user actually read.
enum ConversationLoader {
    /// Returns oldest → newest. Empty array if the file is missing or
    /// nothing parses; never throws.
    static func load(from url: URL) -> [ConversationMessage] {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return []
        }
        // Iterate by lines via Data so we can avoid String allocations for
        // huge transcripts. Each line is <100KB in practice.
        var messages: [ConversationMessage] = []
        var start = data.startIndex
        let newline = UInt8(ascii: "\n")
        for i in data.indices {
            guard data[i] == newline else { continue }
            if let msg = parseLine(data[start..<i]) { messages.append(msg) }
            start = data.index(after: i)
        }
        // Trailing line without a final \n
        if start < data.endIndex, let msg = parseLine(data[start..<data.endIndex]) {
            messages.append(msg)
        }
        return messages
    }

    private static func parseLine(_ slice: Data) -> ConversationMessage? {
        guard !slice.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: slice) as? [String: Any],
              let roleStr = obj["role"] as? String,
              let message = obj["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return nil }

        var fragments: [String] = []
        for block in content {
            guard (block["type"] as? String) == "text",
                  let text = block["text"] as? String else { continue }
            let cleaned = stripUserQueryTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { fragments.append(cleaned) }
        }
        guard !fragments.isEmpty else { return nil }

        let role: ConversationMessage.Role
        switch roleStr {
        case "user": role = .user
        case "assistant": role = .assistant
        default: role = .other
        }
        return ConversationMessage(role: role, text: fragments.joined(separator: " "))
    }

    private static func stripUserQueryTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<user_query>", with: "")
            .replacingOccurrences(of: "</user_query>", with: "")
    }
}

extension Array where Element == ConversationMessage {
    /// Renders the tail of the conversation as plain prose: "USER: …\n\nASSISTANT: …".
    /// `maxChars` is a hard cap; we drop oldest messages until we fit.
    func renderTail(maxChars: Int) -> String {
        guard !isEmpty else { return "" }
        // Walk backwards, accumulating until the budget would overflow.
        var picked: [ConversationMessage] = []
        var total = 0
        for msg in reversed() {
            let renderedLen = msg.role.rawValue.count + 3 + msg.text.count
            if total + renderedLen > maxChars && !picked.isEmpty { break }
            picked.insert(msg, at: 0)
            total += renderedLen + 2
        }
        return picked.map { "\($0.role.rawValue.uppercased()): \($0.text)" }.joined(separator: "\n\n")
    }
}
