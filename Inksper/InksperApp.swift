import SwiftUI

@main
struct InksperApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        // Primary window. Shows onboarding on first launch; otherwise the
        // app runs from the notch/menu bar without a persistent window.
        WindowGroup("Inksper", id: "main") {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .frame(width: 520, height: 620)
        }

        // Menu bar entry as a secondary surface — fine if it's visible, fine
        // if it isn't (the main window covers everything).
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(coordinator)
                .environmentObject(settings)
        } label: {
            Text(coordinator.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                WindowCloser()
            } else {
                OnboardingRootView()
                    .frame(width: 720, height: 560)
            }
        }
    }
}

private struct WindowCloser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.close()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.close()
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(coordinator.statusColor)
                    .frame(width: 10, height: 10)
                Text(coordinator.statusText)
                    .font(.headline)
                Spacer()
            }
            Divider()
            Text("Hold \(settings.hotkeyDisplayString) to dictate")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let err = coordinator.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            Divider()
            Button("Settings…") {
                openSettingsWindow()
            }
            Button("Show onboarding…") {
                settings.hasCompletedOnboarding = false
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button("Quit Inksper") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
