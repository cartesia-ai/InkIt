import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case home
    case dictionary
    case insights
    case meetingNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:         return "Home"
        case .dictionary:   return "Dictionary"
        case .insights:     return "Insights"
        case .meetingNotes: return "Meeting Notes"
        }
    }

    var icon: String {
        switch self {
        case .home:         return "house"
        case .dictionary:   return "character.book.closed"
        case .insights:     return "chart.bar.xaxis"
        case .meetingNotes: return "note.text"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .home:         return "1"
        case .dictionary:   return "2"
        case .insights:     return "3"
        case .meetingNotes: return "4"
        }
    }
}

struct SidebarView: View {
    @Binding var section: MainSection
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            logoRow
                .padding(.horizontal, 8)
                .padding(.top, 20)
                .padding(.bottom, 22)

            ForEach(MainSection.allCases) { s in
                SidebarNavItem(icon: s.icon, title: s.title, selected: section == s) {
                    section = s
                }
                .background(
                    Button(action: { section = s }) { EmptyView() }
                        .keyboardShortcut(s.shortcut, modifiers: .command)
                        .opacity(0)
                        .allowsHitTesting(false)
                )
            }

            Spacer(minLength: 12)

            Rectangle()
                .fill(Color.line)
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            SidebarNavItem(icon: "gearshape", title: "Settings",
                           selected: false, action: onOpenSettings)
            SidebarNavItem(icon: "bubble.left", title: "Feedback",
                           selected: false) {
                NSWorkspace.shared.open(Self.feedbackURL)
            }

            footerMetaRow
                .padding(.horizontal, 6)
                .padding(.top, 10)
        }
        .padding(10)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.sidebar.ignoresSafeArea())
    }

    private var logoRow: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Text("InkIt")
                .font(.inkWordmark)
                .foregroundStyle(Color.inkText)
        }
    }

    private static let feedbackURL = URL(string: "https://forms.gle/jXNtDsTaLt2rKQ8N9")!

    private var footerMetaRow: some View {
        Text("v\(Self.shortVersion)")
            .font(.inkCaption)
            .foregroundStyle(Color.inkFaint)
            .lineLimit(1)
            .fixedSize()
    }

    private static let shortVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
}

private struct SidebarNavItem: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.inkBody)
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.accentColor : Color.inkSub)
                Text(title)
                    .font(selected ? .inkBodyEmphasized : .inkBody)
                    .foregroundStyle(selected ? Color.inkText : Color.inkSub)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .hoverBackdrop(cornerRadius: Radius.control, isActive: selected,
                           activeFill: .navSelected)
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}

