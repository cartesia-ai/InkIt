import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController?

    var canCheckForUpdates: Bool {
        Self.hasSparkleConfiguration
    }

    private override init() {
        super.init()
    }

    func start() {
        guard updaterController == nil, Self.hasSparkleConfiguration else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        start()
        updaterController?.checkForUpdates(nil)
    }

    private static var hasSparkleConfiguration: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        return isResolvedNonEmptyString(info["SUFeedURL"])
            && isResolvedNonEmptyString(info["SUPublicEDKey"])
    }

    private static func isResolvedNonEmptyString(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }
}
