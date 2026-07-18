import XCTest
@testable import InkIt

final class STTFailureRoutingTests: XCTestCase {

    private func clientWithTranscript(_ text: String) -> CartesiaStreamingClient {
        let client = CartesiaStreamingClient(apiKey: "test-key")
        client.handleMessage(#"{"type":"turn.end","transcript":"\#(text)"}"#)
        return client
    }

    func testUnknownWithContentDeliversTranscriptAndNeverErrors() {
        let client = clientWithTranscript("hello world")
        var delivered: String?
        var erroredWith: STTFailure?
        client.onClosed = { delivered = $0 }
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.unknown, errorReason: .receiveFailed)

        XCTAssertEqual(delivered, "hello world", "graceful goodbye must deliver the finished transcript")
        XCTAssertNil(erroredWith, "a benign disconnect must not surface an error")
    }

    func testUnknownWithNoContentCollapsesSilently() {
        let client = CartesiaStreamingClient(apiKey: "test-key")
        var closedCount = 0
        var delivered: String?
        var erroredWith: STTFailure?
        client.onClosed = { closedCount += 1; delivered = $0 }
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.unknown, errorReason: .receiveFailed)

        XCTAssertNil(erroredWith, "a silent / too-short press must not surface an error")
        XCTAssertEqual(closedCount, 1, "must finish cleanly via onClosed")
        XCTAssertEqual(delivered, "", "no speech means an empty transcript, not an error")
    }

    func testNamedFailureSurfacesError() {
        for failure: STTFailure in [.offline, .serverError, .rateLimited, .outOfCredits, .invalidKey] {
            let client = clientWithTranscript("partial words")
            var erroredWith: STTFailure?
            var closed = false
            client.onError = { erroredWith = $0 }
            client.onClosed = { _ in closed = true }

            client.reportFailureOrCollapse(failure, errorReason: .receiveFailed)

            XCTAssertEqual(erroredWith, failure, "\(failure) is actionable and must reach the user")
            XCTAssertFalse(closed, "an error path must not also fire onClosed (would wipe the notice)")
        }
    }

    func testServerErrorAfterCloseWithNoContentCollapsesSilently() {
        let client = CartesiaStreamingClient(apiKey: "test-key")
        client.awaitingClose = true
        var delivered: String?
        var erroredWith: STTFailure?
        client.onClosed = { delivered = $0 }
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.serverError, errorReason: .serverError)

        XCTAssertNil(erroredWith, "a post-close 500 on a silent tap must not surface an error")
        XCTAssertEqual(delivered, "", "must finish via the clean empty-transcript path")
    }

    func testServerErrorMidHoldWithNoContentStillSurfaces() {
        let client = CartesiaStreamingClient(apiKey: "test-key")
        var erroredWith: STTFailure?
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.serverError, errorReason: .serverError)

        XCTAssertEqual(erroredWith, .serverError, "a mid-hold 5xx must reach the user")
    }

    func testServerErrorAfterCloseWithContentStillSurfaces() {
        let client = clientWithTranscript("partial words")
        client.awaitingClose = true
        var erroredWith: STTFailure?
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.serverError, errorReason: .serverError)

        XCTAssertEqual(erroredWith, .serverError, "content in hand means a real failure, not a silent tap")
    }

    func testBenignSocketDisconnectsClassifyAsUnknown() {
        for errno in [57, 32, 54] {
            let err = NSError(domain: NSPOSIXErrorDomain, code: errno)
            XCTAssertEqual(STTFailure.classify(transportError: err, response: nil), .unknown,
                           "POSIX errno \(errno) must classify as .unknown so it is forgiven, not surfaced")
        }
    }

    func testRealTransportErrorsStayNamed() {
        XCTAssertEqual(STTFailure.classify(transportError: URLError(.notConnectedToInternet), response: nil), .offline)
        XCTAssertEqual(STTFailure.classify(transportError: URLError(.timedOut), response: nil), .serverError)
    }
}
