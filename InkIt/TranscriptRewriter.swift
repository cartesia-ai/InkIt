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

/// Calls a Claude model to repair an ASR transcript against a glossary.
/// Returns `nil` on any failure (network, timeout, parse error, sanity-check
/// rejection) — the caller is expected to fall back to the raw transcript.
final class TranscriptRewriter {
    private let apiKey: String
    private let session: URLSession
    // Sonnet 4.6 handles two-words → one-CamelCase merges and casing edits
    // (e.g. "paged attention" → "PagedAttention", "vllm" → "vLLM") far more
    // reliably than Haiku at this prompt length. Latency is ~700–1100ms,
    // which still fits inside the dictation feel.
    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 2.5
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func rewrite(transcript: String, glossary: [String], timeout: TimeInterval = 2.5) async -> String? {
        guard !apiKey.isEmpty, !glossary.isEmpty, !transcript.isEmpty else { return nil }

        let glossaryString = glossary.joined(separator: ", ")
        DebugLog.info("Rewriter glossary (\(glossary.count) terms): \(glossaryString)")
        DebugLog.info("Rewriter raw transcript: \(transcript)")

        let system = """
        You repair speech-to-text transcripts using a glossary of terms the user was just looking at on screen.

        TERMS: \(glossaryString)

        Rules:
        1. Substitute glossary matches. When words in the transcript clearly correspond to a term in TERMS — by phonetic similarity, spelling, or spacing — replace them with the term EXACTLY as written in TERMS, including capitalization, hyphens, and word joining. Multi-word phrases in the transcript may collapse to a single CamelCase or hyphenated term.
        2. Do not add, remove, or change anything outside of a glossary substitution. Punctuation, ordinary word casing, contractions, and sentence structure stay exactly as the transcript wrote them.
        3. Do not insert periods, capital letters, or hyphens that the transcript didn't already have, unless they come from an exact glossary term.
        4. If you are not confident that a glossary term applies, leave the original wording alone. Never invent substitutions for terms not listed in TERMS.

        Examples:
        - TERMS: FlashAttention, PagedAttention, vLLM
          transcript: "use flash attention with paged attention v l l m on long sequences"
          output:     "use FlashAttention with PagedAttention vLLM on long sequences"
        - TERMS: kVK_Function, kVK_Space
          transcript: "bind kvk function instead of kvk space"
          output:     "bind kVK_Function instead of kVK_Space"
        - TERMS: GPT-4, Claude
          transcript: "ask gpt four to compare with claude"
          output:     "ask GPT-4 to compare with Claude"

        Output only the corrected transcript. No preamble, no quotes, no notes.
        """

        let estimatedInputTokens = max(32, transcript.count / 3)
        let maxTokens = min(1024, estimatedInputTokens * 2 + 50)

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
            // ~2× the original length. If it does, the model probably went
            // off-script — fall back.
            if cleaned.count > max(80, transcript.count * 2 + 20) {
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
