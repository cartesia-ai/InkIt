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
                // Sit the wordmark clear of the traffic-light row and give the
                // nav below it real air — the rail leads with the brand, not a
                // row of tabs crowded against the titlebar (round 13).
                .padding(.top, 20)
                .padding(.bottom, 22)

            ForEach(MainSection.allCases) { s in
                SidebarNavItem(icon: s.icon, title: s.title, selected: section == s) {
                    section = s
                }
                // ⌘1 / ⌘2 switch sections from anywhere in the window. The
                // hidden button carries the shortcut so the visible row keeps
                // its hover/selection treatment untouched (same trick as ⌘F).
                .background(
                    Button(action: { section = s }) { EmptyView() }
                        .keyboardShortcut(s.shortcut, modifiers: .command)
                        .opacity(0)
                        .allowsHitTesting(false)
                )
            }

            Spacer(minLength: 12)

            // Hairline splitting the page nav from the bottom utility rows — a
            // quiet cue that what's below *acts* rather than navigating a page.
            Rectangle()
                .fill(Color.line)
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            // Bottom utility group — the rows that act rather than navigate a
            // page: Settings opens a modal, Feedback opens a form. Neither wears
            // the page-selection tint. That treatment marks the *current page*,
            // so lighting Settings while Home is still the page read as two
            // selected rows at once; the modal's scrim already signals it's open.
            SidebarNavItem(icon: "gearshape", title: "Settings",
                           selected: false, action: onOpenSettings)
            // "Feedback" (not "Share feedback") so it stays one clean line in the
            // fixed 180pt rail; the bubble glyph already reads as feedback.
            SidebarNavItem(icon: "bubble.left", title: "Feedback",
                           selected: false) {
                NSWorkspace.shared.open(Self.feedbackURL)
            }

            footerMetaRow
                .padding(.horizontal, 6)
                .padding(.top, 10)
        }
        .padding(10)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.sidebar.ignoresSafeArea())
    }

    // The wordmark: the real app icon + the app name. macOS icons carry their
    // own shape and inset, so it renders a touch larger than a flat tile would.
    private var logoRow: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            // Medium, not bold — the app leads with size over weight; the
            // wordmark sits a hair above the pane titles it navigates to so the
            // brand reads first without a heavy weight shouting over the content.
            Text("InkIt")
                .font(.inkWordmark)
                .foregroundStyle(Color.inkText)
        }
    }

    /// The feedback Google Form — opened by the bottom "Share feedback" row
    /// (and mirrored by the Help menu's "Report an Issue…").
    private static let feedbackURL = URL(string: "https://forms.gle/jXNtDsTaLt2rKQ8N9")!

    // One quiet meta line: just the version, at caption scale.
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

/// A single sidebar navigation row. Selection is the *neutral* `navSelected`
/// deepening of the sidebar paper (not the amber `accentSoft` — the accent only
/// tints the selected glyph), per DESIGN_SYSTEM.md › Shell & structure tokens.
private struct SidebarNavItem: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Body-scale labels, medium (not semibold) when selected — the
            // sidebar sits on the same type ladder as the content it points
            // to, matching how History rows and buttons carry emphasis.
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

