import SwiftUI
import AppKit
import AVFoundation

// MARK: - Root

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
            // Calm, appearance-aware backdrop: a single solid warm-paper fill,
            // the same on every step (no gradient, no per-step rainbow).
            // See DESIGN_SYSTEM.md.
            Color("PaperBG")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StepIndicator(step: step)
                    .padding(.top, 40)

                Spacer(minLength: 56)

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

                Spacer(minLength: 56)
            }
            .padding(.horizontal, 72)
            .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .fill(s.rawValue <= step.rawValue
                          ? Color.accentColor
                          : Color.secondary.opacity(0.3))
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
        VStack(spacing: 24) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .scaleEffect(pulse ? 1.0 : 0.94)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        pulse = true
                    }
                }

            VStack(spacing: 8) {
                Text("Welcome to InkIt")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Think out loud. Ink it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
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

/// Icon + title + one-line benefit, in a quiet card — the Welcome value props.
private struct BenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            GlyphTile(icon: icon, size: 48, corner: 13, iconSize: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color("CardBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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
                icon: "waveform",
                title: "Speak anywhere, paste everywhere",
                subtitle: "InkIt only wakes up while you hold the key. Nothing is captured or sent otherwise."
            )

            VStack(spacing: 12) {
                PermissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "So InkIt can hear you. Asleep until you hold the key.",
                    granted: permissions.hasMicrophone
                ) {
                    permissions.requestMicrophone { _ in }
                }

                PermissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    subtitle: "So your words paste instantly, right at your cursor.",
                    granted: permissions.hasAccessibility
                ) {
                    permissions.requestAccessibility()
                }
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
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            GlyphTile(icon: icon, size: 48, corner: 13, iconSize: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.body).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Enable", action: action)
                    .buttonStyle(InkButtonStyle(compact: true))
                    .modifier(PointingHandCursor())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color("CardBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - API key

private struct APIKeyStep: View {
    let next: () -> Void
    @EnvironmentObject var settings: SettingsStore
    @State private var showKey = false
    @FocusState private var fieldFocused: Bool
    @StateObject private var validator = CartesiaKeyValidator()

    private var trimmedKey: String {
        settings.cartesiaAPIKey.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 24) {
            HeaderBlock(
                icon: "key.fill",
                title: "Turn on the engine",
                subtitle: "Powered by Cartesia ink-2. Your API key is stored locally on this Mac only."
            )

            VStack(alignment: .leading, spacing: 12) {
                keyField

                HStack(alignment: .firstTextBaseline) {
                    validationLabel
                        .animation(.easeInOut(duration: 0.2), value: validator.state)
                    Spacer(minLength: 16)
                    Link(destination: URL(string: "https://play.cartesia.ai/keys")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get a Cartesia API key")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .modifier(PointingHandCursor())
                }
                .frame(minHeight: 18)
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: 460)

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

    /// Custom credential field: CardBG container matching the rest of onboarding,
    /// taller and narrower than a system field, with a leading key glyph, the
    /// eye toggle and a live status icon tucked inside the trailing edge.
    private var keyField: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Group {
                if showKey {
                    TextField("sk_car_…", text: $settings.cartesiaAPIKey)
                } else {
                    SecureField("sk_car_…", text: $settings.cartesiaAPIKey)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15, design: .monospaced))
            .focused($fieldFocused)

            statusIcon
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: validator.state)

            Button {
                showKey.toggle()
            } label: {
                Image(systemName: showKey ? "eye.slash" : "eye")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .help(showKey ? "Hide API key" : "Show API key")
            .modifier(PointingHandCursor())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color("CardBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    fieldFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: fieldFocused ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: fieldFocused)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    /// Compact inline cue inside the field — mirrors the text status below it.
    @ViewBuilder
    private var statusIcon: some View {
        switch validator.state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .verified:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalidKey:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .couldNotVerify:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var validationLabel: some View {
        switch validator.state {
        case .idle:
            Text("Paste your key to verify it.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .verified:
            Label("Key verified", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        case .invalidKey:
            Label("Invalid API key. Double-check you copied the whole key.", systemImage: "xmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
        case .couldNotVerify:
            Label("Couldn’t verify — check your connection", systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Try it

private struct TryItStep: View {
    let next: () -> Void
    @EnvironmentObject var coordinator: AppCoordinator

    /// A real prompt a technical user might dictate to an AI assistant. Spoken
    /// numbers ("two thousand dollars", "five day") that ink-2 renders as
    /// "$2,000" / "5-day" are the at-a-glance accuracy flex — and it reads
    /// cleanly verbatim, since the LLM rewrite is off by default.
    private let sampleWords = "Plan a 5-day trip to Tokyo in April with a budget around $2,000."
        .split(separator: " ").map(String.init)

    /// Matches the HUD's recording dot/waveform color (see NotchHUD): amber is
    /// the app's "live recording" signal, distinct from the resting indigo.
    private static let recordingAmber = Color(red: 1.0, green: 0.62, blue: 0.04)

    @State private var caretOn = true
    @State private var invite = false
    private let caretTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var isRecording: Bool { coordinator.state == .recording }
    var isFinalizing: Bool {
        switch coordinator.state {
        case .finalizing, .rewriting, .pasting: return true
        default: return false
        }
    }
    var transcript: String { coordinator.liveTranscript }
    /// Released the key and got something back — ready to send.
    var isComplete: Bool { !isRecording && !isFinalizing && !transcript.isEmpty }

    var body: some View {
        VStack(spacing: 24) {
            Text("Your turn")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)

            composer
            pushToTalk

            Button("Skip for now") { next() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .modifier(PointingHandCursor())
        }
        .onAppear { coordinator.beginOnboardingTrial() }
        .onDisappear { coordinator.endOnboardingTrial() }
        .onReceive(caretTimer) { _ in caretOn.toggle() }
    }

    // MARK: Composer — the always-focused field the words land in

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            boxText
                .font(.system(size: 18))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)

            Divider()

            HStack {
                Text(isComplete ? "Looks right? Send it →" : "Anywhere you can type")
                    .font(.caption)
                    .foregroundStyle(isComplete ? Color.accentColor : Color.secondary)
                Spacer()
                sendButton
            }
        }
        .padding(18)
        .frame(maxWidth: 564)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("CardBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
        )
        .shadow(color: Color.accentColor.opacity(0.22), radius: 7)
    }

    /// Live transcript in solid ink, with the unread remainder of the sample
    /// trailing it in ghost gray and a blinking caret at the boundary — so the
    /// box is both the script and the result, no extra captions.
    private var boxText: Text {
        let spokenCount = transcript.isEmpty ? 0 : transcript.split(separator: " ").count
        let remaining = sampleWords.dropFirst(spokenCount).joined(separator: " ")
        var t = Text("")
        if !transcript.isEmpty {
            t = t + Text(transcript).foregroundStyle(.primary)
            if !remaining.isEmpty { t = t + Text(" ") }
        }
        t = t + Text("▏").foregroundStyle(caretOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
        if !remaining.isEmpty {
            t = t + Text(remaining).foregroundStyle(.tertiary)
        }
        return t
    }

    private var sendButton: some View {
        Button { if isComplete { next() } } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(!isComplete)
        .opacity(isComplete ? 1 : 0.35)
        .scaleEffect(isComplete ? 1 : 0.9)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isComplete)
        .modifier(PointingHandCursor())
    }

    // MARK: Push-to-talk — the hero control

    private var pushToTalk: some View {
        VStack(spacing: 14) {
            keyCap
            WaveformBar(level: coordinator.inputLevel, active: isRecording, tint: Self.recordingAmber)
                .frame(width: 200, height: 30)
                .opacity(isRecording ? 1 : 0.25)
            statusLine.frame(minHeight: 20)
        }
    }

    private var keyCap: some View {
        HStack(spacing: 12) {
            if isRecording {
                Circle()
                    .fill(Self.recordingAmber)
                    .frame(width: 13, height: 13)
                    .shadow(color: Self.recordingAmber.opacity(0.7), radius: 5)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 7) {
                Text("Hold")
                Text("fn")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentSoft))
                Text("to talk")
            }
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 32).padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isRecording ? Color.accentSoft : Color("CardBG"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isRecording ? Self.recordingAmber : Color(nsColor: .separatorColor),
                        lineWidth: 1.5)
        )
        .scaleEffect(isRecording ? 0.97 : 1)
        .shadow(color: .black.opacity(0.12), radius: isRecording ? 4 : 10, y: isRecording ? 2 : 6)
        .overlay(inviteRing.opacity(isRecording ? 0 : 1))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isRecording)
    }

    /// A soft pulsing ring while idle, to pull the eye to the key.
    private var inviteRing: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(-7)
            .scaleEffect(invite ? 1.1 : 0.97)
            .opacity(invite ? 0 : 0.5)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 2.1).repeatForever(autoreverses: false)) {
                    invite = true
                }
            }
    }

    @ViewBuilder
    private var statusLine: some View {
        if isRecording {
            Label("Listening… keep holding", systemImage: "circle.fill")
                .imageScale(.small)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.recordingAmber)
        } else if isFinalizing {
            Text("Finalizing…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if isComplete {
            Label("Heard you, word for word.", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Text("InkIt listens only while you hold the key.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WaveformBar: View {
    let level: Float
    let active: Bool
    var tint: Color = .accentColor
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { i in
                    let t = (CGFloat(i) / 24) + phase
                    let wobble = (sin(t * .pi * 2) + 1) / 2
                    let lvl = CGFloat(max(0.08, level)) * (0.5 + 0.5 * wobble)
                    Capsule()
                        .fill(tint)
                        .frame(width: 4, height: max(4, geo.size.height * lvl))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(active ? 1 : 0.35)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - Done

private struct DoneStep: View {
    let finish: () -> Void
    @State private var pop = false
    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(Color.accentSoft).frame(width: 160, height: 160)
                Image(systemName: "sparkles")
                    .font(.system(size: 80))
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
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
                Text("InkIt lives in your menu bar. Hold Fn anytime to dictate.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Start using InkIt", action: finish)
        }
    }
}

// MARK: - Shared bits

/// Accent-tinted rounded tile holding an SF Symbol — the recurring glyph
/// treatment across onboarding.
private struct GlyphTile: View {
    let icon: String
    var size: CGFloat = 84
    var corner: CGFloat = 22
    var iconSize: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.accentSoft)
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }
}

extension Color {
    /// Tinted indigo fill behind glyphs/badges. Appearance-aware (14% light /
    /// 18% dark) via the asset catalog so it matches DESIGN_SYSTEM.md exactly,
    /// instead of a flat `accentColor.opacity` that stays too faint in dark.
    static let accentSoft = Color("accentSoft")
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
                .foregroundStyle(.secondary)
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
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
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

/// The "ink" call-to-action: a solid navy fill with white text in light mode,
/// inverting to a warm off-white fill with navy text in dark — the pen color
/// from the app icon. The amber accent stays reserved for live-signal cues
/// (selection, links, the waveform), per DESIGN_SYSTEM.md.
private struct InkButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(Color("InkFillText"))
            .padding(.horizontal, compact ? 14 : 26)
            .padding(.vertical, compact ? 6 : 11)
            .background(
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(Color("InkFill"))
                    .opacity(configuration.isPressed ? 0.82 : 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}
