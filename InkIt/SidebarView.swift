import SwiftUI

// MARK: - Main-window sections

/// The main window's top-level sections, navigated by the left sidebar
/// (round-10 shell — see prototypes/design-direction-round10.md). Dictionary
/// and Styles join under a "Personalize" group in a later round.
enum MainSection: String, CaseIterable, Identifiable {
    case home
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:     return "Home"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house"
        case .insights: return "chart.bar.xaxis"
        }
    }

    /// ⌘1, ⌘2, … in sidebar order.
    var shortcut: KeyEquivalent {
        switch self {
        case .home:     return "1"
        case .insights: return "2"
        }
    }
}

// MARK: - Sidebar

/// The main window's left rail: wordmark, section navigation, and a footer with
/// Settings, the live "armed" status pill, and the version caption. A fixed
/// 180pt column on its own deeper paper (`Color.sidebar`), extending under the
/// transparent titlebar so the column reads floor-to-ceiling.
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

