import XCTest
@testable import InkIt

final class FocusedEditableTests: XCTestCase {

    private func result(isEditable: Bool, focusedPID: pid_t) -> FocusedEditable.Result {
        FocusedEditable.Result(
            isEditable: isEditable,
            app: focusedPID > 0 ? NSRunningApplication(processIdentifier: focusedPID) : nil,
            focusedPID: focusedPID
        )
    }

    func testEditableFocusNeverUsesKeyboardFallback() {
        let target = NSRunningApplication.current
        let focus = result(isEditable: true, focusedPID: target.processIdentifier)
        XCTAssertFalse(focus.allowsKeyboardPasteFallback(to: target))
    }

    func testSameAppFrontmostAllowsKeyboardFallback() {
        let target = NSRunningApplication.current
        let focus = result(isEditable: false, focusedPID: target.processIdentifier)
        XCTAssertTrue(focus.allowsKeyboardPasteFallback(to: target))
    }

    func testNoFocusedPIDStillAllowsFallbackWhenTargetActive() {
        let target = NSRunningApplication.current
        let focus = result(isEditable: false, focusedPID: 0)
        XCTAssertTrue(focus.allowsKeyboardPasteFallback(to: target))
    }

    func testDifferentPIDBlocksKeyboardFallback() {
        let target = NSRunningApplication.current
        let otherPID: pid_t = target.processIdentifier == 1 ? 2 : 1
        let focus = result(isEditable: false, focusedPID: otherPID)
        XCTAssertFalse(focus.allowsKeyboardPasteFallback(to: target))
    }

    func testNilTargetBlocksKeyboardFallback() {
        let focus = result(isEditable: false, focusedPID: 0)
        XCTAssertFalse(focus.allowsKeyboardPasteFallback(to: nil))
    }
}
