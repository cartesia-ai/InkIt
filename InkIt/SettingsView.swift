import SwiftUI
import AppKit
import Carbon.HIToolbox

private enum SettingsMetrics {
    static let fieldHeight: CGFloat = 30
    static let fieldCornerRadius = Radius.keycap
    static let captionSpacing: CGFloat = 3

    static let fieldBackground = Color.modalCard
    static let fieldBorder = Color(nsColor: .separatorColor)
    static let fieldBorderWidth: CGFloat = 1
    static let fieldFocusBorderWidth: CGFloat = 2
}

struct FieldSurface: ViewModifier {
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

extension View {
    func fieldSurface(focused: Bool = false) -> some View {
        modifier(FieldSurface(focused: focused))
    }
}

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

private struct ClickOutsideDismiss: ViewModifier {
    let isActive: Bool
    let onDismiss: () -> Void
    @State private var frameInWindow: CGRect = .zero
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(WindowFrameReader { frameInWindow = $0 })
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
            return event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    func dismissOnClickOutside(isActive: Bool, perform onDismiss: @escaping () -> Void) -> some View {
        modifier(ClickOutsideDismiss(isActive: isActive, onDismiss: onDismiss))
    }
}

private struct APIKeyField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let linkTitle: String
    let linkURL: URL
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
        case .invalidKey:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .couldNotVerify:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

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

struct RevealableSecureField: NSViewRepresentable {
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
        field.applySecure(true)
        field.stringValue = text
        field.onFocusChange = onFocusChange
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: RevealingTextField, context: Context) {
        context.coordinator.parent = self
        field.onFocusChange = onFocusChange
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
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

final class RevealingTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    private(set) var isEditing = false
    private var clickMonitor: Any?

    deinit { removeClickMonitor() }

    func applySecure(_ secure: Bool) {
        let value = stringValue
        let cell: NSTextFieldCell = secure ? NSSecureTextFieldCell() : NSTextFieldCell()
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBordered = false
        cell.isBezeled = false
        cell.focusRingType = .none
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
        applySecure(true)
        onFocusChange?(false)
    }

    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(point) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

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

struct SettingsPopover: View {
    static let size = CGSize(width: 840, height: 600)
    static let breathingRoom: CGFloat = 28

    @EnvironmentObject var settings: SettingsStore
    @Binding var pane: SettingsView.Pane
    let onClose: () -> Void

    @StateObject private var search = SettingsSearch()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingsSearchField(text: $search.query)
                .padding(.top, 8)
                .padding(.bottom, 10)

            ForEach(SettingsView.Pane.allCases) { p in
                SidebarItem(pane: p, selected: !search.isSearching && pane == p) {
                    search.query = ""
                    pane = p
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 224)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.modalBG)
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
            .background(Color.modalBG)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.leading, 20)
    }

}

private struct SidebarItem: View {
    let pane: SettingsView.Pane
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.inkBody)
                    .frame(width: 20)
                Text(pane.title)
                    .font(selected ? .inkBodyEmphasized : .inkBody)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .hoverBackdrop(cornerRadius: Radius.control, isActive: selected)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}

private struct SettingsCloseButton: View {
    let onClose: () -> Void

    var body: some View {
        InkCloseButton(onClose: onClose, help: "Close settings")
            .keyboardShortcut(.cancelAction)
    }
}

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
        .dismissOnClickOutside(isActive: focused) { focused = false }
    }
}

private struct SettingsSearchResults: View {
    let items: [SettingsSearchItem]

    @EnvironmentObject var settings: SettingsStore
    @StateObject private var permissions = PermissionsService.shared

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
                .fixedSize()
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
    func settingsSectionHeader() -> some View {
        font(.inkSectionHeader)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

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
            .labeledContentStyle(.settingsRow)
            .font(.inkBody)
        }
        .background(Color.modalBG)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        _VariadicView.Tree(SettingsRows()) { content }
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.modalCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.modalCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
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

private struct MicrophoneSection: View {
    var body: some View {
        SettingsGroup {
            MicrophonePickerRow()
        } header: {
            Text("Microphone").settingsSectionHeader()
        }
    }
}

private struct MicrophonePickerRow: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var devices = AudioDeviceManager()

    private var pinnedButMissing: Bool {
        !settings.preferredInputDeviceUID.isEmpty
            && !devices.devices.contains { $0.uid == settings.preferredInputDeviceUID }
    }

    private var selectedDevice: AudioInputDevice? {
        devices.devices.first { $0.uid == settings.preferredInputDeviceUID }
    }

    var body: some View {
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
                .fixedSize()
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

struct PolishSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { settings.polishUIState == .on },
            set: { on in on ? (settings.correctionEnabled = true) : settings.pausePolish() }
        )
    }

    var body: some View {
        let state = settings.polishUIState
        let setup = state == .setup
        let broken = state == .keyBroken

        SettingsStack {
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
                .disabled(setup || broken)
            } header: {
                Text("Polish").settingsSectionHeader()
            }

            SettingsGroup {
                providerPicker
                modelRow
                keyField
            } header: {
                Text(setup ? "Choose your AI to turn Polish on" : "Choose your AI")
                    .settingsSectionHeader()
            }
        }
        .navigationTitle("Polish")
    }

    private var providerPicker: some View {
        LabeledContent("Provider") {
            Picker("", selection: $settings.rewriteProvider) {
                ForEach(LLMProvider.allCases) { p in
                    Text(p.isRecommended ? "\(p.displayName) (Recommended)" : p.displayName).tag(p)
                }
            }
            .labelsHidden()
            .fixedSize()
            .modifier(PointingHandCursor())
        }
    }

    private var keyField: some View {
        PolishKeyField()
    }

    private var modelRow: some View {
        LabeledContent("Model", value: settings.rewriteModel)
    }
}

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

private struct AppearanceCardPicker: View {
    @Binding var selection: AppearancePreference

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

private struct AppearanceThumbnail: View {
    enum Style { case light, dark, system }
    let style: Style

    private let lightSurface = Color(red: 0.910, green: 0.902, blue: 0.886)  // ds-allow: dual-appearance preview
    private let darkSurface  = Color(red: 0.118, green: 0.110, blue: 0.102)  // ds-allow: dual-appearance preview
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

struct HotkeyRecorder: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isEditing = false
    @State private var recording = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var fnCapture = FnKeyCapture()
    @State private var modifierCandidate: UInt32?

    var body: some View {
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
            .modifier(PointingHandCursor())
            .dismissOnClickOutside(isActive: isEditing) { cancelEditing() }
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text("Hotkey")
                Text(shortcutDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            cancelEditing()
        }
        .onDisappear {
            cancelEditing()
        }
    }

    private var shortcutDescription: String {
        if isEditing { return "Press a new shortcut" }
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
        startRecording()
    }

    private func cancelEditing() {
        stopRecording()
        isEditing = false
        coordinator.registerHotkey()
    }

    private func saveHotkey(_ hotkey: HotkeyBinding) {
        stopRecording()
        settings.hotkey = hotkey
        coordinator.registerHotkey()
        isEditing = false
        ToastCenter.shared.show("Shortcut saved", style: .success)
    }

    private func rejectShortcut(_ keys: String) {
        ToastCenter.shared.show("\(keys) is invalid. Please try another.", style: .error)
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

            modifierCandidate = nil

            let carbonMods = HotkeyConversion.carbonModifiers(from: event.modifierFlags)
            if carbonMods == 0 {
                rejectShortcut(HotkeyConversion.keyName(for: UInt32(event.keyCode)))
                return nil
            }

            let captured = HotkeyBinding.carbon(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
            if captured.isValidShortcut {
                saveHotkey(captured)
            } else {
                rejectShortcut(HotkeyConversion.displayString(keyCode: UInt32(event.keyCode), modifiers: carbonMods))
            }
            return nil
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.function) {
                saveHotkey(.fn)
                return nil
            }

            let keyCode = UInt32(event.keyCode)
            guard HotkeyConversion.isModifierKeyCode(keyCode) else { return event }

            let mask = HotkeyConversion.nsModifierFlag(for: keyCode)
            let isDown = flags.contains(mask)
            let activeCount = (flags.contains(.command) ? 1 : 0)
                + (flags.contains(.option) ? 1 : 0)
                + (flags.contains(.control) ? 1 : 0)
                + (flags.contains(.shift) ? 1 : 0)
            if isDown {
                modifierCandidate = activeCount == 1 ? keyCode : nil
            } else if modifierCandidate == keyCode {
                modifierCandidate = nil
                saveHotkey(.modifierKey(keyCode: keyCode))
            }
            return event
        }
    }

    private func stopRecording() {
        fnCapture.stop()
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        modifierCandidate = nil
        recording = false
    }

    private static func displayString(for binding: HotkeyBinding) -> String {
        switch binding {
        case .carbon(let keyCode, let modifiers):
            return HotkeyConversion.displayString(keyCode: keyCode, modifiers: modifiers)
        case .fn:
            return "fn"
        case .modifierKey(let keyCode):
            return HotkeyConversion.modifierLabel(for: keyCode)
        }
    }

    private static func keyTokens(for binding: HotkeyBinding) -> [String] {
        HotkeyConversion.displayTokens(for: binding)
    }
}

private final class FnKeyCapture {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
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
            if let runLoop = tapRunLoop {
                if let source = runLoopSource {
                    CFRunLoopRemoveSource(runLoop, source, .commonModes)
                }
                CFRunLoopStop(runLoop)
            }
            eventTap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
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
        eventTap = tap
        runLoopSource = source

        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.tapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.cartesia.InkIt.FnKeyCapture"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
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
                    .fill(Color.modalBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.inset)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}
