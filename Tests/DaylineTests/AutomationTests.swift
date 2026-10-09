import DaylineAutomation
import XCTest
@testable import Dayline

final class AutomationProtocolTests: XCTestCase {
    func testURLRoundTripPreservesUnicodeAndFields() throws {
        let request = DaylineAutomationRequest(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            action: .update,
            itemID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            title: "准备面试 & 复习 Buck",
            time: "10:15"
        )

        let restored = try DaylineAutomationRequest(url: request.url())

        XCTAssertEqual(restored.requestID, request.requestID)
        XCTAssertEqual(restored.action, .update)
        XCTAssertEqual(restored.itemID, request.itemID)
        XCTAssertEqual(restored.title, request.title)
        XCTAssertEqual(restored.time, "10:15")
    }

    func testTimelineRangeURLRoundTripPreservesBoundaries() throws {
        let request = DaylineAutomationRequest(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            action: .setTimelineRange,
            start: "07:00",
            end: "25:00"
        )

        let restored = try DaylineAutomationRequest(url: request.url())

        XCTAssertEqual(restored.requestID, request.requestID)
        XCTAssertEqual(restored.action, .setTimelineRange)
        XCTAssertEqual(restored.start, "07:00")
        XCTAssertEqual(restored.end, "25:00")
    }
}

@MainActor
final class AutomationControllerTests: XCTestCase {
    func testCompleteCRUDFlowUsesTheStoreAsSingleWriter() throws {
        let (store, stateURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let controller = AutomationController(store: store)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

        let added = controller.execute(
            DaylineAutomationRequest(
                action: .add,
                itemID: id,
                title: "准备面试",
                time: "10:15"
            )
        )
        XCTAssertTrue(added.ok)
        XCTAssertEqual(added.todos.first?.minute, 10 * 60 + 15)

        let updated = controller.execute(
            DaylineAutomationRequest(
                action: .update,
                itemID: id,
                title: "进行模拟面试",
                time: "11:30"
            )
        )
        XCTAssertEqual(updated.todos.first?.title, "进行模拟面试")
        XCTAssertEqual(updated.todos.first?.minute, 11 * 60 + 30)

        let completed = controller.execute(
            DaylineAutomationRequest(action: .setCompleted, itemID: id, completed: true)
        )
        XCTAssertEqual(completed.todos.first?.completed, true)

        let listed = controller.execute(DaylineAutomationRequest(action: .list))
        XCTAssertEqual(listed.todos.map(\.id), [id])
        XCTAssertEqual(listed.timeline?.start, "07:00")
        XCTAssertEqual(listed.timeline?.end, "25:00")
        XCTAssertEqual(listed.timeline?.intervalMinutes, 15)

        let deleted = controller.execute(DaylineAutomationRequest(action: .delete, itemID: id))
        XCTAssertTrue(deleted.ok)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testTimelineRangeMutationAdjustsTasksAndPersists() {
        let (store, stateURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let controller = AutomationController(store: store)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        store.addTask(id: id, title: "调整截止时间", at: 7 * 60)

        let response = controller.execute(
            DaylineAutomationRequest(
                action: .setTimelineRange,
                start: "09:00",
                end: "13:00"
            )
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(store.timelineStartMinute, 9 * 60)
        XCTAssertEqual(store.timelineEndMinute, 13 * 60)
        XCTAssertEqual(store.item(id: id)?.minute, 9 * 60)
        XCTAssertEqual(response.timeline?.start, "09:00")
        XCTAssertEqual(response.timeline?.end, "13:00")

        store.persist()
        let restored = TimelineStore(stateURL: stateURL, startsTimer: false)
        XCTAssertEqual(restored.timelineStartMinute, 9 * 60)
        XCTAssertEqual(restored.timelineEndMinute, 13 * 60)
        XCTAssertEqual(restored.item(id: id)?.minute, 9 * 60)
    }

    func testTimelineRangeAcceptsNextDayClockNotation() {
        let (store, stateURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }

        let response = AutomationController(store: store).execute(
            DaylineAutomationRequest(
                action: .setTimelineRange,
                start: "07:00",
                end: "01:00"
            )
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(store.timelineEndMinute, 25 * 60)
        XCTAssertEqual(response.timeline?.end, "25:00")
    }

    func testNextDayDeadlineCanBeReusedFromListResponse() throws {
        let (store, stateURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let controller = AutomationController(store: store)
        let id = store.addTask(title: "After midnight", at: 24 * 60 + 15)
        let listed = controller.execute(.init(action: .list))
        let time = try XCTUnwrap(listed.todos.first?.time)
        XCTAssertEqual(time, "24:15")
        let updated = controller.execute(.init(action: .update, itemID: id, time: time))
        XCTAssertTrue(updated.ok)
        XCTAssertEqual(updated.todos.first?.minute, 24 * 60 + 15)
        XCTAssertEqual(updated.todos.first?.time, time)
    }

    func testUnknownTodoIDFailsInsteadOfCrashing() {
        let (store, stateURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let controller = AutomationController(store: store)
        let missing = UUID()

        for request in [
            DaylineAutomationRequest(action: .update, itemID: missing, title: "旧"),
            DaylineAutomationRequest(action: .setCompleted, itemID: missing, completed: true),
            DaylineAutomationRequest(action: .delete, itemID: missing)
        ] {
            let response = controller.execute(request)
            XCTAssertFalse(response.ok)
            XCTAssertNotNil(response.error)
        }
    }

    private func makeStore() -> (TimelineStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        return (TimelineStore(stateURL: url, startsTimer: false), url)
    }
}
