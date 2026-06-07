import Foundation
import AppKit

/// Lightweight identity of the app a dictation is targeting, snapshotted at
/// key-press. Used for paste-target logging and as the hook for future
/// per-app behavior (e.g. adapting polish tone to the frontmost app). Holds no
/// on-screen content — InkIt no longer reads the target's Accessibility tree.
struct TargetAppSnapshot: Equatable {
    let bundleIdentifier: String?
    let localizedName: String
    let processIdentifier: pid_t

    static func capture(from app: NSRunningApplication?) -> TargetAppSnapshot? {
        guard let app, app.processIdentifier > 0 else { return nil }
        return TargetAppSnapshot(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName ?? "<pid:\(app.processIdentifier)>",
            processIdentifier: app.processIdentifier
        )
    }

    var logDescription: String {
        "app=\(localizedName) bundle=\(bundleIdentifier ?? "nil") pid=\(processIdentifier)"
    }
}
