import SwiftUI
import Foundation

struct DictionaryView: View {
    @EnvironmentObject var settings: SettingsStore

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var flashKey: String?
    @State private var charBudgetBlocked = false
    @State private var exampleIndex = 0
    @State private var exampleOpacity: Double = 1
    @State private var rowWidth: CGFloat = 0

    private var leftColumnWidth: CGFloat {
        min(380, max(340, rowWidth * 0.34))
    }

    private let cycleTimer = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()

    private static let examples: [(misheard: String, correct: String)] = [
        ("Cooper Netty's", "Kubernetes"),
        ("graph cue well", "GraphQL"),
        ("Shivawn", "Siobhan"),
        ("engine X", "nginx"),
        ("Sequel", "SQL")
    ]

    private var terms: [String] { settings.dictionaryTerms }
    private var atTermLimit: Bool { terms.count >= DictionaryLimits.maxTerms }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                layoutBody
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { geo in
                Color.clear.onChange(of: geo.size.width, initial: true) { _, w in rowWidth = w }
            })
            .pageFrame()
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(cycleTimer) { _ in rotateExample() }
        .onChange(of: terms) { _, _ in charBudgetBlocked = false }
    }

    @ViewBuilder private var layoutBody: some View {
        if rowWidth >= 660 {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 16) {
                    exampleBanner
                    addBar
                    limitNoteView
                }
                .frame(width: leftColumnWidth, alignment: .leading)
                wordsPanel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if rowWidth >= 440 {
                    exampleBanner
                }
                addBar
                limitNoteView
                wordsPanel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var limitNoteView: some View {
        if let note = limitNote {
            Text(note.text)
                .font(.inkCaption)
                .foregroundStyle(note.isFull ? Color.accentColor : Color.inkFaint)
                .transition(.opacity)
        }
    }

    private func rotateExample() {
        withAnimation(Motion.state) { exampleOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            exampleIndex = (exampleIndex + 1) % Self.examples.count
            withAnimation(Motion.state) { exampleOpacity = 1 }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dictionary")
                .font(.inkTitle)
                .foregroundStyle(Color.inkText)
            Text("Tell InkIt which words to listen for: names, brands, and anything it keeps mishearing.")
                .font(.inkCallout)
                .foregroundStyle(Color.inkSub)
        }
    }

    private var exampleBanner: some View {
        let pair = Self.examples[exampleIndex]
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Waveform()
                    .frame(width: 88, height: 26)
                Text("“\(pair.misheard)”")
                    .font(.inkCaption)
                    .italic()
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .opacity(exampleOpacity)
            }
            .frame(width: 124, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.inkCaption)
                .foregroundStyle(Color.inkFaint)
            Text(pair.correct)
                .font(.inkModalTitle)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .opacity(exampleOpacity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [Color.card, Color.accentSoft],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: shape
        )
        .overlay(shape.stroke(Color.line, lineWidth: 1))
        .shadow(color: Elevation.soft, radius: 6, y: 2)
    }

    private var addBar: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
        return HStack(spacing: 8) {
            TextField("Add a word or phrase", text: $draft)
                .textFieldStyle(.plain)
                .font(.inkCallout)
                .foregroundStyle(Color.inkText)
                .focused($fieldFocused)
                .disabled(atTermLimit)
                .onSubmit(commitDraft)
                .onKeyPress(.delete) {
                    guard draft.isEmpty, !terms.isEmpty else { return .ignored }
                    remove(terms[terms.count - 1])
                    return .handled
                }
                .padding(.leading, 11)
                .padding(.vertical, 9)
            addButton
        }
        .padding(4)
        .background(Color.card, in: shape)
        .contentShape(shape)
        .onTapGesture {
            guard !atTermLimit else { return }
            fieldFocused = true
        }
        .overlay(shape.stroke(fieldFocused ? Color.accentColor : Color.line, lineWidth: 1))
        .shadow(color: Elevation.soft, radius: 6, y: 2)
        .animation(Motion.state, value: fieldFocused)
        .dismissOnClickOutside(isActive: fieldFocused) { fieldFocused = false }
    }

    private var canAdd: Bool {
        !atTermLimit && SettingsStore.normalizedDictionaryTerm(draft) != nil
    }

    private var addButton: some View {
        Button(action: commitDraft) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.inkCaption)
                Text("Add")
                    .font(.inkCalloutEmphasized)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(Color.accentColor))
            .opacity(canAdd ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .modifier(PointingHandCursor())
        .animation(Motion.state, value: canAdd)
    }

    private var wordsPanel: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your words")
                .font(.inkHeadline)
                .foregroundStyle(Color.inkText)
            if terms.isEmpty {
                Text("Words you add appear here.")
                    .font(.inkCallout)
                    .foregroundStyle(Color.inkFaint)
            } else {
                FlowLayout(spacing: 9, lineSpacing: 9) {
                    ForEach(terms, id: \.self) { term in
                        TermChip(term: term,
                                 flashing: flashKey == term,
                                 onRemove: { remove(term) })
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(Color.card, in: shape)
        .overlay(shape.stroke(Color.line, lineWidth: 1))
        .shadow(color: Elevation.soft, radius: 6, y: 2)
        .animation(Motion.state, value: terms)
    }

    private var limitNote: (text: String, isFull: Bool)? {
        if atTermLimit || charBudgetBlocked {
            return ("Your dictionary is full. Remove a word to add another.", true)
        }
        let remaining = DictionaryLimits.maxTerms - terms.count
        if terms.count >= DictionaryLimits.approachingTerms {
            return ("\(remaining) more to go — a shorter, focused list works best.", false)
        }
        return nil
    }

    private func commitDraft() {
        charBudgetBlocked = false
        guard let clean = SettingsStore.normalizedDictionaryTerm(draft) else {
            draft = ""
            return
        }
        if terms.contains(clean) {
            flash(clean)
            draft = ""
            return
        }
        guard !atTermLimit else { return }
        let used = terms.reduce(0) { $0 + $1.count }
        if used + clean.count > DictionaryLimits.maxCharacters {
            charBudgetBlocked = true
            return
        }
        settings.dictionaryTerms.append(clean)
        draft = ""
    }

    private func remove(_ term: String) {
        settings.dictionaryTerms.removeAll { $0 == term }
    }

    private func flash(_ term: String) {
        withAnimation(Motion.state) { flashKey = term }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if flashKey == term { withAnimation(Motion.state) { flashKey = nil } }
        }
    }
}

private struct Waveform: View {
    var barCount = 14

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Double(i) * 0.55
                    let level = 0.26 + 0.74 * (0.5 + 0.5 * sin(t * 4.2 + phase))
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: 3, height: max(3, 26 * level))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct TermChip: View {
    let term: String
    let flashing: Bool
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Text(term)
                .font(.inkCallout)
                .foregroundStyle(Color.inkText)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.inkEyebrow)
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 14, height: 14)
                    .hoverBackdrop(cornerRadius: Radius.control)
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .onHover { hovering = $0 }
        .animation(Motion.state, value: hovering)
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.chip, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(Color.accentColor, lineWidth: flashing ? 1.5 : 0)
        )
        .scaleEffect(flashing ? 1.06 : 1)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
