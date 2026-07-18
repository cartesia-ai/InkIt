import SwiftUI
import AppKit
import Combine

private enum HUDMetrics {
    static let windowWidth: CGFloat = 520
    static let contentTopGap: CGFloat = 0
    static let contentRowHeight: CGFloat = 12
    static let contentBottomPad: CGFloat = 4
    static let pillContentHeight: CGFloat = contentTopGap + contentRowHeight + contentBottomPad
    static let pillOverhang: CGFloat = 14
    static let minPillWidth: CGFloat = 150

    static let floatingTopGap: CGFloat = 3
    static let floatingHeight: CGFloat = 22
    static let floatingHPad: CGFloat = 12
    static let floatingShadowPad: CGFloat = 16
}

struct NotchGeometry: Equatable {
    var centerX: CGFloat
    var notchWidth: CGFloat
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
        return NotchGeometry(
            centerX: frame.midX,
            notchWidth: 180,
            menuBarHeight: 24,
            hasPhysicalNotch: false
        )
    }

    var hudWindowHeight: CGFloat {
        hasPhysicalNotch
            ? menuBarHeight + HUDMetrics.pillContentHeight
            : menuBarHeight + HUDMetrics.floatingTopGap + HUDMetrics.floatingHeight + HUDMetrics.floatingShadowPad
    }
}

@MainActor
final class HUDLayout: ObservableObject {
    @Published var geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}

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
        NSSize(width: HUDMetrics.windowWidth, height: layout.geometry.hudWindowHeight)
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

private enum HUDPresentation: Equatable {
    case hidden
    case live
    case status(String)
    case notice(String)
    case errorNotice(String)
}

private struct NotchHUDView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var layout: HUDLayout

    private var mode: HUDPresentation {
        switch coordinator.state {
        case .recording:        return .live
        case .heldInHistory:    return .notice("Saved to History")
        case .error(let m):     return .errorNotice(m)
        default:                return .hidden
        }
    }

    private var menuBar: CGFloat { layout.geometry.menuBarHeight }
    private var W: CGFloat { HUDMetrics.windowWidth }
    private var H: CGFloat { layout.geometry.hudWindowHeight }

    private var pillWidth: CGFloat {
        max(layout.geometry.notchWidth + HUDMetrics.pillOverhang * 2, HUDMetrics.minPillWidth)
    }

    private var isVisible: Bool { mode != .hidden }

    private var displayedWidth: CGFloat {
        isVisible ? pillWidth : layout.geometry.notchWidth
    }
    private var displayedHeight: CGFloat {
        menuBar + (isVisible ? HUDMetrics.pillContentHeight : 0)
    }

    var body: some View {
        Group {
            if layout.geometry.hasPhysicalNotch {
                pill(content: islandContent)
            } else {
                floatingIsland
            }
        }
        .frame(width: W, height: H, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: isVisible)
    }

    @ViewBuilder
    private var floatingIsland: some View {
        Group {
            if isVisible {
                islandContent
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, HUDMetrics.floatingHPad)
                    .frame(height: HUDMetrics.floatingHeight)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.black)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
                            )
                            .shadow(color: Elevation.modal, radius: 9, y: 4)
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.top, menuBar + HUDMetrics.floatingTopGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var islandContent: some View {
        switch mode {
        case .live:
            liveContent
        case .status(let label):
            statusContent(label)
                .id(label)
        case .notice(let label):
            noticeContent(label: label)
                .id(label)
        case .errorNotice(let label):
            errorNoticeContent(label: label)
                .id(label)
        case .hidden:
            EmptyView()
        }
    }

    private func shape(radius: CGFloat) -> some View {
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

    private func pill<C: View>(content: C) -> some View {
        shape(radius: 9)
            .overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(height: menuBar + HUDMetrics.contentTopGap)
                    content
                        .frame(height: HUDMetrics.contentRowHeight)
                        .opacity(isVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.16), value: mode)
                    Spacer(minLength: 0)
                }
                .frame(height: displayedHeight, alignment: .top)
                .clipped()
            }
            .frame(width: displayedWidth, height: displayedHeight)
            .position(x: W / 2, y: displayedHeight / 2)
    }

    private var liveContent: some View {
        HStack(spacing: 7) {
            Text("InkIt")
                .font(.inkNotchBrand)
                .foregroundStyle(.white.opacity(0.85))
            Group {
                if coordinator.audioReady {
                    HUDWaveform(level: coordinator.inputLevel)
                } else {
                    HUDPreparingDot()
                }
            }
            .frame(width: 32, height: 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(Motion.state, value: coordinator.audioReady)
    }

    private func statusContent(_ label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
                .scaleEffect(0.7)
            Text(label)
                .font(.inkNotchLabel)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func noticeContent(label: String) -> some View {
        HStack(spacing: 5) {
            Text("InkIt")
                .font(.inkNotchBrand)
                .foregroundStyle(.white.opacity(0.85))
            Text("•")
                .font(.inkNotchBrand)
                .foregroundStyle(.white.opacity(0.4))
            Text(label)
                .font(.inkNotchLabel)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func errorNoticeContent(label: String) -> some View {
        HStack(spacing: 5) {
            Text("InkIt")
                .font(.inkNotchBrand)
                .foregroundStyle(.white.opacity(0.85))
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(Color(nsColor: .systemRed))
            Text(label)
                .font(.inkNotchLabel)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct HUDPreparingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.white.opacity(pulsing ? 0.85 : 0.35))
            .frame(width: 5, height: 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {  // ds-allow: bespoke breathing pulse
                    pulsing = true
                }
            }
    }
}

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

enum ScreenToastStyle: Equatable {
    case success, error
}

private struct ToastItem: Equatable {
    let message: String
    let style: ScreenToastStyle
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published fileprivate var item: ToastItem?
    private var clearWork: DispatchWorkItem?

    private init() {}

    func show(_ message: String, style: ScreenToastStyle) {
        withAnimation(Motion.state) {
            item = ToastItem(message: message, style: style)
        }
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Motion.state) { self?.item = nil }
        }
        clearWork = work
        let seconds: TimeInterval = style == .error ? 4.0 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let item = center.item {
                ToastCard(item: item)
                    .padding(16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
    }
}

private struct ToastCard: View {
    let item: ToastItem

    private var icon: String {
        item.style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
    private var tint: Color {
        item.style == .success ? .green : Color(nsColor: .systemRed)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(tint)
            Text(item.message)
                .font(.inkCallout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Elevation.chip, radius: 5, y: 2)
    }
}
