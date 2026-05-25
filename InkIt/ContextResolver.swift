import Foundation
import AppKit

final class ContextResolver {
    private let cursorBundleID: String
    private let axProvider: ContextProvider

    init(cursorBundleID: String, axProvider: ContextProvider = FocusedWindowAXProvider()) {
        self.cursorBundleID = cursorBundleID
        self.axProvider = axProvider
    }

    func captureContext(target: TargetAppSnapshot?, app: NSRunningApplication?, runID: String) async -> ContextSnapshot {
        guard let target else {
            return .unavailable(target: nil, reason: "no target snapshot")
        }

        DebugLog.info("[\(runID)] context target: \(target.logDescription)")

        if target.bundleIdentifier == cursorBundleID {
            let cursor = cursorContext(target: target, app: app, runID: runID)
            DebugLog.info("[\(runID)] cursor context candidate: \(cursor.logSummary)")
            if cursor.confidence == .high {
                return cursor
            }
            guard cursor.rejectionReason == "remote workspace" else {
                return cursor
            }
            let ax = await axProvider.captureContext(for: target, runID: runID)
            DebugLog.info("[\(runID)] remote Cursor AX context candidate: \(ax.logSummary)")
            return ax.confidence == .high ? ax : cursor
        }

        let ax = await axProvider.captureContext(for: target, runID: runID)
        DebugLog.info("[\(runID)] AX context candidate: \(ax.logSummary)")
        return ax
    }

    private func cursorContext(target: TargetAppSnapshot, app: NSRunningApplication?, runID: String) -> ContextSnapshot {
        guard let app, app.processIdentifier == target.processIdentifier else {
            return .unavailable(
                target: target,
                reason: "cursor target app missing or pid changed",
                evidence: ["expectedPid": "\(target.processIdentifier)", "actualPid": app.map { "\($0.processIdentifier)" } ?? "nil"]
            )
        }

        let currentTitle = FocusedWindowTitle.read(pid: target.processIdentifier)
        guard currentTitle == target.focusedWindowTitle else {
            return ContextSnapshot(
                source: .cursorSession,
                confidence: .low,
                target: target,
                payload: "",
                evidence: [
                    "startTitle": target.focusedWindowTitle ?? "nil",
                    "currentTitle": currentTitle ?? "nil"
                ],
                rejectionReason: "cursor window title changed"
            )
        }

        let result = SessionLocator.locateStrict(windowTitle: target.focusedWindowTitle, runID: runID)
        switch result {
        case .located(let location):
            let messages = ConversationLoader.load(from: location.url)
            let payload = messages.renderTail(maxChars: 6_000)
            guard !payload.isEmpty else {
                return ContextSnapshot(
                    source: .cursorSession,
                    confidence: .none,
                    target: target,
                    payload: "",
                    evidence: location.evidence,
                    rejectionReason: "cursor transcript parsed no messages"
                )
            }
            var evidence = location.evidence
            evidence["messageCount"] = "\(messages.count)"
            return ContextSnapshot(
                source: .cursorSession,
                confidence: .high,
                target: target,
                payload: payload,
                evidence: evidence,
                rejectionReason: nil
            )
        case .rejected(let reason, let evidence):
            return ContextSnapshot(
                source: .cursorSession,
                confidence: reason == "remote workspace" ? .none : .low,
                target: target,
                payload: "",
                evidence: evidence,
                rejectionReason: reason
            )
        }
    }
}
