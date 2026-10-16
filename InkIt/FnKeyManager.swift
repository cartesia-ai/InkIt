import Foundation
import AppKit
import Carbon.HIToolbox

/// Sole owner of the physical fn key's event tap.
final class FnKeyManager {
    var onHoldPress: (() -> Void)?
    var onHoldRelease: (() -> Void)?

    private let tap = EventTapHost()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var fnIsDown = false
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if installEventTap() { return }
        installPassiveMonitor()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        tap.stop()
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        fnIsDown = false
    }

    private func handleFn(down: Bool) {
        fnIsDown = down
        if down {
            DispatchQueue.main.async { [weak self] in self?.onHoldPress?() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onHoldRelease?() }
        }
    }

    private func installEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        return tap.start(mask: mask,
                         options: .defaultTap,
                         threadName: "com.cartesia.InkIt.FnKeyTap") { [weak self] type, event in
            guard let self,
                  type == .flagsChanged,
                  event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Function) else { return false }
            let fnDown = event.flags.contains(.maskSecondaryFn)
            guard fnDown != self.fnIsDown else { return false }
            self.handleFn(down: fnDown)
            return true
        }
    }

    private func installPassiveMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == UInt16(kVK_Function) else { return }
            let fnDown = event.modifierFlags.contains(.function)
            guard fnDown != self.fnIsDown else { return }
            self.handleFn(down: fnDown)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handler($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }
}
