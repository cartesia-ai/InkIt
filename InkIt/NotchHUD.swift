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
    /// Total drop below the notch = a small gap under the notch, the content
    /// row, then padding beneath it so the text/waveform aren't jammed against
    /// the notch's bottom edge.
    static let contentTopGap: CGFloat = 3
    static let contentRowHeight: CGFloat = 6
    static let contentBottomPad: CGFloat = 6
    static let pillContentHeight: CGFloat = contentTopGap + contentRowHeight + contentBottomPad
    static let pillOverhang: CGFloat = 22
    static let minPillWidth: CGFloat = 168
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
        // Pure live surface: the island is only present while recording and
        // collapses the moment the hotkey is released. Polishing/pasting happen
        // silently in the background (the menu bar still reflects them).
        switch coordinator.state {
        case .recording: return .live
        default:         return .hidden
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

    // MARK: Body

    private var isVisible: Bool { mode != .hidden }

    /// Collapsed, the island shrinks to exactly the notch footprint (notch width
    /// × menu-bar height), so it retracts *into* the notch and vanishes there —
    /// black-on-black, no opacity fade. Active, it widens and drops the content
    /// strip below the notch. Animating the geometry (not the alpha) is what
    /// makes release read as a smooth contraction instead of a flicker.
    private var displayedWidth: CGFloat {
        isVisible ? pillWidth : layout.geometry.notchWidth
    }
    private var displayedHeight: CGFloat {
        menuBar + (isVisible ? HUDMetrics.pillContentHeight : 0)
    }

    var body: some View {
        pill(content: islandContent)
            .frame(width: W, height: H, alignment: .top)
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: isVisible)
    }

    @ViewBuilder
    private var islandContent: some View {
        switch mode {
        case .live:
            liveContent
        case .status(let label):
            statusContent(label)
                .id(label) // cross-fade only when the label actually changes
        case .hidden:
            EmptyView()
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
    /// Width/height track `displayed*`, so the whole shape contracts up into the
    /// notch on release; the content strip is clipped as the pill collapses.
    private func pill<C: View>(content: C) -> some View {
        shape(radius: 9)
            .overlay {
                VStack(spacing: 0) {
                    // Clear the notch, then a small gap so content isn't jammed
                    // against the notch's bottom edge.
                    Spacer(minLength: 0)
                        .frame(height: menuBar + HUDMetrics.contentTopGap)
                    content
                        .frame(height: HUDMetrics.contentRowHeight)
                        .opacity(isVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.16), value: mode)
                    Spacer(minLength: 0) // padding below the content row
                }
                .frame(height: displayedHeight, alignment: .top)
                .clipped()
            }
            .frame(width: displayedWidth, height: displayedHeight)
            .position(x: W / 2, y: displayedHeight / 2)
    }

    // MARK: Content

    private var liveContent: some View {
        HStack(spacing: 5) {
            Text("InkIt")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            HUDWaveform(level: coordinator.inputLevel)
                .frame(width: 26, height: 6)
            Text("Live")
                .font(.system(size: 8, weight: .medium))
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
                    let t = phase + CGFloat(i) * 0.30
                    let wobble = (sin(t * .pi * 2) + 1) / 2
                    // Punch up quiet input and widen the per-bar swing so the
                    // waveform reads as lively rather than a faint shimmer.
                    let loudness = CGFloat(min(1, max(0.18, level * 1.7)))
                    let height = 2 + (geo.size.height - 2) * loudness * (0.12 + 0.88 * wobble)
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.95))
                        .frame(width: 2.6, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
