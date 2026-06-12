import XCTest
@testable import InkIt

/// Locks the end-of-session contract: the "Couldn't transcribe" notch fires only
/// for a *named* failure with nothing to show. A `.unknown` (unexplained) ending
/// — a normal server close that raced the receive loop, a benign socket
/// disconnect, an unclassified 400 — never errors: it delivers whatever
/// transcript we have, or finishes silently. Two regressions this guards against:
/// dropping a finished transcript on a graceful goodbye, and showing an error
/// when the user simply said nothing.
final class STTFailureRoutingTests: XCTestCase {

    /// Feed a completed turn so the client has transcript content in hand.
    private func clientWithTranscript(_ text: String) -> CartesiaStreamingClient {
        let client = CartesiaStreamingClient(apiKey: "test-key")
        client.handleMessage(#"{"type":"turn.end","transcript":"\#(text)"}"#)
        return client
    }

    // MARK: - Graceful goodbye → deliver the words, no error

    func testUnknownWithContentDeliversTranscriptAndNeverErrors() {
        let client = clientWithTranscript("hello world")
        var delivered: String?
        var erroredWith: STTFailure?
        client.onClosed = { delivered = $0 }
        client.onError = { erroredWith = $0 }

        // A normal close racing the receive loop classifies as `.unknown`.
        client.reportFailureOrCollapse(.unknown, errorReason: .receiveFailed)

        XCTAssertEqual(delivered, "hello world", "graceful goodbye must deliver the finished transcript")
        XCTAssertNil(erroredWith, "a benign disconnect must not surface an error")
    }

    // MARK: - Said nothing → silent, no error

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

    // MARK: - Named, actionable failures still surface (even with content)

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

    // MARK: - Post-close 500 on a silent tap → silent, no error

    /// A rapid tap-and-release closes the session with ~zero audio; the server
    /// answers the close with a 500 instead of an empty turn. The user has
    /// already released and nothing was transcribed, so "Server error" is
    /// alarming and non-actionable — it must collapse to the clean empty path,
    /// exactly like the 400 flavor of the same press.
    func testServerErrorAfterCloseWithNoContentCollapsesSilently() {
        let client = CartesiaStreamingClient(apiKey: "test-key")
        client.awaitingClose = true  // hotkey released, close requested
        var delivered: String?
        var erroredWith: STTFailure?
        client.onClosed = { delivered = $0 }
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.serverError, errorReason: .serverError)

        XCTAssertNil(erroredWith, "a post-close 500 on a silent tap must not surface an error")
        XCTAssertEqual(delivered, "", "must finish via the clean empty-transcript path")
    }

    /// The carve-out is narrow: a 5xx while the user is still holding (close
    /// not yet requested) is a real, actionable failure — they'd otherwise
    /// speak a whole sentence into a dead session and release to nothing.
    func testServerErrorMidHoldWithNoContentStillSurfaces() {
        let client = CartesiaStreamingClient(apiKey: "test-key")
        var erroredWith: STTFailure?
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.serverError, errorReason: .serverError)

        XCTAssertEqual(erroredWith, .serverError, "a mid-hold 5xx must reach the user")
    }

    /// And a post-close 500 with words in hand still surfaces (covered by the
    /// named-failure loop above too, but locked here against the carve-out
    /// widening to "any post-close server error").
    func testServerErrorAfterCloseWithContentStillSurfaces() {
        let client = clientWithTranscript("partial words")
        client.awaitingClose = true
        var erroredWith: STTFailure?
        client.onError = { erroredWith = $0 }

        client.reportFailureOrCollapse(.serverError, errorReason: .serverError)

        XCTAssertEqual(erroredWith, .serverError, "content in hand means a real failure, not a silent tap")
    }

    // MARK: - The classification assumption the invariant rests on

    /// Benign POSIX socket disconnects (ENOTCONN/EPIPE/ECONNRESET) are NOT
    /// `URLError`s, so they fall through to `.unknown` — which is exactly what
    /// lets `reportFailureOrCollapse` forgive them. If a future change ever maps
    /// these to a named failure, the graceful-goodbye guarantee silently breaks;
    /// this test fails first.
    func testBenignSocketDisconnectsClassifyAsUnknown() {
        for errno in [57 /* ENOTCONN */, 32 /* EPIPE */, 54 /* ECONNRESET */] {
            let err = NSError(domain: NSPOSIXErrorDomain, code: errno)
            XCTAssertEqual(STTFailure.classify(transportError: err, response: nil), .unknown,
                           "POSIX errno \(errno) must classify as .unknown so it is forgiven, not surfaced")
        }
    }

    /// Genuine transport failures must still classify as named errors so they
    /// survive the forgiveness path above.
    func testRealTransportErrorsStayNamed() {
        XCTAssertEqual(STTFailure.classify(transportError: URLError(.notConnectedToInternet), response: nil), .offline)
        XCTAssertEqual(STTFailure.classify(transportError: URLError(.timedOut), response: nil), .serverError)
    }
}
