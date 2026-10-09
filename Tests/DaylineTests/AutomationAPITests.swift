import DaylineAutomation
import XCTest
@testable import Dayline

@MainActor
final class AutomationAPITests: XCTestCase {
    func testListReportsNowNextTodoAndSettings() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        store.setTimelineRange(start: 0, end: 30 * 60)
        let next = store.addTask(title: "下一项", at: 23 * 60 + 45)
        let controller = AutomationController(store: store)

        let response = controller.execute(.init(action: .list))
        let timeline = try XCTUnwrap(response.timeline)

        XCTAssertEqual(timeline.now, String(format: "%02d:%02d", timeline.nowMinute / 60, timeline.nowMinute % 60))
        XCTAssertEqual(timeline.nextTodoID, store.currentTask(at: timeline.nowMinute)?.id)
        XCTAssertEqual(timeline.nextTodoID, next)
        XCTAssertEqual(response.settings?.clockFormat, "system")
        XCTAssertEqual(response.settings?.dockEdge, "left")
    }

    func testAddManyIsAllOrNothing() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        store.setTimelineRange(start: 9 * 60, end: 10 * 60)
        let controller = AutomationController(store: store)

        let tooMany = controller.execute(.init(action: .addMany, todos: (0..<5).map {
            DaylineAutomationNewTodo(title: "任务 \($0)")
        }))
        XCTAssertFalse(tooMany.ok)
        XCTAssertEqual(tooMany.errorCode, .timelineFull)
        XCTAssertTrue(store.items.isEmpty)

        let badTime = controller.execute(.init(action: .addMany, todos: [
            .init(title: "好的", time: "09:15"), .init(title: "坏的", time: "九点")
        ]))
        XCTAssertEqual(badTime.errorCode, .invalidTime)
        XCTAssertTrue(store.items.isEmpty)

        let added = controller.execute(.init(action: .addMany, todos: [
            .init(title: "写报告", time: "09:15"), .init(title: "开会", time: "09:30")
        ]))
        XCTAssertTrue(added.ok)
        XCTAssertEqual(added.todos.map(\.time), ["09:15", "09:30"])
    }

    func testUpdateSettingsClampsNumbersAndRejectsBadEnumsAtomically() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = AutomationController(store: store)

        var bad = DaylineAutomationSettings()
        bad.fontSize = 12
        bad.clockFormat = "sixteenHour"
        let rejected = controller.execute(.init(action: .updateSettings, settings: bad))
        XCTAssertEqual(rejected.errorCode, .invalidRequest)
        XCTAssertEqual(store.fontSize, 16)

        var good = DaylineAutomationSettings()
        good.fontSize = 99
        good.clockFormat = "twelveHour"
        good.dockEdge = "right"
        good.dockPosition = 0.3
        good.showsOverFullScreen = true
        good.autoReturn = "firstTodo"
        good.autoReturnDelay = 1
        let applied = controller.execute(.init(action: .updateSettings, settings: good))

        XCTAssertTrue(applied.ok)
        XCTAssertEqual(store.fontSize, 19)
        XCTAssertEqual(store.clockFormat, .twelveHour)
        XCTAssertEqual(store.dockEdge, .right)
        XCTAssertEqual(store.dockY, 0.3)
        XCTAssertTrue(store.showsOverFullScreen)
        XCTAssertEqual(store.autoReturnMode, .firstTodo)
        XCTAssertEqual(store.autoReturnDelay, 5)
        XCTAssertEqual(applied.settings?.fontSize, 19)
    }

    func testErrorCodesBlankTitlesAndDeletedTodoEcho() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = AutomationController(store: store)

        XCTAssertEqual(controller.execute(.init(action: .add, title: "   ")).errorCode, .invalidRequest)
        XCTAssertEqual(controller.execute(.init(action: .delete, itemID: UUID())).errorCode, .notFound)
        XCTAssertEqual(
            controller.execute(.init(action: .setTimelineRange, start: "7", end: "9:00")).errorCode,
            .invalidTime
        )

        let id = store.addTask(title: "读书", at: 21 * 60)
        let deleted = controller.execute(.init(action: .delete, itemID: id))
        XCTAssertEqual(deleted.todos.first?.title, "读书")
        XCTAssertEqual(deleted.todos.first?.time, "21:00")
    }

    func testShowAndControlRailGoThroughThePanel() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let panel = FakePanel()
        let controller = AutomationController(store: store, panel: panel)
        let id = store.addTask(title: "读书", at: 21 * 60)

        XCTAssertTrue(controller.execute(.init(action: .show, itemID: id)).ok)
        XCTAssertTrue(controller.execute(.init(action: .show)).ok)
        XCTAssertEqual(panel.revealed, [id, nil])

        var hide = DaylineAutomationSettings()
        hide.controlsVisible = false
        let response = controller.execute(.init(action: .updateSettings, settings: hide))
        XCTAssertEqual(response.settings?.controlsVisible, false)
    }

    func testNewFieldsSurviveTheURLRoundTrip() throws {
        var settings = DaylineAutomationSettings()
        settings.clockFormat = "twelveHour"
        settings.dockPosition = 0.25
        let request = DaylineAutomationRequest(
            action: .addMany,
            todos: [.init(title: "准备面试 & 复习", time: "10:15"), .init(title: "读书")],
            settings: settings
        )

        let restored = try DaylineAutomationRequest(url: request.url())

        XCTAssertEqual(restored.action, .addMany)
        XCTAssertEqual(restored.todos?.map(\.title), ["准备面试 & 复习", "读书"])
        XCTAssertEqual(restored.todos?.first?.time, "10:15")
        XCTAssertNil(restored.todos?.last?.time)
        XCTAssertEqual(restored.settings, settings)
    }

    private func makeStore() -> (TimelineStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        return (TimelineStore(stateURL: url, startsTimer: false), url)
    }
}

@MainActor
private final class FakePanel: TimelinePanelControlling {
    private(set) var controlsAreVisible = true
    private(set) var revealed: [UUID?] = []
    func setControlsVisible(_ visible: Bool) { controlsAreVisible = visible }
    func reveal(todo id: UUID?) { revealed.append(id) }
}
