import Foundation

/// An LLM provider for the transcript rewrite ("Polish transcripts").
///
/// All providers except Anthropic speak the OpenAI-compatible
/// `/chat/completions` shape, so they share one request path that only varies
/// by `endpoint` + bearer key + model. Anthropic uses its native Messages API.
enum LLMProvider: String, CaseIterable, Identifiable, Hashable {
    case groq
    case gemini
    case openai
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    /// Placeholder hint for the Settings key field — the provider's key prefix
    /// so it's obvious you've pasted the right credential. Shown only while the
    /// field is empty.
    var keyPlaceholder: String {
        switch self {
        case .groq:      return "gsk_…"
        case .gemini:    return "AIza…"
        case .openai:    return "sk-…"
        case .anthropic: return "sk-ant-…"
        }
    }

    /// Chat endpoint. Anthropic uses its native Messages API; the rest are
    /// OpenAI-compatible `/chat/completions`.
    var endpoint: URL {
        switch self {
        case .groq:      return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .gemini:    return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .openai:    return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        }
    }

    var isOpenAICompatible: Bool { self != .anthropic }

    /// Curated, latency-friendly models for the rewrite task (filler removal,
    /// punctuation, proper-noun repair). Ordered with the recommended default
    /// first. Benchmarked 2026-05: Groq Llama 3.3 70B ≈ 280ms, Gemini Flash-Lite
    /// ≈ 510ms — both fast enough for the push-to-talk hot path.
    var models: [String] {
        switch self {
        case .groq:      return ["llama-3.3-70b-versatile"]
        case .gemini:    return ["gemini-2.5-flash-lite"]
        case .openai:    return ["gpt-4.1-nano"]
        case .anthropic: return ["claude-haiku-4-5-20251001"]
        }
    }

    var defaultModel: String { models.first! }

    /// Where the user obtains an API key.
    var keyURL: URL {
        switch self {
        case .groq:      return URL(string: "https://console.groq.com/keys")!
        case .gemini:    return URL(string: "https://aistudio.google.com/apikey")!
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }
}

/// Validates a Groq key via a credit-free `GET /openai/v1/models`, used by the
/// optional onboarding "Polish" step so a good key earns a reassuring
/// "verified" before the user finishes setup.
///
/// Groq-only by design: onboarding pins Groq as the recommended provider and
/// hides the picker, so a focused subclass is less code than a per-provider
/// one. Provider switching lives in Settings. See `APIKeyValidator` for the
/// shared debounce/verdict machinery. Purely advisory — never blocks.
@MainActor
final class GroqKeyValidator: APIKeyValidator {
    init() {
        super.init(makeRequest: { key in
            var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
            req.httpMethod = "GET"
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 8
            return req
        })
    }
}
