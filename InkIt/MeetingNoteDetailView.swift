import SwiftUI
import AppKit

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

struct MeetingNoteDetailView: View {
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
