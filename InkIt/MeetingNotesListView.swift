import SwiftUI
import AppKit

private struct RowAnchorKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

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
                notesList
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pageFrame()
        }
        .scrollIndicators(.hidden)
        .onReceive(hintTimer) { _ in rotateHint() }
        .overlay { apiKeyGateModal }
        .overlayPreferenceValue(RowAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let id = hoveredNoteID,
                   let note = meetingNotes.notes.first(where: { $0.id == id }),
                   let anchor = anchors[id] {
                    let rowFrame = proxy[anchor]
                    let margin: CGFloat = 12
                    let flipped = rowFrame.minY + HoverFlyoutCard.estimatedMaxHeight > proxy.size.height - margin
                    let availableHeight = flipped ? rowFrame.maxY - margin : proxy.size.height - rowFrame.minY - margin
                    let desiredX = rowFrame.maxX + Self.flyoutGap
                    let maxX = proxy.size.width - HoverFlyoutCard.width - Self.scrollbarInset
                    let offsetX = min(desiredX, max(0, maxX))
                    VStack(spacing: 0) {
                        if flipped {
                            Spacer(minLength: 0)
                            HoverFlyoutCard(note: note, availableHeight: availableHeight,
                                            onOpenNote: { selectedNoteID = note.id })
                            Color.clear.frame(height: max(0, proxy.size.height - rowFrame.maxY))
                        } else {
                            Color.clear.frame(height: max(0, rowFrame.minY))
                            HoverFlyoutCard(note: note, availableHeight: availableHeight,
                                            onOpenNote: { selectedNoteID = note.id })
                            Spacer(minLength: 0)
                        }
                    }
                    .id(note.id)
                    .frame(width: HoverFlyoutCard.width, height: proxy.size.height, alignment: .leading)
                    .offset(x: offsetX)
                }
            }
        }
    }

    private static let flyoutGap: CGFloat = 24
    private static let scrollbarInset: CGFloat = 16

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

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 4) {
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

}

private struct HoverFlyoutCard: View {
    let note: MeetingNotesStore.Note
    let availableHeight: CGFloat
    let onOpenNote: () -> Void

    static let width: CGFloat = 300
    static let collapsedBodyMaxHeight: CGFloat = 110
    private static let chromeHeight: CGFloat = 100
    private static let expandedChromeHeight: CGFloat = chromeHeight + 34
    static let estimatedMaxHeight: CGFloat = chromeHeight + collapsedBodyMaxHeight

    private static let bodyFont = NSFont.systemFont(ofSize: 15)
    private static let bodyEmphasizedFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    private static let innerWidth: CGFloat = width - 40
    private static let actionItemIndent: CGFloat = 12 + 14

    @State private var isExpanded = false

    private var effectiveBodyMaxHeight: CGFloat {
        let chrome = isExpanded ? Self.expandedChromeHeight : Self.chromeHeight
        let desired = isExpanded ? availableHeight - chrome : Self.collapsedBodyMaxHeight
        return max(60, min(desired, availableHeight - chrome))
    }

    private var naturalBodyHeight: CGFloat {
        if !note.summaryLines.isEmpty {
            let overview = note.overviewLines
            let actionItems = note.actionItemLines
            var total: CGFloat = 0
            for (index, line) in overview.enumerated() {
                if index > 0 { total += 8 }
                total += Self.measuredHeight(line.text, font: Self.bodyFont, width: Self.innerWidth)
            }
            if !actionItems.isEmpty {
                total += overview.isEmpty ? 0 : 4
                total += Self.measuredHeight("Action Items", font: Self.bodyEmphasizedFont, width: Self.innerWidth)
                for (index, line) in actionItems.enumerated() {
                    if index > 0 { total += 6 }
                    total += Self.measuredHeight(line.text, font: Self.bodyFont, width: Self.innerWidth - Self.actionItemIndent)
                }
            }
            return total
        } else if let summary = note.summary, !summary.isEmpty {
            return Self.measuredHeight(summary, font: Self.bodyFont, width: Self.innerWidth)
        }
        return 0
    }

    private static func measuredHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else { return 0 }
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let rect = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height)
    }

    private var isTruncated: Bool { naturalBodyHeight > effectiveBodyMaxHeight }

    var body: some View {
        if !note.summaryLines.isEmpty || !(note.summary ?? "").isEmpty {
            let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            VStack(alignment: .leading, spacing: 10) {
                Text(note.title)
                    .font(.inkReadingEmphasized)
                    .foregroundStyle(Color.inkText)
                Text(DateGrouping.timestampFmt.string(from: note.createdAt))
                    .font(.inkCaption)
                    .foregroundStyle(Color.inkFaint)
                summaryBody
                if isExpanded {
                    expandedFooterRow
                }
            }
            .padding(20)
            .frame(width: Self.width, alignment: .topLeading)
            .background(Color.card, in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(Color.line, lineWidth: 1))
            .shadow(color: Elevation.card, radius: 12, y: 4)
            .shadow(color: Elevation.soft, radius: 3, y: 1)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var summaryBody: some View {
        summaryContent
            .frame(maxHeight: effectiveBodyMaxHeight, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                if isTruncated {
                    LinearGradient(colors: [Color.card.opacity(0), Color.card],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 32)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isExpanded, isTruncated {
                    pillButton(title: "Show more", systemImage: "chevron.down") {
                        withAnimation(Motion.state) { isExpanded = true }
                    }
                }
            }
    }

    @ViewBuilder private var expandedFooterRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if isTruncated {
                pillButton(title: "Open note", systemImage: "arrow.right", action: onOpenNote)
            } else {
                pillButton(title: "Show less", systemImage: "chevron.up") {
                    withAnimation(Motion.state) { isExpanded = false }
                }
            }
        }
    }

    private func pillButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))  // ds-allow: icon
            }
            .font(.inkCaption)
            .fontWeight(.medium)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.card, in: Capsule())
            .overlay(Capsule().stroke(Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }

    @ViewBuilder private var summaryContent: some View {
        if !note.summaryLines.isEmpty {
            let overview = note.overviewLines
            let actionItems = note.actionItemLines
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
            rowIcon
                .frame(width: 20)
                .padding(.top, 2)
            Text(note.title)
                .font(.inkReading)
                .foregroundStyle(Color.inkText)
                .lineLimit(1)
            Spacer(minLength: 0)
            rowActions
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            Text(Self.timeFmt.string(from: note.createdAt))
                .font(.inkCaption)
                .foregroundStyle(Color.inkSub)
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * 0.65 }
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
        .anchorPreference(key: RowAnchorKey.self, value: .bounds) { [note.id: $0] }
        .alert("Delete this note?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteNote(note.id) }
        } message: {
            Text("This permanently deletes the recording and transcript.")
        }
    }

    @ViewBuilder private var rowIcon: some View {
        if let icon = note.icon, !icon.isEmpty {
            Text(icon)
                .font(.inkBody)
        } else {
            Image(systemName: "doc.text")
                .font(.inkBody)
                .foregroundStyle(Color.inkSub)
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
