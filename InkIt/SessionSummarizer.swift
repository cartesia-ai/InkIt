import Foundation

/// Calls Anthropic Haiku to compress a long agent conversation into a
/// short summary suitable for use as a cache-control'd prefix on the
/// rewriter call. Persists the result via `SessionSummaryStore`.
///
/// Blocking by design — the caller awaits this on the dictation hot path
/// when the cached summary is stale. Haiku is ~500ms.
enum SessionSummarizer {
    private static let model = "claude-haiku-4-5-20251001"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let timeout: TimeInterval = 5.0

    /// Returns the freshest summary for the session — either the cached
    /// one (when it's still considered valid) or a newly generated one.
    /// Returns nil if there's no usable summary (short conversation, API
    /// failure, etc.); caller should treat that as "no summary available".
    static func ensureFresh(uuid: String,
                            transcriptPath: String,
                            messages: [ConversationMessage],
                            apiKey: String) async -> SessionSummary? {
        if !SessionSummaryStore.needsRefresh(uuid: uuid, messageCount: messages.count) {
            return SessionSummaryStore.load(uuid: uuid)
        }
        guard let summary = await regenerate(uuid: uuid,
                                             transcriptPath: transcriptPath,
                                             messages: messages,
                                             apiKey: apiKey) else {
            // Haiku call failed; fall back to stale-but-existing summary if any.
            return SessionSummaryStore.load(uuid: uuid)
        }
        return summary
    }

    private static func regenerate(uuid: String,
                                   transcriptPath: String,
                                   messages: [ConversationMessage],
                                   apiKey: String) async -> SessionSummary? {
        guard !apiKey.isEmpty, !messages.isEmpty else { return nil }

        // Render the whole conversation for Haiku, capped at a generous
        // budget. Haiku 4.5 is plenty for ~30k char input.
        let conversation = messages.renderTail(maxChars: 30_000)
        DebugLog.info("SessionSummarizer: regenerating uuid=\(uuid) messages=\(messages.count) input=\(conversation.count) chars")

        let system = """
        You produce summaries of technical conversations for another LLM to use as context when repairing speech-to-text transcripts.

        Hard requirements:
        - Preserve EXACT spelling and casing of every identifier, library name, framework, file path, model name, hardware term, function name, and proper noun mentioned in the conversation.
        - The final 1-2 sentences must describe the current subject under discussion (most recent topic).
        - Be terse. 150-300 words. No prose fluff, no preamble, no quoting.

        Output the summary text only.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 600,
            "temperature": 0,
            "system": system,
            "messages": [
                ["role": "user", "content": conversation]
            ]
        ]
        if let json = DebugLog.prettyJSONString(body) {
            DebugLog.infoBlock(
                title: "SessionSummarizer Anthropic request payload uuid=\(uuid)",
                text: DebugLog.redacted(json, secrets: [apiKey])
            )
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = payload
        req.timeoutInterval = timeout

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let elapsed = String(format: "%.3fs", Date().timeIntervalSince(started))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)?.prefix(300) ?? "<non-utf8>"
                DebugLog.error("SessionSummarizer HTTP error: \(String(describing: response)) body=\(body) elapsed=\(elapsed)")
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]] else {
                DebugLog.error("SessionSummarizer parse failed elapsed=\(elapsed)")
                return nil
            }
            let text = content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            DebugLog.info("SessionSummarizer: \(text.count)-char summary generated in \(elapsed)")

            let summary = SessionSummary(
                sessionUUID: uuid,
                summary: text,
                summarizedUpToMessageCount: messages.count,
                summaryLastUpdated: Date(),
                cursorTranscriptPath: transcriptPath
            )
            SessionSummaryStore.save(summary)
            return summary
        } catch {
            let elapsed = String(format: "%.3fs", Date().timeIntervalSince(started))
            DebugLog.error("SessionSummarizer error: \(error.localizedDescription) elapsed=\(elapsed)")
            return nil
        }
    }
}
