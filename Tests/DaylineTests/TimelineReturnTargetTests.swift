import XCTest
@testable import Dayline

@MainActor
final class TimelineReturnTargetTests: XCTestCase {
    func testNowWithinOneSlotAboveShowsNoTopReturnTarget() {
        // Slot height at font size 16 is 41.6 points.
        let visible = TimelineProjection(firstMinute: 600, firstCenterY: -40, fontSize: 16)
        let scrolled = TimelineProjection(firstMinute: 600, firstCenterY: -43, fontSize: 16)

        XCTAssertNil(TimelineView.currentTimeReturnEdge(
            minute: 600, projection: visible, viewportHeight: 500
        ))
        XCTAssertEqual(TimelineView.currentTimeReturnEdge(
            minute: 600, projection: scrolled, viewportHeight: 500
        ), .top)
    }

    func testNowWithinOneSlotBelowShowsNoBottomReturnTarget() {
        let visible = TimelineProjection(firstMinute: 600, firstCenterY: 540, fontSize: 16)
        let scrolled = TimelineProjection(firstMinute: 600, firstCenterY: 543, fontSize: 16)

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
