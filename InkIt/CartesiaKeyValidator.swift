import Foundation
import Combine

@MainActor
class APIKeyValidator: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case verified
        case invalidKey
        case couldNotVerify
    }

    @Published private(set) var state: State = .idle

    private var makeRequest: (String) -> URLRequest

    func updateRequest(_ make: @escaping (String) -> URLRequest) {
        makeRequest = make
    }

    private var task: URLSessionDataTask?
    private var debounce: DispatchWorkItem?
    private var generation = 0
    private var settledKey: String?

    init(makeRequest: @escaping (String) -> URLRequest) {
        self.makeRequest = makeRequest
    }

    func keyChanged(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        debounce?.cancel()

        guard !key.isEmpty else {
            cancelInFlight()
            state = .idle
            settledKey = nil
            return
        }
        if key == settledKey, state != .checking { return }

        let work = DispatchWorkItem { [weak self] in self?.start(key: key) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func start(key: String) {
        cancelInFlight()
        generation &+= 1
        let gen = generation
        state = .checking

        task = URLSession.shared.dataTask(with: makeRequest(key)) { [weak self] _, response, error in
            let verdict: State
            if error != nil {
                verdict = .couldNotVerify
            } else {
                switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
                case 200...299:      verdict = .verified
                case 400, 401, 403:  verdict = .invalidKey
                default:             verdict = .couldNotVerify
                }
            }
            DispatchQueue.main.async { self?.settle(verdict, key: key, gen: gen) }
        }
        task?.resume()
    }

    private func settle(_ result: State, key: String, gen: Int) {
        guard gen == generation, state == .checking else { return }
        state = result
        settledKey = key
        task = nil
    }

    private func cancelInFlight() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class CartesiaKeyValidator: APIKeyValidator {
    init() {
        super.init(makeRequest: { key in
            var comps = URLComponents(string: "https://api.cartesia.ai/voices")!
            comps.queryItems = [URLQueryItem(name: "limit", value: "1")]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "GET"
            req.setValue(key, forHTTPHeaderField: "X-API-Key")
            req.setValue("2026-03-01", forHTTPHeaderField: "Cartesia-Version")
            req.timeoutInterval = 8
            return req
        })
    }
}

@MainActor
final class LLMKeyValidator: APIKeyValidator {
    private(set) var provider: LLMProvider

    init(provider: LLMProvider) {
        self.provider = provider
        super.init(makeRequest: { key in provider.validationRequest(key: key) })
    }

    func setProvider(_ provider: LLMProvider) {
        self.provider = provider
        updateRequest { key in provider.validationRequest(key: key) }
    }
}
