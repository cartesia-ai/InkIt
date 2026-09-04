import SwiftUI

struct TryItPracticeCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore

    var sampleLine = "Help me plan a slow Sunday full of pancakes, sunshine, and a long nap."
    var onSend: () -> Void = {}

    @State private var invite = false
    @State private var hasPressed = false
    @State private var revealed = false
    @State private var editedText = ""
    @State private var hasLogged = false
    @FocusState private var boxFocused: Bool

    private var isRecording: Bool {
        if case .recording = coordinator.state { return true }
        return false
    }
    private var isFinalizing: Bool {
        switch coordinator.state {
        case .finalizing, .rewriting, .pasting: return true
        default: return false
        }
    }
    private var transcript: String { coordinator.liveTranscript }
    private var isComplete: Bool {
        !isRecording && !isFinalizing
            && !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        panel
            .onAppear {
                coordinator.beginOnboardingTrial()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.45)) { revealed = true }  // ds-allow: bespoke reveal timing
                    boxFocused = true
                }
            }
            .onDisappear {
                coordinator.endOnboardingTrial()
                logToHistory()
            }
            .onChange(of: isRecording) { _, recording in
                if recording {
                    hasPressed = true
                    if !revealed { withAnimation(.easeOut(duration: 0.3)) { revealed = true } }  // ds-allow: bespoke reveal timing
                }
            }
            .onChange(of: transcript) { _, newValue in
                editedText = newValue
            }
    }

    private func logToHistory() {
        let final = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty, !hasLogged else { return }
        hasLogged = true
        TranscriptHistoryStore.shared.add(final, latency: coordinator.lastTrialLatency, polish: .off,
                                          recordingMs: coordinator.lastTrialRecordingMs)
    }

    private func send() {
        guard isComplete else { return }
        logToHistory()
        onSend()
    }

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
            RoundedRectangle(cornerRadius: Radius.practice, style: .continuous)
                .fill(Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.practice, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: Elevation.soft, radius: 14, y: 6)
    }

    private var promptBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("READ THIS ALOUD")
                .font(.inkEyebrow)
                .tracking(1.1)
                .foregroundStyle(Color.accentColor)
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
            RoundedRectangle(cornerRadius: Radius.bar, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3)
        }
    }

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
            RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
                .fill(Color.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
                .stroke(boxFocused ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                        lineWidth: boxFocused ? 1.5 : 1)
        )
        .animation(Motion.state, value: boxFocused)
    }

    private var sendButton: some View {
        Button { send() } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(!isComplete)
        .opacity(isComplete ? 1 : 0.3)
        .scaleEffect(isComplete ? 1 : 0.9)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isComplete)
        .modifier(PointingHandCursor())
    }

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
            if settings.hotkey.isSet {
                HStack(spacing: 7) {
                    Text("Hold")
                    Text(settings.hotkeyDisplayString)
                        .font(.system(size: 14, weight: .medium))  // ds-allow: inline keycap
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).fill(Color.accentSoft))
                    Text("to talk")
                }
                .font(.inkReadingEmphasized)
                .foregroundStyle(.primary)
            } else {
                Text("Set a Hold to talk shortcut in Settings")
                    .font(.inkReadingEmphasized)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                .fill(isRecording ? Color.accentSoft : Color.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                .stroke(isRecording ? Color.recordingAmber : Color(nsColor: .separatorColor),
                        lineWidth: 1.5)
        )
        .scaleEffect(isRecording ? 0.97 : 1)
        .shadow(color: Elevation.soft, radius: 5, y: 2)
        .overlay(inviteRing.opacity(showInvite ? 1 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isRecording)
        .animation(.easeOut(duration: 0.4), value: showInvite)  // ds-allow: bespoke invite-fade timing
    }

    private var showInvite: Bool { revealed && !hasPressed && !isRecording }

    private var inviteRing: some View {
        RoundedRectangle(cornerRadius: Radius.ring, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(-6)
            .scaleEffect(invite ? 1.09 : 0.97)
            .opacity(invite ? 0 : 0.5)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 2.1).repeatForever(autoreverses: false)) {  // ds-allow: bespoke invite-pulse timing
                    invite = true
                }
            }
    }
}
