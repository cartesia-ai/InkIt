import SwiftUI
import AppKit

struct MeetingSessionView: View {
    static let windowWidth: CGFloat = 380

    @EnvironmentObject var session: MeetingSessionCoordinator

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.line).frame(height: 1)
            transcript
            Rectangle().fill(Color.line).frame(height: 1)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.canvas)
        .overlay { stopConfirmModal }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                session.requestStop()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))  // ds-allow: icon
                    .foregroundStyle(Color.inkSub)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                Text(elapsedLabel)
                    .font(.inkCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSub)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if session.segments.isEmpty {
                    Text("Listening…")
                        .font(.inkCallout)
                        .foregroundStyle(Color.inkFaint)
                } else {
                    ForEach(session.segments) { segment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.speakerLabel)
                                .font(.inkCalloutEmphasized)
                                .foregroundStyle(Color.inkText)
                            Text(segment.text)
                                .font(.inkCallout)
                                .foregroundStyle(Color.inkSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        Button {
            session.endMeeting()
        } label: {
            Text("End meeting").frame(maxWidth: .infinity)
        }
        .buttonStyle(InkButtonStyle(variant: .accent))
        .modifier(PointingHandCursor())
        .padding(12)
    }

    private var elapsedLabel: String {
        let m = session.elapsedSeconds / 60
        let s = session.elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder private var stopConfirmModal: some View {
        if session.showStopConfirm {
            ZStack {
                Color.scrimStrong
                    .contentShape(Rectangle())
                    .onTapGesture { session.cancelStopRequest() }
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text("Stop recording?")
                            .font(.inkSheetTitle)
                            .foregroundStyle(Color.inkText)
                        Text("This ends the recording and saves your note.")
                            .font(.inkCaption)
                            .foregroundStyle(Color.inkSub)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 8) {
                        Button {
                            session.confirmStop()
                        } label: {
                            Text("Stop Recording").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(InkButtonStyle(variant: .accent, compact: true))
                        .modifier(PointingHandCursor())

                        Button {
                            session.cancelStopRequest()
                        } label: {
                            Text("Cancel").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(InkSecondaryButtonStyle(compact: true))
                        .modifier(PointingHandCursor())
                    }
                }
                .padding(18)
                .frame(width: 240)
                .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Color.line, lineWidth: 1)
                )
                .shadow(color: Elevation.modal, radius: 30, y: 12)
            }
            .transition(.opacity)
            .animation(Motion.state, value: session.showStopConfirm)
        }
    }
}

@MainActor
final class MeetingWindowResizer {
    static let shared = MeetingWindowResizer()
    private var savedFrame: NSRect?
    private var isNarrow = false

    func apply(sessionActive: Bool, to window: NSWindow) {
        if sessionActive, !isNarrow {
            isNarrow = true
            savedFrame = window.frame
            var frame = window.frame
            frame.size.width = MeetingSessionView.windowWidth
            window.setFrame(frame, display: true, animate: true)
        } else if !sessionActive, isNarrow {
            isNarrow = false
            if let saved = savedFrame {
                window.setFrame(saved, display: true, animate: true)
            }
            savedFrame = nil
        }
    }
}
