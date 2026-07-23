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

        let deleted = controller.execute(DaylineAutomationRequest(action: .delete, itemID: id))
        XCTAssertTrue(deleted.ok)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRejectsNonQuarterHourTime() {
        let (store, stateURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }

        let response = AutomationController(store: store).execute(
            DaylineAutomationRequest(action: .add, title: "无效时间", time: "10:07")
        )

        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.error?.contains("15 分钟") == true)
        XCTAssertTrue(store.items.isEmpty)
    }

    private func makeStore() -> (TodayStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("today.json")
        return (TodayStore(stateURL: url, startsTimer: false), url)
    }
}
