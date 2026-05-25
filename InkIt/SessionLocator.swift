import Foundation

struct SessionLocation: Equatable {
    let url: URL
    let uuid: String
    let project: String
    let evidence: [String: String]
}

enum SessionLookupResult: Equatable {
    case located(SessionLocation)
    case rejected(reason: String, evidence: [String: String])
}

enum SessionLocator {
    static func locateStrict(windowTitle: String?, runID: String? = nil) -> SessionLookupResult {
        locateStrict(
            windowTitle: windowTitle,
            projectsRoot: projectsRoot(),
            workspaceStorageRoot: workspaceStorageRoot(),
            now: Date(),
            runID: runID
        )
    }

    static func locateStrict(windowTitle: String?,
                             projectsRoot: URL,
                             workspaceStorageRoot: URL,
                             now: Date,
                             runID: String? = nil) -> SessionLookupResult {
        let logPrefix = runID.map { "[\($0)] " } ?? ""
        guard FileManager.default.fileExists(atPath: projectsRoot.path) else {
            DebugLog.info("\(logPrefix)SessionLocator: projects root missing path=\(projectsRoot.path)")
            return .rejected(reason: "cursor projects root missing", evidence: ["projectsRoot": projectsRoot.path])
        }

        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return .rejected(reason: "missing cursor window title", evidence: [:])
        }

        if title == "Cursor Agents" || title == "Agents" {
            return locateUniqueSession(
                inProject: "empty-window",
                under: projectsRoot,
                now: now,
                evidence: ["match": "literal-window-title", "windowTitle": title],
                runID: runID
            )
        }

        let records = workspaceRecords(root: workspaceStorageRoot)
        let matchingRemote = records.filter { record in
            guard case .remoteSSH = record.workspace else { return false }
            return titleMatchesWorkspace(title: title, workspace: record.workspace)
        }
        if !matchingRemote.isEmpty {
            let first = matchingRemote[0]
            DebugLog.info("\(logPrefix)SessionLocator: remote workspace detected \(first.workspace.evidenceDescription)")
            return .rejected(
                reason: "remote workspace",
                evidence: [
                    "workspace": first.workspace.evidenceDescription,
                    "workspaceJSON": first.workspaceJSON.path,
                    "windowTitle": title
                ]
            )
        }

        let matchingLocal = records.compactMap { record -> (record: WorkspaceRecord, project: String)? in
            guard case .local(let url) = record.workspace,
                  titleMatchesWorkspace(title: title, workspace: record.workspace) else {
                return nil
            }
            let slug = projectSlug(forLocalWorkspace: url)
            let candidate = projectsRoot.appendingPathComponent(slug, isDirectory: true)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return (record, slug)
        }

        guard !matchingLocal.isEmpty else {
            return .rejected(reason: "no exact local workspace match", evidence: ["windowTitle": title])
        }
        guard matchingLocal.count == 1 else {
            return .rejected(
                reason: "ambiguous local workspace match",
                evidence: [
                    "windowTitle": title,
                    "matches": matchingLocal.map(\.project).joined(separator: ",")
                ]
            )
        }

        let match = matchingLocal[0]
        return locateUniqueSession(
            inProject: match.project,
            under: projectsRoot,
            now: now,
            evidence: [
                "match": "workspaceStorage-local-file",
                "workspace": match.record.workspace.evidenceDescription,
                "workspaceJSON": match.record.workspaceJSON.path,
                "windowTitle": title
            ],
            runID: runID
        )
    }

    // MARK: - Compatibility helpers used by existing slug tests

    static func projectMatching(title: String, candidates: [String]) -> String? {
        let lowerTitle = title.lowercased()
        var bestMatch: (project: String, score: Int)? = nil
        for project in candidates where project != "empty-window" {
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

    // MARK: - Roots

    private static func projectsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    private static func workspaceStorageRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
    }

    // MARK: - Workspace matching

    private struct WorkspaceRecord {
        let workspaceJSON: URL
        let workspace: WorkspaceURI
        let modifiedAt: Date
    }

    private static func workspaceRecords(root: URL) -> [WorkspaceRecord] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { storageDir -> WorkspaceRecord? in
            let workspaceJSON = storageDir.appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: workspaceJSON),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = obj["folder"] as? String else {
                return nil
            }
            let modifiedAt = (try? storageDir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return WorkspaceRecord(workspaceJSON: workspaceJSON, workspace: WorkspaceURI.parse(folder), modifiedAt: modifiedAt)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private static func titleMatchesWorkspace(title: String, workspace: WorkspaceURI) -> Bool {
        guard let leaf = workspace.pathLeaf?.lowercased(), leaf.count >= 3 else { return false }
        return title.lowercased().contains(leaf)
    }

    private static func projectSlug(forLocalWorkspace url: URL) -> String {
        url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - Transcript candidates

    private static func locateUniqueSession(inProject project: String,
                                            under root: URL,
                                            now: Date,
                                            evidence: [String: String],
                                            runID: String?) -> SessionLookupResult {
        let logPrefix = runID.map { "[\($0)] " } ?? ""
        let transcriptsRoot = root
            .appendingPathComponent(project, isDirectory: true)
            .appendingPathComponent("agent-transcripts", isDirectory: true)
        guard FileManager.default.fileExists(atPath: transcriptsRoot.path) else {
            return .rejected(reason: "project has no agent-transcripts", evidence: evidence.merging(["project": project]) { current, _ in current })
        }

        let candidates = sessionCandidates(under: transcriptsRoot)
        guard !candidates.isEmpty else {
            return .rejected(reason: "no cursor transcript candidates", evidence: evidence.merging(["project": project]) { current, _ in current })
        }
        // Pick the most-recently-modified session in the project. No staleness
        // cutoff and no uniqueness requirement: the empty-window project (and
        // many local workspaces) accumulate sessions across days, and the user
        // may be reading a multi-day-old conversation in the Cursor Agents
        // window — its mtime advances only when the agent emits new turns.
        // The literal-window-title and workspaceStorage paths are already
        // strong positive signals for the right *project*.
        let candidate = candidates[0]
        let uuid = candidate.url.deletingPathExtension().lastPathComponent
        let mergedEvidence = evidence.merging([
            "project": project,
            "sessionUUID": uuid,
            "transcriptPath": candidate.url.path,
            "transcriptModifiedAt": "\(candidate.modifiedAt)"
        ]) { current, _ in current }
        DebugLog.info("\(logPrefix)SessionLocator: high-confidence match project=\(project) session=\(uuid)")
        return .located(SessionLocation(url: candidate.url, uuid: uuid, project: project, evidence: mergedEvidence))
    }

    private static func sessionCandidates(under dir: URL) -> [(url: URL, modifiedAt: Date)] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard !url.pathComponents.contains("subagents") else { continue }
            guard url.deletingPathExtension().lastPathComponent == url.deletingLastPathComponent().lastPathComponent else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            result.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return result.sorted(by: { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt })
    }
}
