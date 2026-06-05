import SwiftUI
import AppKit
import AVFoundation

// MARK: - Root

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case apiKey
    case tryIt
    case polish
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
                    case .polish:      PolishStep(next: next)
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

/// Compact validation status shown inside the field's trailing edge — a glyph
/// plus a concise label so the verdict reads in place without a caption below.
/// Shared by both key steps since both validators expose the same
/// `APIKeyValidator.State`.
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
                  Color(nsColor: .secondaryLabelColor))
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
        VStack(spacing: 24) {
            HeaderBlock(
                icon: "key.fill",
                title: "Turn on the engine",
                subtitle: "Powered by Cartesia ink-2. Free to start."
            )

            VStack(alignment: .leading, spacing: 12) {
                keyField

                HStack(alignment: .firstTextBaseline) {
                    Link(destination: URL(string: "https://play.cartesia.ai/keys")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get your free Cartesia API key")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .modifier(PointingHandCursor())
                    Spacer(minLength: 0)
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
    /// taller and narrower than a system field, with a leading key glyph and the
    /// live validation status tucked inside the trailing edge. Always masked —
    /// the key is never rendered in plain text.
    private var keyField: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            SecureField("sk_car_…", text: $settings.cartesiaAPIKey)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .monospaced))
                .focused($fieldFocused)

            KeyValidationLabel(state: validator.state)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: validator.state)
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

}

// MARK: - Try it

private struct TryItStep: View {
    let next: () -> Void
    @EnvironmentObject var coordinator: AppCoordinator

    private let sampleLine = "Help me plan a slow Sunday full of pancakes, sunshine, and a long nap."

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
            VStack(spacing: 6) {
                Text("Try it")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Hold the key, read the line aloud, then let go.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            promptCard
            pushToTalk
            resultField

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

    // MARK: Prompt card — the line to read aloud, kept separate from the result

    private var promptCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\u{275D}")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentSoft))
            VStack(alignment: .leading, spacing: 4) {
                Text("READ THIS ALOUD")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.accentColor)
                Text(sampleLine)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: 540)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentSoft))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: Result field — the clean box the words land in after release

    private var resultField: some View {
        VStack(alignment: .leading, spacing: 10) {
            boxText
                .font(.system(size: 18))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)

            HStack {
                if isComplete {
                    Text("Looks right? Send it →")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                sendButton
            }
        }
        .padding(18)
        .frame(maxWidth: 540)
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

    /// Live transcript in solid ink with a blinking caret — empty until the user
    /// releases the key. The line to read lives in the prompt card above, so the
    /// box stays a clean result surface (matches the "Try it" prototype, option A).
    private var boxText: Text {
        var t = Text("")
        if !transcript.isEmpty {
            t = t + Text(transcript).foregroundStyle(.primary) + Text(" ")
        }
        t = t + Text("\u{258F}").foregroundStyle(caretOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
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

// MARK: - Polish (optional)

/// Optional final-mile step: offer the LLM "Polish transcripts" rewrite by
/// collecting a Groq key. Skippable — polish stays off unless a key is given.
/// Placed after Try-it so the accuracy demo there stays verbatim. Groq is
/// pinned as the recommended provider and the picker is hidden; switching
/// providers lives in Settings.
private struct PolishStep: View {
    let next: () -> Void
    @EnvironmentObject var settings: SettingsStore
    @State private var key: String = ""
    @FocusState private var fieldFocused: Bool
    @StateObject private var validator = GroqKeyValidator()

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 24) {
            HeaderBlock(
                icon: "wand.and.stars",
                title: "Polish as you speak",
                subtitle: "Your words in, polished text out — powered by Groq."
            )

            chips

            VStack(alignment: .leading, spacing: 12) {
                keyField

                HStack(alignment: .firstTextBaseline) {
                    Link(destination: LLMProvider.groq.keyURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get your free Groq API key")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .modifier(PointingHandCursor())
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 18)
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: 460)

            VStack(spacing: 14) {
                PrimaryButton(
                    title: "Continue",
                    enabled: !trimmedKey.isEmpty,
                    action: commit
                )
                Button("Skip for now") { next() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .modifier(PointingHandCursor())
            }
        }
        .onAppear {
            key = settings.apiKey(for: .groq)
            validator.keyChanged(key)
        }
        .onChange(of: key) { _, newValue in validator.keyChanged(newValue) }
    }

    /// Save the key and turn polish on. Never half-configured: we only flip
    /// `correctionEnabled` here, where a non-empty key is guaranteed.
    private func commit() {
        let k = trimmedKey
        guard !k.isEmpty else { next(); return }
        settings.setAPIKey(k, for: .groq)
        settings.enablePolish(provider: .groq)
        next()
    }

    /// Three at-a-glance value props, matching the accent-soft glyph treatment.
    private var chips: some View {
        HStack(spacing: 8) {
            PolishChip(icon: "scissors", text: "Removes filler")
            PolishChip(icon: "textformat", text: "Fixes punctuation")
            PolishChip(icon: "checkmark", text: "Repairs names")
        }
    }

    /// Same custom credential field as the Cartesia step, bound to the Groq key.
    /// Always masked — the key is never rendered in plain text.
    private var keyField: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            SecureField("gsk_…", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .monospaced))
                .focused($fieldFocused)

            KeyValidationLabel(state: validator.state)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: validator.state)
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
}

/// Accent-soft capsule with an SF Symbol + label — the Polish-step value props.
private struct PolishChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2.weight(.semibold))
            Text(text).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.accentSoft))
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
