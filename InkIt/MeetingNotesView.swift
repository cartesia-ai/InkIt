import SwiftUI

struct MeetingNotesView: View {
    @EnvironmentObject var meetingNotes: MeetingNotesStore

    @State private var searchQuery = ""
    @State private var hintIndex = 0
    @FocusState private var searchFocused: Bool

    private let hintTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private static let searchHints = [
        "What happened in my last meeting?",
        "Why did Bob need to push back the timeline?",
        "Who was supposed to email Jen?",
        "What were this week's action items?",
        "Did we agree on a launch date?",
        "Which objections came up during the demo?"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                searchBar
                    .padding(.top, 16)
                recentMeetingSummary
                notesList
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pageFrame()
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(hintTimer) { _ in rotateHint() }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Meeting notes")
                    .font(.inkTitle)
                    .foregroundStyle(Color.inkText)
                Text("Recorded meetings and their transcripts live here.")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkSub)
            }
            Spacer(minLength: 12)
            newNoteButton
        }
    }

    private var newNoteButton: some View {
        Button {
            // Intentional no-op: wire up once note creation is ready.
        } label: {
            Label("New note", systemImage: "plus")
        }
        .buttonStyle(InkButtonStyle(variant: .accentSoft))
        .modifier(PointingHandCursor())
    }

    private var searchBar: some View {
        let shape = Capsule(style: .continuous)
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if searchQuery.isEmpty {
                    Text(Self.searchHints[hintIndex])
                        .font(.inkReading)
                        .foregroundStyle(Color.inkFaint)
                        .allowsHitTesting(false)
                        .id(hintIndex)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
                TextField("", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.inkReading)
                    .foregroundStyle(Color.inkText)
                    .focused($searchFocused)
                    .accessibilityLabel("Search your notes")
            }
            .clipped()
            if !searchQuery.isEmpty {
                Button {
                    // Intentional no-op: sends a query once LLM search over notes exists.
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13))  // ds-allow: icon
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.card, in: shape)
        .overlay(shape.stroke(Color.line, lineWidth: 1))
        .dismissOnClickOutside(isActive: searchFocused) { searchFocused = false }
    }

    private func rotateHint() {
        guard searchQuery.isEmpty else { return }
        withAnimation(Motion.rotate) {
            hintIndex = (hintIndex + 1) % Self.searchHints.count
        }
    }

    private var groupedNotes: [DayGroup<MeetingNotesStore.Note>] {
        DateGrouping.byDay(meetingNotes.notes) { $0.createdAt }
    }

    @ViewBuilder private var recentMeetingSummary: some View {
        if let latest = meetingNotes.notes.first,
           let summary = latest.summary, !summary.isEmpty {
            let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent meeting summary")
                    .font(.inkHeadline)
                    .foregroundStyle(Color.inkText)
                VStack(alignment: .leading, spacing: 6) {
                    Text(latest.title)
                        .font(.inkCalloutEmphasized)
                        .foregroundStyle(Color.inkText)
                    Text(Self.summaryDateFmt.string(from: latest.createdAt))
                        .font(.inkCaption)
                        .foregroundStyle(Color.inkFaint)
                    Text(summary)
                        .font(.inkCallout)
                        .foregroundStyle(Color.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: shape)
                .overlay(shape.stroke(Color.line, lineWidth: 1))
            }
            .padding(.top, 20)
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My notes")
                .font(.inkReadingEmphasized)
                .foregroundStyle(Color.inkText)
                .padding(.bottom, 6)
            if meetingNotes.notes.isEmpty {
                Text("Recorded meetings will show up here.")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 8)
            } else {
                ForEach(groupedNotes) { group in
                    Section {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, note in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.line)
                                    .frame(height: 1)
                                    .padding(.horizontal, 8)
                            }
                            MeetingNoteRow(note: note)
                        }
                    } header: {
                        DayGroupHeader(title: group.title)
                    }
                }
            }
        }
    }

    private static let summaryDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()
}

private struct MeetingNoteRow: View {
    let note: MeetingNotesStore.Note
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.inkBody)
                .foregroundStyle(Color.inkSub)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.inkBody)
                    .foregroundStyle(Color.inkText)
                Text((note.summary?.isEmpty == false) ? note.summary! : "No summary yet")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkSub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(Self.timeFmt.string(from: note.createdAt))
                .font(.inkCaption)
                .foregroundStyle(Color.inkFaint)
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(hovering ? Color.accentColor.opacity(Hover.rowTintOpacity) : Color.clear))
        .modifier(PointingHandCursor())
        .onHover { isHovering in
            withAnimation(Hover.animation) { hovering = isHovering }
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
