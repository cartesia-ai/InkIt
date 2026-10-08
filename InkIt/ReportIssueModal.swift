import SwiftUI
import AVFoundation

@MainActor
final class ClipPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var bars: [Float] = Array(repeating: 0.08, count: ClipPlayer.barCount)
    let duration: TimeInterval
    private static let barCount = 56

    private let player: AVAudioPlayer?
    private var timer: Timer?

    init(id: UUID) {
        player = try? AVAudioPlayer(contentsOf: ClipStore.url(for: id))
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        Task { [weak self] in
            let bars = await Task.detached(priority: .userInitiated) {
                ClipStore.waveform(for: id, bars: Self.barCount)
            }.value
            self?.bars = bars
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        stopTimer()
        isPlaying = false
        progress = 0
        elapsed = 0
    }

    private func tick() {
        guard let player else { return }
        if player.isPlaying {
            elapsed = player.currentTime
            progress = duration > 0 ? player.currentTime / duration : 0
        } else {
            stop()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct ReportIssueModal: View {
    let entry: TranscriptHistoryStore.Entry
    let onReported: () -> Void
    let onClose: () -> Void

    private enum Phase: Equatable {
        case composing
        case sending
        case sent
    }

    @StateObject private var player: ClipPlayer
    @State private var phase: Phase = .composing
    @State private var categories: Set<IssueCategory> = []
    @State private var editedText = ""
    @State private var transcriptHeight: CGFloat = 0
    @State private var showDetails = false
    @State private var errorMessage: String?
    @State private var canRetry = true
    @FocusState private var editorFocused: Bool

    init(entry: TranscriptHistoryStore.Entry, onReported: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.entry = entry
        self.onReported = onReported
        self.onClose = onClose
        _player = StateObject(wrappedValue: ClipPlayer(id: entry.id))
    }

    var body: some View {
        Group {
            if phase == .sent {
                sentCard
            } else {
                composeCard
            }
        }
        .onDisappear { player.stop() }
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Text("Report a transcription issue")
                    .font(.inkModalTitle)
                    .foregroundStyle(Color.inkText)
                Spacer(minLength: 12)
                InkCloseButton(onClose: close)
                    .padding(.top, -2)
                    .padding(.trailing, -6)
            }

            playerCard

            VStack(alignment: .leading, spacing: 10) {
                Text("What went wrong?")
                    .font(.inkSectionHeader)
                    .foregroundStyle(Color.inkSub)
                WrapLayout(spacing: 8) {
                    ForEach(IssueCategory.allCases) { category in
                        categoryChip(category)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                (Text("Feedback ").foregroundStyle(Color.inkSub)
                 + Text("(optional)").foregroundStyle(Color.inkFaint))
                    .font(.inkSectionHeader)
                TextEditor(text: $editedText)
                    .font(.inkBody)
                    .foregroundStyle(Color.inkText)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .onChange(of: editedText) { _, text in
                        if text.count > IssueReportPayload.feedbackLimit {
                            editedText = String(text.prefix(IssueReportPayload.feedbackLimit))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if editedText.isEmpty {
                            Text("Add any details that might help.")
                                .font(.inkBody)
                                .foregroundStyle(Color.inkFaint)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(height: 84)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color.modalCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(editorFocused ? Color.accentColor : Color.line, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 10) {
                disclosure
                if showDetails { detailsPanel }
                if let errorMessage { errorBanner(errorMessage) }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel", action: close)
                        .buttonStyle(InkSecondaryButtonStyle(compact: true))
                        .keyboardShortcut(.cancelAction)
                        .modifier(PointingHandCursor())
                    if canRetry {
                        Button(action: send) {
                            Text(primaryLabel)
                        }
                        .buttonStyle(InkButtonStyle(variant: .ink, compact: true))
                        .disabled(phase == .sending)
                        .modifier(PointingHandCursor())
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(width: 500)
        .animation(Motion.expand, value: showDetails)
        .animation(Motion.state, value: errorMessage)
    }

    private var primaryLabel: String {
        if phase == .sending { return "Sending…" }
        return errorMessage == nil ? "Send report" : "Retry"
    }

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))  // ds-allow: icon
                        .foregroundStyle(Color("InkFillText"))
                        .offset(x: player.isPlaying ? 0 : 1)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color("InkFill")))
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
                .accessibilityLabel(player.isPlaying ? "Pause recording" : "Play recording")

                waveform

                Text("\(Self.clock(player.elapsed)) / \(Self.clock(player.duration))")
                    .font(.inkCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSub)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcript")
                    .font(.inkSectionHeader)
                    .foregroundStyle(Color.inkSub)
                ScrollView {
                    Text(entry.text)
                        .font(.inkBody)
                        .foregroundStyle(Color.inkText)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: TranscriptHeightKey.self, value: proxy.size.height)
                        })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(transcriptHeight, Self.transcriptMaxHeight))
                .onPreferenceChange(TranscriptHeightKey.self) { transcriptHeight = $0 }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
                .fill(Color.modalCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 1)
        )
    }

    private var waveform: some View {
        let played = Int((player.progress * Double(player.bars.count)).rounded())
        let active = player.isPlaying || player.progress > 0
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(player.bars.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(active && index < played ? Color.accentColor : Color.inkFaint.opacity(0.45))
                    .frame(height: max(4, CGFloat(level) * 30))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 32)
    }

    private func categoryChip(_ category: IssueCategory) -> some View {
        let on = categories.contains(category)
        return Button {
            if on { categories.remove(category) } else { categories.insert(category) }
        } label: {
            Text(category.title)
                .font(on ? .inkCalloutEmphasized : .inkCallout)
                .foregroundStyle(on ? Color.accentColor : Color.inkText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(on ? Color.accentSoft : Color.modalCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(on ? Color.accentColor : Color.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(Motion.quick, value: on)
    }

    private var disclosure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            (Text("This recording, transcript, and device info will be shared with Cartesia to improve our models. ")
                .foregroundStyle(Color.inkSub)
             + Text(showDetails ? "Hide details" : "What’s included")
                .foregroundStyle(Color.accentColor)
                .fontWeight(.medium))
                .font(.inkCaption)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { showDetails.toggle() }
                .modifier(PointingHandCursor())
        }
    }

    private var detailsPanel: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            detailRow("Dictated", Self.dictatedFmt.string(from: entry.diagnostics?.startedAt ?? entry.timestamp))
            detailRow("App", entry.appName ?? "Unknown")
            detailRow("Dictionary", dictionarySummary)
            detailRow("Microphone", micSummary)
            detailRow("Mac", "\(DeviceInfo.macModel) · macOS \(DeviceInfo.osVersion)")
            detailRow("InkIt", "\(DeviceInfo.appVersion) · \(entry.diagnostics?.model ?? "ink-2") model")
        }
        .font(.inkCaption)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.chip)
        )
        .transition(.opacity)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Color.inkSub)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .foregroundStyle(Color.inkText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var dictionarySummary: String {
        let terms = entry.diagnostics?.keyterms ?? []
        return terms.isEmpty ? "None" : terms.joined(separator: ", ")
    }

    private var micSummary: String {
        guard let d = entry.diagnostics else { return "Unknown" }
        var parts: [String] = []
        if let name = d.micName { parts.append(name) }
        if let transport = d.micTransport { parts.append(transport.replacingOccurrences(of: "_", with: "-")) }
        if let rate = d.micSampleRate { parts.append("\(rate / 1000) kHz") }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " · ")
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.inkCaption)
            .foregroundStyle(Color.inkDanger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.inkDanger.opacity(0.1))
            )
            .transition(.opacity)
    }

    private var sentCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))  // ds-allow: icon
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.accentSoft))
                .padding(.bottom, 8)
            Text("Report sent")
                .font(.inkModalTitle)
                .foregroundStyle(Color.inkText)
            Text("Thanks. Reports like this help us make InkIt more accurate.")
                .font(.inkCallout)
                .foregroundStyle(Color.inkSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onClose) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(InkButtonStyle(variant: .ink))
            .keyboardShortcut(.defaultAction)
            .modifier(PointingHandCursor())
            .padding(.top, 18)
        }
        .padding(.horizontal, 42)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 408)
    }

    private func close() {
        guard phase != .sending else { return }
        onClose()
    }

    private func send() {
        player.stop()
        phase = .sending
        let entry = entry
        let categories = categories
        let text = editedText
        Task { @MainActor in
            do {
                try await IssueReporter.submit(entry: entry, categories: categories, editedText: text)
                onReported()
                withAnimation(Motion.state) { phase = .sent }
            } catch {
                phase = .composing
                apply(error)
            }
        }
    }

    private func apply(_ error: Error) {
        switch error {
        case IssueReportError.network:
            errorMessage = "Couldn’t send your report. Check your connection and try again."
            canRetry = true
        case IssueReportError.rateLimited:
            errorMessage = "Too many reports right now. Try again later."
            canRetry = false
        case IssueReportError.tooLarge:
            errorMessage = "This recording is too long to send."
            canRetry = false
        default:
            errorMessage = "Couldn’t send this report."
            canRetry = false
        }
        DebugLog.info("IssueReport: send failed — \(error)")
    }

    private static let transcriptMaxHeight: CGFloat = 126

    private static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private static let dictatedFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
}

private struct TranscriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
