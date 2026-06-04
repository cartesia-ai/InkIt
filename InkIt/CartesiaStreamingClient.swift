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
final class CartesiaStreamingClient: NSObject, URLSessionWebSocketDelegate {
    var onTranscriptUpdate: ((String) -> Void)?
    var onError: ((String) -> Void)?
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
            onError?("Invalid Cartesia URL")
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
            if let err { self?.onError?("Send failed: \(err.localizedDescription)") }
        }
    }

    /// Request close. Server may emit one final `turn.end` before disconnecting.
    func finalizeAndClose() {
        guard let task, !hasClosed else { onClosed?(joinedTranscript()); return }
        stateLock.lock()
        let connected = isConnected
        if !connected { pendingClose = true }
        stateLock.unlock()
        if !connected {
            // Defer the close until buffered audio has been flushed in
            // `handleConnected()`. The 2.5s safety timer below still fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, !self.hasClosed else { return }
                self.finishClose(reason: .graceTimerExpired)
            }
            return
        }
        closeRequestedAt = Date()
        task.send(.string(#"{"type":"close"}"#)) { _ in }
        // Safety: if the server never closes, force-close after 2.5s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !self.hasClosed else { return }
            self.finishClose(reason: .graceTimerExpired)
        }
    }

    func cancel() { finishClose(reason: .externalCancel) }

    private func finishClose(reason: CloseReason) {
        guard !hasClosed else { return }
        hasClosed = true
        let elapsed = closeRequestedAt.map { Date().timeIntervalSince($0) }
        SessionMetrics.record(reason: reason, elapsedAfterCloseSent: elapsed)
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onClosed?(joinedTranscript())
    }

    // MARK: - Receive loop

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                if !self.hasClosed {
                    self.onError?("Receive failed: \(error.localizedDescription)")
                    self.finishClose(reason: .receiveFailed)
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
            currentTurn = (json["transcript"] as? String) ?? currentTurn
            onTranscriptUpdate?(joinedTranscript())

        case "turn.end":
            let finalText = (json["transcript"] as? String) ?? currentTurn
            if !finalText.isEmpty { completedTurns.append(finalText) }
            currentTurn = ""
            onTranscriptUpdate?(joinedTranscript())

        case "turn.resume":
            // User continued a previously "eagerly ended" turn; keep current state.
            break

        case "connected":
            handleConnected()

        case "turn.start":
            break

        case "error":
            let msg = (json["message"] as? String) ?? (json["title"] as? String) ?? "Cartesia error"
            onError?(msg)
            finishClose(reason: .serverError)

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
                if let err { self?.onError?("Send failed: \(err.localizedDescription)") }
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
        var parts = completedTurns
        if !currentTurn.isEmpty { parts.append(currentTurn) }
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
}

// MARK: - Close-path metrics

enum CloseReason: String, Codable {
    case serverClosed         // server closed the socket (happy path)
    case graceTimerExpired    // 2.5s safety timer fired before server closed
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
        for reason in [CloseReason.serverClosed, .graceTimerExpired, .serverError, .receiveFailed, .externalCancel] {
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
