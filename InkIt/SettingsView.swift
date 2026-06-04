import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Shared style tokens for the editable controls in Settings (API-key fields
/// and the hotkey recorder) so they read as one consistent family. Colors are
/// semantic system tokens, never hardcoded literals — see DESIGN_SYSTEM.md.
private enum SettingsMetrics {
    /// Shared height for text-entry controls.
    static let fieldHeight: CGFloat = 30
    /// Corner radius for those fields.
    static let fieldCornerRadius: CGFloat = 7
    /// Side of the borderless eye / inline glyph accessory buttons.
    static let accessoryButton: CGFloat = 24
    /// Gap between a control and its caption.
    static let captionSpacing: CGFloat = 3

    /// Editable-field surface. The same token backs every text field and the
    /// hotkey recorder so they match exactly.
    static let fieldBackground = Color(nsColor: .textBackgroundColor)
    /// Resting field border.
    static let fieldBorder = Color(nsColor: .separatorColor)
    static let fieldBorderWidth: CGFloat = 1
    /// Border while focused / actively recording (accent, slightly heavier).
    static let fieldFocusBorderWidth: CGFloat = 2
}

/// The bordered surface shared by every editable control in Settings — one
/// definition so the API-key fields and the hotkey recorder are pixel-identical.
private struct FieldSurface: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .frame(height: SettingsMetrics.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: SettingsMetrics.fieldCornerRadius, style: .continuous)
                    .fill(SettingsMetrics.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.fieldCornerRadius, style: .continuous)
                    .stroke(
                        focused ? Color.accentColor : SettingsMetrics.fieldBorder,
                        lineWidth: focused ? SettingsMetrics.fieldFocusBorderWidth : SettingsMetrics.fieldBorderWidth
                    )
            )
    }
}

private extension View {
    func fieldSurface(focused: Bool = false) -> some View {
        modifier(FieldSurface(focused: focused))
    }
}

/// A grouped-Form section header with an inline info glyph that reveals an
/// explanatory tooltip on hover. Keeps every category self-documenting.
private struct SectionHeader: View {
    let title: String
    let help: String

    init(_ title: String, help: String) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            InfoTooltip(text: help)
        }
    }
}

/// An info glyph that reveals an explanatory popover. Shows on hover (with a
/// small grace delay so it doesn't flicker) and on click, so it's discoverable
/// either way — `.help()` tooltips proved unreliable inside Form headers.
private struct InfoTooltip: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Image(systemName: "info.circle")
            .imageScale(.small)
            .foregroundStyle(isShown ? Color.accentColor : .secondary)
            .contentShape(Rectangle())
            .onHover { hovering in isShown = hovering }
            .onTapGesture { isShown.toggle() }
            .modifier(PointingHandCursor())
            .popover(isPresented: $isShown, arrowEdge: .bottom) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
                    .padding(12)
            }
            .accessibilityLabel(Text(text))
    }
}

/// A switch styled the one way switches are styled across Settings.
private struct SettingsToggle: View {
    let title: String
    let caption: String?
    @Binding var isOn: Bool

    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            if let caption {
                VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                    Text(title)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(title)
            }
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .controlSize(.small)
    }
}

/// A secure API-key entry: bordered field sharing the Settings field surface,
/// show/hide eye toggle, and a caption link to where the key is managed.
///
/// Reports its own frame in window coordinates (bottom-left origin, matching
/// `NSEvent.locationInWindow`) so a mouse-down monitor can tell inside-clicks
/// from outside-clicks without any coordinate flipping.
private struct WindowFrameReader: NSViewRepresentable {
    let onFrame: (CGRect) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onFrame = onFrame
        return v
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onFrame = onFrame
    }

    final class TrackingView: NSView {
        var onFrame: ((CGRect) -> Void)?
        private func report() { if window != nil { onFrame?(convert(bounds, to: nil)) } }
        override func layout() { super.layout(); report() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
    }
}

/// Restores an inline editing state when the user clicks anywhere outside the
/// modified view while `isActive`. Uses a local mouse-down monitor + the view's
/// window-space frame, so it catches clicks a `Form` won't forward as taps (dead
/// space, labels, other rows). Window-switch dismissal stays the caller's job.
private struct ClickOutsideDismiss: ViewModifier {
    let isActive: Bool
    let onDismiss: () -> Void
    @State private var frameInWindow: CGRect = .zero
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(WindowFrameReader { frameInWindow = $0 })
            .onChange(of: isActive) { _, active in active ? install() : remove() }
            .onDisappear(perform: remove)
    }

    private func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            guard event.window != nil else { return event }
            if !frameInWindow.contains(event.locationInWindow) {
                DispatchQueue.main.async { onDismiss() }
            }
            return event  // never consume — the click still does its normal job
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// Calls `onDismiss` on a click outside this view while `isActive`.
    func dismissOnClickOutside(isActive: Bool, perform onDismiss: @escaping () -> Void) -> some View {
        modifier(ClickOutsideDismiss(isActive: isActive, onDismiss: onDismiss))
    }
}

/// Redaction follows the common dashboard convention (Stripe / OpenAI): a key
/// at rest is shown only by its last four characters, the rest masked. The eye
/// reveals the full value; tapping the field lets you edit it (hidden) in place.
private struct APIKeyField: View {
    let title: String
    @Binding var text: String
    let linkTitle: String
    let linkURL: URL

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                editor
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($isFocused)

                Button {
                    isRevealed.toggle()
                    if isRevealed { isFocused = false }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsMetrics.accessoryButton,
                               height: SettingsMetrics.accessoryButton)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .help(isRevealed ? "Hide \(title)" : "Show \(title)")
                .modifier(PointingHandCursor())
            }
            .padding(.horizontal, 10)
            .fieldSurface(focused: isFocused)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .frame(width: 230)
            // Click anywhere outside while editing or revealed → snap back to the
            // redacted resting state.
            .dismissOnClickOutside(isActive: isFocused || isRevealed) {
                isFocused = false
                isRevealed = false
            }
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text(title)
                Link(linkTitle, destination: linkURL)
                    .font(.caption)
                    .modifier(PointingHandCursor())
            }
        }
    }

    /// The editable field stays mounted at all times so focus lands reliably:
    /// revealed shows plaintext, hidden shows a `SecureField`. At rest, a masked
    /// preview (last four characters) is overlaid on top of the secure field —
    /// taps fall through to focus the field beneath, so the key can be edited
    /// in place even while redacted.
    @ViewBuilder private var editor: some View {
        ZStack(alignment: .leading) {
            if isRevealed {
                TextField("", text: $text)
            } else {
                SecureField("", text: $text)
            }

            if !isRevealed && !isFocused && !text.isEmpty {
                Text(Self.redacted(text))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SettingsMetrics.fieldBackground)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Masks all but the trailing `visible` characters with a fixed-length run
    /// of bullets, so neither the key nor its exact length is exposed at rest.
    private static func redacted(_ key: String, visible: Int = 4) -> String {
        guard key.count > visible else {
            return String(repeating: "•", count: max(key.count, 1))
        }
        return String(repeating: "•", count: 12) + key.suffix(visible)
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var permissions = PermissionsService.shared

    private var llmKeyBinding: Binding<String> {
        Binding(
            get: { settings.apiKey(for: settings.rewriteProvider) },
            set: { settings.setAPIKey($0, for: settings.rewriteProvider) }
        )
    }

    var body: some View {
        Form {
            Section {
                AppearanceCardPicker(selection: $settings.appearance)
            } header: {
                SectionHeader(
                    "Appearance",
                    help: "Choose how InkIt looks. System follows your Mac’s appearance automatically."
                )
            }

            Section {
                APIKeyField(
                    title: "Cartesia API key",
                    text: $settings.cartesiaAPIKey,
                    linkTitle: "Manage Cartesia API key",
                    linkURL: URL(string: "https://play.cartesia.ai/keys")!
                )
            } header: {
                SectionHeader(
                    "API key",
                    help: "Your Cartesia key powers ink-2 speech-to-text. It’s stored locally on this Mac and only sent to Cartesia."
                )
            }

            Section {
                HotkeyRecorder()
                    .environmentObject(settings)
                SettingsToggle("Play sound on press and release", isOn: $settings.playFeedbackSounds)
            } header: {
                SectionHeader(
                    "Hotkey",
                    help: "Hold this shortcut to dictate; release to transcribe and paste. Pick any key with a modifier, or use Fn."
                )
            }

            Section {
                SettingsToggle(
                    "Polish transcripts",
                    caption: "Cleans up dictation with an LLM before pasting.",
                    isOn: $settings.correctionEnabled
                )

                if settings.correctionEnabled {
                    SettingsToggle(
                        "Use screen context",
                        caption: "Reads the focused app to fix names and identifiers.",
                        isOn: $settings.screenContextEnabled
                    )

                    Picker("Provider", selection: $settings.rewriteProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: settings.rewriteProvider) { _, newProvider in
                        if !newProvider.models.contains(settings.rewriteModel) {
                            settings.rewriteModel = newProvider.defaultModel
                        }
                    }

                    // With a single curated model per provider the picker is
                    // just a one-item dropdown, so show the model as a label.
                    // The picker reappears automatically if a provider regains
                    // multiple models.
                    if settings.rewriteProvider.models.count > 1 {
                        Picker("Model", selection: $settings.rewriteModel) {
                            ForEach(settings.rewriteProvider.models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        LabeledContent("Model", value: settings.rewriteModel)
                    }

                    APIKeyField(
                        title: "\(settings.rewriteProvider.displayName) API key",
                        text: llmKeyBinding,
                        linkTitle: "Get a \(settings.rewriteProvider.displayName) API key",
                        linkURL: settings.rewriteProvider.keyURL
                    )
                }
            } header: {
                SectionHeader(
                    "AI correction",
                    help: "Optionally run your transcript through an LLM to fix punctuation, filler words, and names before it’s pasted. Uses your own provider key."
                )
            }

            Section {
                PermissionRow(label: "Microphone", granted: permissions.hasMicrophone) {
                    permissions.requestMicrophone { _ in }
                }
                PermissionRow(label: "Accessibility", granted: permissions.hasAccessibility) {
                    permissions.requestAccessibility()
                }
            } header: {
                SectionHeader(
                    "Permissions",
                    help: "InkIt needs the microphone to record dictation, and Accessibility to read on-screen context and paste into the focused app."
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }
}

/// Light / Dark / System chooser rendered as three selectable preview cards
/// (à la macOS System Settings → Appearance). Each card shows a mini window
/// mock in the corresponding appearance with an indigo ring on the selection.
private struct AppearanceCardPicker: View {
    @Binding var selection: AppearancePreference

    // Light → Dark → System reads most naturally; the enum's own order puts
    // System first, so we fix the display order explicitly.
    private let order: [AppearancePreference] = [.light, .dark, .system]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(order) { pref in
                AppearanceCard(
                    preference: pref,
                    isSelected: selection == pref
                ) {
                    selection = pref
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AppearanceCard: View {
    let preference: AppearancePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppearanceThumbnail(style: thumbnailStyle)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

                HStack(spacing: 5) {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary,
                            lineWidth: 1.5
                        )
                        .background(
                            Circle().fill(isSelected ? Color.accentColor : .clear)
                                .padding(2.5)
                        )
                        .frame(width: 11, height: 11)
                    Text(preference.displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .modifier(PointingHandCursor())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var thumbnailStyle: AppearanceThumbnail.Style {
        switch preference {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return .system
        }
    }
}

/// A tiny window mock used inside an `AppearanceCard`: traffic-light dots and a
/// few text lines, one of them the indigo accent. The `.system` style splits
/// the canvas diagonally between the light and dark surfaces.
private struct AppearanceThumbnail: View {
    enum Style { case light, dark, system }
    let style: Style

    private let lightSurface = Color(red: 0.945, green: 0.945, blue: 0.957)
    private let darkSurface  = Color(red: 0.12, green: 0.12, blue: 0.13)
    private let lightLine    = Color(red: 0.79, green: 0.79, blue: 0.82)
    private let darkLine      = Color(red: 0.29, green: 0.29, blue: 0.31)

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .light:  lightSurface
        case .dark:   darkSurface
        case .system:
            ZStack {
                lightSurface
                darkSurface.clipShape(DiagonalSplit())
            }
        }
    }

    private var lineColor: Color {
        switch style {
        case .light:  return lightLine
        case .dark:   return darkLine
        // Mid gray reads on both halves of the split.
        case .system: return Color(white: 0.55)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 5, height: 5)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 5, height: 5)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 5, height: 5)
            }
            .padding(.bottom, 2)
            Capsule().fill(lineColor).frame(width: 38, height: 4)
            Capsule().fill(lineColor).frame(width: 48, height: 4)
            Capsule().fill(Color.accentColor).frame(width: 26, height: 4)
        }
        .padding(8)
    }
}

/// Right-hand diagonal wedge used to split the System appearance thumbnail.
private struct DiagonalSplit: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct PermissionRow: View {
    let label: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        LabeledContent {
            if granted {
                Text("Granted")
                    .foregroundStyle(.secondary)
            } else {
                Button("Request") { action() }
                    .buttonStyle(.bordered)
                    .modifier(PointingHandCursor())
            }
        } label: {
            Label {
                Text(label)
            } icon: {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? .green : .orange)
            }
        }
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
            LabeledContent {
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
                // Click outside while recording → cancel back to the pencil button.
                .dismissOnClickOutside(isActive: isEditing) { cancelEditing() }
            } label: {
                VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                    Text("Shortcut")
                    Text(shortcutDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let recorderMessage {
                Text(recorderMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 188)
        .fieldSurface(focused: isActive)
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .frame(minWidth: 28, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}
