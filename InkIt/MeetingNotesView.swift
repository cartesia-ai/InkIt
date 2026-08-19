import SwiftUI
import AppKit

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

    @ViewBuilder private func summaryPreviewBody(_ note: MeetingNotesStore.Note) -> some View {
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

private enum RowSummaryHighlighter {
    static func text(_ summary: String, speakers: [MeetingNotesStore.Speaker]) -> Text {
        var attributed = AttributedString(summary)
        var matchedRanges: [Range<AttributedString.Index>] = []

        for speaker in speakers {
            for range in wholeWordRanges(of: speaker.displayLabel, in: attributed) {
                attributed[range].foregroundColor = SpeakerColor.forLabel(speaker.displayLabel)
                matchedRanges.append(range)
            }
        }

        for range in NameCandidateHighlighting.candidateRanges(in: attributed, excluding: matchedRanges) {
            attributed[range].font = .inkCalloutEmphasized
        }

        return Text(attributed)
    }

    private static func wholeWordRanges(of word: String, in attributed: AttributedString) -> [Range<AttributedString.Index>] {
        guard !word.isEmpty else { return [] }
        var ranges: [Range<AttributedString.Index>] = []
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: word) {
            if isWholeWord(range, in: attributed) {
                ranges.append(range)
            }
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func isWholeWord(_ range: Range<AttributedString.Index>, in attributed: AttributedString) -> Bool {
        if range.lowerBound > attributed.startIndex {
            let before = attributed.index(beforeCharacter: range.lowerBound)
            if attributed.characters[before].isLetter || attributed.characters[before].isNumber { return false }
        }
        if range.upperBound < attributed.endIndex,
           attributed.characters[range.upperBound].isLetter || attributed.characters[range.upperBound].isNumber {
            return false
        }
        return true
    }
}

private enum NameCandidateHighlighting {
    private static let sentenceStarters: Set<String> = [
        "The", "This", "That", "These", "Those", "It", "I", "We", "They", "He", "She", "You",
        "A", "An", "In", "On", "At", "For", "With", "After", "Before", "During", "As", "If",
        "When", "While", "Because", "So", "But", "And", "Or", "Also", "However", "Next", "Then",
        "Action", "Items", "Summary", "Overview", "Notes", "Meeting", "No"
    ]

    static func candidateRanges(
        in attributed: AttributedString,
        excluding matchedRanges: [Range<AttributedString.Index>]
    ) -> [Range<AttributedString.Index>] {
        var candidates: [Range<AttributedString.Index>] = []
        var isSentenceStart = true
        var index = attributed.startIndex

        while index < attributed.endIndex {
            while index < attributed.endIndex, attributed.characters[index] == " " {
                index = attributed.index(afterCharacter: index)
            }
            guard index < attributed.endIndex else { break }

            var wordEnd = index
            while wordEnd < attributed.endIndex, attributed.characters[wordEnd] != " " {
                wordEnd = attributed.index(afterCharacter: wordEnd)
            }

            let startsSentence = isSentenceStart
            let lastChar = attributed.characters[attributed.index(beforeCharacter: wordEnd)]
            isSentenceStart = lastChar == "." || lastChar == "!" || lastChar == "?"

            var trimmedStart = index
            while trimmedStart < wordEnd,
                  !(attributed.characters[trimmedStart].isLetter || attributed.characters[trimmedStart].isNumber) {
                trimmedStart = attributed.index(afterCharacter: trimmedStart)
            }
            var trimmedEnd = wordEnd
            while trimmedEnd > trimmedStart {
                let before = attributed.index(beforeCharacter: trimmedEnd)
                if attributed.characters[before].isLetter || attributed.characters[before].isNumber { break }
                trimmedEnd = before
            }

            if trimmedStart < trimmedEnd, !startsSentence {
                let range = trimmedStart..<trimmedEnd
                let trimmed = String(attributed.characters[range])
                if let first = trimmed.first, first.isUppercase,
                   trimmed.dropFirst().contains(where: { $0.isLowercase }),
                   !sentenceStarters.contains(trimmed),
                   !matchedRanges.contains(where: { $0.overlaps(range) }) {
                    candidates.append(range)
                }
            }

            index = wordEnd
        }

        return candidates
    }
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

@MainActor
final class EditCoordinator: ObservableObject {
    @Published private(set) var activeFieldID: UUID?
    private var saveActiveHandler: (() -> Void)?

    func requestEdit(_ id: UUID, saveAndClose: @escaping () -> Void) {
        if activeFieldID != nil, activeFieldID != id {
            let previousSave = saveActiveHandler
            activeFieldID = nil
            saveActiveHandler = nil
            previousSave?()
        }
        activeFieldID = id
        saveActiveHandler = saveAndClose
    }

    func resignEdit(_ id: UUID) {
        guard activeFieldID == id else { return }
        activeFieldID = nil
        saveActiveHandler = nil
    }
}

@MainActor
private final class MeetingEditSession: ObservableObject {
    let noteID: UUID
    let store: MeetingNotesStore
    let undoManager = UndoManager()

    init(noteID: UUID, store: MeetingNotesStore) {
        self.noteID = noteID
        self.store = store
        undoManager.groupsByEvent = false
    }

    private func registerUndo(withTarget target: MeetingEditSession, handler: @escaping (MeetingEditSession) -> Void) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: target, handler: handler)
        undoManager.endUndoGrouping()
    }

    func setSummaryLineText(lineID: UUID, text: String, previous: String) {
        guard text != previous else { return }
        store.updateSummaryLine(noteID: noteID, lineID: lineID, text: text)
        registerUndo(withTarget: self) { $0.setSummaryLineText(lineID: lineID, text: previous, previous: text) }
    }

    func setLineText(lineID: UUID, text: String, previous: String) {
        guard text != previous else { return }
        store.updateLineText(noteID: noteID, lineID: lineID, text: text)
        registerUndo(withTarget: self) { $0.setLineText(lineID: lineID, text: previous, previous: text) }
    }

    func deleteSummaryLine(lineID: UUID) {
        guard let result = store.deleteSummaryLine(noteID: noteID, lineID: lineID) else { return }
        registerUndo(withTarget: self) { $0.undoDeleteSummaryLine(line: result.line, index: result.index) }
    }

    private func undoDeleteSummaryLine(line: MeetingNotesStore.SummaryLine, index: Int) {
        store.insertSummaryLine(noteID: noteID, line: line, at: index)
        registerUndo(withTarget: self) { $0.deleteSummaryLine(lineID: line.id) }
    }

    func deleteTranscriptLine(lineID: UUID) {
        guard let result = store.deleteTranscriptLine(noteID: noteID, lineID: lineID) else { return }
        registerUndo(withTarget: self) { $0.undoDeleteTranscriptLine(line: result.line, index: result.index) }
    }

    private func undoDeleteTranscriptLine(line: MeetingNotesStore.TranscriptLine, index: Int) {
        store.insertTranscriptLine(noteID: noteID, line: line, at: index)
        registerUndo(withTarget: self) { $0.deleteTranscriptLine(lineID: line.id) }
    }

    func reassign(lineID: UUID, speakerID: UUID, previous: UUID) {
        guard speakerID != previous else { return }
        store.reassignLine(noteID: noteID, lineID: lineID, speakerID: speakerID)
        registerUndo(withTarget: self) { $0.reassign(lineID: lineID, speakerID: previous, previous: speakerID) }
    }

    func renameSpeaker(speakerID: UUID, name: String?, previous: String?) {
        guard name != previous else { return }
        store.renameSpeaker(noteID: noteID, speakerID: speakerID, displayName: name)
        registerUndo(withTarget: self) { $0.renameSpeaker(speakerID: speakerID, name: previous, previous: name) }
    }

    func addSpeakerAndReassign(lineID: UUID, previousSpeakerID: UUID, label: String) {
        let speaker = store.addSpeaker(noteID: noteID, label: label)
        store.reassignLine(noteID: noteID, lineID: lineID, speakerID: speaker.id)
        registerUndo(withTarget: self) {
            $0.undoAddSpeaker(speaker: speaker, lineID: lineID, previousSpeakerID: previousSpeakerID)
        }
    }

    private func undoAddSpeaker(speaker: MeetingNotesStore.Speaker, lineID: UUID, previousSpeakerID: UUID) {
        store.reassignLine(noteID: noteID, lineID: lineID, speakerID: previousSpeakerID)
        store.removeSpeaker(noteID: noteID, speakerID: speaker.id)
        registerUndo(withTarget: self) {
            $0.redoAddSpeaker(speaker: speaker, lineID: lineID, previousSpeakerID: previousSpeakerID)
        }
    }

    private func redoAddSpeaker(speaker: MeetingNotesStore.Speaker, lineID: UUID, previousSpeakerID: UUID) {
        store.insertSpeaker(noteID: noteID, speaker: speaker)
        store.reassignLine(noteID: noteID, lineID: lineID, speakerID: speaker.id)
        registerUndo(withTarget: self) {
            $0.undoAddSpeaker(speaker: speaker, lineID: lineID, previousSpeakerID: previousSpeakerID)
        }
    }

    func removeSpeaker(speaker: MeetingNotesStore.Speaker) {
        let affected = store.removeSpeaker(noteID: noteID, speakerID: speaker.id)
        registerUndo(withTarget: self) { $0.undoRemoveSpeaker(speaker: speaker, affected: affected) }
    }

    private func undoRemoveSpeaker(speaker: MeetingNotesStore.Speaker, affected: [(lineID: UUID, previousSpeakerID: UUID)]) {
        store.insertSpeaker(noteID: noteID, speaker: speaker)
        for item in affected {
            store.reassignLine(noteID: noteID, lineID: item.lineID, speakerID: item.previousSpeakerID)
        }
        registerUndo(withTarget: self) { $0.removeSpeaker(speaker: speaker) }
    }
}

private struct MeetingNoteDetailView: View {
    @EnvironmentObject var meetingNotes: MeetingNotesStore
    let noteID: UUID
    let onBack: () -> Void

    @StateObject private var editCoordinator = EditCoordinator()
    @StateObject private var editSession: MeetingEditSession

    @State private var copied = false
    @State private var copiedSummary = false
    @State private var showDeleteConfirm = false
    @State private var deleteHovering = false

    init(noteID: UUID, onBack: @escaping () -> Void) {
        self.noteID = noteID
        self.onBack = onBack
        _editSession = StateObject(wrappedValue: MeetingEditSession(noteID: noteID, store: MeetingNotesStore.shared))
    }

    private var note: MeetingNotesStore.Note? {
        meetingNotes.notes.first(where: { $0.id == noteID })
    }

    var body: some View {
        Group {
            if let note {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(note)
                        summarySection(note)
                            .padding(.top, 20)
                        transcriptSection(note)
                            .padding(.top, 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pageFrame()
                }
                .scrollIndicators(.hidden)
                .background(undoRedoShortcuts)
            } else {
                Color.clear.onAppear(perform: onBack)
            }
        }
    }

    private var undoRedoShortcuts: some View {
        HStack(spacing: 0) {
            Button("") { editSession.undoManager.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("") { editSession.undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func header(_ note: MeetingNotesStore.Note) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))  // ds-allow: icon
                    .foregroundStyle(Color.inkSub)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())

            VStack(alignment: .leading, spacing: 6) {
                Text(note.title)
                    .font(.inkTitle)
                    .foregroundStyle(Color.inkText)
                Text(Self.dateFmt.string(from: note.createdAt))
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkSub)
            }
            Spacer(minLength: 0)
            deleteNoteButton(note)
        }
        .alert("Delete this note?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                meetingNotes.deleteNote(id: note.id)
                onBack()
            }
        } message: {
            Text("This permanently deletes the recording and transcript.")
        }
    }

    private func deleteNoteButton(_ note: MeetingNotesStore.Note) -> some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(.white)  // ds-allow: legible icon on the red destructive fill
                .frame(width: 36, height: 36)
                .background(Color.inkDanger, in: Circle())
                .brightness(deleteHovering ? Hover.fillShift : 0)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .onHover { deleteHovering = $0 }
        .animation(Hover.animation, value: deleteHovering)
        .accessibilityLabel("Delete note")
    }

    @ViewBuilder private func summarySection(_ note: MeetingNotesStore.Note) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Summary")
                    .font(.inkHeadline)
                    .foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                copySummaryButton(note)
            }
            Group {
                if !note.summaryLines.isEmpty {
                    editableSummaryLines(note)
                } else if let summary = note.summary, !summary.isEmpty {
                    SummaryRendering.text(summary, speakerLabels: note.speakers.map(\.label))
                        .font(.inkReading)
                        .foregroundStyle(Color.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No summary yet.")
                        .font(.inkReading)
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: shape)
            .overlay(shape.stroke(Color.line, lineWidth: 1))
        }
    }

    @ViewBuilder private func editableSummaryLines(_ note: MeetingNotesStore.Note) -> some View {
        let overview = note.summaryLines.filter { !$0.isActionItem }
        let actionItems = note.summaryLines.filter { $0.isActionItem }
        let speakerLabels = note.speakers.map(\.label)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(overview) { line in
                EditableLineRow(id: line.id, text: line.text, prefix: "-", font: .inkReading, fontSize: 17,
                                textColor: Color.inkSub,
                                coloredText: SummaryRendering.text(line.text, speakerLabels: speakerLabels),
                                editCoordinator: editCoordinator,
                                onCommit: { newText in
                    editSession.setSummaryLineText(lineID: line.id, text: newText, previous: line.text)
                }, onDelete: {
                    editSession.deleteSummaryLine(lineID: line.id)
                })
            }
            if !actionItems.isEmpty {
                Text("Action Items")
                    .font(.inkReadingEmphasized)
                    .foregroundStyle(Color.inkText)
                    .padding(.top, overview.isEmpty ? 0 : 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(actionItems) { line in
                        EditableLineRow(id: line.id, text: line.text, prefix: "\u{2022}", font: .inkReading,
                                        fontSize: 17, textColor: Color.inkSub,
                                        coloredText: SummaryRendering.text(line.text, speakerLabels: speakerLabels),
                                        editCoordinator: editCoordinator,
                                        onCommit: { newText in
                            editSession.setSummaryLineText(lineID: line.id, text: newText, previous: line.text)
                        }, onDelete: {
                            editSession.deleteSummaryLine(lineID: line.id)
                        })
                    }
                }
                .padding(.leading, 12)
            }
        }
    }

    @ViewBuilder private func transcriptSection(_ note: MeetingNotesStore.Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            transcriptHeader(note)
            speakersPanel(note)
            if !note.lines.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(note.lines) { line in
                        EditableTranscriptBubble(
                            line: line,
                            speakerName: note.displayName(for: line.speakerID),
                            speakers: note.speakers,
                            editCoordinator: editCoordinator,
                            onTextCommit: { newText in
                                editSession.setLineText(lineID: line.id, text: newText, previous: line.text)
                            },
                            onReassign: { newSpeakerID in
                                editSession.reassign(lineID: line.id, speakerID: newSpeakerID, previous: line.speakerID)
                            },
                            onNewSpeaker: {
                                editSession.addSpeakerAndReassign(lineID: line.id, previousSpeakerID: line.speakerID,
                                                                  label: nextSpeakerLabel(note))
                            },
                            onDelete: {
                                editSession.deleteTranscriptLine(lineID: line.id)
                            }
                        )
                    }
                }
            } else if !legacyLines(note).isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(legacyLines(note).enumerated()), id: \.offset) { _, line in
                        TranscriptBubble(speaker: line.speaker, text: line.text)
                    }
                }
            } else {
                Text("No transcript available.")
                    .font(.inkBody)
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    private func nextSpeakerLabel(_ note: MeetingNotesStore.Note) -> String {
        let prefix = "Speaker "
        let used = Set(note.speakers.compactMap { speaker -> Int? in
            guard speaker.label.hasPrefix(prefix) else { return nil }
            return Int(speaker.label.dropFirst(prefix.count))
        })
        var n = 1
        while used.contains(n) { n += 1 }
        return "\(prefix)\(n)"
    }

    private func transcriptHeader(_ note: MeetingNotesStore.Note) -> some View {
        HStack(spacing: 10) {
            Text("Transcript")
                .font(.inkHeadline)
                .foregroundStyle(Color.inkText)
            let count = participantCount(note)
            if count > 0 {
                Text(count == 1 ? "1 person" : "\(count) people")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer(minLength: 0)
            copyTranscriptButton(note)
        }
    }

    @ViewBuilder private func speakersPanel(_ note: MeetingNotesStore.Note) -> some View {
        let showUnknown = note.lines.contains(where: { $0.speakerID == MeetingNotesStore.Speaker.unknownID })
        if !note.speakers.isEmpty || showUnknown {
            SpeakersInCallPanel(
                speakers: note.speakers,
                showUnknown: showUnknown,
                editCoordinator: editCoordinator,
                onRename: { speaker, newName in
                    editSession.renameSpeaker(speakerID: speaker.id, name: newName, previous: speaker.displayName)
                },
                onRemove: { speaker in
                    editSession.removeSpeaker(speaker: speaker)
                }
            )
        }
    }

    private func copyTranscriptButton(_ note: MeetingNotesStore.Note) -> some View {
        Button(action: { copyTranscript(note) }) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .medium))  // ds-allow: icon
                .foregroundStyle(copied ? Color.accentColor : Color.inkSub)
                .frame(width: 26, height: 26)
                .hoverBackdrop(cornerRadius: Radius.control, isActive: copied)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .animation(Motion.state, value: copied)
        .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }

    private func copySummaryButton(_ note: MeetingNotesStore.Note) -> some View {
        Button(action: { copySummary(note) }) {
            Image(systemName: copiedSummary ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .medium))  // ds-allow: icon
                .foregroundStyle(copiedSummary ? Color.accentColor : Color.inkSub)
                .frame(width: 26, height: 26)
                .hoverBackdrop(cornerRadius: Radius.control, isActive: copiedSummary)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .animation(Motion.state, value: copiedSummary)
        .accessibilityLabel(copiedSummary ? "Copied summary" : "Copy summary")
    }

    private func copyTranscript(_ note: MeetingNotesStore.Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptPlainText(note), forType: .string)
        withAnimation(Motion.state) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(Motion.state) { copied = false }
        }
    }

    private func copySummary(_ note: MeetingNotesStore.Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryPlainText(note), forType: .string)
        withAnimation(Motion.state) { copiedSummary = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(Motion.state) { copiedSummary = false }
        }
    }

    private func legacyLines(_ note: MeetingNotesStore.Note) -> [(speaker: String, text: String)] {
        guard note.lines.isEmpty, let transcript = note.transcript, !transcript.isEmpty else { return [] }
        return transcript.split(separator: "\n").map { line in
            if let range = line.range(of: ": ") {
                let speaker = String(line[line.startIndex..<range.lowerBound])
                return (speaker == "Me" ? "You" : speaker, String(line[range.upperBound...]))
            }
            return ("", String(line))
        }
    }

    private func participantCount(_ note: MeetingNotesStore.Note) -> Int {
        if !note.lines.isEmpty {
            return Set(note.lines.map { note.displayName(for: $0.speakerID) }).count
        }
        return Set(legacyLines(note).map(\.speaker).filter { !$0.isEmpty }).count
    }

    private func transcriptPlainText(_ note: MeetingNotesStore.Note) -> String {
        if !note.lines.isEmpty {
            return note.lines.map { "\(note.displayName(for: $0.speakerID)): \($0.text)" }.joined(separator: "\n")
        }
        return legacyLines(note).map { $0.speaker.isEmpty ? $0.text : "\($0.speaker): \($0.text)" }
            .joined(separator: "\n")
    }

    private func summaryPlainText(_ note: MeetingNotesStore.Note) -> String {
        if !note.summaryLines.isEmpty {
            let overview = note.summaryLines.filter { !$0.isActionItem }
            let actionItems = note.summaryLines.filter { $0.isActionItem }
            var parts = overview.map(\.text)
            if !actionItems.isEmpty {
                parts.append("Action Items")
                parts.append(contentsOf: actionItems.map { "\u{2022} \($0.text)" })
            }
            return parts.joined(separator: "\n")
        }
        return note.summary ?? ""
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()
}

private struct TranscriptBubble: View {
    let speaker: String
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 5) {
            if !speaker.isEmpty {
                Text(speaker)
                    .font(.inkCalloutEmphasized)
                    .foregroundStyle(SpeakerColor.forLabel(speaker))
            }
            Text(text)
                .font(.inkBody)
                .foregroundStyle(Color.inkText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: shape)
                .overlay(shape.stroke(Color.line, lineWidth: 1))
        }
    }
}

private struct TextEditCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.iBeam.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func textEditCursor() -> some View { modifier(TextEditCursor()) }
}

private struct CursorRegion: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> TrackingView { TrackingView(cursor: cursor) }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.cursor = cursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    final class TrackingView: NSView {
        var cursor: NSCursor
        init(cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }
    }
}

private extension View {
    func cursorRect(_ cursor: NSCursor) -> some View {
        background(CursorRegion(cursor: cursor))
    }
}

private final class AutoGrowTextField: NSTextField {
    override func resetCursorRects() {}
}

private struct InlineEditableText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    var showsText: Bool = true
    var minLineHeight: CGFloat? = nil
    @Binding var forceCommit: Bool
    let onCommit: (String) -> Void
    let onBeginEditing: () -> Void
    let onDeleteEmptyLine: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AutoGrowTextField {
        let field = AutoGrowTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.lineBreakMode = .byWordWrapping
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.stringValue = text
        style(field)
        return field
    }

    func updateNSView(_ field: AutoGrowTextField, context: Context) {
        context.coordinator.parent = self
        style(field)
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
        if forceCommit {
            field.window?.makeFirstResponder(nil)
            DispatchQueue.main.async { forceCommit = false }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AutoGrowTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0, let cell = nsView.cell else { return nil }
        let height = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(ceil(height), minLineHeight ?? 0))
    }

    private func style(_ field: AutoGrowTextField) {
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = showsText ? NSColor(textColor) : .clear
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineEditableText
        init(_ parent: InlineEditableText) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onBeginEditing()
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.onCommit(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty {
                control.window?.makeFirstResponder(nil)
                parent.onDeleteEmptyLine()
                return true
            }
            return false
        }
    }
}

private let editableRowHoverOpacity: Double = 0.06

private struct EditableLineRow: View {
    let id: UUID
    let text: String
    var prefix: String? = nil
    var font: Font = .inkBody
    var fontSize: CGFloat = 15
    var textColor: Color = .inkText
    var coloredText: Text?
    @ObservedObject var editCoordinator: EditCoordinator
    let onCommit: (String) -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var isEditing = false
    @State private var forceCommit = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let prefix {
                Text(prefix)
                    .font(font)
                    .foregroundStyle(textColor)
            }
            ZStack(alignment: .leading) {
                (coloredText ?? Text(text))
                    .font(font)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isEditing ? 0 : 1)
                    .allowsHitTesting(false)
                InlineEditableText(text: text, fontSize: fontSize, textColor: textColor, showsText: isEditing,
                                   minLineHeight: fontSize + 8,
                                   forceCommit: $forceCommit,
                                   onCommit: commit, onBeginEditing: beginEdit, onDeleteEmptyLine: deleteAndClose)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(hovering && !isEditing ? Color.primary.opacity(editableRowHoverOpacity) : Color.clear))
        .onHover { hovering = $0 }
        .textEditCursor()
        .dismissOnClickOutside(isActive: isEditing) { forceCommit = true }
    }

    private func beginEdit() {
        isEditing = true
        editCoordinator.requestEdit(id, saveAndClose: { forceCommit = true })
    }

    private func commit(_ newText: String) {
        isEditing = false
        editCoordinator.resignEdit(id)
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != text {
            onCommit(trimmed)
        }
    }

    private func deleteAndClose() {
        isEditing = false
        editCoordinator.resignEdit(id)
        onDelete()
    }
}

private struct SpeakerLabelControl: View {
    let speakerID: UUID
    let displayName: String
    let speakers: [MeetingNotesStore.Speaker]
    let onReassign: (UUID) -> Void
    let onNewSpeaker: () -> Void

    @State private var hovering = false
    @State private var showReassignMenu = false

    var body: some View {
        Button {
            showReassignMenu = true
        } label: {
            Text(displayName)
                .font(.inkBodyEmphasized)
                .foregroundStyle(SpeakerColor.forLabel(displayName))
                .padding(.horizontal, 3)
                .background(Color.primary.opacity(hovering ? Hover.backdropOpacity : 0),
                           in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .onHover { hovering = $0 }
        .inkDetailPopover(isPresented: $showReassignMenu) {
            SpeakerReassignPopover(currentID: speakerID, speakers: speakers, onSelect: { id in
                showReassignMenu = false
                onReassign(id)
            }, onNewSpeaker: {
                showReassignMenu = false
                onNewSpeaker()
            })
        }
    }
}

private struct SpeakersInCallPanel: View {
    let speakers: [MeetingNotesStore.Speaker]
    let showUnknown: Bool
    @ObservedObject var editCoordinator: EditCoordinator
    let onRename: (MeetingNotesStore.Speaker, String) -> Void
    let onRemove: (MeetingNotesStore.Speaker) -> Void

    @State private var isExpanded = false

    private var rowCount: Int { speakers.count + (showUnknown ? 1 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Motion.expand) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))  // ds-allow: icon
                        .foregroundStyle(Color.inkFaint)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Speakers in this call (\(rowCount))")
                        .font(.inkCalloutEmphasized)
                        .foregroundStyle(Color.inkSub)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.chip))
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(speakers) { speaker in
                        SpeakerRosterRow(speaker: speaker, isRemovable: true, editCoordinator: editCoordinator,
                                         onRename: { onRename(speaker, $0) }, onRemove: { onRemove(speaker) })
                    }
                    if showUnknown {
                        SpeakerRosterRow(speaker: MeetingNotesStore.Speaker(id: MeetingNotesStore.Speaker.unknownID,
                                                                             label: "Unknown"),
                                         isRemovable: false, editCoordinator: editCoordinator,
                                         onRename: { _ in }, onRemove: {})
                    }
                }
                .padding(.leading, 2)
            }
        }
    }
}

private struct SpeakerRosterRow: View {
    let speaker: MeetingNotesStore.Speaker
    let isRemovable: Bool
    @ObservedObject var editCoordinator: EditCoordinator
    let onRename: (String) -> Void
    let onRemove: () -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var showRemoveConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SpeakerColor.forLabel(speaker.displayLabel))
                .frame(width: 8, height: 8)

            if isRenaming {
                TextField("", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.inkCallout)
                    .focused($focused)
                    .onSubmit(commitRename)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commitRename() } }
                    .frame(minWidth: 80)
            } else {
                Button(action: beginRename) {
                    Text(speaker.displayLabel)
                        .font(.inkCallout)
                        .foregroundStyle(Color.inkText)
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
            }

            Spacer(minLength: 0)

            if isRemovable {
                Button {
                    showRemoveConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))  // ds-allow: icon
                        .foregroundStyle(Color.inkDanger)
                        .frame(width: 22, height: 22)
                        .hoverBackdrop(cornerRadius: Radius.chip)
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
                .accessibilityLabel("Remove \(speaker.displayLabel)")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(hovering ? Color.primary.opacity(Hover.backdropOpacity) : Color.clear))
        .onHover { hovering = $0 }
        .alert("Remove \(speaker.displayLabel)?", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { onRemove() }
        } message: {
            Text("Their lines will be reassigned to Unknown.")
        }
    }

    private func beginRename() {
        draftName = speaker.displayLabel
        editCoordinator.requestEdit(speaker.id, saveAndClose: commitRename)
        isRenaming = true
        focused = true
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        focused = false
        editCoordinator.resignEdit(speaker.id)
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != speaker.displayLabel {
            onRename(trimmed)
        }
    }
}

private struct SpeakerReassignPopover: View {
    let currentID: UUID
    let speakers: [MeetingNotesStore.Speaker]
    let onSelect: (UUID) -> Void
    let onNewSpeaker: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(speakers) { speaker in
                SpeakerMenuRow(speaker: speaker, isCurrent: speaker.id == currentID) {
                    onSelect(speaker.id)
                }
            }
            Divider()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            Button(action: onNewSpeaker) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.inkCallout)
                        .frame(width: 16)
                    Text("New speaker")
                        .font(.inkCallout)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.inkText)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hoverBackdrop(cornerRadius: Radius.chip)
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())
        }
        .padding(5)
        .frame(width: 190)
    }
}

private struct SpeakerMenuRow: View {
    let speaker: MeetingNotesStore.Speaker
    let isCurrent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(SpeakerColor.forLabel(speaker.displayLabel))
                    .frame(width: 8, height: 8)
                Text(speaker.displayLabel)
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkText)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))  // ds-allow: icon
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(isCurrent
                           ? SpeakerColor.forLabel(speaker.displayLabel).opacity(0.14)
                           : Color.primary.opacity(hovering ? Hover.backdropOpacity : 0))
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .onHover { hovering = $0 }
        .animation(Hover.animation, value: hovering)
    }
}

private struct EditableTranscriptBubble: View {
    let line: MeetingNotesStore.TranscriptLine
    let speakerName: String
    let speakers: [MeetingNotesStore.Speaker]
    @ObservedObject var editCoordinator: EditCoordinator
    let onTextCommit: (String) -> Void
    let onReassign: (UUID) -> Void
    let onNewSpeaker: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var isEditing = false
    @State private var forceCommit = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 5) {
            SpeakerLabelControl(speakerID: line.speakerID, displayName: speakerName, speakers: speakers,
                               onReassign: onReassign, onNewSpeaker: onNewSpeaker)
            InlineEditableText(text: line.text, fontSize: 15, textColor: Color.inkText, minLineHeight: 23,
                               forceCommit: $forceCommit,
                               onCommit: commit, onBeginEditing: beginEdit, onDeleteEmptyLine: deleteAndClose)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(hovering && !isEditing ? Color.primary.opacity(editableRowHoverOpacity) : Color.clear))
                .background(Color.card, in: shape)
                .overlay(shape.stroke(Color.line, lineWidth: 1))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .textEditCursor()
                .dismissOnClickOutside(isActive: isEditing) { forceCommit = true }
        }
    }

    private func beginEdit() {
        isEditing = true
        editCoordinator.requestEdit(line.id, saveAndClose: { forceCommit = true })
    }

    private func commit(_ newText: String) {
        isEditing = false
        editCoordinator.resignEdit(line.id)
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != line.text {
            onTextCommit(trimmed)
        }
    }

    private func deleteAndClose() {
        isEditing = false
        editCoordinator.resignEdit(line.id)
        onDelete()
    }
}

private enum SpeakerColor {
    private static let prefix = "Speaker "

    static func forLabel(_ label: String) -> Color {
        if label == "You" || label == "Me" { return .speakerYou }
        guard label.hasPrefix(prefix), let n = Int(label.dropFirst(prefix.count)), n >= 1 else {
            return Color.inkSub
        }
        return Color.speakerPalette[(n - 1) % Color.speakerPalette.count]
    }
}

private enum SummaryRendering {
    static func text(_ summary: String, speakerLabels: [String], boldUnregisteredNames: Bool = false) -> Text {
        guard var attributed = try? AttributedString(markdown: summary) else {
            return Text(summary)
        }
        let matchedRanges = colorSpeakerMentions(in: &attributed, labels: speakerLabels)
        if boldUnregisteredNames {
            for range in NameCandidateHighlighting.candidateRanges(in: attributed, excluding: matchedRanges) {
                attributed[range].font = .inkBodyEmphasized
            }
        }
        return Text(attributed)
    }

    private static func colorSpeakerMentions(
        in attributed: inout AttributedString,
        labels: [String]
    ) -> [Range<AttributedString.Index>] {
        var matched: [Range<AttributedString.Index>] = []
        for label in labels {
            matched.append(contentsOf: highlightWholeWord(label, in: &attributed))
        }
        return matched
    }

    private static func highlightWholeWord(_ word: String, in attributed: inout AttributedString) -> [Range<AttributedString.Index>] {
        var matched: [Range<AttributedString.Index>] = []
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: word) {
            if isWholeWord(range, in: attributed) {
                attributed[range].foregroundColor = SpeakerColor.forLabel(word)
                matched.append(range)
            }
            searchStart = range.upperBound
        }
        return matched
    }

    private static func isWholeWord(_ range: Range<AttributedString.Index>, in attributed: AttributedString) -> Bool {
        if range.lowerBound > attributed.startIndex {
            let before = attributed.index(beforeCharacter: range.lowerBound)
            if attributed.characters[before].isLetter || attributed.characters[before].isNumber { return false }
        }
        if range.upperBound < attributed.endIndex,
           attributed.characters[range.upperBound].isLetter || attributed.characters[range.upperBound].isNumber {
            return false
        }
        return true
    }
}
