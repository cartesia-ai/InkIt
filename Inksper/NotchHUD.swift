import SwiftUI
import AppKit
import Combine

// MARK: - Window controller

/// Floating notch-anchored panel that morphs based on dictation state:
///
/// - idle: thin dark pill just below the notch, clickable to show history
/// - recording: wider pill with animated waveform
/// - finalizing / pasting: spinner pill
/// - history expanded: tall panel with scrollable recent transcripts
@MainActor
final class NotchHUDController: NSObject {
    private var panel: NSPanel?
    private var coordinator: AppCoordinator
    private var history: TranscriptHistoryStore
    private var screenObserver: NSObjectProtocol?

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
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func present() {
        let size = NSSize(width: 460, height: 480)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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

        let host = NSHostingView(rootView: NotchHUDView()
            .environmentObject(coordinator)
            .environmentObject(history))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        // Align top of panel with top of screen — content positions itself
        // anchored to the top edge.
        let y = screen.frame.maxY - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - SwiftUI view

private struct NotchHUDView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var history: TranscriptHistoryStore
    @State private var showHistory = false
    @State private var copiedID: UUID?

    var isRecording: Bool { coordinator.state == .recording }
    var isFinalizing: Bool {
        switch coordinator.state {
        case .finalizing, .pasting: return true
        default: return false
        }
    }

    var mode: HUDMode {
        if showHistory { return .history }
        if isRecording { return .recording }
        if isFinalizing { return .finalizing }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchPill(mode: mode)
                    .frame(width: mode.width, height: mode.height)
                    .overlay(content)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: mode)
            Spacer(minLength: 0)
        }
        // Click outside to dismiss the history drawer.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if showHistory {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showHistory = false
                        }
                    }
                }
        )
        .onChange(of: isRecording) { _, newValue in
            if newValue, showHistory {
                withAnimation { showHistory = false }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .idle:       idleContent
        case .recording:  recordingContent
        case .finalizing: finalizingContent
        case .history:    historyContent
        }
    }

    private var idleContent: some View {
        HStack(spacing: 6) {
            Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
            Text("Inksper").font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRecording, !isFinalizing else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                showHistory = true
            }
        }
    }

    private var recordingContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
                .shadow(color: .red.opacity(0.7), radius: 4)
            HUDWaveform(level: coordinator.inputLevel)
                .frame(width: 26, height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 5)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private var historyContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent transcripts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button(action: closeHistory) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !history.entries.isEmpty {
                    Button(action: { history.clear() }) {
                        Text("Clear").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("No transcripts yet.\nHold Fn and speak.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(history.entries) { entry in
                            HistoryRow(
                                entry: entry,
                                isCopied: copiedID == entry.id,
                                onCopy: { copy(entry) }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private func copy(_ entry: TranscriptHistoryStore.Entry) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(entry.text, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func closeHistory() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showHistory = false
        }
    }
}

private enum HUDMode: Equatable {
    case idle, recording, finalizing, history

    var width: CGFloat {
        switch self {
        case .idle:       return 76
        case .recording:  return 76
        case .finalizing: return 76
        case .history:    return 420
        }
    }

    var height: CGFloat {
        switch self {
        case .idle:       return 22
        case .recording:  return 22
        case .finalizing: return 22
        case .history:    return 420
        }
    }
}

// MARK: - Pill shape (rounded bottom, square top, anchored to screen edge)

private struct NotchPill: View {
    let mode: HUDMode

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
            .stroke(.white.opacity(mode == .idle ? 0.04 : 0.08), lineWidth: 0.5)
        )
    }

    private var cornerRadius: CGFloat {
        switch mode {
        case .idle: return 11
        case .recording, .finalizing: return 11
        case .history: return 22
        }
    }
}

// MARK: - Waveform

private struct HUDWaveform: View {
    let level: Float
    @State private var phase: CGFloat = 0
    private let barCount = 16

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let t = (CGFloat(i) / CGFloat(barCount)) + phase
                    let wobble = (sin(t * .pi * 2) + 1) / 2
                    let lvl = CGFloat(max(0.1, level)) * (0.4 + 0.6 * wobble)
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: 3, height: max(3, geo.size.height * lvl))
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

// MARK: - History row

private struct HistoryRow: View {
    let entry: TranscriptHistoryStore.Entry
    let isCopied: Bool
    let onCopy: () -> Void
    @State private var hovering = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(3)
                Text(Self.fmt.string(from: entry.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 4)
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    Text(isCopied ? "Copied" : "Copy")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(isCopied ? .green.opacity(0.7) : .white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(hovering ? 0.10 : 0.06))
        )
        .onHover { hovering = $0 }
    }
}
