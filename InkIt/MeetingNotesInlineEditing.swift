import SwiftUI
import AppKit

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

struct TranscriptBubble: View {
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

extension View {
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
        let resolvedColor = NSColor(textColor)
        field.textColor = resolvedColor
        if let editor = field.currentEditor() as? NSTextView {
            editor.textColor = resolvedColor
        }
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

struct EditableTranscriptBubble: View {
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
