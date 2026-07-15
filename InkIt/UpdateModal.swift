import SwiftUI

struct UpdateModal: View {
    @ObservedObject private var updates = UpdateManager.shared
    @EnvironmentObject private var coordinator: AppCoordinator

    private var isPresented: Bool {
        updates.phase == .ready && coordinator.state == .idle
    }

    var body: some View {
        ZStack {
            if isPresented {
                InkModal(onDismiss: updates.dismissForNow,
                         scrim: .scrimStrong,
                         dismissOnTapOutside: false) {
                    card
                }
            }
        }
        .animation(Motion.quick, value: isPresented)
    }

    private var card: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 70, height: 70)
                .padding(.bottom, 24)

            Text("A new version of InkIt is available")
                .font(.inkModalTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !updates.availableVersion.isEmpty {
                Text("Version \(updates.availableVersion)")
                    .font(.inkCallout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 9)
            }

            VStack(spacing: 4) {
                Button { updates.restartNow() } label: {
                    Text("Relaunch to update").frame(maxWidth: .infinity)
                }
                .buttonStyle(InkButtonStyle(variant: .accent))
                .keyboardShortcut(.defaultAction)
                .modifier(PointingHandCursor())
                Button { updates.dismissForNow() } label: {
                    Text("Later")
                }
                .buttonStyle(InkSecondaryButtonStyle(compact: true))
                .keyboardShortcut(.cancelAction)
                .modifier(PointingHandCursor())
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 42)
        .padding(.top, 48)
        .padding(.bottom, 30)
        .frame(width: 408)
    }
}
