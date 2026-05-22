import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Restore the main window when the user clicks the Dock icon after
    // closing it. SwiftUI's WindowGroup default activates the app but
    // doesn't reliably re-show the window on macOS, causing a "flash" with
    // nothing visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where !(window is NSPanel) && window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return false
            }
        }
        return true
    }
}

@main
struct InkItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var history = TranscriptHistoryStore.shared

    var body: some Scene {
        WindowGroup("InkIt", id: "main") {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(history)
        }
        .windowResizability(.contentSize)
        .commands {
            // Strip the system menu bar down to the bare minimum. macOS won't
            // let us remove the leading "InkIt" menu (About/Quit live there)
            // while we keep the Dock icon, but everything else can go.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(replacing: .help) {}
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        if settings.hasCompletedOnboarding {
            MainWindowView()
                .frame(minWidth: 520, minHeight: 480)
        } else {
            OnboardingRootView()
                .frame(width: 720, height: 560)
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: TranscriptHistoryStore
    @State private var copiedID: UUID?
    @State private var showingSettings = false

    private struct TranscriptGroup: Identifiable {
        let id: Date
        let title: String
        let entries: [TranscriptHistoryStore.Entry]
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var groupedEntries: [TranscriptGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                let entries = grouped[day, default: []].sorted { $0.timestamp > $1.timestamp }
                return TranscriptGroup(id: day, title: title(for: day, calendar: calendar), entries: entries)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showingSettings {
                SettingsView()
            } else if history.entries.isEmpty {
                emptyState
            } else {
                transcriptList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showingSettings {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingSettings = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                Text("Settings")
                    .font(.headline)
            } else {
                Circle()
                    .fill(coordinator.statusColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("InkIt")
                        .font(.headline)
                    Text("Hold \(settings.hotkeyDisplayString) to dictate · \(coordinator.statusText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !showingSettings {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingSettings = true }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No transcripts yet")
                .font(.headline)
            Text("Hold \(settings.hotkeyDisplayString) and speak to dictate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var transcriptList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedEntries) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 2)

                            LazyVStack(spacing: 8) {
                                ForEach(group.entries) { entry in
                                    transcriptRow(entry)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            Divider()
            HStack {
                Text("\(history.entries.count) transcript\(history.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    history.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    private func transcriptRow(_ entry: TranscriptHistoryStore.Entry) -> some View {
        TranscriptHistoryRow(
            text: entry.text,
            timestamp: Self.timeFmt.string(from: entry.timestamp),
            copied: copiedID == entry.id
        ) {
            copy(entry)
        }
    }

    private func copy(_ entry: TranscriptHistoryStore.Entry) {
        let pb = NSPasteboard.general
        pb.declareTypes([.string], owner: nil)
        pb.setString(entry.text, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        let startOfToday = calendar.startOfDay(for: Date())
        if let daysAgo = calendar.dateComponents([.day], from: day, to: startOfToday).day,
           daysAgo < 7 {
            return Self.dayFmt.string(from: day)
        }

        return Self.dayFmt.string(from: day)
    }
}

private struct TranscriptHistoryRow: View {
    let text: String
    let timestamp: String
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                CopyTranscriptGlyph(copied: copied, highlighted: hovering)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(rowStroke, lineWidth: hovering || copied ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = isHovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: copied)
        .help(copied ? "Copied" : "Copy transcript")
        .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }

    private var rowFill: Color {
        if hovering {
            return Color.accentColor.opacity(0.08)
        }
        return Color(NSColor.controlBackgroundColor)
    }

    private var rowStroke: Color {
        Color.accentColor.opacity(copied ? 0.32 : 0.28)
    }
}

private struct CopyTranscriptGlyph: View {
    let copied: Bool
    let highlighted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(copied ? Color.green.opacity(0.15) : Color.primary.opacity(highlighted ? 0.06 : 0))
                .frame(width: 24, height: 24)

            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .frame(width: 24, height: 24)
        .animation(.easeOut(duration: 0.15), value: copied)
    }
}
