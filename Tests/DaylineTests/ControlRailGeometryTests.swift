import AppKit
import XCTest
@testable import Dayline

final class ControlRailGeometryTests: XCTestCase {
    private let visible = NSRect(x: 100, y: 50, width: 1200, height: 800)

    func testHiddenAxisRestsThreePointsFromEitherEdge() {
        let width: CGFloat = 398
        let axisOffset = DaylineLayout.panelHorizontalPadding
            + DaylineLayout.controlSize
            + DaylineLayout.railSpacing
            + DaylineLayout.timelineAxisInset

        let leftX = ControlRailGeometry.frameX(
            edge: .left,
            controlsAreVisible: false,
            width: width,
            visibleFrame: visible,
            edgeInset: 2
        )
        let rightX = ControlRailGeometry.frameX(
            edge: .right,
            controlsAreVisible: false,
            width: width,
            visibleFrame: visible,
            edgeInset: 2
        )

        XCTAssertEqual(leftX + axisOffset, visible.minX + 3)
        XCTAssertEqual(rightX + width - axisOffset, visible.maxX - 3)
    }

    func testExpandedHandleAndCollapsedBallShareTheSameCenter() {
        let expandedWidth: CGFloat = 398
        let collapsedWidth: CGFloat = 48
        let leftExpandedX = ControlRailGeometry.frameX(
            edge: .left,
            controlsAreVisible: true,
            width: expandedWidth,
            visibleFrame: visible,
            edgeInset: 2
        ) + DaylineLayout.panelHorizontalPadding + DaylineLayout.controlSize / 2
        let rightExpandedX = ControlRailGeometry.frameX(
            edge: .right,
            controlsAreVisible: true,
            width: expandedWidth,
            visibleFrame: visible,
            edgeInset: 2
        ) + expandedWidth - DaylineLayout.panelHorizontalPadding - DaylineLayout.controlSize / 2

        XCTAssertEqual(leftExpandedX, visible.minX + 2 + collapsedWidth / 2)
        XCTAssertEqual(rightExpandedX, visible.maxX - 2 - collapsedWidth / 2)
    }

    func testTimelineHitLaneUsesSevenOutsideAndThreeInside() {
        XCTAssertEqual(DaylineLayout.timelineAxisInset, 7)
        XCTAssertEqual(
            DaylineLayout.timelineHitWidth - DaylineLayout.timelineAxisInset,
            3
        )
    }

    func testExpandedPanelUsesNinetyPercentWithSafeInsets() {
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(visibleHeight: 1000, safeInset: 12),
            900
        )
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(visibleHeight: 500, safeInset: 12),
            476
        )
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(
                visibleHeight: 1000,
                safeInset: 12,
                ratio: 0.75
            ),
            750
        )
    }
}
