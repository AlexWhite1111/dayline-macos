import XCTest
@testable import Dayline

@MainActor
final class TodayStoreCurrentTaskTests: XCTestCase {
    func testCompletingCurrentTaskPromotesTheNextOne() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("today.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TodayStore(stateURL: url, startsTimer: false)
        let first = store.addTask(title: "当前", at: 10 * 60 + 15)
        let second = store.addTask(title: "下一项", at: 10 * 60 + 30)

        XCTAssertEqual(store.currentTask(at: 10 * 60)?.id, first)
        store.toggleCompleted(id: first)
        XCTAssertEqual(store.currentTask(at: 10 * 60)?.id, second)
    }

    func testDragPreviewMatchesTheCollisionResolvedDestination() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("today.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TodayStore(stateURL: url, startsTimer: false)
        let dragged = store.addTask(title: "拖动", at: 10 * 60)
        _ = store.addTask(title: "占位", at: 10 * 60 + 15)

        let preview = store.dragDestination(near: Double(10 * 60 + 14), excluding: dragged)
        store.move(id: dragged, to: preview)

        XCTAssertEqual(preview, 10 * 60 + 30)
        XCTAssertEqual(store.item(id: dragged)?.minute, preview)
    }
}
