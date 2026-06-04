import Foundation
import Combine

/// Advisory check that an API key authenticates against Cartesia, used during
/// onboarding so a good key earns a reassuring "verified" before the user
/// reaches the Try-it step.
///
/// Performs a lightweight, credit-free `GET /voices?limit=1`. Listing voices
/// costs nothing and requires a valid key, so the HTTP status is an honest
/// verdict:
///   - 2xx                  → key authenticated (`verified`)
///   - 401 / 403            → key rejected (`invalidKey`) — we can say so plainly
///   - other / transport err → `couldNotVerify` (most likely offline)
///
/// Distinguishing a rejected key from an offline machine is the reason we use
/// HTTP here rather than the STT websocket handshake, where both failures look
/// identical (the socket simply never opens).
///
/// This is purely advisory and never blocks the flow. `Continue` stays enabled
/// on any non-empty key.
@MainActor
final class CartesiaKeyValidator: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case verified
        case invalidKey
        case couldNotVerify
    }

    @Published private(set) var state: State = .idle

    private let cartesiaVersion = "2026-03-01"
    private var task: URLSessionDataTask?
    private var debounce: DispatchWorkItem?
    /// Bumped on every new check so stale (or cancelled) completions can be
    /// recognised and ignored.
    private var generation = 0
    /// The key the current `state` describes — lets the view avoid re-checking
    /// a key it already has a verdict for.
    private var settledKey: String?

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

        var comps = URLComponents(string: "https://api.cartesia.ai/voices")!
        comps.queryItems = [URLQueryItem(name: "limit", value: "1")]
        guard let url = comps.url else { settle(.couldNotVerify, key: key, gen: gen); return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        req.setValue(cartesiaVersion, forHTTPHeaderField: "Cartesia-Version")
        req.timeoutInterval = 8

        task = URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
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
