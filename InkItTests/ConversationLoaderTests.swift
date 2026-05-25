import XCTest
@testable import InkIt

final class ConversationLoaderTests: XCTestCase {

    private func tempURL(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEmptyFileReturnsEmpty() throws {
        let url = try tempURL("")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ConversationLoader.load(from: url), [])
    }

    func testNonexistentFileReturnsEmpty() {
        let url = URL(fileURLWithPath: "/tmp/this-does-not-exist-\(UUID().uuidString).jsonl")
        XCTAssertEqual(ConversationLoader.load(from: url), [])
    }

    func testSingleValidLine() throws {
        let line = #"{"role":"user","message":{"content":[{"type":"text","text":"Hello there"}]}}"#
        let url = try tempURL(line + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let msgs = ConversationLoader.load(from: url)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?.role, .user)
        XCTAssertEqual(msgs.first?.text, "Hello there")
    }

    func testMultipleValidLinesPreserveOrderAndRoles() throws {
        let lines = [
            #"{"role":"user","message":{"content":[{"type":"text","text":"first user msg"}]}}"#,
            #"{"role":"assistant","message":{"content":[{"type":"text","text":"first assistant msg"}]}}"#,
            #"{"role":"user","message":{"content":[{"type":"text","text":"second user msg"}]}}"#
        ]
        let url = try tempURL(lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let msgs = ConversationLoader.load(from: url)
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs[0].role, .user)
        XCTAssertEqual(msgs[0].text, "first user msg")
        XCTAssertEqual(msgs[1].role, .assistant)
        XCTAssertEqual(msgs[1].text, "first assistant msg")
        XCTAssertEqual(msgs[2].role, .user)
        XCTAssertEqual(msgs[2].text, "second user msg")
    }

    func testLineWithOnlyToolUseIsSkipped() throws {
        let line = #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"x.txt"}}]}}"#
        let url = try tempURL(line + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let msgs = ConversationLoader.load(from: url)
        XCTAssertEqual(msgs, [])
    }

    func testUserQueryTagsAreStripped() throws {
        let line = #"{"role":"user","message":{"content":[{"type":"text","text":"<user_query>\nWhat is FlashAttention?\n</user_query>"}]}}"#
        let url = try tempURL(line + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let msgs = ConversationLoader.load(from: url)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertFalse(msgs[0].text.contains("<user_query>"), "got: \(msgs[0].text)")
        XCTAssertFalse(msgs[0].text.contains("</user_query>"), "got: \(msgs[0].text)")
        XCTAssertTrue(msgs[0].text.contains("What is FlashAttention?"), "got: \(msgs[0].text)")
    }

    func testFileWithoutTrailingNewlineStillParsed() throws {
        let line = #"{"role":"user","message":{"content":[{"type":"text","text":"no newline"}]}}"#
        let url = try tempURL(line) // no trailing newline
        defer { try? FileManager.default.removeItem(at: url) }
        let msgs = ConversationLoader.load(from: url)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?.text, "no newline")
    }

    func testGarbageLineBetweenValidLinesIsSkipped() throws {
        let lines = [
            #"{"role":"user","message":{"content":[{"type":"text","text":"alpha"}]}}"#,
            "this is not json at all",
            #"{"role":"assistant","message":{"content":[{"type":"text","text":"beta"}]}}"#
        ]
        let url = try tempURL(lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let msgs = ConversationLoader.load(from: url)
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0].text, "alpha")
        XCTAssertEqual(msgs[1].text, "beta")
    }

    func testMixedTextAndToolUseJoinsTextOnly() throws {
        let line = #"{"role":"assistant","message":{"content":[{"type":"text","text":"thinking"},{"type":"tool_use","name":"Read","input":{}},{"type":"text","text":"continuing"}]}}"#
        let url = try tempURL(line + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let msgs = ConversationLoader.load(from: url)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?.text, "thinking continuing")
    }
}
