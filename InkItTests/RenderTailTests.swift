import XCTest
@testable import InkIt

final class RenderTailTests: XCTestCase {

    func testEmptyArrayProducesEmptyString() {
        let messages: [ConversationMessage] = []
        XCTAssertEqual(messages.renderTail(maxChars: 1000), "")
    }

    func testSingleMessageUnderBudgetIsFullyRendered() {
        let messages = [
            ConversationMessage(role: .user, text: "Hello world")
        ]
        let out = messages.renderTail(maxChars: 1000)
        XCTAssertEqual(out, "USER: Hello world")
    }

    func testSingleMessageOverBudgetIsStillKept() {
        // Never drop the only message — partial context is better than none.
        let messages = [
            ConversationMessage(role: .user, text: String(repeating: "a", count: 200))
        ]
        let out = messages.renderTail(maxChars: 50)
        XCTAssertFalse(out.isEmpty, "single-message renderTail should not be empty even when over budget")
        XCTAssertTrue(out.hasPrefix("USER: "))
    }

    func testMultipleMessagesAllFit() {
        let messages = [
            ConversationMessage(role: .user, text: "one"),
            ConversationMessage(role: .assistant, text: "two"),
            ConversationMessage(role: .user, text: "three")
        ]
        let out = messages.renderTail(maxChars: 1000)
        let lines = out.components(separatedBy: "\n\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "USER: one")
        XCTAssertEqual(lines[1], "ASSISTANT: two")
        XCTAssertEqual(lines[2], "USER: three")
    }

    func testOldestDroppedWhenOverBudget() {
        let messages = [
            ConversationMessage(role: .user, text: String(repeating: "x", count: 100)),
            ConversationMessage(role: .assistant, text: String(repeating: "y", count: 100)),
            ConversationMessage(role: .user, text: "newest")
        ]
        // Budget small enough that only the newest fits comfortably.
        let out = messages.renderTail(maxChars: 30)
        XCTAssertTrue(out.contains("newest"), "newest should always be preserved; got: \(out)")
        XCTAssertFalse(out.contains("xxxx"), "oldest should be dropped; got: \(out)")
    }

    func testOrderIsPreserved() {
        let messages = [
            ConversationMessage(role: .user, text: "first"),
            ConversationMessage(role: .assistant, text: "second"),
            ConversationMessage(role: .user, text: "third")
        ]
        let out = messages.renderTail(maxChars: 1000)
        guard let firstIdx = out.range(of: "first")?.lowerBound,
              let secondIdx = out.range(of: "second")?.lowerBound,
              let thirdIdx = out.range(of: "third")?.lowerBound else {
            XCTFail("missing substrings in \(out)")
            return
        }
        XCTAssertLessThan(firstIdx, secondIdx)
        XCTAssertLessThan(secondIdx, thirdIdx)
    }
}
