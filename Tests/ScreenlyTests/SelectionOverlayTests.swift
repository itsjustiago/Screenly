import XCTest
import AppKit
@testable import Screenly

/// Regression tests for the "capture stops working after the first screenshot"
/// wedge: an overlay panel hidden without `close()` (AppKit used to do this on
/// app deactivation via NSPanel's `hidesOnDeactivate` default) left `panel` set,
/// and `begin()`'s re-entrancy guard then dropped every capture until relaunch.
@MainActor
final class SelectionOverlayTests: XCTestCase {

    private func makeController() -> SelectionOverlayController {
        SelectionOverlayController(store: CaptureStore(), fallback: { _ in })
    }

    // MARK: Shield panel configuration

    func testShieldPanelNeverHidesOnDeactivate() {
        let panel = SelectionOverlayController.makeShieldPanel(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertFalse(panel.hidesOnDeactivate,
                       "the overlay must survive app deactivation — hiding it bypasses close() and wedges all future captures")
    }

    func testShieldPanelKeepsShieldConfiguration() {
        let panel = SelectionOverlayController.makeShieldPanel(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(panel.canBecomeKey, "must receive Esc / ⌘-shortcuts")
        XCTAssertEqual(panel.level.rawValue, Int(CGShieldingWindowLevel()))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.isOpaque)
    }

    // MARK: Session reclaim

    func testReclaimWithNoSessionStartsFresh() {
        let controller = makeController()
        XCTAssertFalse(controller.reclaimExistingSession(),
                       "no existing panel → a new session should be allowed to start")
    }

    func testReclaimTearsDownHiddenPanel() throws {
        let controller = makeController()
        controller.beginDebug()
        guard let panel = controller.panel, panel.isVisible else {
            throw XCTSkip("no display available to present the overlay")
        }
        // Simulate the wedge: the panel gets ordered out behind the controller's back.
        panel.orderOut(nil)

        XCTAssertFalse(controller.reclaimExistingSession(),
                       "a hidden panel must not swallow the capture request")
        XCTAssertNil(controller.panel,
                     "the wedged session must be torn down so a fresh one can begin")
    }

    func testReclaimRefrontsLiveSession() throws {
        let controller = makeController()
        controller.beginDebug()
        guard let panel = controller.panel, panel.isVisible else {
            throw XCTSkip("no display available to present the overlay")
        }
        XCTAssertTrue(controller.reclaimExistingSession(),
                      "a live overlay owns the event — no second session underneath")
        XCTAssertTrue(controller.panel === panel, "the live session must be kept, not replaced")
        controller.close()
        XCTAssertNil(controller.panel)
    }
}
