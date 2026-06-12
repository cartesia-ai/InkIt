import XCTest
@testable import InkIt

final class DebugLogFormatterTests: XCTestCase {
    func testBoundedBlockIncludesMetadataAndTruncates() {
        let block = DebugLog.boundedBlock(title: "payload", text: "abcdef", limit: 3)
        XCTAssertTrue(block.contains("payload bytes=6"))
        XCTAssertTrue(block.contains("hash="))
        XCTAssertTrue(block.contains("truncated=true"))
        XCTAssertTrue(block.contains("\nabc"))
        XCTAssertFalse(block.contains("abcdef"))
    }

    func testBoundedBlockMarksUntruncated() {
        let block = DebugLog.boundedBlock(title: "payload", text: "abc", limit: 10)
        XCTAssertTrue(block.contains("truncated=false"))
        XCTAssertTrue(block.contains("\nabc"))
    }

    func testRedactsSecrets() {
        let text = #"{"x-api-key":"sk-ant-secret","body":"sk-ant-secret"}"#
        let redacted = DebugLog.redacted(text, secrets: ["sk-ant-secret"])
        XCTAssertFalse(redacted.contains("sk-ant-secret"))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    func testPrettyJSONStringDoesNotInjectAPIKey() {
        let body: [String: Any] = ["model": "claude", "messages": [["role": "user", "content": "hello"]]]
        let json = DebugLog.prettyJSONString(body) ?? ""
        XCTAssertTrue(json.contains("claude"))
        XCTAssertFalse(json.contains("x-api-key"))
    }
}
