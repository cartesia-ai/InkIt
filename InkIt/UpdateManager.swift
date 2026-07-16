import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case downloading
        case ready
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var availableVersion: String = ""

    private var updater: SPUUpdater?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var checkWasUserInitiated = false

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? Self.hasSparkleConfiguration
    }

    private override init() {
        super.init()
    }

    func start() {
        guard updater == nil, Self.hasSparkleConfiguration else { return }
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: nil
        )
        do {
            try updater.start()
        } catch {
            DebugLog.error("Sparkle failed to start: \(error.localizedDescription)")
            return
        }
        self.updater = updater
    }

    func checkForUpdates() {
        start()
        guard let updater, updater.canCheckForUpdates else { return }
        checkWasUserInitiated = true
        updater.checkForUpdates()
    }

    func restartNow() {
        let reply = installReply
        installReply = nil
        reply?(.install)
    }

    func dismissForNow() {
        let reply = installReply
        installReply = nil
        reply?(.dismiss)
        phase = .idle
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

    private func reset() {
        installReply = nil
        checkWasUserInitiated = false
        phase = .idle
    }
}

extension UpdateManager: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        availableVersion = appcastItem.displayVersionString ?? appcastItem.versionString
        phase = .downloading
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if checkWasUserInitiated { Self.showInfoAlert(title: "You're up to date", message: nil) }
        acknowledgement()
        reset()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        DebugLog.error("Sparkle update error: \(error.localizedDescription)")
        if checkWasUserInitiated {
            Self.showInfoAlert(title: "Update failed", message: error.localizedDescription)
        }
        acknowledgement()
        reset()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        phase = .downloading
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        phase = .downloading
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        phase = .ready
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        phase = .downloading
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool,
                                          acknowledgement: @escaping () -> Void) {
        acknowledgement()
        reset()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        reset()
    }

    private static func showInfoAlert(title: String, message: String?) {
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
