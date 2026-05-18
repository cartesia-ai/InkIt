import SwiftUI

@main
struct InksperApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        // Primary window. Shows onboarding on first launch; otherwise the
        // settings/control surface.
        WindowGroup("Inksper") {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)

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
                SettingsView()
                    .frame(minWidth: 480, minHeight: 580)
            } else {
                OnboardingRootView()
                    .frame(width: 720, height: 560)
            }
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore

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
                openMainWindow()
            }
            Button("Show onboarding…") {
                settings.hasCompletedOnboarding = false
                openMainWindow()
            }
            Button("Quit Inksper") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Bring an existing window forward, or open one if none exist.
        if let win = NSApp.windows.first(where: { $0.title == "Inksper" || $0.title.isEmpty == false }) {
            win.makeKeyAndOrderFront(nil)
        } else if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
