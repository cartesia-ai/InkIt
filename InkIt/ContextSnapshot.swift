import Foundation
import AppKit

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
