import XCTest
@testable import InkIt

final class SessionLocatorStrictTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testExactLocalWorkspaceSingleTranscriptLocates() throws {
        let workspace = try makeWorkspace(named: "MyProject")
        let projectsRoot = tempRoot.appendingPathComponent("projects", isDirectory: true)
        let storageRoot = tempRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
        let slug = projectSlug(for: workspace)
        try makeTranscript(projectsRoot: projectsRoot, project: slug, uuid: "11111111-1111-1111-1111-111111111111")
        try makeWorkspaceJSON(storageRoot: storageRoot, folder: "file://\(workspace.path)")

        let result = SessionLocator.locateStrict(
            windowTitle: "MyProject - Cursor",
            projectsRoot: projectsRoot,
            workspaceStorageRoot: storageRoot,
            now: Date()
        )

        guard case .located(let location) = result else {
            XCTFail("expected located, got \(result)")
            return
        }
        XCTAssertEqual(location.project, slug)
        XCTAssertEqual(location.uuid, "11111111-1111-1111-1111-111111111111")
    }

    func testMultipleTranscriptCandidatesPicksNewest() throws {
        let workspace = try makeWorkspace(named: "MyProject")
        let projectsRoot = tempRoot.appendingPathComponent("projects", isDirectory: true)
        let storageRoot = tempRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
        let slug = projectSlug(for: workspace)
        let older = try makeTranscript(projectsRoot: projectsRoot, project: slug, uuid: "11111111-1111-1111-1111-111111111111")
        let newer = try makeTranscript(projectsRoot: projectsRoot, project: slug, uuid: "22222222-2222-2222-2222-222222222222")
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 60 * 60)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: newer.path)
        try makeWorkspaceJSON(storageRoot: storageRoot, folder: "file://\(workspace.path)")

        let result = SessionLocator.locateStrict(
            windowTitle: "MyProject - Cursor",
            projectsRoot: projectsRoot,
            workspaceStorageRoot: storageRoot,
            now: now
        )

        guard case .located(let location) = result else {
            XCTFail("expected located, got \(result)")
            return
        }
        XCTAssertEqual(location.uuid, "22222222-2222-2222-2222-222222222222")
    }

    func testStaleTranscriptDoesNotMakeFreshSingleCandidateAmbiguous() throws {
        let workspace = try makeWorkspace(named: "MyProject")
        let projectsRoot = tempRoot.appendingPathComponent("projects", isDirectory: true)
        let storageRoot = tempRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
        let slug = projectSlug(for: workspace)
        _ = try makeTranscript(projectsRoot: projectsRoot, project: slug, uuid: "11111111-1111-1111-1111-111111111111")
        let stale = try makeTranscript(projectsRoot: projectsRoot, project: slug, uuid: "22222222-2222-2222-2222-222222222222")
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 60 * 60)], ofItemAtPath: stale.path)
        try makeWorkspaceJSON(storageRoot: storageRoot, folder: "file://\(workspace.path)")

        let result = SessionLocator.locateStrict(
            windowTitle: "MyProject - Cursor",
            projectsRoot: projectsRoot,
            workspaceStorageRoot: storageRoot,
            now: now
        )

        guard case .located(let location) = result else {
            XCTFail("expected located, got \(result)")
            return
        }
        XCTAssertEqual(location.uuid, "11111111-1111-1111-1111-111111111111")
    }

    func testEmptyWindowMultipleCandidatesPicksNewest() throws {
        let projectsRoot = tempRoot.appendingPathComponent("projects", isDirectory: true)
        let storageRoot = tempRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
        let older = try makeTranscript(projectsRoot: projectsRoot, project: "empty-window", uuid: "11111111-1111-1111-1111-111111111111")
        let newer = try makeTranscript(projectsRoot: projectsRoot, project: "empty-window", uuid: "22222222-2222-2222-2222-222222222222")
        let now = Date()
        // Both transcripts are days old — the exact case from the real-world
        // bug where the user dictates about a multi-day-old agent conversation
        // in the Cursor Agents window. Newest still wins.
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-48 * 60 * 60)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-44 * 60 * 60)], ofItemAtPath: newer.path)

        let result = SessionLocator.locateStrict(
            windowTitle: "Cursor Agents",
            projectsRoot: projectsRoot,
            workspaceStorageRoot: storageRoot,
            now: now
        )

        guard case .located(let location) = result else {
            XCTFail("expected located, got \(result)")
            return
        }
        XCTAssertEqual(location.project, "empty-window")
        XCTAssertEqual(location.uuid, "22222222-2222-2222-2222-222222222222")
    }

    func testMissingProjectRejects() throws {
        let workspace = try makeWorkspace(named: "MyProject")
        let projectsRoot = tempRoot.appendingPathComponent("projects", isDirectory: true)
        let storageRoot = tempRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try makeWorkspaceJSON(storageRoot: storageRoot, folder: "file://\(workspace.path)")

        let result = SessionLocator.locateStrict(
            windowTitle: "MyProject - Cursor",
            projectsRoot: projectsRoot,
            workspaceStorageRoot: storageRoot,
            now: Date()
        )

        XCTAssertRejected(result, reason: "no exact local workspace match")
    }

    func testRemoteWorkspaceRejectsBeforeLocalTranscriptLookup() throws {
        let projectsRoot = tempRoot.appendingPathComponent("projects", isDirectory: true)
        let storageRoot = tempRoot.appendingPathComponent("workspaceStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try makeWorkspaceJSON(
            storageRoot: storageRoot,
            folder: "vscode-remote://ssh-remote%2Bcxis-dev-1/home/daniele.paliotta/gypsum"
        )

        let result = SessionLocator.locateStrict(
            windowTitle: "gypsum - Cursor",
            projectsRoot: projectsRoot,
            workspaceStorageRoot: storageRoot,
            now: Date()
        )

        XCTAssertRejected(result, reason: "remote workspace")
    }

    private func makeWorkspace(named name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent("workspaces", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeWorkspaceJSON(storageRoot: URL, folder: String) throws {
        let dir = storageRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"folder":"\#(folder)"}"#
        try json.write(to: dir.appendingPathComponent("workspace.json"), atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func makeTranscript(projectsRoot: URL, project: String, uuid: String) throws -> URL {
        let dir = projectsRoot
            .appendingPathComponent(project, isDirectory: true)
            .appendingPathComponent("agent-transcripts", isDirectory: true)
            .appendingPathComponent(uuid, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = #"{"role":"user","message":{"content":[{"type":"text","text":"FlashAttention"}]}}"#
        let url = dir.appendingPathComponent("\(uuid).jsonl")
        try line.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func projectSlug(for workspace: URL) -> String {
        workspace.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: "/", with: "-")
    }

    private func XCTAssertRejected(_ result: SessionLookupResult, reason: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .rejected(let actual, _) = result else {
            XCTFail("expected rejected(\(reason)), got \(result)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, reason, file: file, line: line)
    }
}
