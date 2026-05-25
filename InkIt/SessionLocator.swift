import Foundation
import AppKit

/// Identifies the Cursor agent session the user is currently focused on.
///
/// The hard wall is that nothing inside the JSONL files or Cursor's window
/// AX tree tells us "this is the active session". We combine several weak
/// signals to make a confident guess:
///
/// 1. Focused-window title via AX. Cursor's dedicated agents window has the
///    fixed title "Cursor Agents" and corresponds to the `empty-window`
///    project on disk. Workspace-attached windows usually carry the
///    workspace folder name somewhere in the title.
/// 2. `~/Library/Application Support/Cursor/User/workspaceStorage/<hash>/workspace.json`
///    files contain `{"folder": "file:///path/to/workspace"}`. The most-
///    recently-modified entry there is a reasonable proxy for the
///    workspace Cursor focused most recently.
/// 3. Within the narrowed project (or all projects when we can't narrow),
///    pick the .jsonl with the freshest mtime, filtered to "modified within
///    the last 4 hours" so background-agent activity from days ago can't
///    win.
struct SessionLocation {
    let url: URL
    let uuid: String
    let project: String
}

enum SessionLocator {
    private static let staleAge: TimeInterval = 4 * 60 * 60

    static func locate(forApp app: NSRunningApplication?, windowTitle: String?) -> SessionLocation? {
        let cursorRoot = projectsRoot()
        guard FileManager.default.fileExists(atPath: cursorRoot.path) else {
            DebugLog.info("SessionLocator: ~/.cursor/projects missing")
            return nil
        }

        // 1) Title-driven narrowing
        if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            if title == "Cursor Agents" || title == "Agents" {
                if let loc = newestSession(inProject: "empty-window", under: cursorRoot, label: "title=\(title)") {
                    return loc
                }
            }
            if let project = projectMatching(title: title, under: cursorRoot) {
                if let loc = newestSession(inProject: project, under: cursorRoot, label: "title-match=\(title)") {
                    return loc
                }
            }
        }

        // 2) workspaceStorage cross-reference
        if let project = recentWorkspaceProject(under: cursorRoot) {
            if let loc = newestSession(inProject: project, under: cursorRoot, label: "workspaceStorage") {
                return loc
            }
        }

        // 3) Newest-mtime fallback across all projects
        return newestSessionAnywhere(under: cursorRoot)
    }

    // MARK: - Helpers

    private static func projectsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    /// Looks for a project slug whose decoded path tail matches a token in
    /// the window title. Cursor encodes workspace paths as slugs by
    /// replacing `/` with `-` and dropping the leading `/`. So
    /// `/Users/danielepaliotta/conductor/workspaces/abu-dhabi` becomes
    /// `Users-danielepaliotta-conductor-workspaces-abu-dhabi`. We don't
    /// need to perfectly decode that — just check whether the final
    /// path component appears in the slug AND in the title.
    private static func projectMatching(title: String, under root: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return nil
        }
        return projectMatching(title: title, candidates: entries)
    }

    /// Filesystem-free version, exposed for tests. The caller supplies the
    /// candidate slugs directly.
    static func projectMatching(title: String, candidates: [String]) -> String? {
        let lowerTitle = title.lowercased()
        var bestMatch: (project: String, score: Int)? = nil
        for project in candidates where project != "empty-window" {
            // The last hyphen-separated segment of the slug is the leaf
            // workspace folder. Match against the title.
            let leaf = project.split(separator: "-").last.map(String.init) ?? project
            guard leaf.count >= 3 else { continue }
            if lowerTitle.contains(leaf.lowercased()) {
                let score = leaf.count
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (project, score)
                }
            }
        }
        return bestMatch?.project
    }

    /// The slug of the workspace whose Cursor `workspaceStorage/<hash>/`
    /// directory was modified most recently. Cursor touches these whenever
    /// the user interacts with the window, so this is a strong "last
    /// focused" signal.
    private static func recentWorkspaceProject(under root: URL) -> String? {
        let storageRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: storageRoot,
                                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                                         options: [.skipsHiddenFiles]) else {
            return nil
        }
        // Newest first.
        let sorted = entries.sorted { a, b in
            let am = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bm = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return am > bm
        }
        for storageDir in sorted.prefix(10) {
            let workspaceJSON = storageDir.appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: workspaceJSON),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = obj["folder"] as? String,
                  let url = URL(string: folder),
                  url.scheme == "file"
            else { continue }
            // Convert the file path to a Cursor project slug:
            // /Users/.../workspaces/abu-dhabi → Users-...-workspaces-abu-dhabi
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let slug = path.replacingOccurrences(of: "/", with: "-")
            let candidate = root.appendingPathComponent(slug)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return slug
            }
        }
        return nil
    }

    private static func newestSession(inProject project: String, under root: URL, label: String) -> SessionLocation? {
        let transcriptsRoot = root
            .appendingPathComponent(project, isDirectory: true)
            .appendingPathComponent("agent-transcripts", isDirectory: true)
        guard FileManager.default.fileExists(atPath: transcriptsRoot.path) else { return nil }
        guard let url = newestJSONL(under: transcriptsRoot) else { return nil }
        let uuid = url.deletingPathExtension().lastPathComponent
        DebugLog.info("SessionLocator: matched via \(label) → project=\(project) session=\(uuid)")
        return SessionLocation(url: url, uuid: uuid, project: project)
    }

    private static func newestSessionAnywhere(under root: URL) -> SessionLocation? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return nil
        }
        var best: (url: URL, mtime: Date, project: String)? = nil
        for project in entries {
            let transcripts = root
                .appendingPathComponent(project, isDirectory: true)
                .appendingPathComponent("agent-transcripts", isDirectory: true)
            guard let url = newestJSONL(under: transcripts) else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if let current = best, current.mtime >= mtime { continue }
            best = (url, mtime, project)
        }
        guard let best else { return nil }
        let uuid = best.url.deletingPathExtension().lastPathComponent
        DebugLog.info("SessionLocator: matched via newest-mtime fallback → project=\(best.project) session=\(uuid)")
        return SessionLocation(url: best.url, uuid: uuid, project: best.project)
    }

    private static func newestJSONL(under dir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        let cutoff = Date(timeIntervalSinceNow: -staleAge)
        var best: (URL, Date)? = nil
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let mtime = values?.contentModificationDate ?? .distantPast
            if mtime < cutoff { continue }
            if let (_, current) = best, current >= mtime { continue }
            best = (url, mtime)
        }
        return best?.0
    }
}
