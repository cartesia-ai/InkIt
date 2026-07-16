import XCTest
@testable import InkIt

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

    func testRunsOffTheMainThread() async {
        let ranOnMain = await AX.run(budget: 0.2) { _ in Thread.isMainThread }
        XCTAssertFalse(ranOnMain)
    }
}
