import SwiftUI

@main
struct InksperApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        // Main window: doubles as the settings/control surface. Shows on launch
        // and when the user clicks the Dock icon.
        WindowGroup("Inksper") {
            SettingsView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .frame(minWidth: 480, minHeight: 580)
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
                NSApp.activate(ignoringOtherApps: true)
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            Button("Quit Inksper") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
