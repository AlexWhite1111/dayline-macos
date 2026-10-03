import XCTest
@testable import Dayline

@MainActor
final class TimelineReturnTargetTests: XCTestCase {
    func testFractionalScrollRevealsAndClearsTopReturnTarget() {
        let visible = TimelineProjection(firstMinute: 600, firstCenterY: 2, fontSize: 16)
        let scrolled = TimelineProjection(firstMinute: 600, firstCenterY: -3.5, fontSize: 16)

        // Both offsets can retain the same quarter-hour focus ID.
        XCTAssertNil(TimelineView.currentTimeReturnEdge(
            minute: 600, projection: visible, viewportHeight: 500
        ))
        XCTAssertEqual(TimelineView.currentTimeReturnEdge(
            minute: 600, projection: scrolled, viewportHeight: 500
        ), .top)
    }

    func testFractionalScrollRevealsAndClearsBottomReturnTarget() {
        let visible = TimelineProjection(firstMinute: 600, firstCenterY: 499, fontSize: 16)
        let scrolled = TimelineProjection(firstMinute: 600, firstCenterY: 503.5, fontSize: 16)

        XCTAssertNil(TimelineView.currentTimeReturnEdge(
            minute: 600, projection: visible, viewportHeight: 500
        ))
        XCTAssertEqual(TimelineView.currentTimeReturnEdge(
            minute: 600, projection: scrolled, viewportHeight: 500
        ), .bottom)
    }

    func testReturnTargetProjectsCurrentTimeAwayFromFirstSlot() {
        let projection = TimelineProjection(firstMinute: 480, firstCenterY: -200, fontSize: 7)
        XCTAssertEqual(TimelineView.currentTimeReturnEdge(
            minute: 480, projection: projection, viewportHeight: 500
        ), .top)
        XCTAssertNil(TimelineView.currentTimeReturnEdge(
            minute: 600, projection: projection, viewportHeight: 500
        ))
        XCTAssertEqual(TimelineView.currentTimeReturnEdge(
            minute: 900, projection: projection, viewportHeight: 500
        ), .bottom)
    }
}
