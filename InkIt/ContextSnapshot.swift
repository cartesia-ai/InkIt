import Foundation
import AppKit

struct TargetAppSnapshot: Equatable {
    let bundleIdentifier: String?
    let localizedName: String
    let processIdentifier: pid_t
    let focusedWindowTitle: String?
    let capturedAt: Date

    static func capture(from app: NSRunningApplication?) -> TargetAppSnapshot? {
        guard let app, app.processIdentifier > 0 else { return nil }
        return TargetAppSnapshot(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName ?? "<pid:\(app.processIdentifier)>",
            processIdentifier: app.processIdentifier,
            focusedWindowTitle: FocusedWindowTitle.read(pid: app.processIdentifier),
            capturedAt: Date()
        )
    }

    var logDescription: String {
        "app=\(localizedName) bundle=\(bundleIdentifier ?? "nil") pid=\(processIdentifier) title=\(focusedWindowTitle ?? "nil") capturedAt=\(capturedAt)"
    }
}

enum ContextSourceKind: String, Equatable {
    case accessibility
    case unavailable
}

enum ContextConfidence: Int, Equatable, Comparable {
    case none = 0
    case low = 1
    case high = 2

    static func < (lhs: ContextConfidence, rhs: ContextConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ContextSnapshot: Equatable {
    let source: ContextSourceKind
    let confidence: ContextConfidence
    let target: TargetAppSnapshot?
    let payload: String
    let evidence: [String: String]
    let rejectionReason: String?

    static func unavailable(target: TargetAppSnapshot?, reason: String, evidence: [String: String] = [:]) -> ContextSnapshot {
        ContextSnapshot(
            source: .unavailable,
            confidence: .none,
            target: target,
            payload: "",
            evidence: evidence,
            rejectionReason: reason
        )
    }

    var isHighConfidence: Bool {
        confidence == .high && !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var logSummary: String {
        let evidenceText = evidence.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "source=\(source.rawValue) confidence=\(confidence) payloadChars=\(payload.count) rejection=\(rejectionReason ?? "nil") evidence={\(evidenceText)}"
    }
}

enum CorrectionDecision: Equatable {
    case rewrite(ContextSnapshot)
    case pasteRaw(String)
}

enum ContextCorrectionGate {
    static func decision(for snapshot: ContextSnapshot) -> CorrectionDecision {
        guard snapshot.isHighConfidence else {
            return .pasteRaw(snapshot.rejectionReason ?? "context confidence is \(snapshot.confidence)")
        }
        return .rewrite(snapshot)
    }

    static func correct(raw: String,
                        snapshot: ContextSnapshot,
                        rewrite: (ContextSnapshot) async -> String?) async -> String {
        switch decision(for: snapshot) {
        case .pasteRaw:
            return raw
        case .rewrite(let snapshot):
            return await rewrite(snapshot) ?? raw
        }
    }
}
