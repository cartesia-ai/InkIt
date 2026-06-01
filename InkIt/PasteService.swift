import Foundation
import AppKit
import Carbon.HIToolbox

/// Pastes a string into the frontmost application by swapping the pasteboard
/// and synthesizing Cmd+V, then restoring the previous clipboard contents.
final class PasteService {
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

        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        if !ok {
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let targetApp, !targetApp.isTerminated {
                targetApp.activate(options: [.activateIgnoringOtherApps])
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.synthesizeCmdV()
                // The text is now visible to the user, so this is the end of
                // perceived paste latency — report completion immediately.
                completion(true)

                // Restoring the previous clipboard is cleanup that happens
                // after the user already sees their text, so it runs off the
                // critical path. Still delayed so Cmd+V has definitely been
                // processed before we overwrite the pasteboard.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
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
