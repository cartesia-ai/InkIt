import XCTest
@testable import InkIt

final class GlossaryExtractorTests: XCTestCase {

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(GlossaryExtractor.extract(from: ""), [])
    }

    func testWhitespaceOnlyInputReturnsEmpty() {
        XCTAssertEqual(GlossaryExtractor.extract(from: "   \n\t  "), [])
    }

    func testPlainEnglishIsNotExtracted() {
        // Lowercase English words without identifier shape are not tokens.
        let tokens = GlossaryExtractor.extract(from: "the quick brown fox jumps over the lazy dog")
        XCTAssertEqual(tokens, [])
    }

    func testCamelCaseIsExtracted() {
        let tokens = GlossaryExtractor.extract(from: "We use FlashAttention with vLLM and PagedAttention.")
        // Expect those three terms present, in source order.
        XCTAssertEqual(tokens.first(where: { $0 == "FlashAttention" }), "FlashAttention")
        XCTAssertEqual(tokens.first(where: { $0 == "vLLM" }), "vLLM")
        XCTAssertEqual(tokens.first(where: { $0 == "PagedAttention" }), "PagedAttention")
        let order = tokens.compactMap { ["FlashAttention", "vLLM", "PagedAttention"].contains($0) ? $0 : nil }
        XCTAssertEqual(order, ["FlashAttention", "vLLM", "PagedAttention"])
    }

    func testSnakeCaseIsExtracted() {
        let tokens = GlossaryExtractor.extract(from: "the kVK_Function key bound via key_code_handler")
        XCTAssertTrue(tokens.contains("kVK_Function"), "expected kVK_Function in \(tokens)")
        XCTAssertTrue(tokens.contains("key_code_handler"), "expected key_code_handler in \(tokens)")
    }

    func testAcronymsArePicked() {
        let tokens = GlossaryExtractor.extract(from: "GPU memory and SRAM bandwidth on H100")
        XCTAssertTrue(tokens.contains("GPU"), "expected GPU in \(tokens)")
        XCTAssertTrue(tokens.contains("SRAM"), "expected SRAM in \(tokens)")
        XCTAssertTrue(tokens.contains("H100"), "expected H100 in \(tokens)")
    }

    func testDeduplication() {
        let tokens = GlossaryExtractor.extract(from: "FlashAttention is fast; FlashAttention saves memory; FlashAttention is exact")
        let count = tokens.filter { $0 == "FlashAttention" }.count
        XCTAssertEqual(count, 1, "FlashAttention should appear exactly once, got \(count) in \(tokens)")
    }

    func testLimitHonored() {
        // Build a synthetic input with 200 distinct camelCase tokens.
        var pieces: [String] = []
        for i in 0..<200 {
            pieces.append("camelToken\(i)Foo")
        }
        let tokens = GlossaryExtractor.extract(from: pieces.joined(separator: " "))
        XCTAssertLessThanOrEqual(tokens.count, 80, "limit cap of 80 exceeded: \(tokens.count)")
    }

    func testHyphenatedIsExtracted() {
        let tokens = GlossaryExtractor.extract(from: "Compared FlashAttention-2 to FlashAttention-3 on GPT-4")
        XCTAssertTrue(tokens.contains("FlashAttention-2"), "expected FlashAttention-2 in \(tokens)")
        XCTAssertTrue(tokens.contains("FlashAttention-3"), "expected FlashAttention-3 in \(tokens)")
        XCTAssertTrue(tokens.contains("GPT-4"), "expected GPT-4 in \(tokens)")
    }
}
