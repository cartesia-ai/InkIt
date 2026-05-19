import SwiftUI
import AppKit
import AVFoundation

private struct PointingHandCursor: ViewModifier {
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

// MARK: - Root

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case apiKey
    case fnIntro
    case tryIt
    case done

    var accent: [Color] {
        switch self {
        case .welcome:     return [Color(red: 0.45, green: 0.36, blue: 0.95), Color(red: 0.92, green: 0.41, blue: 0.78)]
        case .permissions: return [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.30, green: 0.85, blue: 0.85)]
        case .apiKey:      return [Color(red: 0.95, green: 0.50, blue: 0.30), Color(red: 0.95, green: 0.78, blue: 0.36)]
        case .fnIntro:     return [Color(red: 0.30, green: 0.78, blue: 0.55), Color(red: 0.55, green: 0.92, blue: 0.78)]
        case .tryIt:       return [Color(red: 0.92, green: 0.36, blue: 0.55), Color(red: 0.62, green: 0.36, blue: 0.92)]
        case .done:        return [Color(red: 0.36, green: 0.85, blue: 0.62), Color(red: 0.36, green: 0.62, blue: 0.95)]
        }
    }
}

struct OnboardingRootView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var step: OnboardingStep = {
        // If we just silently relaunched mid-onboarding to pick up a fresh
        // Accessibility grant, resume at the permissions step.
        let key = "resumeOnboardingAtPermissions"
        if UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.removeObject(forKey: key)
            return .permissions
        }
        return .welcome
    }()
    @State private var direction: Int = 1

    var body: some View {
        ZStack {
            // Animated gradient background that morphs per step.
            LinearGradient(colors: step.accent, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: step)

            // Subtle blurred orbs for depth.
            GeometryReader { geo in
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 360, height: 360)
                    .blur(radius: 80)
                    .offset(x: -120, y: -80)
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: geo.size.width - 180, y: geo.size.height - 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                StepIndicator(step: step).padding(.top, 28)

                Spacer(minLength: 0)

                Group {
                    switch step {
                    case .welcome:     WelcomeStep(next: next)
                    case .permissions: PermissionsStep(next: next)
                    case .apiKey:      APIKeyStep(next: next)
                    case .fnIntro:     FnIntroStep(next: next)
                    case .tryIt:       TryItStep(next: next)
                    case .done:        DoneStep(finish: finish)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
                .id(step)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 56)
            .padding(.bottom, 36)
        }
        .frame(width: 720, height: 560)
        .preferredColorScheme(.dark)
    }

    private func next() {
        guard let idx = OnboardingStep.allCases.firstIndex(of: step),
              idx + 1 < OnboardingStep.allCases.count else { return }
        direction = 1
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            step = OnboardingStep.allCases[idx + 1]
        }
    }

    private func finish() {
        // Flipping the flag causes RootView to swap from OnboardingRootView to
        // MainWindowView in the same WindowGroup window — no need to close.
        settings.hasCompletedOnboarding = true
    }
}

// MARK: - Step indicator

private struct StepIndicator: View {
    let step: OnboardingStep
    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(.white.opacity(s.rawValue <= step.rawValue ? 0.95 : 0.28))
                    .frame(width: s == step ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
            }
        }
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    let next: () -> Void
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 160, height: 160)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(.white)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            VStack(spacing: 10) {
                Text("Welcome to InkIt")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Hold a key. Speak. Watch the text appear.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
            }

            PrimaryButton(title: "Get started", action: next)
                .padding(.top, 6)
        }
    }
}

// MARK: - Permissions

private struct PermissionsStep: View {
    let next: () -> Void
    @StateObject private var permissions = PermissionsService.shared

    var bothGranted: Bool { permissions.hasMicrophone && permissions.hasAccessibility }

    var body: some View {
        VStack(spacing: 28) {
            HeaderBlock(
                icon: "lock.shield.fill",
                title: "A couple of permissions",
                subtitle: "InkIt needs your mic to hear you, and Accessibility to paste the result."
            )

            VStack(spacing: 12) {
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Awake when the hotkey is pressed. Asleep otherwise.",
                    granted: permissions.hasMicrophone
                ) {
                    permissions.requestMicrophone { _ in }
                }

                PermissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    subtitle: "See your words instantly appear right at your cursor.",
                    granted: permissions.hasAccessibility
                ) {
                    permissions.requestAccessibility()
                }
            }
            .frame(maxWidth: 480)

            if bothGranted {
                PrimaryButton(title: "Continue", action: next)
            } else {
                VStack(spacing: 8) {
                    Text("Grant both to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))

                    if !permissions.hasAccessibility {
                        Button("I granted Accessibility") {
                            permissions.confirmAccessibilityGrant()
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.18)))

                        Text("Grant access to this copy:\n\(permissions.appIdentityDescription)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                }
                .padding(.top, 6)
            }
        }
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Granted")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(.green.opacity(0.85)))
            } else {
                Button(action: action) {
                    Text("Grant")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.95)))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.12))
        )
    }
}

// MARK: - API key

private struct APIKeyStep: View {
    let next: () -> Void
    @EnvironmentObject var settings: SettingsStore
    @State private var showKey = false

    var body: some View {
        VStack(spacing: 26) {
            HeaderBlock(
                icon: "key.fill",
                title: "Connect Cartesia",
                subtitle: "Paste your Cartesia API key. Stored locally on this Mac only."
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Group {
                        if showKey {
                            TextField("sk-cartesia-…", text: $settings.cartesiaAPIKey)
                        } else {
                            SecureField("sk-cartesia-…", text: $settings.cartesiaAPIKey)
                        }
                    }
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.95)))
                    .foregroundStyle(.black)

                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Capsule().fill(.white.opacity(0.2)))
                        .foregroundStyle(.white)
                }

                Link(destination: URL(string: "https://play.cartesia.ai/keys")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Get a Cartesia API key")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.95))
                }
                .modifier(PointingHandCursor())
            }
            .frame(maxWidth: 480)

            PrimaryButton(
                title: "Continue",
                enabled: !settings.cartesiaAPIKey.trimmingCharacters(in: .whitespaces).isEmpty,
                action: next
            )
        }
    }
}

// MARK: - Fn intro

private struct FnIntroStep: View {
    let next: () -> Void
    @State private var float = false

    var body: some View {
        VStack(spacing: 24) {
            HeaderBlock(
                icon: "globe",
                title: "Meet your push-to-talk key"
            ) {
                HStack(spacing: 8) {
                    Text("Hold")
                    KeycapLabel("Fn")
                    Text("to dictate. Release to stop.")
                }
                .frame(maxWidth: 480)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 140, height: 100)
                VStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 38, weight: .medium))
                    Text("fn").font(.headline)
                }
                .foregroundStyle(.white)
            }
            .offset(y: float ? -6 : 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    float = true
                }
            }

            PrimaryButton(title: "Let me try it", action: next)
        }
    }
}

// MARK: - Try it

private struct TryItStep: View {
    let next: () -> Void
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore

    private let sample = "The quick brown fox jumps over the lazy dog while the morning light spills across the desk."

    var isRecording: Bool { coordinator.state == .recording }
    var isFinalizing: Bool {
        if case .finalizing = coordinator.state { return true }
        if case .pasting = coordinator.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 22) {
            HeaderBlock(
                icon: "waveform",
                title: "Give it a try",
                subtitle: "Hold the Fn key and read this aloud."
            )

            // Sample paragraph card
            Text(sample)
                .font(.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(18)
                .frame(maxWidth: 560)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.12)))

            // Live waveform + status
            WaveformBar(level: coordinator.inputLevel, active: isRecording)
                .frame(width: 220, height: 44)

            statusBox

            HStack(spacing: 12) {
                Button("Skip") { next() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 10)

                PrimaryButton(title: "Continue", action: next)
            }
        }
        .onAppear {
            coordinator.beginOnboardingTrial()
        }
        .onDisappear {
            coordinator.endOnboardingTrial()
        }
    }

    @ViewBuilder
    private var statusBox: some View {
        let content: AnyView = {
            if isRecording {
                return AnyView(
                    Text("Keep holding Fn and speak.")
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                )
            } else if isFinalizing {
                return AnyView(
                    Text("Finalizing…")
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                )
            } else if !coordinator.liveTranscript.isEmpty {
                return AnyView(
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text(coordinator.liveTranscript)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
            } else {
                return AnyView(
                    Text("Press and hold Fn to start.")
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                )
            }
        }()

        content
            .font(.body)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 560, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.25))
            )
    }
}

private struct WaveformBar: View {
    let level: Float
    let active: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { i in
                    let t = (CGFloat(i) / 24) + phase
                    let wobble = (sin(t * .pi * 2) + 1) / 2
                    let lvl = CGFloat(max(0.08, level)) * (0.5 + 0.5 * wobble)
                    Capsule()
                        .fill(.white)
                        .frame(width: 4, height: max(4, geo.size.height * lvl))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(active ? 1 : 0.4)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

private struct KeycapLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

// MARK: - Done

private struct DoneStep: View {
    let finish: () -> Void
    @State private var pop = false
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(.white.opacity(0.2)).frame(width: 160, height: 160)
                Image(systemName: "sparkles")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .scaleEffect(pop ? 1.0 : 0.7)
                    .opacity(pop ? 1 : 0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.05)) {
                    pop = true
                }
            }

            VStack(spacing: 10) {
                Text("You're ready!")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("InkIt lives in your menu bar. Hold Fn anytime to dictate.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Start using InkIt", action: finish)
        }
    }
}

// MARK: - Shared bits

private struct HeaderBlock: View {
    let icon: String
    let title: String
    let subtitle: AnyView

    init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = AnyView(
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        )
    }

    init<V: View>(icon: String, title: String, @ViewBuilder subtitle: () -> V) {
        self.icon = icon
        self.title = title
        self.subtitle = AnyView(
            subtitle()
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: 480)
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 84, height: 84)
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            subtitle
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(
                    Capsule().fill(.white.opacity(enabled ? 0.98 : 0.4))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }
}
