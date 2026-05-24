import SwiftUI
import AppKit
import Combine

// MARK: - Window controller

/// Floating notch-anchored pill that reflects dictation state. Stays small
/// so it doesn't intercept clicks across the menu bar.
@MainActor
final class NotchHUDController: NSObject {
    private var panel: NSPanel?
    private var transcriptPanel: NSPanel?
    private var coordinator: AppCoordinator
    private var history: TranscriptHistoryStore
    private let settings = SettingsStore.shared
    private var screenObserver: NSObjectProtocol?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var dragStartPosition: Double?

    private static let panelSize = NSSize(width: 96, height: 24)
    fileprivate static let transcriptPanelSize = NSSize(width: 320, height: 300)

    init(coordinator: AppCoordinator, history: TranscriptHistoryStore) {
        self.coordinator = coordinator
        self.history = history
        super.init()
        present()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        settings.$notchHorizontalPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
        }
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
        }
    }

    private func present() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: NotchHUDView(
            onTap: { [weak self] in
                self?.toggleTranscriptPanel()
            },
            onDragChanged: { [weak self] translation in
                self?.drag(translationX: translation)
            },
            onDragEnded: { [weak self] in
                self?.commitDrag()
            }
        )
            .environmentObject(coordinator)
            .environmentObject(history))
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host

        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let x = xOrigin(for: settings.notchHorizontalPosition, on: screen, panelWidth: size.width)
        // Top of pill flush with top of screen — same vertical strip as the
        // menu bar. On notched Macs the user can drag horizontally to avoid
        // the camera notch.
        let y = screen.frame.maxY - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        if transcriptPanel?.isVisible == true {
            positionTranscriptPanel()
        }
    }

    private func xOrigin(for position: Double, on screen: NSScreen, panelWidth: CGFloat) -> CGFloat {
        let minX = screen.frame.minX + 8
        let maxX = screen.frame.maxX - panelWidth - 8
        let raw = screen.frame.minX + screen.frame.width * CGFloat(position) - panelWidth / 2
        return min(max(raw, minX), maxX)
    }

    private func normalizedPosition(for xOrigin: CGFloat, on screen: NSScreen, panelWidth: CGFloat) -> Double {
        let centerX = xOrigin + panelWidth / 2
        let normalized = (centerX - screen.frame.minX) / screen.frame.width
        return Double(min(max(normalized, 0.04), 0.96))
    }

    private func drag(translationX: CGFloat) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        if dragStartPosition == nil {
            dragStartPosition = settings.notchHorizontalPosition
            transcriptPanel?.orderOut(nil)
        }
        let start = dragStartPosition ?? settings.notchHorizontalPosition
        let startX = xOrigin(for: start, on: screen, panelWidth: panel.frame.width)
        let nextX = startX + translationX
        let clampedX = min(max(nextX, screen.frame.minX + 8),
                           screen.frame.maxX - panel.frame.width - 8)
        let y = screen.frame.maxY - panel.frame.height
        panel.setFrameOrigin(NSPoint(x: clampedX, y: y))
    }

    private func commitDrag() {
        defer { dragStartPosition = nil }
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let finalPosition = normalizedPosition(for: panel.frame.origin.x,
                                               on: screen,
                                               panelWidth: panel.frame.width)
        if settings.notchHorizontalPosition != finalPosition {
            settings.notchHorizontalPosition = finalPosition
        }
    }

    private func toggleTranscriptPanel() {
        if transcriptPanel?.isVisible == true {
            hideTranscriptPanel()
        } else {
            showTranscriptPanel()
        }
    }

    private func showTranscriptPanel() {
        let panel: NSPanel
        if let existing = transcriptPanel {
            panel = existing
        } else {
            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.transcriptPanelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: LatestTranscriptPanelView()
                .environmentObject(history))
            transcriptPanel = panel
        }
        positionTranscriptPanel()
        panel.orderFrontRegardless()
        installOutsideClickMonitors()
    }

    private func hideTranscriptPanel() {
        transcriptPanel?.orderOut(nil)
        removeOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        guard localMouseDownMonitor == nil, globalMouseDownMonitor == nil else { return }

        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.dismissTranscriptPanelIfClickIsOutside(event)
            return event
        }
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            Task { @MainActor in
                self?.dismissTranscriptPanelIfClickIsOutside(event)
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
    }

    private func dismissTranscriptPanelIfClickIsOutside(_ event: NSEvent) {
        guard transcriptPanel?.isVisible == true else { return }

        let clickLocation = screenLocation(for: event)
        if panel?.frame.contains(clickLocation) == true {
            return
        }
        if transcriptPanel?.frame.contains(clickLocation) == true {
            return
        }

        hideTranscriptPanel()
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func positionTranscriptPanel() {
        guard let hudPanel = panel, let transcriptPanel else { return }
        guard let screen = hudPanel.screen ?? NSScreen.main else { return }
        let size = transcriptPanel.frame.size
        let hud = hudPanel.frame
        let x = min(
            max(hud.midX - size.width / 2, screen.visibleFrame.minX + 8),
            screen.visibleFrame.maxX - size.width - 8
        )
        let y = max(hud.minY - size.height - 8, screen.visibleFrame.minY + 8)
        transcriptPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func dismiss() {
        hideTranscriptPanel()
        transcriptPanel = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - SwiftUI view

private struct NotchHUDView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    var onTap: () -> Void = {}
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    @GestureState private var didDrag = false

    var isRecording: Bool { coordinator.state == .recording }
    var isRewriting: Bool { coordinator.state == .rewriting }
    var isFinalizing: Bool {
        switch coordinator.state {
        case .finalizing, .pasting: return true
        default: return false
        }
    }

    var mode: HUDMode {
        if isRecording { return .recording }
        if isRewriting { return .rewriting }
        if isFinalizing { return .finalizing }
        return .idle
    }

    var body: some View {
        NotchPill()
            .overlay(content)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .updating($didDrag) { _, state, _ in state = true }
                    .onChanged { value in onDragChanged(value.translation.width) }
                    .onEnded { _ in onDragEnded() }
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !didDrag { onTap() }
                }
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: mode)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .idle:       idleContent
        case .recording:  recordingContent
        case .rewriting:  rewritingContent
        case .finalizing: finalizingContent
        }
    }

    private var idleContent: some View {
        HStack(spacing: 6) {
            Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
            Text("InkIt").font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var recordingContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 1.0, green: 0.62, blue: 0.04))
                .frame(width: 5.5, height: 5.5)
                .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.7), radius: 4)
            HUDWaveform(level: coordinator.inputLevel)
                .frame(width: 34, height: 13)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var finalizingContent: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
                .scaleEffect(0.65)
            Text(coordinator.state == .pasting ? "Paste" : "Done")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var rewritingContent: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
                .scaleEffect(0.65)
            Text("Polish")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private enum HUDMode: Equatable {
    case idle, recording, rewriting, finalizing
}

// MARK: - Pill shape (rounded bottom, square top, anchored to screen edge)

private struct NotchPill: View {
    private let cornerRadius: CGFloat = 11

    var body: some View {
        // Top corners are square (flush with screen edge), bottom corners
        // rounded. On notched Macs this visually extends the camera notch.
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0, bottomLeading: cornerRadius,
                bottomTrailing: cornerRadius, topTrailing: 0
            ),
            style: .continuous
        )
        .fill(.black)
        .overlay(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0, bottomLeading: cornerRadius,
                    bottomTrailing: cornerRadius, topTrailing: 0
                ),
                style: .continuous
            )
            .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Waveform

private struct HUDWaveform: View {
    let level: Float
    @State private var phase: CGFloat = 0
    private let barCount = 6

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let t = phase + CGFloat(i) * 0.18
                    let wobble = (sin(t * .pi * 2) + 1) / 2
                    let loudness = CGFloat(min(1, max(0.15, level)))
                    let height = 3 + (geo.size.height - 3) * loudness * (0.32 + 0.68 * wobble)
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.95))
                        .frame(width: 2.8, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

private struct LatestTranscriptPanelView: View {
    @EnvironmentObject var history: TranscriptHistoryStore
    @State private var copiedID: TranscriptHistoryStore.Entry.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transcripts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if history.entries.isEmpty {
                Text("No transcripts yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(history.entries) { entry in
                            transcriptRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: NotchHUDController.transcriptPanelSize.width, height: NotchHUDController.transcriptPanelSize.height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func transcriptRow(_ entry: TranscriptHistoryStore.Entry) -> some View {
        LatestTranscriptRow(
            text: entry.text,
            copied: copiedID == entry.id
        ) {
            copy(entry)
        }
    }

    private func copy(_ entry: TranscriptHistoryStore.Entry) {
        let pb = NSPasteboard.general
        pb.declareTypes([.string], owner: nil)
        pb.setString(entry.text, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

private struct LatestTranscriptRow: View {
    let text: String
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .top, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(copied ? .green : .white.opacity(hovering ? 0.82 : 0.55))
                    .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(rowStroke, lineWidth: hovering || copied ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = isHovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: copied)
        .help(copied ? "Copied" : "Copy transcript")
        .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }

    private var rowFill: Color {
        if hovering {
            return .white.opacity(0.09)
        }
        return .white.opacity(0.04)
    }

    private var rowStroke: Color {
        copied ? .white.opacity(0.28) : .white.opacity(0.18)
    }
}
