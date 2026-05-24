import SwiftUI
import AppKit
import Carbon.HIToolbox

private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var permissions = PermissionsService.shared
    @State private var showAPIKey = false
    @State private var showAnthropicKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    if showAPIKey {
                        TextField("Cartesia API key", text: $settings.cartesiaAPIKey)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField("Cartesia API key", text: $settings.cartesiaAPIKey)
                            .textFieldStyle(.plain)
                    }
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .help(showAPIKey ? "Hide the Cartesia API key" : "Show the Cartesia API key")
                    .modifier(PointingHandCursor())
                }
                .frame(minHeight: 46)
            } header: {
                Text("API key")
            } footer: {
                Link("Manage Cartesia API key", destination: URL(string: "https://play.cartesia.ai/keys")!)
                    .modifier(PointingHandCursor())
            }

            Section("Hotkey") {
                HotkeyRecorder()
                    .environmentObject(settings)
                Toggle("Play sound on press and release", isOn: $settings.playFeedbackSounds)
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                    .controlSize(.regular)
            }

            Section {
                Toggle("Repair technical terms after dictation", isOn: $settings.correctionEnabled)
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                    .controlSize(.regular)

                HStack {
                    if showAnthropicKey {
                        TextField("Anthropic API key", text: $settings.anthropicAPIKey)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField("Anthropic API key", text: $settings.anthropicAPIKey)
                            .textFieldStyle(.plain)
                    }
                    Button {
                        showAnthropicKey.toggle()
                    } label: {
                        Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .help(showAnthropicKey ? "Hide the Anthropic API key" : "Show the Anthropic API key")
                    .modifier(PointingHandCursor())
                }
                .frame(minHeight: 46)
                .disabled(!settings.correctionEnabled)
                .opacity(settings.correctionEnabled ? 1 : 0.5)

                if settings.correctionEnabled && settings.anthropicAPIKey.isEmpty {
                    Text("Add an Anthropic API key to enable correction. Until then, transcripts paste unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("AI correction")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reads visible text from the focused app via Accessibility, extracts identifiers (camelCase, snake_case, file names), and asks Claude Haiku to fix any matches in the transcript before pasting.")
                    Link("Manage Anthropic API key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .modifier(PointingHandCursor())
                }
            }

            Section("Permissions") {
                PermissionRow(label: "Microphone", granted: permissions.hasMicrophone) {
                    permissions.requestMicrophone { _ in }
                }
                PermissionRow(label: "Accessibility", granted: permissions.hasAccessibility) {
                    permissions.requestAccessibility()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }
}

struct PermissionRow: View {
    let label: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Text(label)
            Spacer()
            Button(granted ? "Granted" : "Request") { action() }
                .disabled(granted)
                .frame(minWidth: 92, minHeight: 34)
        }
        .frame(minHeight: 54)
    }
}

/// Records a hotkey. Two paths:
///
/// - Carbon combo: first qualifying key-down event (must include a modifier)
///   wins.
/// - Fn-only: detected via `.flagsChanged` events where `function` is the only
///   active modifier.
struct HotkeyRecorder: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isEditing = false
    @State private var recording = false
    @State private var recorderMessage: String?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var fnCapture = FnKeyCapture()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Shortcut")
                    Text(shortcutDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 18)

                HStack(spacing: 8) {
                    Button {
                        if isEditing {
                            cancelEditing()
                        } else {
                            beginEditing()
                        }
                    } label: {
                        ShortcutCaptureField(
                            tokens: shortcutTokens,
                            placeholder: shortcutPlaceholder,
                            isActive: isEditing,
                            showsPencil: !isEditing
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help(isEditing ? "Press a new shortcut" : "Change dictation shortcut")
                    .modifier(PointingHandCursor())
                }
            }

            if let recorderMessage {
                Text(recorderMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(minHeight: recorderMessage == nil ? 58 : 74)
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    )
                    .offset(y: -36)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: toastMessage)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            cancelEditing()
        }
        .onDisappear {
            toastTask?.cancel()
            cancelEditing()
        }
    }

    private var shortcutDescription: String {
        if isEditing { return "Press a new shortcut." }
        return "Hold to dictate."
    }

    private var shortcutTokens: [String] {
        if recording { return [] }
        return Self.keyTokens(for: settings.hotkey)
    }

    private var shortcutPlaceholder: String? {
        if recording { return "press shortcut" }
        return nil
    }

    private func beginEditing() {
        coordinator.unregisterHotkey()
        isEditing = true
        recorderMessage = nil
        startRecording()
    }

    private func cancelEditing() {
        stopRecording()
        recorderMessage = nil
        isEditing = false
        coordinator.registerHotkey()
    }

    private func saveHotkey(_ hotkey: HotkeyBinding) {
        stopRecording()
        settings.hotkey = hotkey
        coordinator.registerHotkey()
        recorderMessage = nil
        isEditing = false
        showToast("Shortcut saved")
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                toastMessage = nil
                toastTask = nil
            }
        }
    }

    private func startRecording() {
        stopRecording()
        recording = true
        fnCapture.start {
            saveHotkey(.fn)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                cancelEditing()
                return nil
            }

            if event.keyCode == UInt16(kVK_Function) || event.modifierFlags.contains(.function) {
                saveHotkey(.fn)
                return nil
            }

            let carbonMods = HotkeyConversion.carbonModifiers(from: event.modifierFlags)
            if carbonMods == 0 {
                recorderMessage = "That key needs a modifier. Hold Control or Option, then press a key."
                return nil
            }

            let captured = HotkeyBinding.carbon(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
            if let validationMessage = captured.validationMessage {
                recorderMessage = validationMessage
                return nil
            } else {
                saveHotkey(captured)
            }
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.function) {
                saveHotkey(.fn)
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        fnCapture.stop()
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        recording = false
    }

    private static func displayString(for binding: HotkeyBinding) -> String {
        switch binding {
        case .carbon(let keyCode, let modifiers):
            return HotkeyConversion.displayString(keyCode: keyCode, modifiers: modifiers)
        case .fn:
            return "fn"
        }
    }

    private static func keyTokens(for binding: HotkeyBinding) -> [String] {
        switch binding {
        case .fn:
            return ["fn"]
        case .carbon(let keyCode, let modifiers):
            var tokens: [String] = []
            if modifiers & UInt32(controlKey) != 0 { tokens.append("⌃ Ctrl") }
            if modifiers & UInt32(optionKey) != 0 { tokens.append("⌥ Opt") }
            if modifiers & UInt32(shiftKey) != 0 { tokens.append("⇧ Shift") }
            if modifiers & UInt32(cmdKey) != 0 { tokens.append("⌘ Cmd") }
            tokens.append(keyTokenName(for: keyCode))
            return tokens
        }
    }

    private static func keyTokenName(for keyCode: UInt32) -> String {
        let name = HotkeyConversion.keyName(for: keyCode)
        if name.count == 1, name.rangeOfCharacter(from: .letters) != nil {
            return name.lowercased()
        }
        return name
    }
}

private final class FnKeyCapture {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isFnDown = false
    private var onFnDown: (() -> Void)?

    deinit {
        stop()
    }

    func start(onFnDown: @escaping () -> Void) {
        stop()
        self.onFnDown = onFnDown

        if installEventTap() { return }
        installPassiveMonitors()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isFnDown = false
        onFnDown = nil
    }

    private func installEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let capture = Unmanaged<FnKeyCapture>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = capture.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isFunctionKey = keyCode == Int64(kVK_Function)
            let fnDown = event.flags.contains(.maskSecondaryFn) || isFunctionKey
            if fnDown && !capture.isFnDown {
                capture.isFnDown = true
                DispatchQueue.main.async {
                    capture.onFnDown?()
                }
                return nil
            }
            capture.isFnDown = fnDown
            return Unmanaged.passUnretained(event)
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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    private func installPassiveMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let fnDown = event.modifierFlags.contains(.function) || event.keyCode == UInt16(kVK_Function)
            if fnDown && !isFnDown {
                isFnDown = true
                DispatchQueue.main.async { self.onFnDown?() }
            } else if !fnDown {
                isFnDown = false
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handler($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }
}

private struct ShortcutCaptureField: View {
    let tokens: [String]
    let placeholder: String?
    let isActive: Bool
    let showsPencil: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let placeholder {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(tokens, id: \.self) { token in
                    ShortcutKeycap(text: token)
                }
            }

            if showsPencil {
                Spacer(minLength: 12)

                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 188, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.secondary.opacity(isActive ? 0.42 : 0.26), lineWidth: isActive ? 1.25 : 1)
        )
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 34, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}
