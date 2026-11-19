import XCTest
@testable import MacTab

final class WindowSwitchSessionTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    func testQuickSwitchSelectsPreviousWindowAndRepeatedInvocationReturns() {
        XCTAssertEqual(WindowSwitchSession(windows: [a,b,c], backwards: false)?.selected, b)
        XCTAssertEqual(WindowSwitchSession(windows: [b,a,c], backwards: false)?.selected, a)
    }

    func testSameApplicationWindowsRemainIndependentCandidates() {
        var session = WindowSwitchSession(windows: [a,b,c], backwards: false)!
        XCTAssertEqual(session.selected, b)
        session.advance(backwards: false)
        XCTAssertEqual(session.selected, c)
        session.advance(backwards: false)
        XCTAssertEqual(session.selected, a)
    }

    func testReverseAndWrapInBothDirections() {
        var session = WindowSwitchSession(windows: [a,b,c], backwards: true)!
        XCTAssertEqual(session.selected, c)
        session.advance(backwards: true)
        XCTAssertEqual(session.selected, b)
        session.advance(backwards: true)
        XCTAssertEqual(session.selected, a)
        session.advance(backwards: true)
        XCTAssertEqual(session.selected, c)
    }

    func testEmptyAndSingleWindow() {
        XCTAssertNil(WindowSwitchSession(windows: [], backwards: false))
        var session = WindowSwitchSession(windows: [a], backwards: false)!
        for _ in 0..<100 { session.advance(backwards: false); session.advance(backwards: true) }
        XCTAssertEqual(session.selected, a)
    }

    func testFrozenOrderSurvivesExternalChangesAndCancellationDoesNotMutateCandidates() {
        var candidates = [a,b,c]
        let session = WindowSwitchSession(windows: candidates, backwards: false)!
        candidates.remove(at: 1)
        candidates.reverse()
        XCTAssertEqual(session.windows, [a,b,c])
        XCTAssertEqual(session.selected, b)
        XCTAssertNotEqual(session.token, WindowSwitchSession(windows: candidates, backwards: false)?.token)
    }

    func testPointerSelectionAndKeyboardContinueInFrozenOrder() {
        var session = WindowSwitchSession(windows: [a,b,c], backwards: false)!
        XCTAssertTrue(session.select(c))
        XCTAssertEqual(session.selected, c)
        session.advance(backwards: false)
        XCTAssertEqual(session.selected, a)
        session.advance(backwards: true)
        XCTAssertEqual(session.selected, c)
        XCTAssertEqual(session.windows, [a,b,c])
    }

    func testUnknownAndUnchangedPointerSelectionDoNotMoveSelection() {
        var session = WindowSwitchSession(windows: [a,b,c], backwards: false)!
        XCTAssertFalse(session.select(UUID()))
        XCTAssertFalse(session.select(b))
        XCTAssertEqual(session.selected, b)
    }

    func testParallelsGuestShortcutsPassThrough() {
        XCTAssertFalse(WindowSwitcher.handlesShortcuts(for: "com.parallels.vm"))
        XCTAssertFalse(WindowSwitcher.handlesShortcuts(for: "com.parallels.winapp.vm-id.windows-app"))
        XCTAssertFalse(WindowSwitcher.handlesShortcuts(for: "com.parallels.desktop.console"))
    }

    func testMacApplicationsStillUseWindowSwitcher() {
        XCTAssertTrue(WindowSwitcher.handlesShortcuts(for: nil))
        XCTAssertTrue(WindowSwitcher.handlesShortcuts(for: "com.apple.Safari"))
        XCTAssertTrue(WindowSwitcher.handlesShortcuts(for: "app.mactab"))
    }
}
