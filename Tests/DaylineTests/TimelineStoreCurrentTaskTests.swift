import XCTest
@testable import Dayline

@MainActor
final class TimelineStoreCurrentTaskTests: XCTestCase {
    func testCompletingCurrentTaskPromotesTheNextOne() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TimelineStore(stateURL: url, startsTimer: false)
        let first = store.addTask(title: "当前", at: 10 * 60 + 15)
        let second = store.addTask(title: "下一项", at: 10 * 60 + 30)

        XCTAssertEqual(store.currentTask(at: 10 * 60)?.id, first)
        store.toggleCompleted(id: first)
        XCTAssertEqual(store.currentTask(at: 10 * 60)?.id, second)
    }

    func testCurrentTaskWrapsFromCycleTailToFirstRemainingTask() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TimelineStore(stateURL: url, startsTimer: false)
        let first = store.addTask(title: "轴头任务", at: 8 * 60)
        _ = store.addTask(title: "轴尾任务", at: 23 * 60)

        XCTAssertEqual(store.currentTask(at: 23 * 60 + 15)?.id, first)
    }

    func testDragPreviewMatchesTheCollisionResolvedDestination() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TimelineStore(stateURL: url, startsTimer: false)
        let dragged = store.addTask(title: "拖动", at: 10 * 60)
        _ = store.addTask(title: "占位", at: 10 * 60 + 15)

        let preview = store.dragDestination(near: Double(10 * 60 + 14), excluding: dragged)
        store.move(id: dragged, to: preview)

        XCTAssertEqual(preview, 10 * 60 + 30)
        XCTAssertEqual(store.item(id: dragged)?.minute, preview)
    }

    func testShrinkingRangeKeepsTasksInSeparateSlotsAndOrder() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TimelineStore(stateURL: url, startsTimer: false)
        let earliest = store.addTask(title: "最早", at: 7 * 60)
        let early = store.addTask(title: "较早", at: 7 * 60 + 15)
        let inside = store.addTask(title: "中间", at: 12 * 60)
        let late = store.addTask(title: "较晚", at: 23 * 60)
        let later = store.addTask(title: "更晚", at: 23 * 60 + 30)

        store.setTimelineRange(start: 9 * 60, end: 22 * 60)

        XCTAssertEqual(store.item(id: earliest)?.minute, 9 * 60)
        XCTAssertEqual(store.item(id: early)?.minute, 9 * 60 + 15)
        XCTAssertEqual(store.item(id: inside)?.minute, 12 * 60)
        XCTAssertEqual(store.item(id: late)?.minute, 21 * 60 + 30)
        XCTAssertEqual(store.item(id: later)?.minute, 21 * 60 + 45)
    }

    func testChangesAreSavedOnceAfterABurst() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TimelineStore(stateURL: url, startsTimer: false)
        for size in stride(from: 10.0, through: 15.0, by: 0.5) { store.fontSize = size }

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let restored = TimelineStore(stateURL: url, startsTimer: false)
        XCTAssertEqual(restored.fontSize, 15)
    }

    func testDragPreviewSnapsToNearestQuarter() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let dragged = store.addTask(title: "拖动", at: 10 * 60)

        XCTAssertEqual(store.dragDestination(near: Double(10 * 60) + 1, excluding: dragged), 10 * 60)
        XCTAssertEqual(store.dragDestination(near: Double(10 * 60) + 8, excluding: dragged), 10 * 60 + 15)
        XCTAssertEqual(store.dragDestination(near: Double(10 * 60) - 7, excluding: dragged), 10 * 60)
    }

    func testFullTimelineRefusesNewTasksAndShrinking() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertTrue(store.setTimelineRange(start: 9 * 60, end: 10 * 60))
        for index in 0..<4 { store.addTask(title: "任务 \(index)") }
        XCTAssertFalse(store.hasFreeSlot)
        XCTAssertEqual(Set(store.items.map(\.minute)).count, 4)

        XCTAssertTrue(store.setTimelineRange(start: 9 * 60, end: 11 * 60))
        store.addTask(title: "第五项")
        XCTAssertFalse(store.setTimelineRange(start: 9 * 60, end: 10 * 60))
        XCTAssertEqual(store.timelineEndMinute, 11 * 60)
    }

    func testEscapeRestoresTheOriginalTitle() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = store.addTask(title: "原标题")
        store.editingID = id
        store.updateTitle(id: id, title: "")

        store.cancelEditing()

        XCTAssertEqual(store.item(id: id)?.title, "原标题")
        XCTAssertNil(store.editingID)
        XCTAssertNil(store.recentlyDeleted)
    }

    func testEscapeOnANewUntitledTaskRemovesItWithoutUndo() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = store.addTask()
        store.editingID = id
        store.updateTitle(id: id, title: "写了一半")

        store.cancelEditing()

        XCTAssertNil(store.item(id: id))
        XCTAssertNil(store.recentlyDeleted)
    }

    func testClearingATitleDeletesAndUndoRestoresTheOriginal() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = store.addTask(title: "读书", at: 21 * 60)
        store.editingID = id
        store.updateTitle(id: id, title: "   ")

        store.commitEditing()
        XCTAssertNil(store.item(id: id))
        XCTAssertEqual(store.recentlyDeleted?.title, "读书")

        store.undoDelete()
        XCTAssertEqual(store.item(id: id)?.title, "读书")
        XCTAssertEqual(store.item(id: id)?.minute, 21 * 60)
        XCTAssertNil(store.recentlyDeleted)
    }

    private func makeStore() -> (TimelineStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        return (TimelineStore(stateURL: url, startsTimer: false), url)
    }
}
