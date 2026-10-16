import Foundation

struct DictationDiagnostics: Codable, Equatable {
    var requestID: String?
    var model: String
    var rawText: String
    var keyterms: [String]
    var micName: String?
    var micTransport: String?
    var micSampleRate: Int?
    var startedAt: Date?
    var clipMs: Int?
}

enum IssueCategory: String, CaseIterable, Codable, Identifiable {
    case wrongWords = "wrong_words"
    case missingWords = "missing_words"
    case extraWords = "extra_words"
    case namesOrTerms = "names_or_terms"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongWords: return "Wrong words"
        case .missingWords: return "Missing words"
        case .extraWords: return "Extra words"
        case .namesOrTerms: return "Names or terms"
        case .other: return "Other"
        }
    }
}

struct IssueReportPayload: Encodable {
    let dictatedAt: String
    let requestID: String?
    let model: String
    let rawText: String
    let polishedText: String?
    let userFeedback: String?
    let categories: [String]
    let keyterms: [String]
    let appBundleID: String?
    let micName: String?
    let micTransport: String?
    let micSampleRate: Int?
    let macModel: String
    let osVersion: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case dictatedAt = "dictated_at"
        case requestID = "request_id"
        case model
        case rawText = "raw_text"
        case polishedText = "polished_text"
        case userFeedback = "user_feedback"
        case categories
        case keyterms
        case appBundleID = "app_bundle_id"
        case micName = "mic_name"
        case micTransport = "mic_transport"
        case micSampleRate = "mic_sample_rate"
        case macModel = "mac_model"
        case osVersion = "os_version"
        case appVersion = "app_version"
    }

    init(entry: TranscriptHistoryStore.Entry, categories: Set<IssueCategory>, editedText: String) {
        let diagnostics = entry.diagnostics
        let raw = diagnostics?.rawText ?? entry.original ?? entry.text
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        dictatedAt = ISO8601DateFormatter().string(from: diagnostics?.startedAt ?? entry.timestamp)
        requestID = diagnostics?.requestID
        model = diagnostics?.model ?? "ink-2"
        rawText = raw
        polishedText = entry.polish == .polished ? entry.text : nil
        userFeedback = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.feedbackLimit))
        self.categories = IssueCategory.allCases.filter(categories.contains).map(\.rawValue)
        keyterms = diagnostics?.keyterms ?? []
        appBundleID = entry.appBundleID
        micName = diagnostics?.micName
        micTransport = diagnostics?.micTransport
        micSampleRate = diagnostics?.micSampleRate
        macModel = DeviceInfo.macModel
        osVersion = DeviceInfo.osVersion
        appVersion = DeviceInfo.appVersion
    }

    static let feedbackLimit = 2000

    func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }
}

enum DeviceInfo {
    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func cleanMicName(_ name: String?) -> String? {
        guard let name else { return nil }
        for apostrophe in ["'s ", "’s "] {
            if let range = name.range(of: apostrophe) {
                let rest = String(name[range.upperBound...])
                if !rest.isEmpty { return rest }
            }
        }
        return name
    }
}

enum IssueReportError: Error {
    case tooLarge
    case rejected
    case rateLimited
    case network
}

protocol IssueReportSending {
    func send(_ payload: IssueReportPayload, audio: URL) async throws
}

final class HTTPIssueReportClient: NSObject, IssueReportSending, URLSessionTaskDelegate {
    static let endpoint = URL(string: "https://inkit-reports.preview.cartesia.ai/api/reports")!

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func send(_ payload: IssueReportPayload, audio: URL) async throws {
        let boundary = "inkit-\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("cartesia-inkit/\(DeviceInfo.appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("report/1", forHTTPHeaderField: "X-InkIt-Client")

        var body = Data()
        func part(_ name: String, filename: String?, type: String, data: Data) {
            body.append(Data("--\(boundary)\r\n".utf8))
            let file = filename.map { "; filename=\"\($0)\"" } ?? ""
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(file)\r\n".utf8))
            body.append(Data("Content-Type: \(type)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        part("report", filename: nil, type: "application/json", data: payload.json())
        part("audio", filename: "audio.flac", type: "audio/flac", data: try Data(contentsOf: audio))
        body.append(Data("--\(boundary)--\r\n".utf8))

        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, from: body)
        } catch {
            throw IssueReportError.network
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw IssueReportError.network }
        switch status {
        case 200, 201: return
        case 413: throw IssueReportError.tooLarge
        case 429: throw IssueReportError.rateLimited
        case 500...599: throw IssueReportError.network
        default: throw IssueReportError.rejected
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

enum IssueReporter {
    static let client: IssueReportSending = HTTPIssueReportClient()

    static func submit(entry: TranscriptHistoryStore.Entry,
                       categories: Set<IssueCategory>,
                       editedText: String) async throws {
        let payload = IssueReportPayload(entry: entry, categories: categories, editedText: editedText)
        let flac = try await Task.detached(priority: .userInitiated) {
            try ClipStore.encodeFLAC(for: entry.id)
        }.value
        defer { try? FileManager.default.removeItem(at: flac) }
        let size = (try? FileManager.default.attributesOfItem(atPath: flac.path)[.size] as? Int) ?? 0
        guard size <= ClipStore.uploadLimitBytes else { throw IssueReportError.tooLarge }
        try await client.send(payload, audio: flac)
    }
}
