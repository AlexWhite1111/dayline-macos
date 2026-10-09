import AppKit
import XCTest
@testable import Dayline

final class ControlRailGeometryTests: XCTestCase {
    func testCompactPanelGrowsOnlyWhenTitleLimitExceedsDefault() {
        XCTAssertEqual(
            DaylineLayout.compactPanelWidth(for: 80),
            DaylineLayout.compactPanelWidth
        )
        XCTAssertEqual(
            DaylineLayout.compactPanelWidth(for: 300),
            DaylineLayout.compactPanelWidth + 188
        )
    }

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

    func testTimelineFogUsesHalfPillHeight() {
        let fontSize = 16.0
        let fade = DaylineLayout.timelineFadeDistance(for: fontSize)
        let height: CGFloat = 600

        XCTAssertEqual(fade, DaylineLayout.pillHeight(for: fontSize) / 2)
        XCTAssertEqual(
            DaylineLayout.timelineEdgeOpacity(
                centerY: 0,
                viewportHeight: height,
                fontSize: fontSize
            ),
            0
        )
        XCTAssertEqual(
            DaylineLayout.timelineEdgeOpacity(
                centerY: fade,
                viewportHeight: height,
                fontSize: fontSize
            ),
            1
        )
    }

    func testTimelineProjectionIsSymmetricAroundAnchor() {
        let fontSize = 16.0
        let height: CGFloat = 600
        let anchorY = DaylineLayout.timelineAnchorCenterY(
            viewportHeight: height,
            fontSize: fontSize,
            position: DaylineLayout.defaultTimelineAnchorPosition
        )
        let slotHeight = DaylineLayout.slotHeight(for: fontSize)

        XCTAssertEqual(
            DaylineLayout.timelineCenterY(
                minute: 12 * 60,
                referenceMinute: 12 * 60,
                referenceCenterY: anchorY,
                slotHeight: slotHeight
            ),
            anchorY,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DaylineLayout.timelineCenterY(
                minute: 12 * 60 + 15,
                referenceMinute: 12 * 60,
                referenceCenterY: anchorY,
                slotHeight: slotHeight
            ),
            anchorY + slotHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DaylineLayout.timelineCenterY(
                minute: 12 * 60 - 15,
                referenceMinute: 12 * 60,
                referenceCenterY: anchorY,
                slotHeight: slotHeight
            ),
            anchorY - slotHeight,
            accuracy: 0.001
        )
    }

    func testMeasuredProjectionKeepsItsMatchingSizeScale() {
        let fontSize = 16.0
        let slotHeight = DaylineLayout.slotHeight(for: fontSize)
        let projection = TimelineProjection(
            firstMinute: 7 * 60,
            firstCenterY: -240,
            fontSize: fontSize
        )

        XCTAssertEqual(
            projection.centerY(for: 8 * 60),
            -240 + slotHeight * 4,
            accuracy: 0.001
        )
    }

    func testTimelineAnchorRunsFromSafeBottomToSafeTop() {
        let fontSize = 16.0
        let height: CGFloat = 600
        let halfSlot = DaylineLayout.slotHeight(for: fontSize) / 2

        XCTAssertEqual(
            DaylineLayout.timelineAnchorCenterY(
                viewportHeight: height,
                fontSize: fontSize,
                position: 0
            ),
            height - halfSlot,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DaylineLayout.timelineAnchorCenterY(
                viewportHeight: height,
                fontSize: fontSize,
                position: 1
            ),
            halfSlot,
            accuracy: 0.001
        )
    }

    func testTimelineHitWindowLeavesRealSpaceForCurrentTimeButtons() {
        let panel = NSRect(x: 100, y: 50, width: 398, height: 680)
        let timeline = FloatingItemGeometry.timelineFrame(in: panel, edge: .left)
        let clearance = DaylineLayout.timelineFadeDistance(for: 16)
            + DaylineLayout.currentTimeButtonHitSize / 2
        let lane = FloatingItemGeometry.axisHitFrame(
            in: panel,
            edge: .left,
            edgeClearance: clearance
        )

        XCTAssertEqual(lane.minY, timeline.minY + clearance, accuracy: 0.001)
        XCTAssertEqual(lane.maxY, timeline.maxY - clearance, accuracy: 0.001)
    }

    func testPinnedHitLaneMirrorsAroundTheTimelineAxis() {
        let panel = NSRect(x: 100, y: 50, width: 398, height: 680)
        let leftTimeline = FloatingItemGeometry.timelineFrame(in: panel, edge: .left)
        let leftLane = FloatingItemGeometry.axisHitFrame(in: panel, edge: .left)
        let rightTimeline = FloatingItemGeometry.timelineFrame(in: panel, edge: .right)
        let rightLane = FloatingItemGeometry.axisHitFrame(in: panel, edge: .right)

        XCTAssertEqual(leftTimeline.minX + 7 - leftLane.minX, 7)
        XCTAssertEqual(leftLane.maxX - (leftTimeline.minX + 7), 3)
        XCTAssertEqual(rightTimeline.maxX - 7 - rightLane.minX, 3)
        XCTAssertEqual(rightLane.maxX - (rightTimeline.maxX - 7), 7)
    }

    func testPillAxisGapMirrorsAndLeavesInputLaneClear() {
        let panel = NSRect(x: 100, y: 50, width: 398, height: 680)
        for width: CGFloat in [140, 300, 600] {
            for edge in [DockEdge.left, .right] {
                let timeline = FloatingItemGeometry.timelineFrame(in: panel, edge: edge)
                let lane = FloatingItemGeometry.axisHitFrame(in: panel, edge: edge)
                let task = FloatingItemGeometry.taskFrame(
                    in: panel, edge: edge, centerY: 200,
                    taskSize: NSSize(width: width, height: 80)
                ).insetBy(dx: DaylineLayout.pillWindowPadding, dy: DaylineLayout.pillWindowPadding)
                let axisX = edge == .left
                    ? timeline.minX + DaylineLayout.timelineAxisInset
                    : timeline.maxX - DaylineLayout.timelineAxisInset
                let gap = edge == .left ? task.minX - axisX : axisX - task.maxX

                XCTAssertEqual(gap, DaylineLayout.axisToPillGap, accuracy: 0.001)
                XCTAssertFalse(task.intersects(lane))
                XCTAssertEqual(task.midY, timeline.maxY - 200, accuracy: 0.001)
            }
        }
    }

    func testExpandedPanelUsesConfiguredSafeWorkspaceRatio() {
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(availableHeight: 1000),
            900
        )
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(availableHeight: 500),
            480
        )
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(
                availableHeight: 1000,
                ratio: 0.75
            ),
            750
        )
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(availableHeight: 1000, ratio: 1),
            1000
        )
        XCTAssertEqual(
            DaylineLayout.expandedPanelHeight(availableHeight: 1000, ratio: 0.6),
            600
        )
    }
}
