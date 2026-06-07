import Foundation

/// Minimal client for Cartesia STT streaming over WebSocket (Ink 2).
///
/// Protocol (per docs.cartesia.ai/api-reference/stt/turns/websocket):
///   - URL:    wss://api.cartesia.ai/stt/turns/websocket
///   - Auth:   X-API-Key header
///   - Params: model=ink-2, encoding=pcm_s16le, sample_rate=16000, cartesia_version=2026-03-01
///   - Audio:  binary frames, raw PCM matching encoding/sample_rate
///   - Close:  client sends {"type":"close"}
///
/// Server events:
///   connected, turn.start, turn.update (cumulative transcript),
///   turn.eager_end, turn.resume, turn.end (turn final), error
///
/// All emitted transcripts are already "final" words; partials are not exposed.
/// We accumulate completed turns and append the latest in-flight `turn.update`
/// to produce the full press-to-talk transcript.
/// Why an STT session failed, classified from Cartesia's error event
/// (`status_code` + `error_code`, per docs.cartesia.ai/use-the-api/api-conventions)
/// or a transport-level URLError. Drives the short notch message and the
/// persistent Home "Transcription is paused" card.
enum STTFailure: Equatable {
    case offline        // no network / can't reach host
    case serverError    // 5xx, timeout, or unreachable server
    case rateLimited    // 429 / concurrency_limited
    case outOfCredits   // 402 / quota_exceeded / plan_upgrade_required
    case invalidKey     // 401 / 403
    case unknown        // 400 (bad input) or anything unclassified

    /// Short, glanceable copy for the notch island. Plain language, no codes.
    var notchMessage: String {
        switch self {
        case .offline:      return "No internet"
        case .serverError:  return "Server error"
        case .rateLimited:  return "Too many requests"
        case .outOfCredits: return "Out of credits"
        case .invalidKey:   return "Invalid API key"
        case .unknown:      return "Couldn't transcribe"
        }
    }

    /// Classify from a Cartesia error event. `error_code` is the most reliable
    /// signal (credits come back as quota_exceeded / plan_upgrade_required), then
    /// the HTTP `status_code`.
    static func classify(statusCode: Int?, errorCode: String?) -> STTFailure {
        switch errorCode {
        case "quota_exceeded", "plan_upgrade_required": return .outOfCredits
        case "concurrency_limited":                     return .rateLimited
        default: break
        }
        switch statusCode {
        case 401, 403:                    return .invalidKey
        case 402:                         return .outOfCredits
        case 429:                         return .rateLimited
        case .some(let s) where s >= 500: return .serverError
        default:                          return .unknown
        }
    }

    /// Classify a transport error: prefer the HTTP status on a failed WebSocket
    /// upgrade, else map the URLError (offline vs. server/timeout).
    static func classify(transportError error: Error, response: URLResponse?) -> STTFailure {
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            return classify(statusCode: http.statusCode, errorCode: nil)
        }
        guard let urlError = error as? URLError else { return .unknown }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .serverError
        default:
            return .unknown
        }
    }
}

final class CartesiaStreamingClient: NSObject, URLSessionWebSocketDelegate {
    var onTranscriptUpdate: ((String) -> Void)?
    var onError: ((STTFailure) -> Void)?
    var onClosed: ((String) -> Void)?

    private let apiKey: String
    private let model = "ink-2"
    private let cartesiaVersion = "2026-03-01"
    private let sampleRate = 16_000

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var hasClosed = false
    private var completedTurns: [String] = []
    private var currentTurn: String = ""
    private var closeRequestedAt: Date?

    // Audio captured before the server's `connected` event is held here and
    // flushed in order once the socket is ready. URLSession will technically
    // queue early `send()` calls, but Cartesia may discard binary frames
    // received before it has fully initialized the session. Buffering on our
    // side guarantees no leading audio is dropped.
    private var isConnected = false
    private var pendingAudio: [Data] = []
    private var pendingClose = false
    // Set once we've requested close. The server then flushes buffered audio
    // into a final `turn.end` (carrying the last word) before disconnecting, so
    // we complete on that event rather than racing the socket close.
    private var awaitingClose = false
    private let stateLock = NSLock()

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect() {
        var comps = URLComponents(string: "wss://api.cartesia.ai/stt/turns/websocket")!
        comps.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "cartesia_version", value: cartesiaVersion)
        ]
        guard let url = comps.url else {
            onError?(.unknown)
            return
        }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue(cartesiaVersion, forHTTPHeaderField: "Cartesia-Version")
        task = session.webSocketTask(with: req)
        task?.resume()
        receive()
    }

    func sendAudio(_ data: Data) {
        guard let task, !hasClosed else { return }
        stateLock.lock()
        if !isConnected {
            pendingAudio.append(data)
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        task.send(.data(data)) { [weak self] err in
            if let err { self?.onError?(STTFailure.classify(transportError: err, response: self?.task?.response)) }
        }
    }

    /// Request close. Per the STT docs, the server processes all buffered audio
    /// into events — emitting a final `turn.end` with the last word — and then
    /// disconnects. We therefore complete on that final `turn.end` (see
    /// `handleMessage`) or on the socket close, whichever lands first; the timer
    /// below is only a fallback for a socket that never finishes.
    func finalizeAndClose() {
        guard let task, !hasClosed else { onClosed?(joinedTranscript()); return }
        stateLock.lock()
        let connected = isConnected
        if !connected { pendingClose = true }
        awaitingClose = true
        // If nothing has been transcribed yet, there's no trailing word to
        // protect — the long flush window only exists to catch the final
        // `turn.end`. Collapse fast in that case so silent presses don't leave
        // the "Done" pill hanging for the full grace period.
        let hasContent = !completedTurns.isEmpty || !currentTurn.isEmpty
        stateLock.unlock()
        let fallback: TimeInterval = hasContent ? 3.0 : 2.0
        if !connected {
            // Defer the close until buffered audio has been flushed in
            // `handleConnected()`. The fallback timer below still fires.
            scheduleCloseFallback(after: fallback)
            return
        }
        closeRequestedAt = Date()
        task.send(.string(#"{"type":"close"}"#)) { _ in }
        scheduleCloseFallback(after: fallback)
    }

    /// Fallback only: guarantees we don't hang if the server never emits a final
    /// `turn.end` or closes the socket. The happy path completes earlier, on the
    /// final `turn.end` or `didCloseWith`. The delay is shortened when no
    /// transcript content was received, since there's no last word to wait for.
    private func scheduleCloseFallback(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.hasClosed else { return }
            self.finishClose(reason: .graceTimerExpired)
        }
    }

    func cancel() { finishClose(reason: .externalCancel) }

    /// `reportClosed: false` finishes the session WITHOUT firing `onClosed` — used
    /// on error paths, which already reported via `onError`. Otherwise the error's
    /// close would also deliver an (empty) transcript to `onClosed`, and the
    /// coordinator would reset its state to `.idle`, wiping the error notice.
    private func finishClose(reason: CloseReason, reportClosed: Bool = true) {
        // Atomic so the final `turn.end` and the socket close racing to finish
        // can't both report `onClosed`.
        stateLock.lock()
        if hasClosed { stateLock.unlock(); return }
        hasClosed = true
        stateLock.unlock()
        let elapsed = closeRequestedAt.map { Date().timeIntervalSince($0) }
        SessionMetrics.record(reason: reason, elapsedAfterCloseSent: elapsed)
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if reportClosed { onClosed?(joinedTranscript()) }
    }

    // MARK: - Receive loop

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                if !self.hasClosed {
                    self.onError?(STTFailure.classify(transportError: error, response: self.task?.response))
                    self.finishClose(reason: .receiveFailed, reportClosed: false)
                }
            case .success(let message):
                switch message {
                case .string(let text): self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleMessage(text) }
                @unknown default: break
                }
                if !self.hasClosed { self.receive() }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "turn.update", "turn.eager_end":
            // Cumulative transcript for the in-progress turn.
            stateLock.lock()
            currentTurn = (json["transcript"] as? String) ?? currentTurn
            stateLock.unlock()
            onTranscriptUpdate?(joinedTranscript())

        case "turn.end":
            stateLock.lock()
            let finalText = (json["transcript"] as? String) ?? currentTurn
            if !finalText.isEmpty { completedTurns.append(finalText) }
            currentTurn = ""
            let closing = awaitingClose
            stateLock.unlock()
            onTranscriptUpdate?(joinedTranscript())
            // Once we've requested close, this is the flushed final turn carrying
            // the last word. Complete here so we snapshot the full transcript
            // instead of racing the socket close (which may report before this
            // event is processed).
            if closing { finishClose(reason: .finalTurnReceived) }

        case "turn.resume":
            // User continued a previously "eagerly ended" turn; keep current state.
            break

        case "connected":
            handleConnected()

        case "turn.start":
            break

        case "error":
            // Cartesia error events carry a required `status_code` and an optional
            // `error_code` (e.g. quota_exceeded, concurrency_limited) — classify
            // off those rather than the human-readable message.
            let status = json["status_code"] as? Int
            let code = json["error_code"] as? String
            let msg = (json["message"] as? String) ?? (json["title"] as? String) ?? "Cartesia error"
            NSLog("[InkIt] STT error event: status=\(status.map(String.init) ?? "nil") code=\(code ?? "nil") msg=\(msg)")
            onError?(STTFailure.classify(statusCode: status, errorCode: code))
            finishClose(reason: .serverError, reportClosed: false)

        default:
            break
        }
    }

    /// Called when the server emits `connected`. Flushes any audio captured
    /// during the handshake, then (if the user already released the hotkey)
    /// sends the deferred close. Order matters: audio must be queued onto the
    /// task BEFORE the close frame, and BEFORE we unset `isConnected`'s gate
    /// so concurrent `sendAudio` callers don't race ahead of the buffer.
    private func handleConnected() {
        guard let task else { return }
        stateLock.lock()
        let buffered = pendingAudio
        pendingAudio.removeAll()
        let shouldClose = pendingClose
        pendingClose = false
        for chunk in buffered {
            task.send(.data(chunk)) { [weak self] err in
                if let err { self?.onError?(STTFailure.classify(transportError: err, response: self?.task?.response)) }
            }
        }
        isConnected = true
        stateLock.unlock()
        if shouldClose {
            closeRequestedAt = Date()
            task.send(.string(#"{"type":"close"}"#)) { _ in }
        }
    }

    private func joinedTranscript() -> String {
        stateLock.lock()
        var parts = completedTurns
        if !currentTurn.isEmpty { parts.append(currentTurn) }
        stateLock.unlock()
        return parts.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        finishClose(reason: .serverClosed)
    }

    /// A rejected WebSocket *upgrade* — invalid/expired key, over credit limit,
    /// rate limited — is delivered here, not through `receive()`. Without this
    /// the failure is swallowed and the session ends silently (no notch error).
    /// The HTTP status on `task.response` carries the cause; fall back to the
    /// URLError. Guarded so the happy-path completion and `receive()`'s own
    /// failure handling don't double-report.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !hasClosed else { return }
        if let error {
            onError?(STTFailure.classify(transportError: error, response: task.response))
            finishClose(reason: .receiveFailed, reportClosed: false)
        } else if let http = task.response as? HTTPURLResponse, http.statusCode >= 400 {
            onError?(STTFailure.classify(statusCode: http.statusCode, errorCode: nil))
            finishClose(reason: .receiveFailed, reportClosed: false)
        }
    }
}

// MARK: - Close-path metrics

enum CloseReason: String, Codable {
    case finalTurnReceived    // final turn.end after close (happy path: full transcript captured)
    case serverClosed         // server closed the socket before a post-close turn.end (e.g. nothing to flush)
    case graceTimerExpired    // safety timer fired before the server finished
    case serverError          // server sent {"type":"error"}
    case receiveFailed        // receive loop errored
    case externalCancel       // cancel() called from outside (e.g. audio start failure, app error)
}

struct CloseMetric: Codable {
    let timestamp: Date
    let reason: CloseReason
    /// Seconds between sending {"type":"close"} and the socket finishing.
    /// nil if close was never requested (e.g. externalCancel before finalize).
    let elapsedAfterCloseSent: TimeInterval?
}

enum SessionMetrics {
    private static let key = "CartesiaCloseMetrics"
    private static let maxEntries = 500

    static func record(reason: CloseReason, elapsedAfterCloseSent elapsed: TimeInterval?) {
        let metric = CloseMetric(timestamp: Date(), reason: reason, elapsedAfterCloseSent: elapsed)
        var all = load()
        all.append(metric)
        if all.count > maxEntries { all.removeFirst(all.count - maxEntries) }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
        let elapsedStr = elapsed.map { String(format: "%.3fs", $0) } ?? "n/a"
        NSLog("[InkIt] WS close: reason=\(reason.rawValue) elapsed=\(elapsedStr)")
    }

    static func load() -> [CloseMetric] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([CloseMetric].self, from: data) else {
            return []
        }
        return arr
    }

    /// Human-readable summary for a debug menu or log dump.
    static func summary() -> String {
        let all = load()
        guard !all.isEmpty else { return "No sessions recorded yet." }
        var byReason: [CloseReason: [TimeInterval]] = [:]
        for m in all {
            byReason[m.reason, default: []].append(m.elapsedAfterCloseSent ?? -1)
        }
        var lines = ["Sessions: \(all.count)"]
        for reason in [CloseReason.finalTurnReceived, .serverClosed, .graceTimerExpired, .serverError, .receiveFailed, .externalCancel] {
            guard let times = byReason[reason] else { continue }
            let valid = times.filter { $0 >= 0 }
            let pct = Double(times.count) / Double(all.count) * 100
            if valid.isEmpty {
                lines.append(String(format: "  %@: %d (%.0f%%)", reason.rawValue, times.count, pct))
            } else {
                let avg = valid.reduce(0, +) / Double(valid.count)
                let mx = valid.max() ?? 0
                let mn = valid.min() ?? 0
                lines.append(String(format: "  %@: %d (%.0f%%) — elapsed min %.3fs avg %.3fs max %.3fs",
                                    reason.rawValue, times.count, pct, mn, avg, mx))
            }
        }
        return lines.joined(separator: "\n")
    }
}
