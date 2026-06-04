import SwiftUI
import AppKit
import Combine

// MARK: - Metrics

private enum HUDMetrics {
    /// Window is wide enough to host the centered transcript panel and the
    /// centered live pill that drops below the notch; the rest is click-through.
    static let windowWidth: CGFloat = 520
    static let maxContentHeight: CGFloat = 250
    static let panelWidth: CGFloat = 360
    static let panelContentHeight: CGFloat = 240
    /// Live/status pill extends this far below the notch, and overhangs the
    /// notch by `pillOverhang` on each side so the two merge visually.
    static let pillContentHeight: CGFloat = 30
    static let pillOverhang: CGFloat = 48
    static let minPillWidth: CGFloat = 220
}

// MARK: - Notch geometry

/// Describes where the camera notch is (or where a simulated one should go) so
/// the HUD can anchor itself to the center of the screen and merge with it.
struct NotchGeometry: Equatable {
    /// X coordinate (screen space) of the notch center.
    var centerX: CGFloat
    /// Width of the physical (or simulated) notch.
    var notchWidth: CGFloat
    /// Height of the menu-bar / notch strip. The status tab lives in this band
    /// (beside the notch); the transcript panel drops below it.
    var menuBarHeight: CGFloat
    var hasPhysicalNotch: Bool

    static func detect(on screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchLeft = frame.minX + left.width
            let notchRight = frame.maxX - right.width
            let width = max(notchRight - notchLeft, 120)
            return NotchGeometry(
                centerX: (notchLeft + notchRight) / 2,
                notchWidth: width,
                menuBarHeight: topInset,
                hasPhysicalNotch: true
            )
        }
        // No physical notch: simulate one centered at the top.
        return NotchGeometry(
            centerX: frame.midX,
            notchWidth: 180,
            menuBarHeight: 24,
            hasPhysicalNotch: false
        )
    }
}

/// Shared layout state. `geometry` drives the SwiftUI view; `hitRect` is the
/// region (top-left window coords) that should swallow mouse events — read by
/// the passthrough hit test so the menu bar stays clickable everywhere else.
@MainActor
final class HUDLayout: ObservableObject {
    @Published var geometry: NotchGeometry
    /// Whether the transcript panel is open. Toggled by clicking the island;
    /// cleared by clicking anywhere outside it.
    @Published var expanded: Bool = false
    var hitRect: CGRect

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        let w = geometry.notchWidth
        self.hitRect = CGRect(x: (HUDMetrics.windowWidth - w) / 2, y: 0,
                              width: w, height: geometry.menuBarHeight)
    }
}

// MARK: - Passthrough hosting view

/// Hosting view that only swallows mouse events within `layout.hitRect`.
/// Everywhere else returns nil so the menu bar and desktop stay clickable
/// through the otherwise wide transparent window.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    weak var layout: HUDLayout?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let layout else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let r = layout.hitRect // top-left window coords
        let rect = isFlipped
            ? r
            : CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
        return rect.contains(local) ? super.hitTest(point) : nil
    }
}

// MARK: - Window controller

/// Notch-anchored "ghost island" HUD. Invisible at rest; shows a compact Live
/// tab beside the notch while streaming (no downward drop), and expands into
/// the transcript list below the notch on hover.
@MainActor
final class NotchHUDController: NSObject {
    private var panel: NSPanel?
    private var coordinator: AppCoordinator
    private var history: TranscriptHistoryStore
    private var layout: HUDLayout
    private var screenObserver: NSObjectProtocol?

    init(coordinator: AppCoordinator, history: TranscriptHistoryStore) {
        self.coordinator = coordinator
        self.history = history
        let screen = NSScreen.main ?? NSScreen.screens.first!
        self.layout = HUDLayout(geometry: .detect(on: screen))
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
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize()),
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

        let host = PassthroughHostingView(rootView: NotchHUDView(layout: layout)
            .environmentObject(coordinator)
            .environmentObject(history))
        host.layout = layout
        host.frame = NSRect(origin: .zero, size: windowSize())
        panel.contentView = host

        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    private func windowSize() -> NSSize {
        NSSize(width: HUDMetrics.windowWidth,
               height: layout.geometry.menuBarHeight + HUDMetrics.maxContentHeight)
    }

    private func reposition() {
        guard let panel else { return }
        guard let screen = NSScreen.main else { return }
        layout.geometry = .detect(on: screen)
        let size = windowSize()
        let x = layout.geometry.centerX - size.width / 2
        let y = screen.frame.maxY - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - SwiftUI view

private enum HUDPresentation: Equatable {
    case hidden
    case live
    case status(String)
    case transcripts
}

private struct NotchHUDView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var history: TranscriptHistoryStore
    @ObservedObject var layout: HUDLayout
    @State private var outsideClickMonitor: Any?

    private var mode: HUDPresentation {
        if layout.expanded { return .transcripts }
        switch coordinator.state {
        case .recording: return .live
        case .rewriting: return .status("Polishing")
        case .finalizing: return .status("Done")
        case .pasting:    return .status("Paste")
        default:          return .hidden
        }
    }

    // MARK: Geometry (window-local, top-left origin)

    private var menuBar: CGFloat { layout.geometry.menuBarHeight }
    private var W: CGFloat { HUDMetrics.windowWidth }
    private var H: CGFloat { menuBar + HUDMetrics.maxContentHeight }

    private var notchRect: CGRect {
        let w = layout.geometry.notchWidth
        return CGRect(x: (W - w) / 2, y: 0, width: w, height: menuBar)
    }

    /// Live/status pill: centered under the notch, wide enough to overhang it
    /// on both sides so the two black shapes merge into one island.
    private var pillWidth: CGFloat {
        max(layout.geometry.notchWidth + HUDMetrics.pillOverhang * 2, HUDMetrics.minPillWidth)
    }

    private var pillRect: CGRect {
        CGRect(x: (W - pillWidth) / 2, y: 0,
               width: pillWidth, height: menuBar + HUDMetrics.pillContentHeight)
    }

    private var panelRect: CGRect {
        CGRect(x: (W - HUDMetrics.panelWidth) / 2, y: 0,
               width: HUDMetrics.panelWidth,
               height: menuBar + HUDMetrics.panelContentHeight)
    }

    /// Transparent click target that opens the panel: the visible island
    /// (notch when idle, pill while dictating). While expanded it sits behind
    /// the panel and is inert — the panel handles its own clicks.
    private func triggerRect(for mode: HUDPresentation) -> CGRect {
        switch mode {
        case .hidden:                return notchRect
        case .live, .status:         return pillRect
        case .transcripts:           return panelRect
        }
    }

    /// Region that swallows clicks so the visible island is never click-through.
    private func hitRect(for mode: HUDPresentation) -> CGRect {
        switch mode {
        case .hidden:                return notchRect
        case .live, .status:         return pillRect
        case .transcripts:           return panelRect
        }
    }

    // MARK: Body

    var body: some View {
        let trigger = triggerRect(for: mode)
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: trigger.width, height: trigger.height)
                .contentShape(Rectangle())
                .position(x: trigger.midX, y: trigger.midY)
                .onTapGesture { open() }

            visibleIsland
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: mode)
        .onAppear { layout.hitRect = hitRect(for: mode) }
        .onChange(of: mode) { _, newValue in
            layout.hitRect = hitRect(for: newValue)
            updateOutsideClickMonitor(open: newValue == .transcripts)
        }
        .onChange(of: layout.geometry) { _, _ in layout.hitRect = hitRect(for: mode) }
        .onDisappear { updateOutsideClickMonitor(open: false) }
    }

    private func open() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            layout.expanded = true
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            layout.expanded = false
        }
    }

    /// While the panel is open, watch for a click anywhere outside the app
    /// (menu bar, other windows, desktop) and collapse. Clicks inside the
    /// panel are local events the monitor never sees, so they don't dismiss it.
    private func updateOutsideClickMonitor(open: Bool) {
        if open {
            guard outsideClickMonitor == nil else { return }
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [layout] _ in
                Task { @MainActor in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        layout.expanded = false
                    }
                }
            }
        } else if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    @ViewBuilder
    private var visibleIsland: some View {
        switch mode {
        case .hidden:
            EmptyView()
        case .live:
            pill(content: liveContent)
        case .status(let label):
            pill(content: statusContent(label))
        case .transcripts:
            panel
                .frame(width: panelRect.width, height: panelRect.height)
                .position(x: panelRect.midX, y: panelRect.midY)
        }
    }

    // MARK: Shapes

    private func shape(radius: CGFloat) -> some View {
        // Square top corners (flush with screen edge / notch), rounded bottom.
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: radius,
                               bottomTrailing: radius, topTrailing: 0),
            style: .continuous
        )
        .fill(.black)
        .overlay(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: radius,
                                   bottomTrailing: radius, topTrailing: 0),
                style: .continuous
            )
            .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    /// Centered island that merges with the notch and hangs straight down.
    /// Not hit-testable so the transparent trigger behind it catches the click.
    private func pill<C: View>(content: C) -> some View {
        shape(radius: 14)
            .overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0).frame(height: menuBar) // clear the notch
                    content.frame(height: HUDMetrics.pillContentHeight)
                }
            }
            .frame(width: pillRect.width, height: pillRect.height)
            .position(x: pillRect.midX, y: pillRect.midY)
            .allowsHitTesting(false)
    }

    private var panel: some View {
        shape(radius: 14)
            .overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0).frame(height: menuBar) // reserve notch
                    transcriptsBody
                }
            }
    }

    // MARK: Content

    private var liveContent: some View {
        HStack(spacing: 7) {
            Text("InkIt")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            HUDWaveform(level: coordinator.inputLevel)
                .frame(width: 30, height: 11)
            Text("Live")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func statusContent(_ label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
                .scaleEffect(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var transcriptsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("InkIt")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                if coordinator.state == .recording {
                    Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.04))
                        .frame(width: 5, height: 5)
                    Text("Live")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture { close() }

            if history.entries.isEmpty {
                Text("No transcripts yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(history.entries) { entry in
                            TranscriptRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        .frame(width: 2.6, height: height)
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

// MARK: - Transcript row

private struct TranscriptRow: View {
    let entry: TranscriptHistoryStore.Entry
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.text)
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
                    .fill(.white.opacity(hovering ? 0.09 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(hovering || copied ? (copied ? 0.28 : 0.18) : 0),
                            lineWidth: hovering || copied ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) { hovering = isHovering }
        }
        .animation(.easeOut(duration: 0.15), value: copied)
        .help(copied ? "Copied" : "Copy transcript")
        .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.declareTypes([.string], owner: nil)
        pb.setString(entry.text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}
