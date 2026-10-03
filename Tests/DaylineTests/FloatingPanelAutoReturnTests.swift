import AppKit
import XCTest
@testable import Dayline

@MainActor
final class FloatingPanelAutoReturnTests: XCTestCase {
    func testChangingDelayUsesNewPublishedValue() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        store.autoReturnDelay = 300
        store.autoReturnMode = .currentTime
        let controller = FloatingPanelController(store: store)

        store.autoReturnDelay = 5
        XCTAssertFalse(controller.autoReturnIsActive)
        try await Task.sleep(for: .seconds(5.2))

        // The old willSet callback schedules 300 seconds instead of the new 5.
        XCTAssertTrue(controller.autoReturnIsActive)
        store.autoReturnMode = .off
        XCTAssertFalse(controller.autoReturnIsActive)
    }

    func testCurrentTimeTargetUsesIncomingTickIncludingSeconds() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        store.setTimelineRange(start: 0, end: 24 * 60)
        store.autoReturnMode = .currentTime
        let controller = FloatingPanelController(store: store)
        let tick = try XCTUnwrap(Calendar.current.date(
            bySettingHour: 10, minute: 15, second: 30, of: store.clockDate
        ))

        XCTAssertEqual(try XCTUnwrap(controller.autoReturnTargetMinute(at: tick)), 615.5)
    }

    func testFirstTodoTargetAdvancesOnIncomingTick() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        store.setTimelineRange(start: 0, end: 24 * 60)
        store.addTask(title: "First", at: 10 * 60)
        store.addTask(title: "Next", at: 11 * 60)
        store.autoReturnMode = .firstTodo
        let controller = FloatingPanelController(store: store)
        let before = try XCTUnwrap(Calendar.current.date(
            bySettingHour: 10, minute: 0, second: 30, of: store.clockDate
        ))
        let after = before.addingTimeInterval(30)

        XCTAssertEqual(controller.autoReturnTargetMinute(at: before), 600)
        XCTAssertEqual(controller.autoReturnTargetMinute(at: after), 660)
    }

    func testExplicitScrollUsesFractionalMinuteAndRepeatsWithoutFocusIDChange() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 500))
        let document = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: 100, height: 3000))
        scrollView.documentView = document
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1000))
        let initialOffset = scrollView.contentView.bounds.minY
        let minute = 615.5
        var projection = TimelineProjection(firstMinute: 480, firstCenterY: -900, fontSize: 16)
        let anchor = DaylineLayout.timelineAnchorCenterY(
            viewportHeight: 500, fontSize: 16, position: 0.97
        )

        FloatingPanelController.scrollToAnchor(
            minute, in: scrollView, projection: projection,
            viewportHeight: 500, anchorPosition: 0.97
        )

        let returnedOffset = scrollView.contentView.bounds.minY
        XCTAssertNotEqual(returnedOffset, initialOffset)
        projection = TimelineProjection(
            firstMinute: projection.firstMinute,
            firstCenterY: projection.firstCenterY - (returnedOffset - initialOffset),
            fontSize: projection.fontSize
        )
        XCTAssertEqual(projection.centerY(for: minute), anchor, accuracy: 0.01)

        // A partial-slot scroll need not change SwiftUI's target ID. The explicit
        // operation must still recover the saved anchor on every invocation.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: returnedOffset + 10))
        projection = TimelineProjection(
            firstMinute: projection.firstMinute,
            firstCenterY: projection.firstCenterY - 10,
            fontSize: projection.fontSize
        )
        FloatingPanelController.scrollToAnchor(
            minute, in: scrollView, projection: projection,
            viewportHeight: 500, anchorPosition: 0.97
        )
        XCTAssertEqual(scrollView.contentView.bounds.minY, returnedOffset, accuracy: 0.01)
    }

    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    private func makeStore() -> (TimelineStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        return (TimelineStore(stateURL: url, startsTimer: false), url)
    }
}
