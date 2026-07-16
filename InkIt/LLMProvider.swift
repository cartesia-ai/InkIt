import Foundation

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

    var keyPlaceholder: String {
        switch self {
        case .groq:      return "gsk_…"
        case .gemini:    return "AIza…"
        case .openai:    return "sk-…"
        case .anthropic: return "sk-ant-…"
        }
    }

    var endpoint: URL {
        switch self {
        case .groq:      return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .gemini:    return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .openai:    return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        }
    }

    var isOpenAICompatible: Bool { self != .anthropic }

    var models: [String] {
        switch self {
        case .groq:      return ["openai/gpt-oss-20b"]
        case .gemini:    return ["gemini-2.5-flash-lite"]
        case .openai:    return ["gpt-4.1-nano"]
        case .anthropic: return ["claude-haiku-4-5-20251001"]
        }
    }

    var defaultModel: String { models.first! }

    var rewriteTimeout: TimeInterval {
        switch self {
        case .groq:                       return 1.0
        case .gemini, .openai, .anthropic: return 2.0
        }
    }

    var keyURL: URL {
        switch self {
        case .groq:      return URL(string: "https://console.groq.com/keys")!
        case .gemini:    return URL(string: "https://aistudio.google.com/apikey")!
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }

    var billingURL: URL {
        switch self {
        case .groq:      return URL(string: "https://console.groq.com/settings/billing")!
        case .gemini:    return URL(string: "https://aistudio.google.com/")!
        case .openai:    return URL(string: "https://platform.openai.com/settings/organization/billing")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/billing")!
        }
    }

    var isRecommended: Bool { self == .groq }

    private var validationURL: URL {
        switch self {
        case .groq:      return URL(string: "https://api.groq.com/openai/v1/models")!
        case .gemini:    return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/models")!
        case .openai:    return URL(string: "https://api.openai.com/v1/models")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/models")!
        }
    }

    func validationRequest(key: String) -> URLRequest {
        var req = URLRequest(url: validationURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 8
        if self == .anthropic {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return req
    }
}
