import SwiftUI

/// The shared practice card behind onboarding's "Try it" step and the Home empty
/// state. Read the highlighted line, hold the key, watch the words land in an
/// editable box, fix a mistranscription, then send. The card is identical in both
/// places — only the surrounding header/footer differ, so each parent supplies
/// those and this owns everything inside (and around) the rounded panel.
///
/// Lifecycle and history logging live here so the two call sites stay thin:
///   • onAppear  → `beginOnboardingTrial` + the staged reveal (line first, then
///     the key cap and box fade in a beat later, so the eye lands on the prompt).
///   • send / onDisappear → the take is persisted to history (verbatim, `.off`),
///     carrying the trial's transcribe latency. Logging is idempotent.
/// `onSend` is the only place the parent gets to react to an explicit send:
/// onboarding advances the step; Home does nothing (the new row flips Home off
/// the empty state and the history list replaces this panel).
struct TryItPracticeCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore

    var sampleLine = "Help me plan a slow Sunday full of pancakes, sunshine, and a long nap."
    /// Called once, when the user explicitly sends a non-empty take. NOT called on
    /// skip or plain disappear — those still log, but shouldn't advance anything.
    var onSend: () -> Void = {}

    @State private var invite = false
    /// Once the user has held the key even once, the inviting glow ring retires —
    /// it exists only to prompt the very first press; pulsing forever distracts.
    @State private var hasPressed = false
    /// Staged reveal: the card lands showing only the line to read; the key cap and
    /// result box fade in ~1s later. In testing, people grabbed the key before
    /// noticing the prompt — holding the loud controls back until the eye has had a
    /// beat on the line fixes the order without adding steps. Faded in place (space
    /// reserved) so the panel never changes height.
    @State private var revealed = false
    /// The editable contents of the result box. Seeded from the live transcript on
    /// release, then fully the user's to edit by keyboard — the whole point being
    /// that a mistranscription is fixable in place before it's sent.
    @State private var editedText = ""
    /// History is written at most once per card (send or disappear, whichever
    /// first); this guards the double-fire.
    @State private var hasLogged = false
    @FocusState private var boxFocused: Bool

    private var isRecording: Bool { coordinator.state == .recording }
    private var isFinalizing: Bool {
        switch coordinator.state {
        case .finalizing, .rewriting, .pasting: return true
        default: return false
        }
    }
    private var transcript: String { coordinator.liveTranscript }
    /// There's text to send and we're not mid-take.
    private var isComplete: Bool {
        !isRecording && !isFinalizing
            && !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        panel
            .onAppear {
                coordinator.beginOnboardingTrial()
                // Hold the key cap + result box back for a beat so the eye lands on
                // the line first, then fade them in and drop the cursor into the box.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.45)) { revealed = true }
                    boxFocused = true
                }
            }
            .onDisappear {
                coordinator.endOnboardingTrial()
                // Persist what the user produced — skip-after-typing, or Home's
                // list-takeover after a send — so the take isn't lost. Idempotent.
                logToHistory()
            }
            .onChange(of: isRecording) { _, recording in
                if recording {
                    hasPressed = true
                    // Safety: if they press before the timed reveal, snap everything
                    // in so their words have somewhere to land — never a blank panel.
                    if !revealed { withAnimation(.easeOut(duration: 0.3)) { revealed = true } }
                }
            }
            // Drop the final transcript into the editable field once the take closes.
            // Interim words are suppressed (see suppressLivePreview), so liveTranscript
            // stays empty until release and then lands the whole line at once — the
            // user's manual edits afterward are never clobbered mid-stream.
            .onChange(of: transcript) { _, newValue in
                editedText = newValue
            }
    }

    /// Write the (possibly hand-edited) take to history once. Verbatim, so it's an
    /// `.off` entry; the trial's transcribe latency is the only timing that applies.
    private func logToHistory() {
        let final = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty, !hasLogged else { return }
        hasLogged = true
        TranscriptHistoryStore.shared.add(final, latency: coordinator.lastTrialLatency, polish: .off)
    }

    private func send() {
        guard isComplete else { return }
        logToHistory()
        onSend()
    }

    // MARK: Unified panel — prompt, the key, and the result in one calm card.
    // The waveform and live status live in the real Notch HUD (shown during the
    // trial), so the card itself stays quiet: read the line, hold the key, watch
    // the words land here.

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
                .font(.inkReadingEmphasized)
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
                        .font(.system(size: 11))  // ds-allow: icon
                        .foregroundStyle(.green)
                }
                Text("What InkIt heard")
                    .font(.inkEyebrow)
                    .foregroundStyle(.tertiary)
            }
            ZStack(alignment: .topLeading) {
                if editedText.isEmpty {
                    Text("Your words appear here after you let go.")
                        .font(.inkReading)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $editedText)
                    .font(.inkReading)
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
        Button { send() } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .semibold))  // ds-allow: icon
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
                    .font(.system(size: 19))  // ds-allow: icon
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 7) {
                Text("Hold")
                Text(settings.hotkeyDisplayString)
                    .font(.system(size: 14, weight: .bold))  // ds-allow: inline keycap
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentSoft))
                Text("to talk")
            }
            .font(.system(size: 17, weight: .bold))  // ds-allow: practice hint
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
