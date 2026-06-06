import Foundation
import Combine

/// Advisory check that an API key authenticates against a service, used during
/// onboarding so a good key earns a reassuring "verified" before the user
/// proceeds.
///
/// The shared machinery lives here: a 0.6s keystroke debounce, a generation
/// counter so stale (or cancelled) completions are ignored, and `settledKey`
/// caching so a key that already has a verdict isn't re-hit. Subclasses supply
/// only the credit-free probe request via `makeRequest`. The HTTP status is the
/// verdict:
///   - 2xx                   → key authenticated (`verified`)
///   - 401 / 403             → key rejected (`invalidKey`) — we can say so plainly
///   - other / transport err → `couldNotVerify` (most likely offline)
///
/// This is purely advisory and never blocks the flow.
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

    /// Builds the credit-free probe request for a given key. Should target an
    /// endpoint that needs auth but costs nothing (e.g. a list call). Settable
    /// so a provider-aware validator can re-point it when the provider changes.
    private var makeRequest: (String) -> URLRequest

    /// Swap the probe builder (e.g. after the user picks a different provider).
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

    /// Debounced entry point: call on every keystroke. Empty keys reset to idle.
    func keyChanged(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        debounce?.cancel()

        guard !key.isEmpty else {
            cancelInFlight()
            state = .idle
            settledKey = nil
            return
        }
        // Already have a verdict for this exact key — don't re-hit the network.
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
                case 200...299: verdict = .verified
                case 401, 403:  verdict = .invalidKey
                default:        verdict = .couldNotVerify
                }
            }
            DispatchQueue.main.async { self?.settle(verdict, key: key, gen: gen) }
        }
        task?.resume()
    }

    private func settle(_ result: State, key: String, gen: Int) {
        // Ignore stale callbacks from a superseded (or cancelled) check.
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

/// Validates a Cartesia key via a credit-free `GET /voices?limit=1`: listing
/// voices costs nothing and requires a valid key. Using HTTP (rather than the
/// STT websocket handshake, where a rejected key and an offline machine look
/// identical) lets us tell those two failures apart.
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

/// Validates a rewrite-provider key against whichever provider is currently
/// selected, re-pointing its probe when the user switches providers in the
/// Polish settings pane. Advisory, like its base. See `LLMProvider.validationRequest`.
@MainActor
final class LLMKeyValidator: APIKeyValidator {
    private(set) var provider: LLMProvider

    init(provider: LLMProvider) {
        self.provider = provider
        super.init(makeRequest: { key in provider.validationRequest(key: key) })
    }

    /// Point the validator at a new provider (clears no state; caller should
    /// re-run `keyChanged` with that provider's key).
    func setProvider(_ provider: LLMProvider) {
        self.provider = provider
        updateRequest { key in provider.validationRequest(key: key) }
    }
}
