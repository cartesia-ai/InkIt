import SwiftUI
import AppKit
import SwiftData


extension Color {
    static let accentSoft = Color("accentSoft")
    static let recordingAmber = Color("recordingAmber")
    static let diffAdd = Color.green
    static let inkDanger = Color("InkDanger")

    static let canvas  = Color("HomeCanvas")
    static let surface = Color("HomeSurface")
    static let card    = Color("CardBG")
    static let paper   = Color("PaperBG")
    static let modalBG   = Color("ModalBG")
    static let modalCard = Color("ModalCard")

    static let sidebar = Color("SidebarBG")
    static let line = Color("InkLine")
    static let chip = Color("InkChip")
    static let navSelected = Color("NavSelected")

    static let inkText = Color("InkText")
    static let inkSub = Color("InkSub")
    static let inkFaint = Color("InkFaint")

    static let hudPill = Color.black

    static let scrim = Color.black.opacity(0.18)
    static let scrimStrong = Color.black.opacity(0.5)

    static let speakerYou = Color("SpeakerYou")
    static let speakerPalette: [Color] = [
        Color("SpeakerSage"),
        Color("SpeakerLavender"),
        Color("SpeakerGold"),
        Color("SpeakerSky"),
    ]
}

enum Radius {
    static let bar: CGFloat = 2
    static let inset: CGFloat = 5
    static let chip: CGFloat = 6
    static let keycap: CGFloat = 7
    static let control: CGFloat = 8
    static let button: CGFloat = 9
    static let card: CGFloat = 10
    static let well: CGFloat = 12
    static let tile: CGFloat = 14
    static let key: CGFloat = 15
    static let panel: CGFloat = 16
    static let practice: CGFloat = 18
    static let ring: CGFloat = 19
}

enum Elevation {
    static let ambient = Color.black.opacity(0.04)
    static let soft    = Color.black.opacity(0.06)
    static let hover   = Color.black.opacity(0.07)
    static let drop    = Color.black.opacity(0.08)
    static let card    = Color.black.opacity(0.12)
    static let lifted  = Color.black.opacity(0.18)
    static let chip    = Color.black.opacity(0.22)
    static let modal   = Color.black.opacity(0.28)
}

struct DayGroup<Item>: Identifiable {
    let id: Date
    let title: String
    let items: [Item]
}

enum DateGrouping {
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    static func byDay<Item>(_ items: [Item], newestFirst: Bool = true, date: (Item) -> Date) -> [DayGroup<Item>] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: date($0)) }
        return grouped.keys
            .sorted(by: newestFirst ? (>) : (<))
            .map { day in
                let dayItems = grouped[day, default: []].sorted {
                    newestFirst ? date($0) > date($1) : date($0) < date($1)
                }
                return DayGroup(id: day, title: title(for: day, calendar: calendar), items: dayItems)
            }
    }

    static func title(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return dayFmt.string(from: day)
    }
}

struct DayGroupHeader: View {
    let title: String
    var large: Bool = false

    var body: some View {
        Group {
            if large {
                Text(title)
                    .font(.inkReadingEmphasized)
                    .foregroundStyle(Color.inkText)
            } else {
                Text(title)
                    .font(.inkEyebrow)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Color.canvas)
    }
}

enum PageLayout {
    static let gutter: CGFloat = 40
    static let top: CGFloat = 32
    static let bottom: CGFloat = 40
}

struct PageFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, PageLayout.gutter)
            .padding(.top, PageLayout.top)
            .padding(.bottom, PageLayout.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func pageFrame() -> some View { modifier(PageFrame()) }
}

extension Font {
    static let inkLargeTitle = Font.system(size: 34, weight: .medium, design: .serif)
    static let inkHero = Font.system(size: 33, weight: .regular, design: .serif)
    static let inkHeroKeycap = Font.system(size: 21, weight: .medium)
    static let inkTitle = Font.system(size: 20, weight: .regular)
    static let inkSheetTitle = Font.system(size: 16, weight: .medium)
    static let inkModalTitle = Font.system(size: 22, weight: .regular, design: .serif)
    static let inkWordmark = Font.system(size: 21, weight: .medium)
    static let inkHeadline = Font.system(size: 15, weight: .medium)
    static let inkStat = Font.system(size: 30, weight: .regular, design: .serif)
    static let inkStatSmall = Font.system(size: 20, weight: .medium, design: .serif)
    static let inkEyebrow = Font.system(size: 11.5, weight: .medium)
    static let inkBody = Font.system(size: 15)
    static let inkBodyEmphasized = Font.system(size: 15, weight: .medium)
    static let inkReading = Font.system(size: 17)
    static let inkReadingEmphasized = Font.system(size: 17, weight: .medium)
    static let inkMono = Font.system(size: 15, design: .monospaced)
    static let inkCallout = Font.system(size: 13.5)
    static let inkCalloutEmphasized = Font.system(size: 13.5, weight: .medium)
    static let inkSectionHeader = Font.system(size: 13, weight: .medium)
    static let inkCaption = Font.system(size: 12.5)
    static let inkNotchBrand = Font.system(size: 10, weight: .semibold)
    static let inkNotchLabel = Font.system(size: 10, weight: .medium)
}


enum Motion {
    static let quick: Animation = .easeOut(duration: 0.12)
    static let state: Animation = .easeOut(duration: 0.15)
    static let expand: Animation = .easeOut(duration: 0.16)
    static let step: Animation = .spring(response: 0.45, dampingFraction: 1)
    static let rotate: Animation = .easeInOut(duration: 0.5)
}

enum Hover {
    static let backdropOpacity: Double = 0.08
    static let fillShift: Double = 0.07
    static let grayTintOpacity: Double = 0.16
    static let borderOpacity: Double = 0.22
    static let rowTintOpacity: Double = 0.055
    static let animation: Animation = Motion.quick

    static func cardBorder(isSelected: Bool, hovering: Bool) -> Color {
        if isSelected { return .accentColor }
        return hovering ? Color.primary.opacity(borderOpacity) : Color.line
    }
}

struct HoverBackdrop: ViewModifier {
    var cornerRadius: CGFloat = 8
    var isActive: Bool = false
    var activeFill: Color = .accentSoft
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape.fill(isActive
                           ? activeFill
                           : Color.primary.opacity(hovering ? Hover.backdropOpacity : 0))
            )
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Hover.animation, value: hovering)
    }
}

extension View {
    func hoverBackdrop(cornerRadius: CGFloat = 8, isActive: Bool = false,
                       activeFill: Color = .accentSoft) -> some View {
        modifier(HoverBackdrop(cornerRadius: cornerRadius, isActive: isActive,
                               activeFill: activeFill))
    }
}

struct PointingHandCursor: ViewModifier {
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

struct ExternalLink: View {
    let title: String
    let url: URL
    var font: Font = .caption

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.right")
            }
            .font(font)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}

private struct HeaderIconLabel: View {
    let systemName: String
    let hint: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))  // ds-allow: icon
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .hoverBackdrop(cornerRadius: Radius.control)
            .modifier(PointingHandCursor())
            .inkHoverHint(hint)
    }
}

struct HeaderIconButton: View {
    let systemName: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderIconLabel(systemName: systemName, hint: hint)
        }
        .buttonStyle(.plain)
    }
}

struct ManageMenuRow: View {
    let title: String
    var icon: String? = nil
    var checked: Bool = false
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon ?? "checkmark")
                    .font(.inkCallout)
                    .opacity(icon == nil && !checked ? 0 : 1)
                    .frame(width: 16)
                Text(title)
                    .font(.inkCallout)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverBackdrop(cornerRadius: Radius.chip)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}

struct InkModal<Content: View>: View {
    let onDismiss: () -> Void
    var scrim: Color = .scrim
    var dismissOnTapOutside: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            scrim
                .contentShape(Rectangle())
                .onTapGesture { if dismissOnTapOutside { onDismiss() } }
            content
                .background(Color.modalBG)
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
                .shadow(color: Elevation.modal, radius: 40, y: 18)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}

struct InkCloseButton: View {
    let onClose: () -> Void
    var help: String = "Close"

    var body: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .hoverBackdrop(cornerRadius: Radius.control)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .accessibilityLabel(help)
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("InkIt.openSettings")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.applyAppearance()
        UpdateManager.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where !(window is NSPanel) && window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return false
            }
        }
        return true
    }
}

@main
struct InkItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var history = TranscriptHistoryStore.shared
    @StateObject private var aggregates = UsageAggregateStore.shared
    @StateObject private var meetingNotes = MeetingNotesStore.shared
    @StateObject private var meetingSession = MeetingSessionCoordinator()

    var body: some Scene {
        WindowGroup("InkIt", id: "main") {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(aggregates)
                .environmentObject(meetingNotes)
                .environmentObject(meetingSession)
        }
        .modelContainer(history.modelContainer)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateManager.shared.checkForUpdates()
                }
                .disabled(!UpdateManager.shared.canCheckForUpdates)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("InkIt on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/cartesia-ai/InkIt")!)
                }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(URL(string: "https://forms.gle/jXNtDsTaLt2rKQ8N9")!)
                }
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowList) {}
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingSession: MeetingSessionCoordinator
    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingRootView()
                    .frame(minWidth: 620, idealWidth: 1140, maxWidth: .infinity,
                           minHeight: 560, idealHeight: 860, maxHeight: .infinity)
            } else if meetingSession.isSessionActive {
                MeetingSessionView()
                    .frame(width: MeetingSessionView.windowWidth)
                    .frame(maxHeight: .infinity)
            } else {
                MainWindowView()
                    .frame(minWidth: SettingsPopover.size.width + 2 * SettingsPopover.breathingRoom,
                           minHeight: SettingsPopover.size.height + 2 * SettingsPopover.breathingRoom
                                      - MainWindowView.titlebarHeight)
            }
        }
        .background(WindowChrome(meetingSessionActive: meetingSession.isSessionActive))
        .onAppear { settings.applyAppearance() }
    }
}

struct MainWindowView: View {
    static let titlebarHeight: CGFloat = 28

    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: TranscriptHistoryStore
    @EnvironmentObject var meetingSession: MeetingSessionCoordinator

    @State private var section: MainSection =
        ProcessInfo.processInfo.arguments.contains("--open-insights") ? .insights : .home
    @State private var showSettings =
        ProcessInfo.processInfo.arguments.contains("--open-settings")
    @State private var settingsPane: SettingsView.Pane = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--settings-pane"), args.indices.contains(i + 1),
              let pane = SettingsView.Pane(rawValue: args[i + 1]) else { return .general }
        return pane
    }()
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(section: $section,
                        onOpenSettings: { openSettings(pane: .general) })
            VStack(spacing: 0) {
                dictationIssueBanner
                switch section {
                case .home:
                    HomeView(onOpenSettings: { openSettings(pane: $0) },
                             onRequestDeleteAll: {
                                 withAnimation(Motion.quick) { showDeleteConfirm = true }
                             })
                case .insights:
                    InsightsView()
                case .dictionary:
                    DictionaryView()
                case .meetingNotes:
                    MeetingNotesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
            .shadow(color: Elevation.ambient, radius: 8, y: 1)
            .padding(.top, 26)
            .padding([.trailing, .bottom], 10)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sidebar)
            .background(WindowChrome())
            .overlay { UpdateModal() }
            .overlay { settingsModal }
            .overlay { deleteConfirmModal }
            .overlay(alignment: .bottomTrailing) { ToastOverlay() }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                openSettings(pane: .general)
            }
            .onAppear {
                if meetingSession.pendingNavigateToMeetingNotes {
                    section = .meetingNotes
                    meetingSession.pendingNavigateToMeetingNotes = false
                }
            }
    }

    private func openSettings(pane: SettingsView.Pane) {
        settingsPane = pane
        withAnimation(Motion.quick) { showSettings = true }
    }

    @ViewBuilder private var settingsModal: some View {
        if showSettings {
            InkModal(onDismiss: dismissSettings) {
                SettingsPopover(pane: $settingsPane, onClose: dismissSettings)
            }
        }
    }

    private func dismissSettings() {
        withAnimation(Motion.quick) { showSettings = false }
    }

    @ViewBuilder private var deleteConfirmModal: some View {
        if showDeleteConfirm {
            InkModal(onDismiss: dismissDeleteConfirm) {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("Delete all transcripts")
                            .font(.inkSheetTitle)
                            .foregroundStyle(.primary)
                        Text(deleteConfirmMessage)
                            .font(.inkCallout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Button("Cancel") { dismissDeleteConfirm() }
                            .buttonStyle(InkSecondaryButtonStyle(compact: true))
                            .keyboardShortcut(.cancelAction)
                            .modifier(PointingHandCursor())
                        Button("Delete All", role: .destructive) { confirmDeleteAll() }
                            .buttonStyle(InkButtonStyle(variant: .destructive, compact: true))
                            .keyboardShortcut(.defaultAction)
                            .modifier(PointingHandCursor())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 36)
                .padding(.bottom, 32)
                .frame(width: 400)
                .overlay(alignment: .topTrailing) {
                    InkCloseButton(onClose: dismissDeleteConfirm)
                        .padding(10)
                }
            }
        }
    }

    private var deleteConfirmMessage: String {
        let n = history.entries.count
        let noun = n == 1 ? "transcript" : "transcripts"
        return "\(n) \(noun) will be permanently removed. This can't be undone."
    }

    private func dismissDeleteConfirm() {
        withAnimation(Motion.quick) { showDeleteConfirm = false }
    }

    private func confirmDeleteAll() {
        history.clear()
        dismissDeleteConfirm()
    }

    @ViewBuilder private var dictationIssueBanner: some View {
        if let issue = settings.transcriptionIssue {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))  // ds-allow: icon
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictation is paused")
                        .font(.inkBodyEmphasized)
                        .foregroundStyle(.primary)
                    Text(transcriptionIssueMessage(issue))
                        .font(.inkCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { transcriptionIssueAction(issue) } label: {
                    Text(transcriptionIssueCTA(issue))
                        .font(.inkCaption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
            )
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
    }


    private func transcriptionIssueMessage(_ issue: SettingsStore.ServiceIssue) -> String {
        switch issue {
        case .keyInvalid:
            return "Your Cartesia API key is invalid. Update it to start dictating again."
        case .outOfCredits:
            return "You're out of Cartesia credits. Review your plan to keep going before your credits reset."
        }
    }
    private func transcriptionIssueCTA(_ issue: SettingsStore.ServiceIssue) -> String {
        switch issue {
        case .keyInvalid:   return "Update your Cartesia key"
        case .outOfCredits: return "Review your Cartesia plan"
        }
    }
    private func transcriptionIssueAction(_ issue: SettingsStore.ServiceIssue) {
        switch issue {
        case .keyInvalid:
            openSettings(pane: .dictation)
        case .outOfCredits:
            NSWorkspace.shared.open(URL(string: "https://play.cartesia.ai/subscription")!)
        }
    }
}

struct HotkeyCaps: View {
    let tokens: [String]

    var body: some View {
        Text(tokens.joined(separator: " + "))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
                    .fill(Color.accentSoft)
            )
    }
}

struct RotatingDictateHeader: View {
    let tokens: [String]

    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var hovering = false
    @State private var timer: Timer?

    private static let dwell: TimeInterval = 2.4

    private struct Bucket { let category: String; let logos: [String] }

    private static let buckets: [Bucket] = [
        .init(category: "AI",       logos: ["LogoClaude", "LogoChatgpt", "LogoGemini"]),
        .init(category: "email",    logos: ["LogoGmail", "LogoMail", "LogoOutlook"]),
        .init(category: "messages", logos: ["LogoMessages", "LogoSlack", "LogoWhatsapp"]),
        .init(category: "your editor", logos: ["LogoVscode", "LogoTerminal", "LogoXcode"]),
        .init(category: "your notes", logos: ["LogoNotion", "LogoObsidian", "LogoNotes"]),
        .init(category: "the browser", logos: ["LogoChrome", "LogoSafari", "LogoFirefox"]),
    ]

    var body: some View {
        HStack(spacing: 10) {
            Text(settings.dictationModeVerb)
                .foregroundStyle(.primary)
            HotkeyCaps(tokens: tokens)
                .font(.inkHeroKeycap)
            Text("to dictate in")
                .foregroundStyle(.primary)
            bucketView
                .id(index)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity.combined(with: .offset(y: -6))
                ))
            Spacer(minLength: 0)
        }
        .font(.inkHero)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering = $0 }
        .onAppear(perform: startRotating)
        .onDisappear { timer?.invalidate() }
    }

    private var bucketView: some View {
        let bucket = Self.buckets[index]
        return HStack(spacing: 11) {
            Text(bucket.category)
                .foregroundStyle(.primary)
            HStack(spacing: 7) {
                ForEach(bucket.logos, id: \.self) { logoTile($0) }
            }
        }
    }

    private func logoTile(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: Elevation.soft, radius: 2, y: 1)
    }

    private func startRotating() {
        guard !reduceMotion else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.dwell, repeats: true) { _ in
            guard !hovering else { return }
            withAnimation(Motion.rotate) {
                index = (index + 1) % Self.buckets.count
            }
        }
    }
}

struct HomeTryItPanel: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text("No transcripts yet")
                    .font(.headline)
                Text("Give it a try right here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TryItPracticeCard()

            Text("Or \(settings.dictationModeVerb.lowercased()) \(settings.hotkeyDisplayString) in any app and start talking.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }
}

struct TranscriptHistoryRow: View {
    let text: String
    let timestamp: String
    let latency: TranscriptHistoryStore.Latency?
    let original: String?
    let polish: TranscriptHistoryStore.PolishOutcome?
    let failure: TranscriptHistoryStore.PolishFailure?
    let appName: String?
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false
    @State private var showingDiff = false
    @State private var showingLatency = false
    @State private var showingFailure = false

    private var outcome: TranscriptHistoryStore.PolishOutcome {
        if let polish { return polish }
        return original != nil ? .polished : .off
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timestamp)
                .font(.inkCallout)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 74, alignment: .leading)
                .padding(.top, 1)

            Text(text)
                .font(.inkBody)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 16)

            trailingControls
                .frame(width: 88, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(Hover.rowTintOpacity) : Color.clear)
        )
        .onTapGesture { copy() }
        .modifier(PointingHandCursor())
        .onHover { isHovering in
            withAnimation(Hover.animation) {
                hovering = isHovering
            }
        }
        .animation(Motion.state, value: copied)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }

    private var trailingControls: some View {
        ZStack(alignment: .trailing) {
            if let appName, !hovering, !copied {
                Text(appName)
                    .font(.inkCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                CopyTranscriptGlyph(copied: copied)
                    .opacity(hovering || copied ? 1 : 0)
                if outcome == .polished {
                    polishPill.opacity(hovering ? 1 : 0)
                }
                if outcome == .failed {
                    failurePill.opacity(hovering ? 1 : 0)
                }
                if let latency {
                    timePill(latency).opacity(hovering ? 1 : 0)
                }
            }
        }
    }

    private var polishPill: some View {
        IconChip(systemName: "sparkles", fg: Color.accentColor, help: "See what changed")
            .onTapGesture { showingDiff.toggle() }
            .inkDetailPopover(isPresented: $showingDiff) {
                DiffPopover(before: original ?? text, after: text)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel("Polished — show changes")
    }

    private var failurePill: some View {
        IconChip(systemName: "exclamationmark.triangle.fill", fg: .orange, help: "Polish failed")
            .onTapGesture { showingFailure.toggle() }
            .inkDetailPopover(isPresented: $showingFailure) {
                Text(Self.failureMessage(failure))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 240, alignment: .leading)
                    .padding(12)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel(Text(Self.failureMessage(failure)))
    }

    private func timePill(_ latency: TranscriptHistoryStore.Latency) -> some View {
        IconChip(systemName: "clock", fg: .secondary, help: "Speed")
            .onTapGesture { showingLatency.toggle() }
            .inkDetailPopover(isPresented: $showingLatency) {
                LatencyPopover(latency: latency, polishFailed: outcome == .failed)
            }
            .modifier(PointingHandCursor())
            .accessibilityLabel("Time to text \(Self.fmt(latency.totalMs)) — show breakdown")
    }

    static func failureMessage(_ failure: TranscriptHistoryStore.PolishFailure?) -> String {
        guard let failure else {
            return "Polish failed — raw text pasted. Re-dictate to retry."
        }
        let p = failure.provider
        switch failure.reason {
        case .rateLimited:
            return "\(p) rate limit — raw text pasted. \(retryHint(failure.retryAt))"
        case .offline:
            return "No internet — raw text pasted. Reconnect and re-dictate."
        case .timedOut:
            return "Polish timed out — raw text pasted. Re-dictate to retry."
        case .invalidKey:
            return "Invalid \(p) API key — raw text pasted. Fix it in Settings."
        case .outOfCredits:
            return "Out of \(p) credits — raw text pasted. Review your \(p) plan to re-enable Polish."
        case .serverError:
            return "\(p) server error — raw text pasted. Try again shortly."
        case .unknown:
            return "Polish failed — raw text pasted. Re-dictate to retry."
        }
    }

    private static func retryHint(_ retryAt: Date?) -> String {
        guard let retryAt else { return "Retry soon or switch provider." }
        let secs = retryAt.timeIntervalSinceNow
        if secs <= 5 { return "Try again now or switch provider." }
        let mins = Int(ceil(secs / 60))
        if mins <= 1 { return "Try again in ~1 min or switch provider." }
        return "Try again in ~\(mins) min or switch provider."
    }

    private static func fmt(_ ms: Int) -> String {
        ms < 1000 ? "\(ms)ms" : String(format: "%.1fs", Double(ms) / 1000)
    }
}

private struct LatencyPopover: View {
    let latency: TranscriptHistoryStore.Latency
    var polishFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time to text")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text("Hotkey release → text on screen")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                stageRow("Transcribe", latency.transcribeMs)
                if latency.polishMs > 0 {
                    stageRow(polishFailed ? "Polish attempt" : "Polish", latency.polishMs)
                }
            }

            Divider()

            stageRow("Total", latency.totalMs, emphasized: true)
        }
        .padding(14)
        .frame(width: 220)
    }

    private func stageRow(_ label: String, _ ms: Int, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(emphasized ? .primary : .secondary)
            Spacer(minLength: 12)
            Text(Self.fmt(ms))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(emphasized ? .caption.weight(.semibold) : .caption)
    }

    private static func fmt(_ ms: Int) -> String {
        ms < 1000 ? "\(ms)ms" : String(format: "%.1fs", Double(ms) / 1000)
    }
}

private struct DiffPopover: View {
    let before: String
    let after: String

    private var changed: Bool { before != after }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(changed ? "Polished" : "Polished — no changes")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(Self.diff(from: before, to: after))
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)

            if changed {
                HStack(spacing: 12) {
                    Label("added", systemImage: "circle.fill")
                        .foregroundStyle(Self.addColor)
                    Label("removed", systemImage: "circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .labelStyle(DiffLegendLabelStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: 308, alignment: .leading)
    }

    private static let addColor = Color.diffAdd

    private enum Kind { case same, added, removed }
    private struct Piece { let kind: Kind; let text: String }
    private struct WordToken { let pieces: [Piece] }

    private static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func core(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func diff(from before: String, to after: String) -> AttributedString {
        let tokens = wordTokens(from: before, to: after)
        var result = AttributedString()
        for (i, token) in tokens.enumerated() {
            for piece in token.pieces {
                var s = AttributedString(piece.text)
                switch piece.kind {
                case .same:
                    s.foregroundColor = .primary
                case .added:
                    s.foregroundColor = addColor
                    s.backgroundColor = addColor.opacity(0.16)
                case .removed:
                    s.foregroundColor = .secondary
                    s.strikethroughStyle = .single
                }
                result += s
            }
            if i < tokens.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    private static func wordTokens(from before: String, to after: String) -> [WordToken] {
        let beforeWords = tokenize(before)
        let afterWords = tokenize(after)
        let changes = afterWords.difference(from: beforeWords)

        var removedSet = Set<Int>()
        var insertedSet = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removedSet.insert(offset)
            case .insert(let offset, _, _): insertedSet.insert(offset)
            }
        }

        struct Raw { let kind: Kind; let word: String }
        var raw: [Raw] = []
        var bi = 0, ai = 0
        while bi < beforeWords.count || ai < afterWords.count {
            if bi < beforeWords.count, removedSet.contains(bi) {
                raw.append(Raw(kind: .removed, word: beforeWords[bi]))
                bi += 1
            } else if ai < afterWords.count, insertedSet.contains(ai) {
                raw.append(Raw(kind: .added, word: afterWords[ai]))
                ai += 1
            } else {
                if ai < afterWords.count {
                    raw.append(Raw(kind: .same, word: afterWords[ai]))
                }
                bi += 1
                ai += 1
            }
        }

        var tokens: [WordToken] = []
        var i = 0
        while i < raw.count {
            if raw[i].kind == .same {
                tokens.append(WordToken(pieces: [Piece(kind: .same, text: raw[i].word)]))
                i += 1
                continue
            }
            var removedRun: [String] = []
            while i < raw.count, raw[i].kind == .removed { removedRun.append(raw[i].word); i += 1 }
            var addedRun: [String] = []
            while i < raw.count, raw[i].kind == .added { addedRun.append(raw[i].word); i += 1 }
            tokens.append(contentsOf: refine(removed: removedRun, added: addedRun))
        }
        return tokens
    }

    private static func refine(removed: [String], added: [String]) -> [WordToken] {
        var usedRemoved = Array(repeating: false, count: removed.count)
        var pairFor: [Int: Int] = [:]
        for (aIdx, a) in added.enumerated() {
            let ac = core(a)
            guard !ac.isEmpty else { continue }
            for rIdx in removed.indices where !usedRemoved[rIdx] && core(removed[rIdx]) == ac {
                usedRemoved[rIdx] = true
                pairFor[aIdx] = rIdx
                break
            }
        }

        var tokens: [WordToken] = []
        for rIdx in removed.indices where !usedRemoved[rIdx] {
            tokens.append(WordToken(pieces: [Piece(kind: .removed, text: removed[rIdx])]))
        }
        for (aIdx, a) in added.enumerated() {
            if let rIdx = pairFor[aIdx] {
                tokens.append(WordToken(pieces: charPieces(from: removed[rIdx], to: a)))
            } else {
                tokens.append(WordToken(pieces: [Piece(kind: .added, text: a)]))
            }
        }
        return tokens
    }

    private static func charPieces(from before: String, to after: String) -> [Piece] {
        let b = Array(before), a = Array(after)
        let changes = a.difference(from: b)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var pieces: [Piece] = []
        func append(_ kind: Kind, _ ch: Character) {
            if let last = pieces.last, last.kind == kind {
                pieces[pieces.count - 1] = Piece(kind: kind, text: last.text + String(ch))
            } else {
                pieces.append(Piece(kind: kind, text: String(ch)))
            }
        }

        var bi = 0, ai = 0
        while bi < b.count || ai < a.count {
            if bi < b.count, removed.contains(bi) {
                append(.removed, b[bi]); bi += 1
            } else if ai < a.count, inserted.contains(ai) {
                append(.added, a[ai]); ai += 1
            } else {
                if ai < a.count { append(.same, a[ai]) }
                bi += 1; ai += 1
            }
        }
        return pieces
    }
}

private struct DiffLegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))  // ds-allow: icon
            configuration.title
        }
    }
}

private struct WindowChrome: NSViewRepresentable {
    var meetingSessionActive: Bool = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in configure(view?.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in configure(nsView?.window) }
    }
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        if let ground = NSColor(named: "SidebarBG") {
            window.backgroundColor = ground
        }
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        MeetingWindowResizer.shared.apply(sessionActive: meetingSessionActive, to: window)
    }
}


private struct HoverHintLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))  // ds-allow: hover-hint pill
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(Color.hudPill)
            )
            .shadow(color: Elevation.chip, radius: 5, y: 1)
    }
}

private struct HoverHintPanelContent: View {
    let text: String
    var body: some View { HoverHintLabel(text: text).padding(6) }
}

@MainActor
final class HoverHintWindow {
    static let shared = HoverHintWindow()
    private let panel: NSPanel
    private let hosting: NSHostingView<HoverHintPanelContent>
    private var clickMonitor: Any?

    private init() {
        hosting = NSHostingView(rootView: HoverHintPanelContent(text: ""))
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting
    }

    func show(text: String, above anchor: CGRect) {
        hosting.rootView = HoverHintPanelContent(text: text)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.hide()
                return event
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}

private struct HostViewReader: NSViewRepresentable {
    let onView: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onView(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class AnchorBox: ObservableObject { weak var view: NSView? }

private struct HoverHint: ViewModifier {
    let text: String
    @State private var hovering = false
    @StateObject private var anchor = AnchorBox()

    func body(content: Content) -> some View {
        content
            .background(HostViewReader { anchor.view = $0 })
            .onHover { inside in
                hovering = inside
                if inside {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard hovering,
                              let view = anchor.view,
                              let frame = Self.screenFrame(of: view) else { return }
                        HoverHintWindow.shared.show(text: text, above: frame)
                    }
                } else {
                    HoverHintWindow.shared.hide()
                }
            }
            .onDisappear { HoverHintWindow.shared.hide() }
    }

    private static func screenFrame(of view: NSView) -> CGRect? {
        guard let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

extension View {
    func inkHoverHint(_ text: String) -> some View { modifier(HoverHint(text: text)) }

    func inkDetailPopover<C: View>(isPresented: Binding<Bool>,
                                   @ViewBuilder content: @escaping () -> C) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom, content: content)
    }
}

private struct IconChip: View {
    let systemName: String
    let fg: Color
    let help: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))  // ds-allow: icon
            .foregroundStyle(fg)
            .frame(width: 24, height: 24)
            .hoverBackdrop(cornerRadius: Radius.chip)
            .inkHoverHint(help)
    }
}

private struct CopyTranscriptGlyph: View {
    let copied: Bool

    var body: some View {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 12, weight: .medium))  // ds-allow: icon
            .foregroundStyle(copied ? Color.accentColor : .secondary)
            .frame(width: 24, height: 24)
            .hoverBackdrop(cornerRadius: Radius.chip, isActive: copied)
            .inkHoverHint("Copy")
            .animation(Motion.state, value: copied)
    }
}
