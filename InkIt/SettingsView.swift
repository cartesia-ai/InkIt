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
    static let fieldCornerRadius = Radius.keycap
    /// Gap between a control and its caption.
    static let captionSpacing: CGFloat = 3

    /// Editable-field surface. The same token backs every text field and the
    /// hotkey recorder so they match exactly. Warm card, matching the onboarding
    /// key field, so Settings reads as the same paper as the rest of the app.
    static let fieldBackground = Color.card
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
        // Spread the label and switch to the row's edges ourselves — outside a
        // grouped `Form`, a `Toggle`'s label and knob hug together instead.
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
                .controlSize(.small)
                .modifier(PointingHandCursor())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        private var lastReported: CGRect?
        // Only emit when the window-space frame actually changes. report() runs on
        // every layout() pass; the callback writes SwiftUI @State, so an
        // unconditional emit re-renders → re-lays-out → re-emits, an infinite loop
        // that pegs the main thread (and, here, freezes the app's CGEventTap).
        private func report() {
            guard window != nil else { return }
            let frame = convert(bounds, to: nil)
            guard frame != lastReported else { return }
            lastReported = frame
            onFrame?(frame)
        }
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
            // Install on appear too: a view that's conditionally rendered only
            // while active (e.g. the History search field) is born with
            // isActive == true, so onChange never fires for it.
            .onAppear { if isActive { install() } }
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

/// Secret-field handling follows the minimal convention used by macOS
/// dictation apps (e.g. VoiceInk): the key is always redacted — a `SecureField`
/// renders bullets and never reveals the plaintext — and there is no eye or
/// copy accessory. The field owns its own clicks, so clicking in places the
/// caret and you edit (or replace) the key in place while it stays masked.
private struct APIKeyField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let linkTitle: String
    let linkURL: URL
    /// Drives the field's verdict, all rendered against the field itself: a glyph
    /// inside the trailing edge (spinner / green check / red ✗) and, for the error
    /// states, a one-line message directly beneath it — never a separate row.
    var validationState: APIKeyValidator.State = .idle

    @State private var isFocused = false

    var body: some View {
        LabeledContent {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    RevealableSecureField(text: $text, placeholder: placeholder) { focused in
                        isFocused = focused
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    inlineStatus
                }
                .padding(.horizontal, 10)
                .fieldSurface(focused: isFocused)

                statusMessage
            }
            .frame(width: 230)
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text(title)
                ExternalLink(title: linkTitle, url: linkURL)
            }
        }
    }

    @ViewBuilder private var inlineStatus: some View {
        switch validationState {
        case .checking:
            ProgressView().controlSize(.small)
        case .verified:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Key verified")
        case .invalidKey:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("Invalid key")
        case .couldNotVerify:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .help("Couldn’t verify")
        default:
            EmptyView()
        }
    }

    /// Spelled out directly under the field for the two error states; checking
    /// and verified speak through the inline glyph alone.
    @ViewBuilder private var statusMessage: some View {
        switch validationState {
        case .invalidKey:
            Text("Invalid key")
                .font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .couldNotVerify:
            Text("Couldn’t verify — check your connection")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }
}

/// A single-line credential field that reveals its plaintext while it is the
/// first responder and masks to bullets at rest — focus-reveal without an eye
/// toggle. It toggles secure entry *in place* on one `NSTextField` (swapping
/// the cell at a safe moment) rather than swapping a SwiftUI `TextField` for a
/// `SecureField`, which crashes AppKit's layout pass when the swap lands inside
/// a focus change. Native placeholder rendering gives the leading, gray hint
/// for free.
private struct RevealableSecureField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RevealingTextField {
        let field = RevealingTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.applySecure(true)          // masked at rest
        field.stringValue = text
        field.onFocusChange = onFocusChange
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: RevealingTextField, context: Context) {
        context.coordinator.parent = self
        field.onFocusChange = onFocusChange
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        // Don't clobber what the user is mid-edit; only sync external changes.
        if !field.isEditing, field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RevealableSecureField
        init(_ parent: RevealableSecureField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

/// `NSTextField` that swaps between a plain and a secure cell as it gains and
/// loses first-responder status, preserving its string, font, and placeholder.
private final class RevealingTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    private(set) var isEditing = false
    private var clickMonitor: Any?

    deinit { removeClickMonitor() }

    /// Rebuilds the cell as secure (bullets) or plain (plaintext), carrying the
    /// styling and current value across the swap.
    func applySecure(_ secure: Bool) {
        let value = stringValue
        let cell: NSTextFieldCell = secure ? NSSecureTextFieldCell() : NSTextFieldCell()
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBordered = false
        cell.isBezeled = false
        cell.focusRingType = .none      // the outer FieldSurface accent border is our only focus cue
        cell.drawsBackground = false
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byTruncatingTail
        cell.isScrollable = true
        cell.wraps = false
        cell.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        cell.placeholderString = placeholderString
        cell.alignment = .natural
        (cell as? NSSecureTextFieldCell)?.echosBullets = true
        self.cell = cell
        self.stringValue = value
    }

    // Reveal just before we actually take focus, while we are not yet the first
    // responder, so the cell swap can't reenter AppKit's editing machinery.
    override func becomeFirstResponder() -> Bool {
        applySecure(false)
        let became = super.becomeFirstResponder()
        if became {
            isEditing = true
            onFocusChange?(true)
            installClickMonitor()
        }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        isEditing = false
        removeClickMonitor()
        applySecure(true)                // re-mask once editing ends
        onFocusChange?(false)
    }

    /// A click in a SwiftUI `Form`'s dead space doesn't resign first responder,
    /// so we watch for a mouse-down outside our bounds while editing and end
    /// editing ourselves — that fires `textDidEndEditing`, re-masking the key
    /// and clearing the focus border.
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(point) {
                window.makeFirstResponder(nil)   // → textDidEndEditing
            }
            return event                          // never consume; the click still lands
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    /// Settings is organized into a small sidebar. Dictation holds the core
    /// flow (activation, shortcut, microphone, transcription key); Polish is its
    /// own rich, multi-state pane; General gathers app chrome, the OS permission
    /// grants, and the lone Advanced toggle.
    enum Pane: String, CaseIterable, Identifiable {
        case general, dictation, polish
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dictation: return "Dictation"
            case .polish:    return "Polish"
            case .general:   return "General"
            }
        }
        var icon: String {
            switch self {
            case .dictation: return "mic"
            case .polish:    return "wand.and.stars"
            case .general:   return "gearshape"
            }
        }
    }

    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 220)
        } detail: {
            Group {
                switch pane ?? .dictation {
                case .dictation:   DictationSettingsPane()
                case .polish:      PolishSettingsView()
                case .general:     GeneralSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// Settings as a popover: a seamless sidebar → detail layout in a fixed-size
/// panel, opened from the Home gear button. There's no divider between the two
/// columns and none under the detail header — sidebar and detail read as one
/// warm sheet. Dismisses on the ✕, on Esc, or by clicking outside (the modal
/// host handles click-out). A sidebar search field surfaces matching settings
/// as editable controls in the detail. Reuses the existing panes so there's one
/// source of truth for each.
struct SettingsPopover: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var pane: SettingsView.Pane
    let onClose: () -> Void

    @StateObject private var search = SettingsSearch()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(width: 840, height: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingsSearchField(text: $search.query)
                .padding(.top, 8)
                .padding(.bottom, 10)

            ForEach(SettingsView.Pane.allCases) { p in
                // While searching, no pane is "current", so nothing reads as selected.
                SidebarItem(pane: p, selected: !search.isSearching && pane == p) {
                    search.query = ""
                    pane = p
                }
            }
            Spacer()
            ExternalLink(
                title: "Share feedback",
                url: URL(string: "https://forms.gle/jXNtDsTaLt2rKQ8N9")!
            )
            .padding(.horizontal, 9)
            .padding(.bottom, 4)
        }
        .padding(10)
        .frame(width: 224)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.canvas)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(search.isSearching ? "Search Results" : pane.title)
                    .foregroundStyle(.primary)
                    .font(.inkSheetTitle)
                Spacer()
                SettingsCloseButton(onClose: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Group {
                if search.isSearching {
                    SettingsSearchResults(items: search.results())
                } else {
                    switch pane {
                    case .dictation:   DictationSettingsPane()
                    case .polish:      PolishSettingsView()
                    case .general:     GeneralSettingsPane()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Warm canvas behind the grouped Forms (each hides its own system
            // scroll background) so Settings reads as the same paper as Home.
            .background(Color.canvas)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // With no divider, a left gutter keeps the detail from crowding the
        // sidebar — the breathing room the divider used to imply.
        .padding(.leading, 20)
    }

}

/// A single Settings sidebar row. Selected rows hold the amber soft-fill and stay
/// put; unselected rows lift an 8% backdrop on hover — the same quiet treatment as
/// the header chips elsewhere in the app.
private struct SidebarItem: View {
    let pane: SettingsView.Pane
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.inkNav)
                    .frame(width: 18)
                Text(pane.title)
                    .font(.inkNav)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            // Selected row holds the amber fill; others lift the standard backdrop.
            .hoverBackdrop(cornerRadius: Radius.control, isActive: selected)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}

/// The Settings ✕ in the top-right; carries the Esc shortcut so the keyboard path
/// the old hidden button owned still works, and lifts the same hover backdrop as
/// the rest of the icon-button family (26pt frame, radius 13 → a circle).
private struct SettingsCloseButton: View {
    let onClose: () -> Void

    var body: some View {
        // Reuse the shared icon ✕ and add the Esc path the old hidden button owned.
        InkCloseButton(onClose: onClose, help: "Close settings")
            .keyboardShortcut(.cancelAction)
    }
}

// MARK: - Settings search

/// Cross-pane Settings search: holds the live `query` and resolves it to the
/// matching settings, which the detail renders inline as editable controls.
final class SettingsSearch: ObservableObject {
    @Published var query: String = ""

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func results() -> [SettingsSearchItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return SettingsSearchItem.all.filter { $0.matches(q) }
    }
}

/// One searchable setting: its display title, the pane it lives in, a stable
/// `anchor` (the key the results view switches on to render the control), and
/// extra keywords so a search finds it by intent ("mic" → Microphone) not just
/// by its exact label.
struct SettingsSearchItem: Identifiable {
    let title: String
    let pane: SettingsView.Pane
    let anchor: String
    let keywords: [String]

    var id: String { anchor }

    func matches(_ q: String) -> Bool {
        if title.lowercased().contains(q) { return true }
        return keywords.contains { $0.contains(q) }
    }

    static let all: [SettingsSearchItem] = [
        .init(title: "Appearance", pane: .general, anchor: "general.appearance",
              keywords: ["theme", "light", "dark", "system", "mode", "color", "look"]),
        .init(title: "Launch InkIt at login", pane: .general, anchor: "general.login",
              keywords: ["startup", "login", "launch", "open", "boot", "start", "auto", "sign in"]),
        .init(title: "Activation", pane: .dictation, anchor: "general.activation",
              keywords: ["activation", "hold", "toggle", "push to talk", "hands free", "tap", "mode"]),
        .init(title: "Dictation shortcut", pane: .dictation, anchor: "general.hotkey",
              keywords: ["hotkey", "shortcut", "key", "binding", "dictate", "fn", "trigger"]),
        .init(title: "Sound on press and release", pane: .dictation, anchor: "general.sound",
              keywords: ["sound", "feedback", "audio", "cue", "beep", "haptic"]),
        .init(title: "Microphone", pane: .dictation, anchor: "general.microphone",
              keywords: ["mic", "input", "device", "audio", "bluetooth", "airpods"]),
        .init(title: "Cartesia API key", pane: .dictation, anchor: "general.cartesia",
              keywords: ["transcription", "api", "key", "cartesia", "token", "credential"]),
        .init(title: "Language", pane: .dictation, anchor: "general.language",
              keywords: ["language", "english", "locale", "multilingual", "spanish", "french"]),
        .init(title: "Debug logging", pane: .general, anchor: "general.debug",
              keywords: ["advanced", "log", "trace", "debug", "diagnostics"]),
        .init(title: "Polish transcripts", pane: .polish, anchor: "polish.toggle",
              keywords: ["polish", "rewrite", "clean", "fillers", "punctuation", "ai", "tidy"]),
        .init(title: "AI provider", pane: .polish, anchor: "polish.provider",
              keywords: ["provider", "groq", "openai", "gemini", "anthropic", "model", "ai", "llm"]),
        .init(title: "Polish API key", pane: .polish, anchor: "polish.key",
              keywords: ["api", "key", "provider", "token", "credential", "llm"]),
        .init(title: "Microphone permission", pane: .general, anchor: "perm.mic",
              keywords: ["microphone", "mic", "permission", "privacy", "access"]),
        .init(title: "Accessibility permission", pane: .general, anchor: "perm.accessibility",
              keywords: ["accessibility", "permission", "privacy", "type", "paste", "control"]),
    ]
}

/// The sidebar search field: magnifying glass, plain text entry, and a clear
/// button once there's text. Taller than the shared field surface, with its own
/// rounded background, and it gives up focus on any click outside it (otherwise
/// the caret keeps blinking after you click away — a SwiftUI `Form`/window quirk
/// where clicks elsewhere don't resign first responder).
private struct SettingsSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    private let height: CGFloat = 36

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))  // ds-allow: icon
                .foregroundStyle(.secondary)
            TextField("Search settings", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))  // ds-allow: icon
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(SettingsMetrics.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(
                    focused ? Color.accentColor : SettingsMetrics.fieldBorder,
                    lineWidth: focused ? SettingsMetrics.fieldFocusBorderWidth : SettingsMetrics.fieldBorderWidth
                )
        )
        // Click anywhere outside the field → drop the caret. Without this the
        // text field stays first responder and keeps blinking.
        .dismissOnClickOutside(isActive: focused) { focused = false }
    }
}

/// The search results shown in the detail while searching. Rather than redirect
/// to a pane, it renders each matching setting's *actual* control inline, grouped
/// under its pane, so it can be edited right here. The stateful rows reuse the
/// same extracted components as the panes (CartesiaKeyField / PolishKeyField /
/// MicrophonePickerRow), so behavior stays identical; the rest are plain bindings
/// to the shared `SettingsStore`.
private struct SettingsSearchResults: View {
    let items: [SettingsSearchItem]

    @EnvironmentObject var settings: SettingsStore
    @StateObject private var permissions = PermissionsService.shared

    /// Matches grouped by pane, preserving the canonical pane and within-pane
    /// order from `SettingsSearchItem.all`.
    private var grouped: [(pane: SettingsView.Pane, matches: [SettingsSearchItem])] {
        SettingsView.Pane.allCases.compactMap { pane in
            let matches = items.filter { $0.pane == pane }
            return matches.isEmpty ? nil : (pane, matches)
        }
    }

    private var polishMasterBinding: Binding<Bool> {
        Binding(
            get: { settings.polishUIState == .on },
            set: { on in on ? (settings.correctionEnabled = true) : settings.pausePolish() }
        )
    }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .regular))  // ds-allow: icon
                    .foregroundStyle(.tertiary)
                Text("No matching settings")
                    .font(.inkBody)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SettingsStack {
                ForEach(grouped, id: \.pane) { group in
                    SettingsGroup {
                        ForEach(group.matches) { item in
                            row(for: item.anchor)
                        }
                    } header: {
                        Text(group.pane.title).settingsSectionHeader()
                    }
                }
            }
            .onAppear { permissions.startPolling() }
            .onDisappear { permissions.stopPolling() }
        }
    }

    @ViewBuilder private func row(for anchor: String) -> some View {
        switch anchor {
        case "general.appearance":
            AppearanceCardPicker(selection: $settings.appearance)
        case "general.login":
            SettingsToggle("Launch InkIt at login", isOn: $settings.launchAtLogin)
        case "general.activation":
            ActivationModeCardPicker(mode: $settings.dictationMode)
        case "general.hotkey":
            HotkeyRecorder().environmentObject(settings)
        case "general.sound":
            SettingsToggle("Play sound on press and release", isOn: $settings.playFeedbackSounds)
        case "general.microphone":
            MicrophonePickerRow()
        case "general.cartesia":
            CartesiaKeyField()
        case "general.language":
            LanguageRow()
        case "general.debug":
            SettingsToggle(
                "Debug logging",
                caption: "Writes a developer trace to ~/Library/Logs/InkIt-debug.log.",
                isOn: $settings.debugLoggingEnabled
            )
        case "polish.toggle":
            SettingsToggle(
                "Polish transcripts",
                caption: "Cleans up fillers, punctuation, and misheard words",
                isOn: polishMasterBinding
            )
        case "polish.provider":
            LabeledContent("Provider") {
                Picker("", selection: $settings.rewriteProvider) {
                    ForEach(LLMProvider.allCases) { p in
                        Text(p.isRecommended ? "\(p.displayName) (Recommended)" : p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .modifier(PointingHandCursor())
            }
            LabeledContent("Model", value: settings.rewriteModel)
        case "polish.key":
            PolishKeyField()
        case "perm.mic":
            PermissionRow(label: "Microphone",
                          subtitle: "So InkIt can hear you",
                          granted: permissions.hasMicrophone) {
                permissions.requestMicrophone { _ in }
            }
        case "perm.accessibility":
            PermissionRow(label: "Accessibility",
                          subtitle: "So InkIt can type for you",
                          granted: permissions.hasAccessibility) {
                permissions.requestAccessibility()
            }
        default:
            EmptyView()
        }
    }
}

private extension View {
    /// Section-header styling for Settings: a small, muted label that sits
    /// quietly above its card, instead of the bold near-black default that
    /// grouped `Form` headers ship with. Sentence case, never uppercased.
    func settingsSectionHeader() -> some View {
        font(.inkSectionHeader)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

// MARK: - Grouped settings layout
//
// Replaces SwiftUI's `.formStyle(.grouped)`. The native grouped section
// background lands *below* `Color.canvas`, so every section read as a sunken
// well — the chrome inverted, content felt recessed instead of raised. These
// primitives put each section on `Color.lift` with a hairline (no shadow): one
// calm step *above* the canvas, in line with the app's surface ladder
// (canvas → surface → lift → card). See DESIGN_SYSTEM.md › Color and
// prototypes/settings-surface-elevation.html.

/// Spreads a `LabeledContent`'s label to the leading edge and its control to the
/// trailing edge — the label-left / control-right row a grouped `Form` gave us for
/// free, restored now that Settings rows live on the custom `SettingsCard` surface
/// instead of inside a `Form` (which otherwise packs the two together on the left).
/// Applied once at the `SettingsStack` level so every row shares the one pattern:
/// API-key fields, the provider/microphone pickers, the hotkey recorder, and the
/// permission buttons. The activation-mode and appearance pickers are full-width
/// card pickers, not `LabeledContent`, so they stay full-width — the two intended
/// exceptions.
private struct SettingsRowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension LabeledContentStyle where Self == SettingsRowLabeledContentStyle {
    static var settingsRow: SettingsRowLabeledContentStyle { .init() }
}

/// Scrolling column of sections on the warm canvas. Drop-in replacement for
/// `Form { … }.formStyle(.grouped).scrollContentBackground(.hidden)`.
private struct SettingsStack<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Restore the label-left / control-right row the grouped Form gave us;
            // every LabeledContent in the panes and search inherits it from here.
            .labeledContentStyle(.settingsRow)
        }
        .background(Color.canvas)
    }
}

/// The `lift` card a group's rows sit on: hairline border, no shadow, rows split
/// by leading-inset hairline dividers — the macOS grouped inset, recolored to the
/// app's paper. Auto-divides whatever rows it's handed.
private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        _VariadicView.Tree(SettingsRows()) { content }
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.lift)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

/// Lays each row with the shared inset and drops a hairline between rows (never
/// after the last). `_VariadicView` is what lets a `SettingsCard { rowA; rowB }`
/// call site read like a `Section` while we own the divider + padding.
private struct SettingsRows: _VariadicView.MultiViewRoot {
    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if child.id != last {
                    Divider().padding(.leading, 15)
                }
            }
        }
    }
}

/// A muted header above a `lift` card — the standard section. Mirrors
/// `Section(content:header:)` so call sites read the same.
private struct SettingsGroup<Header: View, Content: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            SettingsCard { content }
        }
    }
}

/// A header above bare content with no card chrome — for sections whose content
/// is already a self-contained surface (the activation / appearance card pickers
/// bring their own `lift` cards, so wrapping them in another would be lift-on-lift).
private struct SettingsPlainGroup<Header: View, Content: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
    }
}

/// Dictation pane — the core flow: how you trigger dictation (activation mode,
/// shortcut), what it listens to (microphone), and what powers transcription
/// (the Cartesia key + language). The settings a user actually configures to
/// dictate, gathered under one purpose-named tab.
private struct DictationSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        SettingsStack {
            SettingsPlainGroup {
                ActivationModeCardPicker(mode: $settings.dictationMode)
            } header: {
                Text("Activation mode").settingsSectionHeader()
            }

            SettingsGroup {
                HotkeyRecorder()
                    .environmentObject(settings)
                SettingsToggle("Play sound on press and release", isOn: $settings.playFeedbackSounds)
            } header: {
                Text("Shortcut").settingsSectionHeader()
            }

            MicrophoneSection()

            SettingsGroup {
                CartesiaKeyField()
                LanguageRow()
            } header: {
                Text("Transcription").settingsSectionHeader()
            }
        }
        .navigationTitle("Dictation")
    }
}

/// General pane — app chrome (appearance, launch behavior), the OS permission
/// grants, and the lone Advanced (debug) toggle. Everything that isn't the
/// dictation flow or Polish. Permissions live here (rather than a dedicated
/// tab) because they're two static rows once granted; onboarding and the Home
/// status cards still surface a missing grant, and search finds them directly.
private struct GeneralSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var permissions = PermissionsService.shared

    var body: some View {
        SettingsStack {
            SettingsPlainGroup {
                AppearanceCardPicker(selection: $settings.appearance)
            } header: {
                Text("Appearance").settingsSectionHeader()
            }

            SettingsGroup {
                SettingsToggle("Launch InkIt at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("Behavior").settingsSectionHeader()
            }

            SettingsGroup {
                PermissionRow(label: "Microphone",
                              subtitle: "So InkIt can hear you",
                              granted: permissions.hasMicrophone) {
                    permissions.requestMicrophone { _ in }
                }
                PermissionRow(label: "Accessibility",
                              subtitle: "So InkIt can type for you",
                              granted: permissions.hasAccessibility) {
                    permissions.requestAccessibility()
                }
            } header: {
                Text("Permissions").settingsSectionHeader()
            }

            SettingsGroup {
                SettingsToggle(
                    "Debug logging",
                    caption: "Writes a developer trace to ~/Library/Logs/InkIt-debug.log.",
                    isOn: $settings.debugLoggingEnabled
                )
            } header: {
                Text("Advanced").settingsSectionHeader()
            }
        }
        .navigationTitle("General")
        .onAppear {
            settings.syncLaunchAtLoginFromSystem()
            permissions.startPolling()
        }
        .onDisappear { permissions.stopPolling() }
    }
}

/// Activation-mode chooser as two selectable cards, side by side — each shows
/// the mode name and its one-line gesture, so the two options can be compared
/// at a glance and picked directly (the same card pattern as Appearance).
/// Shared by the General pane and search.
private struct ActivationModeCardPicker: View {
    @Binding var mode: DictationMode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(DictationMode.allCases) { m in
                ActivationModeCard(mode: m, isSelected: mode == m) { mode = m }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ActivationModeCard: View {
    let mode: DictationMode
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14))  // ds-allow: icon
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(mode.displayName)
                        .font(.inkCalloutEmphasized)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                Text(mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            // Fill the tallest card's height so both cards match even when one
            // description wraps to two lines and the other to one.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    // `lift`, not white `card`, so the activation cards match the
                    // grouped section surfaces and the whole pane reads as one
                    // ladder above the canvas (DESIGN_SYSTEM.md › Color).
                    .fill(Color.lift)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    // On hover an unselected card firms its border so it reads as
                    // pickable; the selected card keeps its amber outline.
                    .stroke(Hover.cardBorder(isSelected: isSelected, hovering: hovering),
                            lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: hovering && !isSelected ? Elevation.hover : .clear,
                    radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Hover.animation, value: hovering)
        .modifier(PointingHandCursor())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The transcription-language row. Read-only today — Cartesia STT is
/// English-only — with the note as subtext directly under the label (no
/// divider between value and note). Becomes a real picker when more languages
/// ship. Shared by the General pane and search.
private struct LanguageRow: View {
    var body: some View {
        LabeledContent {
            Text("English").foregroundStyle(.secondary)
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text("Language")
                Text("English-only for now. More languages coming soon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The Cartesia transcription-key field: shares the redacted `APIKeyField` and
/// owns the validator that drives its inline verdict. Extracted so the General
/// pane and search results render the identical, self-validating control.
private struct CartesiaKeyField: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var validator = CartesiaKeyValidator()

    var body: some View {
        APIKeyField(
            title: "Cartesia API key",
            text: $settings.cartesiaAPIKey,
            placeholder: "sk_car_…",
            linkTitle: "Get your free Cartesia API key",
            linkURL: URL(string: "https://play.cartesia.ai/keys")!,
            validationState: validator.state
        )
        .onAppear { validator.keyChanged(settings.cartesiaAPIKey) }
        .onChange(of: settings.cartesiaAPIKey) { _, key in validator.keyChanged(key) }
    }
}

/// Microphone picker for the General pane. Lets the user *pin* a specific input
/// device for dictation instead of inheriting whatever macOS routes to — the fix
/// for AirPods/Bluetooth silently hijacking the mic and degrading transcription.
/// "System default" follows macOS; any other choice is honored at record time,
/// with a graceful fallback to the default if the pinned device is unplugged
/// (surfaced here as the "unavailable" caption). See AudioCaptureService.
private struct MicrophoneSection: View {
    var body: some View {
        SettingsGroup {
            MicrophonePickerRow()
        } header: {
            Text("Microphone").settingsSectionHeader()
        }
    }
}

/// The microphone input-device picker and its advisory caption, extracted so it
/// can render both in the General pane and inline in search results. Owns its own
/// device manager (each mount starts/stops its own polling).
private struct MicrophonePickerRow: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var devices = AudioDeviceManager()

    /// The pinned UID is set but no attached device matches it — we're falling
    /// back to the system default until it's reconnected.
    private var pinnedButMissing: Bool {
        !settings.preferredInputDeviceUID.isEmpty
            && !devices.devices.contains { $0.uid == settings.preferredInputDeviceUID }
    }

    /// The currently selected device, when present and pinned.
    private var selectedDevice: AudioInputDevice? {
        devices.devices.first { $0.uid == settings.preferredInputDeviceUID }
    }

    var body: some View {
        // One row block: label-left / picker-right (spread via LabeledContent,
        // since we're outside a grouped Form), with the advisory caption tucked
        // beneath so no hairline divides it from the picker it explains.
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Input device") {
                Picker("", selection: $settings.preferredInputDeviceUID) {
                    Text("System default").tag("")
                    Divider()
                    ForEach(devices.devices) { device in
                        Text(device.isBluetooth ? "\(device.name) (Bluetooth)" : device.name)
                            .tag(device.uid)
                    }
                }
                .labelsHidden()
                .modifier(PointingHandCursor())
            }

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(captionIsWarning ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { devices.start() }
        .onDisappear { devices.stop() }
    }

    private var captionIsWarning: Bool {
        pinnedButMissing || (selectedDevice?.isBluetooth ?? false)
    }

    private var caption: String? {
        if pinnedButMissing {
            return "Pinned mic isn’t connected — using the system default until it’s back"
        }
        if selectedDevice?.isBluetooth ?? false {
            return "Bluetooth mics use a narrowband profile that can lower transcription accuracy. A wired or built-in mic usually works better"
        }
        return nil
    }
}

// MARK: - Polish pane

/// The "Polish" settings pane. The key is the switch: with no key it's a setup
/// screen (no toggle); a valid key turns polish on. Four honest states —
/// setup / on / paused / key-broken — so it never silently pastes raw while
/// claiming to be on. Provider defaults to Groq (recommended) but any of the
/// supported providers works. See prototypes/polish-settings-sidebar.html.
struct PolishSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    /// Master on/off as the user sees it: only truly "on" when running. Turning
    /// it off pauses (keeps the key); turning it on resumes if the key is good.
    private var masterBinding: Binding<Bool> {
        Binding(
            get: { settings.polishUIState == .on },
            set: { on in on ? (settings.correctionEnabled = true) : settings.pausePolish() }
        )
    }

    var body: some View {
        SettingsStack {
            switch settings.polishUIState {
            case .setup:     setupSections
            case .on:        configuredSections(paused: false, broken: false)
            case .paused:    configuredSections(paused: true, broken: false)
            case .keyBroken: configuredSections(paused: false, broken: true)
            }
        }
        .navigationTitle("Polish")
    }

    // MARK: Setup (no key)

    @ViewBuilder private var setupSections: some View {
        SettingsGroup {
            providerPicker
            modelRow
            keyField
        } header: {
            // Same muted section-header treatment as every other pane, with the
            // one-line explainer beneath it — so the setup header doesn't read as
            // a heavier, different-scale title than the rest of Settings.
            VStack(alignment: .leading, spacing: 3) {
                Text("Turn on Polish").settingsSectionHeader()
                Text("Cleans up fillers, punctuation, and misheard words")
                    .font(.caption).foregroundStyle(.secondary).textCase(nil)
            }
            .padding(.bottom, 2)
        }
    }

    // MARK: Configured (on / paused / key-broken)

    @ViewBuilder private func configuredSections(paused: Bool, broken: Bool) -> some View {
        if broken {
            SettingsCard {
                Label {
                    Text("Polish is paused. Your key stopped working. Transcripts are pasting unchanged. Re-enter a key to resume.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
        }

        SettingsGroup {
            SettingsToggle(
                "Polish transcripts",
                caption: "Cleans up fillers, punctuation, and misheard words",
                isOn: masterBinding
            )
            .disabled(broken)   // in the broken state the fix is re-entering the key below
        } header: {
            Text("Polish").settingsSectionHeader()
        }

        // Always expanded: the provider dropdown and key field are live at all
        // times, so switching providers or pasting a new key is one click away —
        // no Change/Done round-trip, no collapsed summary to expand first.
        SettingsGroup {
            providerPicker
            modelRow
            keyField
        } header: {
            Text("Choose your AI").settingsSectionHeader()
        }
    }

    // MARK: Shared rows

    private var providerPicker: some View {
        // Spread label / popup to the row edges (LabeledContent), as we're no
        // longer inside a grouped Form that would do it automatically.
        LabeledContent("Provider") {
            Picker("", selection: $settings.rewriteProvider) {
                ForEach(LLMProvider.allCases) { p in
                    Text(p.isRecommended ? "\(p.displayName) (Recommended)" : p.displayName).tag(p)
                }
            }
            .labelsHidden()
            .modifier(PointingHandCursor())
        }
    }

    private var keyField: some View {
        PolishKeyField()
    }

    /// The curated model for the selected provider — shown read-only (one model
    /// per provider today; the picker returns automatically if that changes).
    private var modelRow: some View {
        LabeledContent("Model", value: settings.rewriteModel)
    }
}

/// The Polish provider key field. Owns the LLM validator and the policy that a
/// verified key is the commit — it turns Polish on from setup or resumes it from
/// a broken key (never auto-resuming a deliberate pause), and keeps the validator
/// pointed at the current provider/key. Extracted so the Polish pane and search
/// results share one self-contained, self-enabling control.
private struct PolishKeyField: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var validator = LLMKeyValidator(provider: SettingsStore.shared.rewriteProvider)

    private var keyBinding: Binding<String> {
        Binding(
            get: { settings.apiKey(for: settings.rewriteProvider) },
            set: { settings.setAPIKey($0, for: settings.rewriteProvider) }
        )
    }

    var body: some View {
        APIKeyField(
            title: "API key",
            text: keyBinding,
            placeholder: settings.rewriteProvider.keyPlaceholder,
            linkTitle: "Get your \(settings.rewriteProvider.displayName) API key",
            linkURL: settings.rewriteProvider.keyURL,
            validationState: validator.state
        )
        .onAppear {
            validator.setProvider(settings.rewriteProvider)
            validator.keyChanged(settings.apiKey(for: settings.rewriteProvider))
        }
        .onChange(of: settings.rewriteProvider) { _, p in
            if !p.models.contains(settings.rewriteModel) { settings.rewriteModel = p.defaultModel }
            validator.setProvider(p)
            validator.keyChanged(settings.apiKey(for: p))
        }
        .onChange(of: settings.llmAPIKeys) { _, _ in
            validator.keyChanged(settings.apiKey(for: settings.rewriteProvider))
        }
        .onChange(of: validator.state) { _, state in
            guard state == .verified else { return }
            switch settings.polishUIState {
            case .setup, .keyBroken:
                settings.enablePolish(provider: settings.rewriteProvider)
            default: break
            }
        }
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
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppearanceThumbnail(style: thumbnailStyle)
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.button)
                            // Firm the border on hover so an unselected swatch
                            // reads as pickable; selected keeps its amber outline.
                            .stroke(Hover.cardBorder(isSelected: isSelected, hovering: hovering),
                                    lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: hovering && !isSelected ? Elevation.lifted : Elevation.card,
                            radius: 2, y: 1)

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
        .onHover { hovering = $0 }
        .animation(Hover.animation, value: hovering)
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
/// few text lines, one of them the amber accent. The `.system` style splits the
/// canvas diagonally between the light and dark surfaces.
///
/// These are the one place raw literals are correct, not a smell: each card must
/// show *both* appearances at once regardless of the active mode, so they can't
/// resolve a single appearance-aware token. The values mirror the warm-paper
/// `HomeCanvas` token (light + dark) so the preview reads as the real app.
private struct AppearanceThumbnail: View {
    enum Style { case light, dark, system }
    let style: Style

    private let lightSurface = Color(red: 0.910, green: 0.902, blue: 0.886)  // HomeCanvas light — ds-allow: dual-appearance preview
    private let darkSurface  = Color(red: 0.118, green: 0.110, blue: 0.102)  // HomeCanvas dark — ds-allow: dual-appearance preview
    private let lightLine    = Color(red: 0.80, green: 0.79, blue: 0.76)  // ds-allow: dual-appearance preview
    private let darkLine     = Color(red: 0.29, green: 0.28, blue: 0.26)  // ds-allow: dual-appearance preview

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
        case .system: return Color(white: 0.55)  // ds-allow: dual-appearance preview
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 5, height: 5)  // ds-allow: dual-appearance preview
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 5, height: 5)  // ds-allow: dual-appearance preview
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 5, height: 5)  // ds-allow: dual-appearance preview
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
    var subtitle: String? = nil
    let granted: Bool
    let action: () -> Void
    var body: some View {
        LabeledContent {
            if granted {
                Text("Enabled")
                    .foregroundStyle(.secondary)
            } else {
                Button("Enable") { action() }
                    .buttonStyle(InkButtonStyle(compact: true))
                    .modifier(PointingHandCursor())
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                    Text(label)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                    Text("Hotkey")
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
        if isEditing { return "Press a new shortcut" }
        // The gesture is explained by the Activation mode cards above; here the
        // caption just says what this key is, so the two don't repeat.
        return "Your dictation shortcut, active in any app"
    }

    private var shortcutTokens: [String] {
        if recording { return [] }
        return Self.keyTokens(for: settings.hotkey)
    }

    private var shortcutPlaceholder: String? {
        if recording { return "press new shortcut" }
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
                    .font(.system(size: 13, weight: .semibold))  // ds-allow: icon
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        // Hug the caps, but never grow past the right column into the "Hotkey"
        // label/subtext: 188pt floor keeps the common case looking unchanged,
        // 280pt ceiling stays clear of the caption. The recording placeholder
        // centers in the field; recorded caps stay trailing-aligned.
        .frame(minWidth: 188, maxWidth: 280, alignment: placeholder == nil ? .trailing : .center)
        .fixedSize(horizontal: true, vertical: false)
        .fieldSurface(focused: isActive)
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.inkSectionHeader)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .frame(minWidth: 28, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: Radius.inset)
                    .fill(Color.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.inset)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}
