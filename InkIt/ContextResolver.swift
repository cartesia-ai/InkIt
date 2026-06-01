import Foundation
import AppKit

/// Captures correction context for the focused window via Accessibility.
/// (The Cursor-session path was removed; this is now a thin wrapper over the
/// AX provider, kept so the capture source stays swappable in tests.)
final class ContextResolver {
    private let axProvider: ContextProvider

    init(axProvider: ContextProvider = FocusedWindowAXProvider()) {
        self.axProvider = axProvider
    }

    func captureContext(target: TargetAppSnapshot?, runID: String) async -> ContextSnapshot {
        guard let target else {
            return .unavailable(target: nil, reason: "no target snapshot")
        }

        DebugLog.info("[\(runID)] context target: \(target.logDescription)")

        let ax = await axProvider.captureContext(for: target, runID: runID)
        DebugLog.info("[\(runID)] AX context candidate: \(ax.logSummary)")
        return ax
    }
}
