import SwiftUI

/// Floating, undismissable pill that surfaces Sparkle update state on Home.
/// Hidden while `.idle`; otherwise sits bottom-center over the window content.
/// Maps 1:1 to `UpdateManager.Phase` (see prototypes/update-indicator.html).
struct UpdatePill: View {
    @ObservedObject private var updates = UpdateManager.shared

    var body: some View {
        Group {
            switch updates.phase {
            case .idle:
                EmptyView()
            case .available:
                pill(label: "New app version available") {
                    actionButton("Update now") { updates.installNow() }
                }
            case .updating:
                pill(label: "Updating…") {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 2)
                }
            case .ready:
                pill(label: "Update ready") {
                    actionButton("Restart now") { updates.restartNow() }
                }
            }
        }
        .animation(Motion.expand, value: updates.phase)
    }

    @ViewBuilder
    private func pill<Trailing: View>(label: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14, weight: .medium))  // ds-allow: icon
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.inkCallout)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
            trailing()
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .shadow(color: Elevation.chip, radius: 12, y: 4)
        .padding(.bottom, 22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // Same accentSoft keycap chip as the Home "dictate anywhere" header
    // (`HotkeyCaps`), made tappable — keeps the pill low and on-pattern.
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.inkCallout)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
                        .fill(Color.accentSoft)
                )
        }
        .buttonStyle(.plain)
        .modifier(PointingHandCursor())
    }
}
