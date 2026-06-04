import SwiftUI
import AppKit
import Combine

// MARK: - Metrics

private enum HUDMetrics {
    /// Window is wide enough to host the centered live/status pill that drops
    /// below the notch; the whole window is click-through.
    static let windowWidth: CGFloat = 520
    /// Live/status pill extends this far below the notch, and overhangs the
    /// notch by `pillOverhang` on each side so the two merge visually.
    static let pillContentHeight: CGFloat = 22
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
    /// Height of the menu-bar / notch strip. The pill drops below it.
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

/// Shared layout state. `geometry` drives the SwiftUI view and is refreshed when
/// the screen configuration changes.
@MainActor
final class HUDLayout: ObservableObject {
    @Published var geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}

// MARK: - Window controller

/// Notch-anchored "ghost island" HUD. Invisible at rest; while dictating or
/// processing it shows a compact status pill that merges with the notch and
/// hangs straight down. Purely a status surface — it never captures the mouse,
/// so the cursor stays where the user put it. History lives in the main app.
@MainActor
final class NotchHUDController: NSObject {
    private var panel: NSPanel?
    private var coordinator: AppCoordinator
    private var layout: HUDLayout
    private var screenObserver: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
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
        // Pure status surface: the window never swallows clicks, so the menu bar
        // and whatever is behind the pill stay fully interactive.
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: NotchHUDView(layout: layout)
            .environmentObject(coordinator))
        host.frame = NSRect(origin: .zero, size: windowSize())
        panel.contentView = host

        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    private func windowSize() -> NSSize {
        NSSize(width: HUDMetrics.windowWidth,
               height: layout.geometry.menuBarHeight + HUDMetrics.pillContentHeight)
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
}

private struct NotchHUDView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var layout: HUDLayout

    private var mode: HUDPresentation {
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
    private var H: CGFloat { menuBar + HUDMetrics.pillContentHeight }

    /// Live/status pill: centered under the notch, wide enough to overhang it
    /// on both sides so the two black shapes merge into one island.
    private var pillWidth: CGFloat {
        max(layout.geometry.notchWidth + HUDMetrics.pillOverhang * 2, HUDMetrics.minPillWidth)
    }

    private var pillRect: CGRect {
        CGRect(x: (W - pillWidth) / 2, y: 0,
               width: pillWidth, height: menuBar + HUDMetrics.pillContentHeight)
    }

    // MARK: Body

    var body: some View {
        visibleIsland
            .frame(width: W, height: H, alignment: .topLeading)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: mode)
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
