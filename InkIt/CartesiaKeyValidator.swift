import Foundation
import Combine

/// Advisory check that an API key authenticates against Cartesia, used during
/// onboarding so a good key earns a reassuring "verified" before the user
/// reaches the Try-it step.
///
/// It reuses the real STT websocket handshake (`CartesiaStreamingClient`): the
/// server's `connected` event means the key authenticated. It records **no**
/// audio and closes immediately.
///
/// This is purely advisory and never blocks the flow. A wrong key and an
/// offline machine both fail the websocket upgrade identically (the socket
/// never opens), so we can't honestly claim "invalid" — failures surface as
/// "couldn't verify", not an accusation. `Continue` stays enabled on any
/// non-empty key.
@MainActor
final class CartesiaKeyValidator: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case verified
        case couldNotVerify
    }

    @Published private(set) var state: State = .idle

    private var client: CartesiaStreamingClient?
    private var debounce: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    /// The key the current `state` describes — lets the view avoid re-checking
    /// a key it already has a verdict for.
    private var settledKey: String?

    /// Debounced entry point: call on every keystroke. Empty keys reset to idle.
    func keyChanged(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        debounce?.cancel()

        guard !key.isEmpty else {
            teardown()
            state = .idle
            settledKey = nil
            return
        }
        // Already have a verdict for this exact key — don't re-hit the network.
        if key == settledKey, state == .verified || state == .couldNotVerify { return }

        let work = DispatchWorkItem { [weak self] in self?.start(key: key) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func start(key: String) {
        teardown()
        state = .checking

        let client = CartesiaStreamingClient(apiKey: key)
        self.client = client

        client.onConnected = { [weak self] in
            DispatchQueue.main.async { self?.settle(.verified, for: key) }
        }
        client.onError = { [weak self] _ in
            DispatchQueue.main.async { self?.settle(.couldNotVerify, for: key) }
        }
        client.onClosed = { [weak self] _ in
            DispatchQueue.main.async {
                // A close that arrives before `connected` means we never
                // authenticated. (A close after `verified` is just our own
                // teardown and is ignored by the settled-key guard.)
                self?.settle(.couldNotVerify, for: key)
            }
        }
        client.connect()

        let timeout = DispatchWorkItem { [weak self] in self?.settle(.couldNotVerify, for: key) }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    private func settle(_ result: State, for key: String) {
        // Ignore stale callbacks from a superseded check.
        guard client != nil, state == .checking else { return }
        state = result
        settledKey = key
        teardown()
    }

    private func teardown() {
        timeout?.cancel(); timeout = nil
        let c = client
        client = nil
        // Drop callbacks so the imminent close doesn't re-enter settle().
        c?.onConnected = nil; c?.onError = nil; c?.onClosed = nil
        c?.cancel()
    }
}
