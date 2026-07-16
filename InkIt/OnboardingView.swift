import SwiftUI
import AppKit
import AVFoundation

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case apiKey
    case tryIt
    case done
}

struct OnboardingRootView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var permissions = PermissionsService.shared
    @State private var step: OnboardingStep = {
        let key = "resumeOnboardingAtPermissions"
        if UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.removeObject(forKey: key)
            return .permissions
        }
        return .welcome
    }()
    @State private var direction: Int = 1

    private let dotsTopInset: CGFloat = 40
    private let dotsBandHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper
                .ignoresSafeArea()

            Group {
                switch step {
                case .welcome:     WelcomeStep(next: next)
                case .permissions: PermissionsStep(next: next)
                case .apiKey:      APIKeyStep(next: next)
                case .tryIt:       TryItStep(next: next)
                case .done:        DoneStep(finish: finish)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
            ))
            .id(step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 72)
            .padding(.top, dotsTopInset + dotsBandHeight)
            .padding(.bottom, 56)

            StepIndicator(step: step, isReachable: isReachable, go: go)
                .padding(.top, dotsTopInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func next() {
        guard let idx = OnboardingStep.allCases.firstIndex(of: step),
              idx + 1 < OnboardingStep.allCases.count else { return }
        direction = 1
        withAnimation(Motion.step) {
            step = OnboardingStep.allCases[idx + 1]
        }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
    }

    private func go(to target: OnboardingStep) {
        guard target != step, isReachable(target) else { return }
        direction = target.rawValue > step.rawValue ? 1 : -1
        withAnimation(Motion.step) {
            step = target
        }
    }

    private func isComplete(_ s: OnboardingStep) -> Bool {
        switch s {
        case .welcome, .tryIt, .done:
            return true
        case .permissions:
            return permissions.hasMicrophone && permissions.hasAccessibility
        case .apiKey:
            return !settings.cartesiaAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func isReachable(_ s: OnboardingStep) -> Bool {
        OnboardingStep.allCases
            .filter { $0.rawValue < s.rawValue }
            .allSatisfy(isComplete)
    }
}

// MARK: - Step indicator

private struct StepIndicator: View {
    let step: OnboardingStep
    let isReachable: (OnboardingStep) -> Bool
    let go: (OnboardingStep) -> Void

    // Page dots: reached steps filled, upcoming hollow. Only the fill changes.
    private let dot: CGFloat = 9      // dot diameter
    private let slot: CGFloat = 26    // pitch + hit target

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                StepDot(
                    isFilled: s.rawValue <= step.rawValue,
                    tappable: s != step && isReachable(s),
                    dot: dot,
                    slot: slot
                ) { go(s) }
            }
        }
        .animation(Motion.step, value: step)
    }
}

private struct StepDot: View {
    let isFilled: Bool
    let tappable: Bool
    let dot: CGFloat
    let slot: CGFloat
    let go: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1.5)
                .opacity(isFilled ? 0 : 1)
            Circle()
                .fill(Color.accentColor)
                .opacity(isFilled ? 1 : 0)
        }
        .brightness(tappable && hovering ? -Hover.fillShift : 0)
        .frame(width: dot, height: dot)
        .animation(Hover.animation, value: hovering)
        .frame(width: slot, height: slot)
        .contentShape(Rectangle())
        .onHover { hovering = tappable && $0 }
        .onTapGesture(perform: go)
        .modifier(ConditionalPointer(active: tappable))
    }
}

private struct ConditionalPointer: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.modifier(PointingHandCursor())
        } else {
            content
        }
    }
}

private struct WelcomeStep: View {
    let next: () -> Void
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: Elevation.lifted, radius: 12, y: 6)
                .scaleEffect(pulse ? 1.0 : 0.94)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        pulse = true
                    }
                }

            VStack(spacing: 8) {
                Text("Welcome to InkIt")
                    .font(.inkLargeTitle)
                    .foregroundStyle(Color.inkText)
                Text("Think out loud. Ink it.")
                    .font(.title3)
                    .foregroundStyle(Color.inkSub)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                BenefitRow(
                    icon: "bolt.fill",
                    title: "Faster than your keyboard",
                    subtitle: "Words land the instant you stop talking."
                )
                BenefitRow(
                    icon: "ear",
                    title: "Built for the real world",
                    subtitle: "Cafés, calls, open offices. It hears you over the noise."
                )
                BenefitRow(
                    icon: "paperplane.fill",
                    title: "Send it as-is",
                    subtitle: "No re-reading. No cleanup. Just send."
                )
            }
            .frame(maxWidth: 560)

            PrimaryButton(title: "Get started", action: next)
                .padding(.top, 2)
        }
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            GlyphTile(icon: icon, size: 48, corner: 13, iconSize: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Color.inkText)
                Text(subtitle).font(.body).foregroundStyle(Color.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(Color.line, lineWidth: 1)
        )
    }
}

private struct PermissionsStep: View {
    let next: () -> Void
    @StateObject private var permissions = PermissionsService.shared

    var bothGranted: Bool { permissions.hasMicrophone && permissions.hasAccessibility }

    var body: some View {
        VStack(spacing: 28) {
            HeaderBlock(
                icon: "waveform",
                title: "Speak anywhere, paste everywhere",
                subtitle: "InkIt only wakes up while you hold the key. Nothing is captured or sent otherwise."
            )

            VStack(spacing: 12) {
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "So InkIt can hear you.",
                    state: permissions.microphoneState,
                    manualWhy: "This is how InkIt hears you. Without it, there’s nothing to transcribe.",
                    settingsPath: "Privacy & Security ▸ Microphone",
                    enable: { permissions.requestMicrophone { _ in } },
                    openSettings: { permissions.openMicrophoneSettings() }
                )

                PermissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    subtitle: "So InkIt can type for you.",
                    state: permissions.accessibilityState,
                    manualWhy: "This is how InkIt types into whatever app you’re in. Without it, dictation has nowhere to land.",
                    settingsPath: "Privacy & Security ▸ Accessibility",
                    enable: { permissions.requestAccessibility() },
                    openSettings: { permissions.openAccessibilitySettings() }
                )
            }
            .frame(maxWidth: 560)

            if bothGranted {
                PrimaryButton(title: "Continue", action: next)
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
    let state: PermissionState
    let manualWhy: String
    let settingsPath: String
    let enable: () -> Void
    let openSettings: () -> Void

    var manual: Bool { state == .needsManual }

    var body: some View {
        Group {
            if manual {
                manualBody
            } else {
                defaultRow
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(manual ? Color.accentSoft : Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(manual ? Color.accentColor.opacity(0.4) : Color.line,
                        lineWidth: 1)
        )
    }

    private var defaultRow: some View {
        HStack(spacing: 14) {
            GlyphTile(icon: icon, size: 48, corner: 13, iconSize: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Color.inkText)
                Text(subtitle).font(.body).foregroundStyle(Color.inkSub)
            }
            Spacer()
            if state == .granted {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Enable", action: enable)
                    .buttonStyle(InkButtonStyle(compact: true))
                    .modifier(PointingHandCursor())
            }
        }
    }

    private var manualBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                GlyphTile(icon: icon, size: 48, corner: 13, iconSize: 22,
                          fill: Color.accentColor.opacity(0.22))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(Color.inkText)
                    Text("Finish in System Settings")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.inkSub)
                }
                Spacer()
            }

            Text(manualWhy)
                .font(.body)
                .foregroundStyle(Color.inkSub)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ManualStep(number: 1, prefix: "Open ", emphasis: settingsPath)
                ManualStep(number: 2, prefix: "Turn on ", emphasis: title)
            }

            Button("Open System Settings", action: openSettings)
                .buttonStyle(InkButtonStyle(compact: true))
                .modifier(PointingHandCursor())
        }
    }
}

private struct ManualStep: View {
    let number: Int
    let prefix: String
    let emphasis: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.inkEyebrow)
                .foregroundStyle(.black.opacity(0.85))  // ds-allow: legible numeral on the amber badge
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(prefix + emphasis)
                .font(.body)
                .foregroundStyle(Color.inkText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct KeyValidationLabel: View {
    let state: APIKeyValidator.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .verified:
            label("checkmark.circle.fill", "Verified", .green)
        case .invalidKey:
            label("xmark.circle.fill", "Invalid key", .red)
        case .couldNotVerify:
            label("exclamationmark.circle", "Couldn’t verify",
                  Color.inkSub)
        }
    }

    private func label(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(color)
        .fixedSize()
    }
}

private struct APIKeyStep: View {
    let next: () -> Void
    @EnvironmentObject var settings: SettingsStore
    @FocusState private var fieldFocused: Bool
    @StateObject private var validator = CartesiaKeyValidator()

    private var trimmedKey: String {
        settings.cartesiaAPIKey.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 22) {
            HeaderBlock(
                icon: "key.fill",
                title: "Turn on the engine",
                subtitle: "Fast and accurate dictation that just works."
            )

            VStack(alignment: .leading, spacing: 8) {
                keyField

                ExternalLink(
                    title: "Get your free Cartesia API key",
                    url: URL(string: "https://play.cartesia.ai/keys")!,
                    font: .subheadline.weight(.medium)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 18)
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: 460)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "gift")
                    .font(.system(size: 13))  // ds-allow: icon
                    .foregroundStyle(Color.inkFaint)
                Text("About 15,000 words of dictation a month, free with your Cartesia key. Powered by Cartesia Ink-2.")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(.horizontal, 2)

            PrimaryButton(
                title: "Continue",
                enabled: !trimmedKey.isEmpty,
                action: next
            )
        }
        .onAppear { validator.keyChanged(settings.cartesiaAPIKey) }
        .onChange(of: settings.cartesiaAPIKey) { _, newValue in
            validator.keyChanged(newValue)
        }
    }

    private var keyField: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 15))  // ds-allow: icon
                .foregroundStyle(Color.inkSub)

            SecureField("sk_car_…", text: $settings.cartesiaAPIKey)
                .textFieldStyle(.plain)
                .font(.inkMono)
                .focused($fieldFocused)

            KeyValidationLabel(state: validator.state)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: validator.state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .stroke(
                    fieldFocused ? Color.accentColor : Color.line,
                    lineWidth: fieldFocused ? 2 : 1
                )
        )
        .shadow(color: Elevation.drop, radius: 12, x: 0, y: 5)
        .animation(.easeInOut(duration: 0.15), value: fieldFocused)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

}

private struct TryItStep: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text("Try it")
                    .font(.inkLargeTitle)
                    .foregroundStyle(Color.inkText)
                Text("Hold the key, read the line aloud, then let go.")
                    .font(.title3)
                    .foregroundStyle(Color.inkSub)
                    .multilineTextAlignment(.center)
            }

            TryItPracticeCard(onSend: next)

            Button("Skip for now") { next() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Color.inkSub)
                .padding(.top, 2)
                .modifier(PointingHandCursor())
        }
    }
}

private struct DoneStep: View {
    let finish: () -> Void
    @State private var pop = false
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(Color.accentSoft).frame(width: 160, height: 160)
                Image(systemName: "sparkles")
                    .font(.system(size: 80))  // ds-allow: icon
                    .foregroundStyle(Color.accentColor)
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
                    .font(.inkLargeTitle)
                    .foregroundStyle(Color.inkText)
                Text("Type with your voice. Hold Fn and go.")
                    .font(.title3)
                    .foregroundStyle(Color.inkSub)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Start using InkIt", action: finish)
        }
    }
}

private struct GlyphTile: View {
    let icon: String
    var size: CGFloat = 84
    var corner: CGFloat = 22
    var iconSize: CGFloat = 36
    var fill: Color = Color.accentSoft

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(fill)
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct HeaderBlock: View {
    let icon: String
    let title: String
    let subtitle: AnyView

    init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = AnyView(
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(Color.inkSub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        )
    }

    init<V: View>(icon: String, title: String, @ViewBuilder subtitle: () -> V) {
        self.icon = icon
        self.title = title
        self.subtitle = AnyView(
            subtitle()
                .frame(maxWidth: 560)
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            GlyphTile(icon: icon)
            Text(title)
                .font(.inkLargeTitle)
                .foregroundStyle(Color.inkText)
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
                .frame(minWidth: 120)
        }
        .buttonStyle(InkButtonStyle())
        .disabled(!enabled)
        .modifier(PointingHandCursor())
    }
}

struct InkButtonStyle: ButtonStyle {
    enum Variant { case ink, destructive, accent }

    var variant: Variant = .ink
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, variant: variant, compact: compact)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var fill: Color {
            switch variant {
            case .ink:         return Color("InkFill")
            case .destructive: return .inkDanger
            case .accent:      return .accentColor
            }
        }

        private var textColor: Color {
            switch variant {
            case .ink:         return Color("InkFillText")
            case .destructive: return .white  // ds-allow: legible label on the red destructive fill
            case .accent:      return .white  // ds-allow: white label on the amber accent fill, matching the accent CTA
            }
        }

        var body: some View {
            configuration.label
                .font(compact ? .inkCalloutEmphasized : .inkBodyEmphasized)
                .foregroundStyle(textColor)
                .padding(.horizontal, compact ? 14 : 26)
                .padding(.vertical, compact ? 6 : 11)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                        .fill(fill)
                        .brightness(hovering && isEnabled ? Hover.fillShift : 0)
                        .opacity(configuration.isPressed ? 0.82 : 1)
                        .animation(Hover.animation, value: hovering)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct InkSecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, compact: compact)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(compact ? .inkCalloutEmphasized : .inkBodyEmphasized)
                .foregroundStyle(Color.inkSub)
                .padding(.horizontal, compact ? 14 : 26)
                .padding(.vertical, compact ? 6 : 11)
                .opacity(configuration.isPressed ? 0.55 : (hovering ? 0.75 : 1))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(Hover.animation, value: hovering)
        }
    }
}
