import XCTest
@testable import InkIt

final class SessionLocatorSlugTests: XCTestCase {

    func testTitleMatchesSlugLeaf() {
        let candidates = [
            "Users-x-conductor-workspaces-inkit-abu-dhabi",
            "Users-x-other-project"
        ]
        let match = SessionLocator.projectMatching(title: "abu-dhabi", candidates: candidates)
        XCTAssertEqual(match, "Users-x-conductor-workspaces-inkit-abu-dhabi")
    }

    func testTitleNoMatchReturnsNil() {
        let candidates = [
            "Users-x-conductor-workspaces-inkit-abu-dhabi",
            "Users-x-other-project"
        ]
        let match = SessionLocator.projectMatching(title: "completely unrelated", candidates: candidates)
        XCTAssertNil(match)
    }

    func testEmptyWindowProjectIsSkipped() {
        // Even if "empty-window" would match by leaf, it's never the right
        // pick here — handled by the dedicated literal-title branch.
        let candidates = ["empty-window"]
        let match = SessionLocator.projectMatching(title: "empty-window", candidates: candidates)
        XCTAssertNil(match, "empty-window must not be matched via title-projectMatching path")
    }

    func testLongerLeafWins() {
        // When two candidates both contain leaves present in the title,
        // the longer leaf is the more specific match.
        let candidates = [
            "Users-x-foo",                // leaf "foo" → length 3
            "Users-x-foobar"              // leaf "foobar" → length 6
        ]
        let match = SessionLocator.projectMatching(title: "foobar is the project", candidates: candidates)
        XCTAssertEqual(match, "Users-x-foobar")
    }

    func testShortLeafsBelowMinimumAreSkipped() {
        let candidates = ["Users-x-a", "Users-x-ab"]
        // Both leaves are <3 chars; matcher should skip them.
        let match = SessionLocator.projectMatching(title: "a project named ab", candidates: candidates)
        XCTAssertNil(match)
    }

    func testCaseInsensitiveMatch() {
        let candidates = ["Users-x-AbuDhabi"]
        let match = SessionLocator.projectMatching(title: "abudhabi", candidates: candidates)
        XCTAssertEqual(match, "Users-x-AbuDhabi")
    }
}
