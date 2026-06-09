import XCTest
@testable import InkIt

/// Locks the shared AX traversal budget. `AX.run` is the single primitive every
/// Accessibility walk in the app routes through: it runs the work off the
/// calling thread, hands it a `deadline` exactly `budget` seconds out, and
/// returns the closure's result. Running off-main under a wall-clock deadline is
/// what keeps a slow or huge AX tree from stalling the main run loop — the stall
/// that historically froze modifier keys and dropped pastes.
final class AXBudgetTests: XCTestCase {

    func testReturnsClosureResult() async {
        let result = await AX.run(budget: 1.0) { _ in 42 }
        XCTAssertEqual(result, 42)
    }

    func testDeadlineIsBudgetInTheFuture() async {
        let before = Date()
        let deadline = await AX.run(budget: 0.5) { $0 }
        let delta = deadline.timeIntervalSince(before)
        XCTAssertGreaterThanOrEqual(delta, 0.4)
        XCTAssertLessThanOrEqual(delta, 1.0)
    }

    /// A walk that checks the deadline returns promptly with whatever it had,
    /// instead of running unbounded — the property the freeze fix depends on.
    func testClosureHonorsDeadlineAndReturnsPartialWork() async {
        let start = Date()
        let visited = await AX.run(budget: 0.1) { deadline -> Int in
            var n = 0
            while Date() < deadline { n += 1 }
            return n
        }
        XCTAssertGreaterThan(visited, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    /// The work must not run on the main thread — that is the whole point.
    func testRunsOffTheMainThread() async {
        let ranOnMain = await AX.run(budget: 0.2) { _ in Thread.isMainThread }
        XCTAssertFalse(ranOnMain)
    }
}
