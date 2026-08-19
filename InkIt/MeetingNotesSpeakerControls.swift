import SwiftUI

struct SpeakerLabelControl: View {
    let speakerID: UUID
    let displayName: String
    let speakers: [MeetingNotesStore.Speaker]
    let onReassign: (UUID) -> Void
    let onNewSpeaker: () -> Void

    @State private var hovering = false
    @State private var showReassignMenu = false

    private var colorKey: String {
        speakers.first(where: { $0.id == speakerID })?.label ?? displayName
    }

    var body: some View {
        Button {
            showReassignMenu = true
        } label: {
            Text(displayName)
                .font(.inkBodyEmphasized)
                .foregroundStyle(SpeakerColor.forLabel(colorKey))
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

struct SpeakersInCallPanel: View {
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
                .fill(SpeakerColor.forLabel(speaker.label))
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
                    .fill(SpeakerColor.forLabel(speaker.label))
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
                           ? SpeakerColor.forLabel(speaker.label).opacity(0.14)
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
