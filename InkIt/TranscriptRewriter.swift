import Foundation

/// Pulls identifier-like tokens out of a chunk of arbitrary text. We send
/// these to the LLM as a glossary so it can repair ASR mistakes on proper
/// nouns (e.g. "flash attention" → "FlashAttention", "kvk function" →
/// "kVK_Function").
enum GlossaryExtractor {
    /// Order is preserved: tokens that appeared first in the source text
    /// (roughly: closer to the focused element on screen) come first.
    static func extract(from text: String, limit: Int = 80) -> [String] {
        guard !text.isEmpty else { return [] }

        var seen = Set<String>()
        var result: [String] = []

        text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                 options: [.byWords, .localized]) { substring, _, _, stop in
            guard result.count < limit else {
                stop = true
                return
            }
            guard let raw = substring else { return }
            // Word enumeration sometimes splits on internal punctuation; we
            // also want camelCase whole tokens. The naive word-by-word pass
            // is good enough for v1 — we re-scan on punctuation below.
            for token in tokensInWordCandidate(raw) {
                if seen.insert(token).inserted {
                    result.append(token)
                    if result.count >= limit {
                        stop = true
                        break
                    }
                }
            }
        }

        // Second pass for tokens the word-iterator may have missed
        // (e.g. hyphenated names like "FlashAttention-2", dotted paths
        // like "App.tsx", snake_case straddling punctuation). Bounded by `limit`.
        if result.count < limit {
            let pattern = #"[A-Za-z][A-Za-z0-9]+(?:-[A-Za-z0-9]+)+|[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+|[A-Za-z]+_[A-Za-z0-9_]+|[A-Za-z]+[0-9]+[A-Za-z0-9]*|[a-z]+[A-Z][A-Za-z0-9]*"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = text as NSString
                let range = NSRange(location: 0, length: min(ns.length, 20_000))
                regex.enumerateMatches(in: text, range: range) { match, _, stop in
                    guard let match else { return }
                    let token = ns.substring(with: match.range)
                    if isAcceptable(token), seen.insert(token).inserted {
                        result.append(token)
                        if result.count >= limit { stop.pointee = true }
                    }
                }
            }
        }

        return result
    }

    private static func tokensInWordCandidate(_ raw: String) -> [String] {
        guard isAcceptable(raw) else { return [] }
        return [raw]
    }

    private static func isAcceptable(_ token: String) -> Bool {
        let count = token.count
        guard count >= 3, count <= 40 else { return false }

        var hasUpper = false
        var hasLower = false
        var hasDigit = false
        var hasUnderscore = false
        var hasDot = false
        var hasHyphen = false
        var hasLetter = false
        for ch in token.unicodeScalars {
            if CharacterSet.uppercaseLetters.contains(ch) { hasUpper = true; hasLetter = true }
            else if CharacterSet.lowercaseLetters.contains(ch) { hasLower = true; hasLetter = true }
            else if CharacterSet.decimalDigits.contains(ch) { hasDigit = true }
            else if ch == "_" { hasUnderscore = true }
            else if ch == "." { hasDot = true }
            else if ch == "-" { hasHyphen = true }
            else { return false }
        }
        guard hasLetter else { return false }

        // Hyphenated identifier (FlashAttention-2, gpt-4, flash-attn)
        if hasHyphen && (hasUpper || hasDigit) { return true }
        // camelCase / PascalCase
        if hasUpper && hasLower { return true }
        // snake_case / SCREAMING_SNAKE
        if hasUnderscore && (hasUpper || hasLower) { return true }
        // letter+digit mix (Mamba2, gpt4, H100)
        if hasDigit && (hasUpper || hasLower) && count >= 3 { return true }
        // dotted path (App.tsx)
        if hasDot && (hasUpper || hasLower) { return true }
        // All-caps acronym, length ≥ 3 (HTML, GPU, LLM)
        if hasUpper && !hasLower && !hasDigit && !hasUnderscore && !hasDot && !hasHyphen && count >= 3 && count <= 8 {
            return true
        }
        return false
    }
}

/// Calls a Claude model to repair an ASR transcript using prose context from
/// whatever the user was just reading. Returns `nil` on any failure (network,
/// timeout, parse error, sanity-check rejection) — the caller is expected to
/// fall back to the raw transcript.
final class TranscriptRewriter {
    private let apiKey: String
    private let session: URLSession
    // Sonnet 4.6 reasons about the conversation context well enough to fix
    // technical terms even when they aren't lexically present, while staying
    // sub-2s on the prompt sizes we send.
    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.5
        config.timeoutIntervalForResource = 3.5
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func rewrite(transcript: String, context: String, timeout: TimeInterval = 3.5) async -> String? {
        guard !apiKey.isEmpty, !transcript.isEmpty, !context.isEmpty else { return nil }

        DebugLog.info("Rewriter context: \(context.count) chars")
        DebugLog.info("Rewriter raw transcript: \(transcript)")

        let system = """
        You repair speech-to-text transcripts dictated by a software engineer mid-conversation with an AI coding assistant.

        Below is the recent transcript of that assistant conversation — what the user was just reading and thinking about when they started dictating. Use it to understand the technical subject they are working on.

        CONVERSATION CONTEXT:
        ---
        \(context)
        ---

        Your task: rewrite the user's dictated transcript so it reads as the engineer almost certainly intended.

        Use the conversation context to infer:
        - Which libraries, frameworks, models, file paths, identifiers, and proper nouns are being discussed.
        - Correct spelling, capitalization, hyphenation, and word-joining of those terms (e.g. "flash attention" → "FlashAttention", "vllm" / "BLM" / "v lol m" → "vLLM", "page attention" → "PagedAttention", "kvk function" → "kVK_Function", "gpt four" → "GPT-4").
        - Likely homophones and ASR slips that misrepresent technical content.

        Beyond explicit terms in the context, use general technical knowledge to recognize and fix terms the engineer is likely referring to even when not literally in the context (e.g. common library names, hardware terms, Python APIs).

        Rules:
        - Preserve the user's voice, sentence structure, contractions, hesitations, and intent. Do NOT paraphrase, summarize, expand, or add new content.
        - Only fix when you are confident. If a word might be a generic English word, leave it alone.
        - Don't invent punctuation that wasn't there, with one exception: you may join multi-word ASR splits into a single canonical term (e.g. "kvk function" → "kVK_Function"), and you may add a missing apostrophe/hyphen that's part of a proper name.
        - Keep length roughly equal to the input. If your output is substantially longer than the transcript, you've over-corrected — pull back.

        Output ONLY the corrected transcript on a single segment. No preamble, no quotes, no notes, no markdown.
        """

        let estimatedInputTokens = max(48, transcript.count / 3)
        let maxTokens = min(1500, estimatedInputTokens * 3 + 80)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": 0,
            "system": system,
            "messages": [
                ["role": "user", "content": transcript]
            ]
        ]
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
            let (data, response) = try await session.data(for: req)
            let elapsed = String(format: "%.3fs", Date().timeIntervalSince(started))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let bodyStr = String(data: data, encoding: .utf8)?.prefix(400) ?? "<non-utf8>"
                DebugLog.error("Rewriter HTTP error: \(String(describing: response)) body=\(bodyStr) elapsed=\(elapsed)")
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]] else {
                DebugLog.error("Rewriter response parse failed elapsed=\(elapsed)")
                return nil
            }
            let text = content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()

            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.info("Rewriter response (\(elapsed)): \(cleaned)")
            guard !cleaned.isEmpty else { return nil }
            // Sanity check: a corrected transcript shouldn't balloon beyond
            // ~2.5× the original length. The freer prompt may legitimately
            // add a few characters when joining words (e.g. "flash attention"
            // → "FlashAttention" actually shrinks), so the bound is generous.
            // If we exceed it, the model went off-script — fall back.
            if cleaned.count > max(120, Int(Double(transcript.count) * 2.5) + 40) {
                DebugLog.error("Rewriter response rejected by length sanity check (\(cleaned.count) chars vs raw \(transcript.count))")
                return nil
            }
            return cleaned
        } catch {
            let elapsed = String(format: "%.3fs", Date().timeIntervalSince(started))
            DebugLog.error("Rewriter error: \(error.localizedDescription) elapsed=\(elapsed)")
            return nil
        }
    }
}
