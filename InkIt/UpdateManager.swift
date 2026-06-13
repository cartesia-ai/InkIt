import AppKit
import Combine
import Sparkle

/// Drives Sparkle through a fully custom user driver so update state surfaces in
/// our own UI (the floating pill on Home) instead of Sparkle's standard windows.
/// The flow: a background check finds an update → `.available` pill → user taps
/// "Update now" → silent download (`.updating`) → `.ready` pill → "Restart now"
/// installs and relaunches. Sparkle's modal never appears; the menu's "Check for
/// Updates…" routes through the same driver and only adds an alert for the
/// user-initiated "you're up to date" / error cases the pill can't show.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle        // nothing to show — pill hidden
        case available   // "New app version available" · Update now
        case updating    // "Updating…" · spinner
        case ready       // "Update ready" · Restart now
    }

    @Published private(set) var phase: Phase = .idle

    private var updater: SPUUpdater?

    // Sparkle hands us a reply block at two decision points; we stash whichever is
    // live and invoke it when the user taps the pill's button.
    private var updateFoundReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    // Set while a user-initiated (menu) check is running, so "no update"/errors
    // get an alert rather than failing silently.
    private var checkWasUserInitiated = false

    var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? Self.hasSparkleConfiguration
    }

    private override init() {
        super.init()
    }

    /// Build and start the updater. Safe to call repeatedly; only the first call
    /// with valid Sparkle configuration does anything.
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

    /// Menu "Check for Updates…" — explicit user request.
    func checkForUpdates() {
        start()
        guard let updater, updater.canCheckForUpdates else { return }
        checkWasUserInitiated = true
        updater.checkForUpdates()
    }

    // MARK: - Pill actions

    /// "Update now" — begin the (silent) download of the found update.
    func installNow() {
        let reply = updateFoundReply
        updateFoundReply = nil
        reply?(.install)
    }

    /// "Restart now" — install the downloaded update and relaunch.
    func restartNow() {
        let reply = installReply
        installReply = nil
        reply?(.install)
    }

    // MARK: - Config

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
        updateFoundReply = nil
        installReply = nil
        checkWasUserInitiated = false
        phase = .idle
    }
}

// MARK: - SPUUserDriver

extension UpdateManager: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // SUEnableAutomaticChecks is set in Info.plist, so this rarely fires; if it
        // does, opt into automatic checks without sending a system profile.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // No indeterminate progress UI — the menu check resolves into the pill or
        // an alert below. Nothing to show here.
    }

    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Don't auto-install: surface the pill and wait for "Update now".
        updateFoundReply = reply
        phase = .available
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
        phase = .updating
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        phase = .updating
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        phase = .ready
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        phase = .updating
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
