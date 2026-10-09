import XCTest
@testable import Dayline

final class DayClockTests: XCTestCase {
    func testDefaultTimeMovesToQuarterAtOrAfterNow() throws {
        XCTAssertEqual(DayClock.defaultTaskMinute(for: try date(hour: 9, minute: 0)), 9 * 60)
        XCTAssertEqual(DayClock.defaultTaskMinute(for: try date(hour: 9, minute: 1)), 9 * 60 + 15)
        XCTAssertEqual(DayClock.defaultTaskMinute(for: try date(hour: 9, minute: 14)), 9 * 60 + 15)
        XCTAssertEqual(DayClock.defaultTaskMinute(for: try date(hour: 9, minute: 15)), 9 * 60 + 15)
    }

    func testDefaultTimeStaysInsideCycle() throws {
        XCTAssertEqual(DayClock.defaultTaskMinute(for: try date(hour: 5, minute: 30)), DayClock.startMinute)
        XCTAssertEqual(DayClock.defaultTaskMinute(for: try date(hour: 23, minute: 59)), 24 * 60)
    }

    func testContinuousTimeMovesForwardToQuarter() {
        XCTAssertEqual(DayClock.quarterAtOrAfter(Double(9 * 60)), 9 * 60)
        XCTAssertEqual(DayClock.quarterAtOrAfter(Double(9 * 60) + 0.25), 9 * 60 + 15)
        XCTAssertEqual(DayClock.quarterAtOrAfter(Double(9 * 60) + 14.75), 9 * 60 + 15)
        XCTAssertEqual(DayClock.quarterAtOrAfter(Double(9 * 60) + 15), 9 * 60 + 15)
        XCTAssertEqual(DayClock.quarterAtOrAfter(Double(DayClock.startMinute) - 0.25), DayClock.startMinute)
        XCTAssertEqual(DayClock.quarterAtOrAfter(Double(DayClock.endMinute) - 0.25), DayClock.lastTaskMinute)
    }

    func testTimeMovesForwardAndClamps() {
        XCTAssertEqual(DayClock.quarterAtOrAfter(7 * 60 + 7), 7 * 60 + 15)
        XCTAssertEqual(DayClock.quarterAtOrAfter(7 * 60 + 14), 7 * 60 + 15)
        XCTAssertEqual(DayClock.quarterAtOrAfter(7 * 60 + 15), 7 * 60 + 15)
        XCTAssertEqual(DayClock.quarterAtOrAfter(2 * 60), DayClock.startMinute)
        XCTAssertEqual(DayClock.quarterAtOrAfter(26 * 60), DayClock.lastTaskMinute)
    }

    func testFractionalCurrentTimeClampsInsideTheVisibleTimeline() {
        XCTAssertEqual(
            DayClock.clamp(Double(23 * 60 + 5), start: 8 * 60, end: 21 * 60),
            Double(20 * 60 + 45)
        )
        XCTAssertEqual(
            DayClock.clamp(Double(7 * 60 + 30), start: 8 * 60, end: 21 * 60),
            Double(8 * 60)
        )
        XCTAssertEqual(
            DayClock.clamp(Double(12 * 60 + 0.5), start: 8 * 60, end: 21 * 60),
            Double(12 * 60 + 0.5)
        )
    }

    func testEveryMinuteHasExactlyOneCurrentMarkerRow() {
        let quarter = 10 * 60
        for currentMinute in quarter..<(quarter + 15) {
            let owners = [quarter, quarter + 15].compactMap {
                DaylineLayout.currentMarkerFraction(
                    currentMinute: currentMinute,
                    around: $0
                )
            }
            XCTAssertEqual(owners.count, 1, "missing marker at \(currentMinute)")
            XCTAssertTrue(owners.allSatisfy { (0..<1).contains($0) })
        }
    }

    func testDisplayUsesTwentyFourHourClock() {
        XCTAssertEqual(DayClock.displayTime(7 * 60), "07:00")
        XCTAssertEqual(DayClock.displayTime(13 * 60 + 45), "13:45")
        XCTAssertEqual(DayClock.displayTime(24 * 60), "00:00")
        XCTAssertEqual(DayClock.displayTime(25 * 60), "01:00")
    }

    func testAfterMidnightTimeRemainsInsideTheSameCycle() throws {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: Date())
        let afterMidnight = try XCTUnwrap(calendar.date(byAdding: .minute, value: 24 * 60 + 30, to: day))
        XCTAssertEqual(DayClock.minuteOfDay(for: afterMidnight, dayEndMinute: 25 * 60), 24 * 60 + 30)
    }

    func testFractionalMinuteIncludesSecondsAndMovesProjectionContinuously() throws {
        let exact = try date(hour: 9, minute: 30, second: 30)
        XCTAssertEqual(
            DayClock.minuteOfDayFraction(for: exact),
            Double(9 * 60 + 30) + 0.5,
            accuracy: 0.001
        )

        let projection = TimelineProjection(firstMinute: 9 * 60, firstCenterY: 50, fontSize: 16)
        XCTAssertEqual(
            projection.centerY(for: Double(9 * 60) + 0.5) - projection.centerY(for: 9 * 60),
            DaylineLayout.slotHeight(for: 16) / 30,
            accuracy: 0.001
        )
    }

    private func date(hour: Int, minute: Int, second: Int = 0) throws -> Date {
        let calendar = Calendar.autoupdatingCurrent
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = second
        return try XCTUnwrap(calendar.date(from: components))
    }

    func testTwelveHourDisplayHasNoPeriodMarker() {
        XCTAssertEqual(DayClock.displayTime(21 * 60 + 30, twelveHour: true), "9:30")
        XCTAssertEqual(DayClock.displayTime(12 * 60, twelveHour: true), "12:00")
        XCTAssertEqual(DayClock.displayTime(24 * 60 + 15, twelveHour: true), "12:15")
        XCTAssertEqual(DayClock.displayTime(21 * 60 + 30), "21:30")
        XCTAssertEqual(DayClock.displayHour(13, twelveHour: true), 1)
        XCTAssertEqual(DayClock.displayHour(0, twelveHour: true), 12)
    }
}
