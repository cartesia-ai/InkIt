import XCTest
@testable import InkIt

final class WorkspaceURITests: XCTestCase {
    func testParsesLocalFileURI() {
        let uri = WorkspaceURI.parse("file:///Users/danielepaliotta/project")
        XCTAssertEqual(uri, .local(URL(fileURLWithPath: "/Users/danielepaliotta/project")))
        XCTAssertEqual(uri.pathLeaf, "project")
    }

    func testParsesPlainRemoteSSHURI() {
        let raw = "vscode-remote://ssh-remote%2Bcxis-dev-1/home/daniele.paliotta/gypsum"
        let uri = WorkspaceURI.parse(raw)
        XCTAssertEqual(uri, .remoteSSH(host: "cxis-dev-1", path: "/home/daniele.paliotta/gypsum", raw: raw))
        XCTAssertEqual(uri.pathLeaf, "gypsum")
    }

    func testParsesHexEncodedJSONRemoteSSHURI() {
        let raw = "vscode-remote://ssh-remote%2B7b22686f73744e616d65223a2262363563393039652d30322e636c6f75642e746f6765746865722e6169227d/home/danielepaliotta/gypsum"
        let uri = WorkspaceURI.parse(raw)
        XCTAssertEqual(
            uri,
            .remoteSSH(
                host: "b65c909e-02.cloud.together.ai",
                path: "/home/danielepaliotta/gypsum",
                raw: raw
            )
        )
    }

    func testUnsupportedURI() {
        let raw = "https://example.com/workspace"
        XCTAssertEqual(WorkspaceURI.parse(raw), .unsupported(raw: raw))
    }
}
