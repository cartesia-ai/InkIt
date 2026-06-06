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
            Color.paper
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
                    .font(.inkLargeTitle)
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
                .fill(Color.card)
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
                    state: permissions.microphoneState,
                    deniedWhy: "This is how InkIt hears you. Without microphone access, there’s nothing for InkIt to transcribe. Let’s turn it back on.",
                    settingsPath: "Privacy & Security ▸ Microphone",
                    enable: { permissions.requestMicrophone { _ in } },
                    openSettings: { permissions.openMicrophoneSettings() }
                )

                PermissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    subtitle: "So your words paste instantly, right at your cursor.",
                    state: permissions.accessibilityState,
                    deniedWhy: "This is how InkIt types your words straight into whatever app you’re in. Without it, your dictation has nowhere to land. Let’s turn it back on.",
                    settingsPath: "Privacy & Security ▸ Accessibility",
                    enable: { permissions.requestAccessibility() },
                    // Re-route through requestAccessibility so InkIt stays pre-added
                    // to the Accessibility list (toggle present, just off).
                    openSettings: { permissions.requestAccessibility() }
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
    /// Friendly one-liner explaining why the permission is required, shown only
    /// in the `needsManual` state.
    let deniedWhy: String
    /// The System Settings pane to send the user to, e.g.
    /// "Privacy & Security ▸ Accessibility".
    let settingsPath: String
    /// Fire the system TCC prompt (only meaningful in `notRequested`).
    let enable: () -> Void
    /// Jump straight to the relevant System Settings pane (the `needsManual`
    /// action — never re-fires the prompt).
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(manual ? Color.accentSoft : Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(manual ? Color.accentColor.opacity(0.4) : Color(nsColor: .separatorColor),
                        lineWidth: 1)
        )
    }

    private var defaultRow: some View {
        HStack(spacing: 14) {
            GlyphTile(icon: icon, size: 48, corner: 13, iconSize: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.body).foregroundStyle(.secondary)
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
                // Stronger amber tile so the glyph reads against the tinted card.
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Label("Just one more step to start dictating",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }

            Text(deniedWhy)
                .font(.body)
                .foregroundStyle(.secondary)
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

/// A numbered instruction line — amber badge + "prefix **emphasis**" text — used
/// in the permission card's manual-fix state.
private struct ManualStep: View {
    let number: Int
    let prefix: String
    let emphasis: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            (Text(prefix) + Text(emphasis).fontWeight(.semibold))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                .fill(Color.card)
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

    @State private var invite = false
    /// Once the user has held the key even once, the inviting glow ring retires —
    /// it exists only to prompt the very first press, and pulsing forever reads
    /// as distracting after that.
    @State private var hasPressed = false
    /// Staged reveal: the screen lands showing only the line to read; the key cap
    /// and result box fade in ~1s later. In testing, people grabbed the key before
    /// noticing the prompt — holding the loud controls back until the eye has had
    /// a beat on the line fixes the order without adding steps. Faded in place
    /// (space reserved) so the panel never changes height.
    @State private var revealed = false
    /// The editable contents of the result box. Seeded from the live transcript
    /// while dictating, then fully the user's to edit by keyboard afterward —
    /// the whole point being that a mistranscription is fixable in place.
    @State private var editedText = ""
    @FocusState private var boxFocused: Bool

    var isRecording: Bool { coordinator.state == .recording }
    var isFinalizing: Bool {
        switch coordinator.state {
        case .finalizing, .rewriting, .pasting: return true
        default: return false
        }
    }
    var transcript: String { coordinator.liveTranscript }
    /// There's text to send and we're not mid-take.
    var isComplete: Bool {
        !isRecording && !isFinalizing
            && !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text("Try it")
                    .font(.inkLargeTitle)
                    .foregroundStyle(.primary)
                Text(revealed
                     ? "Hold the key, read the line aloud, then let go."
                     : "Read this line aloud…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }

            panel

            Button("Skip for now") { next() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .modifier(PointingHandCursor())
        }
        .onAppear {
            coordinator.beginOnboardingTrial()
            // Hold the key cap + result box back for a beat so the eye lands on the
            // line first, then fade them in and drop the cursor into the box.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.45)) { revealed = true }
                boxFocused = true
            }
        }
        .onDisappear {
            coordinator.endOnboardingTrial()
            // Persist what the user produced here so Home isn't empty the first
            // time they open it. Logged once on the way out (send or skip-after-
            // trying), using the box's final — possibly hand-edited — text. The
            // trial is verbatim, so it's an `.off` entry with no latency/diff.
            let final = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !final.isEmpty {
                TranscriptHistoryStore.shared.add(final, polish: .off)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                hasPressed = true
                // Safety: if they press before the timed reveal, snap everything in
                // so their words have somewhere to land — never a blank panel.
                if !revealed { withAnimation(.easeOut(duration: 0.3)) { revealed = true } }
            }
        }
        // Mirror the transcript into the editable field as it streams in and when
        // it finalizes. liveTranscript only changes during a take, so the user's
        // manual edits afterward are never clobbered.
        .onChange(of: transcript) { _, newValue in
            editedText = newValue
        }
    }

    // MARK: Unified panel — prompt, the key, and the result in one calm card.
    // The waveform and live status now live in the real Notch HUD (shown during
    // the trial), so the screen itself stays quiet: read the line, hold the key,
    // watch the words land here.

    private var panel: some View {
        VStack(spacing: 28) {
            promptBar
            keyCap
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 8)
            resultBox
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 8)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 30)
        .frame(maxWidth: 600)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    // MARK: Prompt — the line to read aloud, marked by a quiet left accent bar

    private var promptBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("READ THIS ALOUD")
                .font(.inkEyebrow)
                .tracking(0.8)
                .foregroundStyle(Color.accentColor)
            // Wrapped in curly quotes so it reads as a spoken line, with a larger
            // size and looser leading to give the prompt room to breathe.
            Text("\u{201C}\(sampleLine)\u{201D}")
                .font(.system(size: 17, weight: .medium))
                .lineSpacing(5)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3)
        }
    }

    // MARK: Result — a real editable field. Lands focused (cursor already in it),
    // fills from the transcript, and stays fully keyboard-editable so a
    // mistranscription can be fixed in place before sending.

    private var resultBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                Text("What InkIt heard")
                    .font(.inkEyebrow)
                    .foregroundStyle(.tertiary)
            }
            ZStack(alignment: .topLeading) {
                if editedText.isEmpty {
                    Text("Your words appear here after you let go.")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $editedText)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .tint(Color.accentColor)
                    .focused($boxFocused)
                    .frame(minHeight: 72)
            }
            HStack {
                Spacer()
                sendButton
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(boxFocused ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                        lineWidth: boxFocused ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: boxFocused)
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
        .opacity(isComplete ? 1 : 0.3)
        .scaleEffect(isComplete ? 1 : 0.9)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isComplete)
        .modifier(PointingHandCursor())
    }

    // MARK: Push-to-talk key — the hero control

    private var keyCap: some View {
        HStack(spacing: 12) {
            if isRecording {
                Circle()
                    .fill(Color.recordingAmber)
                    .frame(width: 13, height: 13)
                    .shadow(color: Color.recordingAmber.opacity(0.7), radius: 5)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 19))
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
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 26).padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isRecording ? Color.accentSoft : Color.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isRecording ? Color.recordingAmber : Color(nsColor: .separatorColor),
                        lineWidth: 1.5)
        )
        .scaleEffect(isRecording ? 0.97 : 1)
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .overlay(inviteRing.opacity(showInvite ? 1 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isRecording)
        .animation(.easeOut(duration: 0.4), value: showInvite)
    }

    /// The glow only invites the *first* press — once `hasPressed` flips it never
    /// returns, and it's always hidden while actively recording.
    private var showInvite: Bool { revealed && !hasPressed && !isRecording }

    private var inviteRing: some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(-6)
            .scaleEffect(invite ? 1.09 : 0.97)
            .opacity(invite ? 0 : 0.5)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 2.1).repeatForever(autoreverses: false)) {
                    invite = true
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
                    .font(.inkLargeTitle)
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
                .font(.inkLargeTitle)
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
