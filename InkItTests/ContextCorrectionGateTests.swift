import XCTest
@testable import InkIt

final class ContextCorrectionGateTests: XCTestCase {
    func testHighConfidenceSnapshotCallsRewrite() async {
        let snapshot = ContextSnapshot(
            source: .accessibility,
            confidence: .high,
            target: nil,
            payload: "FlashAttention",
            evidence: [:],
            rejectionReason: nil
        )
        var called = false
        let out = await ContextCorrectionGate.correct(raw: "flash attention", snapshot: snapshot) { _ in
            called = true
            return "FlashAttention"
        }
        XCTAssertTrue(called)
        XCTAssertEqual(out, "FlashAttention")
    }

    func testLowConfidenceSnapshotPastesRawWithoutRewrite() async {
        let snapshot = ContextSnapshot(
            source: .cursorSession,
            confidence: .low,
            target: nil,
            payload: "FlashAttention",
            evidence: [:],
            rejectionReason: "ambiguous"
        )
        var called = false
        let out = await ContextCorrectionGate.correct(raw: "flash attention", snapshot: snapshot) { _ in
            called = true
            return "FlashAttention"
        }
        XCTAssertFalse(called)
        XCTAssertEqual(out, "flash attention")
    }

    func testEmptyHighConfidenceSnapshotPastesRaw() {
        let snapshot = ContextSnapshot(
            source: .accessibility,
            confidence: .high,
            target: nil,
            payload: "",
            evidence: [:],
            rejectionReason: nil
        )
        XCTAssertEqual(ContextCorrectionGate.decision(for: snapshot), .pasteRaw("context confidence is high"))
    }
}
