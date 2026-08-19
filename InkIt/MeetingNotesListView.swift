import SwiftUI

struct MeetingNotesView: View {
    @EnvironmentObject var meetingNotes: MeetingNotesStore
    @EnvironmentObject var meetingSession: MeetingSessionCoordinator
    @EnvironmentObject var settings: SettingsStore

    @State private var searchQuery = ""
    @State private var hintIndex = 0
    @State private var showAPIKeyGate = false
    @State private var selectedNoteID: UUID?
    @State private var hoveredNoteID: UUID?
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
        Group {
            if let id = selectedNoteID {
                MeetingNoteDetailView(noteID: id, onBack: { selectedNoteID = nil })
            } else {
                notesListBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var notesListBody: some View {
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
        .onReceive(hintTimer) { _ in rotateHint() }
        .overlay { apiKeyGateModal }
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
            handleNewNoteTapped()
        } label: {
            Label("New note", systemImage: "plus")
        }
        .buttonStyle(InkButtonStyle(variant: .accentSoft))
        .modifier(PointingHandCursor())
    }

    private func handleNewNoteTapped() {
        switch meetingSession.checkGate() {
        case .ready:
            meetingSession.start()
        case .needsAPIKey:
            withAnimation(Motion.state) { showAPIKeyGate = true }
        }
    }

    @ViewBuilder private var apiKeyGateModal: some View {
        if showAPIKeyGate {
            InkModal(onDismiss: { showAPIKeyGate = false }) {
                MeetingAPIKeyGate(onContinue: {
                    showAPIKeyGate = false
                    meetingSession.start()
                }, onCancel: {
                    showAPIKeyGate = false
                })
            }
        }
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

    private var previewedNote: MeetingNotesStore.Note? {
        meetingNotes.notes.first(where: { $0.id == hoveredNoteID }) ?? meetingNotes.notes.first
    }

    @ViewBuilder private var recentMeetingSummary: some View {
        if let latest = previewedNote,
           !latest.summaryLines.isEmpty || !(latest.summary ?? "").isEmpty {
            let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            VStack(alignment: .leading, spacing: 10) {
                Text("Summary")
                    .font(.inkReadingEmphasized)
                    .foregroundStyle(Color.inkText)
                VStack(alignment: .leading, spacing: 10) {
                    Text(latest.title)
                        .font(.inkTitle)
                        .foregroundStyle(Color.inkText)
                    Text(Self.summaryDateFmt.string(from: latest.createdAt))
                        .font(.inkCaption)
                        .foregroundStyle(Color.inkFaint)
                    summaryPreviewBody(latest)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: shape)
                .overlay(shape.stroke(Color.line, lineWidth: 1))
            }
            .padding(.top, 20)
        }
    }

    private static let summaryPreviewHeight: CGFloat = 160

    @ViewBuilder private func summaryPreviewBody(_ note: MeetingNotesStore.Note) -> some View {
        summaryPreviewContent(note)
            .frame(height: Self.summaryPreviewHeight, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.card.opacity(0), Color.card],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder private func summaryPreviewContent(_ note: MeetingNotesStore.Note) -> some View {
        if !note.summaryLines.isEmpty {
            let overview = note.summaryLines.filter { !$0.isActionItem }
            let actionItems = note.summaryLines.filter { $0.isActionItem }
            let speakerLabels = note.speakers.map(\.label)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(overview) { line in
                    SummaryRendering.text(line.text, speakerLabels: speakerLabels, boldUnregisteredNames: true)
                        .font(.inkBody)
                        .foregroundStyle(Color.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !actionItems.isEmpty {
                    Text("Action Items")
                        .font(.inkBodyEmphasized)
                        .foregroundStyle(Color.inkText)
                        .padding(.top, overview.isEmpty ? 0 : 4)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(actionItems) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\u{2022}")
                                    .font(.inkBody)
                                    .foregroundStyle(Color.inkSub)
                                SummaryRendering.text(line.text, speakerLabels: speakerLabels, boldUnregisteredNames: true)
                                    .font(.inkBody)
                                    .foregroundStyle(Color.inkSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 12)
                }
            }
        } else if let summary = note.summary, !summary.isEmpty {
            SummaryRendering.text(summary, speakerLabels: note.speakers.map(\.label), boldUnregisteredNames: true)
                .font(.inkBody)
                .foregroundStyle(Color.inkSub)
                .fixedSize(horizontal: false, vertical: true)
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
                            MeetingNoteRow(note: note, onTap: { selectedNoteID = note.id },
                                          deleteNote: { meetingNotes.deleteNote(id: $0) },
                                          onHover: { isHovering in
                                if isHovering { hoveredNoteID = note.id }
                            })
                        }
                    } header: {
                        DayGroupHeader(title: group.title, large: true)
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
    let onTap: () -> Void
    let deleteNote: (UUID) -> Void
    var onHover: ((Bool) -> Void)? = nil
    @State private var hovering = false
    @State private var showDeleteAction = false
    @State private var showDeleteConfirm = false

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
                RowSummaryHighlighter.text(
                    (note.summary?.isEmpty == false) ? note.summary! : "No summary yet",
                    speakers: note.speakers
                )
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkSub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering {
                rowActions
            }
            Text(Self.timeFmt.string(from: note.createdAt))
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(hovering ? Color.accentColor.opacity(Hover.rowTintOpacity) : Color.clear))
        .cursorRect(.pointingHand)
        .onHover { isHovering in
            withAnimation(Hover.animation) { hovering = isHovering }
            onHover?(isHovering)
        }
        .onChange(of: hovering) { _, isHovering in
            if !isHovering { showDeleteAction = false }
        }
        .onTapGesture { onTap() }
        .alert("Delete this note?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteNote(note.id) }
        } message: {
            Text("This permanently deletes the recording and transcript.")
        }
    }

    @ViewBuilder private var rowActions: some View {
        HStack(spacing: 4) {
            Button {
                showDeleteAction.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))  // ds-allow: icon
                    .foregroundStyle(Color.inkSub)
                    .frame(width: 22, height: 22)
                    .hoverBackdrop(cornerRadius: Radius.control)
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())

            if showDeleteAction {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))  // ds-allow: icon
                        .foregroundStyle(Color.red)
                        .frame(width: 22, height: 22)
                        .hoverBackdrop(cornerRadius: Radius.control)
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
            }
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

private struct MeetingAPIKeyGate: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var validator = LLMKeyValidator(provider: SettingsStore.shared.rewriteProvider)
    let onContinue: () -> Void
    let onCancel: () -> Void

    private var keyBinding: Binding<String> {
        Binding(
            get: { settings.apiKey(for: settings.rewriteProvider) },
            set: { settings.setAPIKey($0, for: settings.rewriteProvider) }
        )
    }

    @State private var isKeyFieldFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add an API key for meeting notes")
                    .font(.inkSheetTitle)
                    .foregroundStyle(Color.inkText)
                Text("Meeting notes require an LLM to prepare your notes.")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                providerField
                apiKeyField
            }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(InkSecondaryButtonStyle(compact: true))
                    .modifier(PointingHandCursor())
                Button("Add Key") { onContinue() }
                    .buttonStyle(InkButtonStyle(variant: .accent, compact: true))
                    .modifier(PointingHandCursor())
                    .disabled(validator.state != .verified)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            validator.setProvider(settings.rewriteProvider)
            validator.keyChanged(settings.apiKey(for: settings.rewriteProvider))
        }
        .onChange(of: settings.rewriteProvider) { _, p in
            if !p.models.contains(settings.rewriteModel) { settings.rewriteModel = p.defaultModel }
            validator.setProvider(p)
            validator.keyChanged(settings.apiKey(for: p))
        }
        .onChange(of: settings.llmAPIKeys) { _, _ in
            validator.keyChanged(settings.apiKey(for: settings.rewriteProvider))
        }
    }

    private var providerField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Provider")
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
            Picker("", selection: $settings.rewriteProvider) {
                ForEach(LLMProvider.allCases) { p in
                    Text(p.isRecommended ? "\(p.displayName) (Recommended)" : p.displayName).tag(p)
                }
            }
            .labelsHidden()
            .modifier(PointingHandCursor())
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API key")
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
            HStack(spacing: 6) {
                RevealableSecureField(
                    text: keyBinding,
                    placeholder: settings.rewriteProvider.keyPlaceholder
                ) { isKeyFieldFocused = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)
                keyStatusIcon
            }
            .padding(.horizontal, 10)
            .fieldSurface(focused: isKeyFieldFocused)

            keyStatusMessage

            ExternalLink(
                title: "Get your \(settings.rewriteProvider.displayName) API key",
                url: settings.rewriteProvider.keyURL
            )
        }
    }

    @ViewBuilder private var keyStatusIcon: some View {
        switch validator.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .verified:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .invalidKey:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .couldNotVerify:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var keyStatusMessage: some View {
        switch validator.state {
        case .invalidKey:
            Text("Invalid key").font(.inkCaption).foregroundStyle(.red)
        case .couldNotVerify:
            Text("Couldn’t verify. Check your connection.").font(.inkCaption).foregroundStyle(Color.inkSub)
        default:
            EmptyView()
        }
    }
}
