import Foundation
import AppKit
import Carbon.HIToolbox

/// Pastes a string into the frontmost application by swapping the pasteboard
/// and synthesizing Cmd+V, then restoring the previous clipboard contents.
final class PasteService {
    /// Time for a synchronous `setString` to propagate before the target reads
    /// it on Cmd+V. Peer dictation apps (VoiceInk 100ms, Handy 60ms, Whispering
    /// 50ms) all use a fixed settle like this — none poll.
    private let clipboardSettleDelay: TimeInterval = 0.08
    /// Extra margin after `activate()` for the focus change to land before we
    /// post Cmd+V. Only paid when the target wasn't already frontmost —
    /// `activate()` is async with no "now focused" callback, so this is the
    /// blind wait covering that gap. Skipped entirely in the common case.
    private let activationFocusDelay: TimeInterval = 0.12
    /// Cleanup happens off the critical path; still delayed so Cmd+V has
    /// definitely been processed before we touch the pasteboard again.
    private let clipboardRestoreDelay: TimeInterval = 0.4

    /// Private pasteboard type carrying a per-paste UUID, so before restoring we
    /// can confirm we still own the clipboard and didn't race a clipboard
    /// manager or a fast manual copy. Borrowed from VoiceInk.
    private static let sessionType = NSPasteboard.PasteboardType("com.cartesia.InkIt.PasteSession")
    /// Convention type that tells clipboard-history apps to ignore an entry, so
    /// the dictated text doesn't pollute the user's clipboard history.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    func paste(text: String, targetApp: NSRunningApplication?, completion: @escaping (Bool) -> Void) {
        let pb = NSPasteboard.general
        // Snapshot existing items so non-string content is preserved when possible.
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict.isEmpty ? nil : dict
        } ?? []

        let sessionID = UUID().uuidString
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        if !ok {
            completion(false)
            return
        }
        // Tag the write so the restore step can verify ownership, and mark it
        // transient so clipboard managers skip the dictated text.
        pb.setString(sessionID, forType: Self.sessionType)
        pb.setString("1", forType: Self.transientType)

        // Only bring the target forward if it isn't already frontmost. Our
        // recorder is a non-activating panel, so the target normally never lost
        // focus — `activate()` + its focus wait are pure overhead in that case.
        // A nil target means "paste into whatever is frontmost", also no-wait.
        let alreadyFront = targetApp.map { $0.isActive } ?? true
        if !alreadyFront, let targetApp, !targetApp.isTerminated {
            targetApp.activate()
        }

        let preDelay = alreadyFront ? clipboardSettleDelay : clipboardSettleDelay + activationFocusDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + preDelay) {
            self.synthesizeCmdV()
            // The text is now visible to the user, so this is the end of
            // perceived paste latency — report completion immediately.
            completion(true)

            // Restoring the previous clipboard is cleanup that happens after the
            // user already sees their text, so it runs off the critical path.
            DispatchQueue.main.asyncAfter(deadline: .now() + self.clipboardRestoreDelay) {
                // Only restore if our write is still on the clipboard. If another
                // app (or the user) wrote to it in the interim, leave theirs be.
                let stillOurs = pb.string(forType: .string) == text
                    && pb.string(forType: Self.sessionType) == sessionID
                guard stillOurs else { return }

                pb.clearContents()
                if !saved.isEmpty {
                    let restored = saved.map { dict -> NSPasteboardItem in
                        let item = NSPasteboardItem()
                        for (type, data) in dict { item.setData(data, forType: type) }
                        return item
                    }
                    pb.writeObjects(restored)
                }
            }
        }
    }

    private func synthesizeCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
