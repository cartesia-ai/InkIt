import Foundation
import AppKit
import Carbon.HIToolbox

/// Sole owner of the physical fn key's event tap.
final class FnKeyManager {
    var onHoldPress: (() -> Void)?
    var onHoldRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
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
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoop = tapRunLoop, let src = runLoopSource {
                CFRunLoopRemoveSource(runLoop, src, .commonModes)
            }
            if let runLoop = tapRunLoop { CFRunLoopStop(runLoop) }
            eventTap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
        }
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
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<FnKeyManager>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .flagsChanged,
                  event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Function) else {
                return Unmanaged.passUnretained(event)
            }

            let fnDown = event.flags.contains(.maskSecondaryFn)
            guard fnDown != manager.fnIsDown else { return Unmanaged.passUnretained(event) }
            manager.handleFn(down: fnDown)
            return nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source

        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.tapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.cartesia.InkIt.FnKeyTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        return true
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
