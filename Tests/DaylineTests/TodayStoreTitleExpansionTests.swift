import XCTest
@testable import Dayline

@MainActor
final class TodayStoreTitleExpansionTests: XCTestCase {
    func testPanelResizesOnTheSameExpansionClick() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let id = store.addTask()
        store.updateTitle(id: id, title: String(repeating: "长标题", count: 12))
        let controller = FloatingPanelController(store: store)
        let compactWidth = try! XCTUnwrap(controller.window).frame.width

        store.toggleTitleExpansion(id: id)
        XCTAssertGreaterThan(try! XCTUnwrap(controller.window).frame.width, compactWidth)

        store.toggleTitleExpansion(id: id)
        XCTAssertEqual(try! XCTUnwrap(controller.window).frame.width, compactWidth, accuracy: 0.5)
    }

    func testEditingAndResizingDoNotForgetExpansionChoice() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = store.addTask()
        store.updateTitle(id: id, title: String(repeating: "长标题", count: 12))
        store.toggleTitleExpansion(id: id)
        XCTAssertTrue(store.item(id: id)?.isTitleExpanded == true)

        store.updateTitle(id: id, title: "短标题")
        store.fontSize = 13
        XCTAssertTrue(store.item(id: id)?.isTitleExpanded == true)

        store.isExpanded = false
        store.isExpanded = true
        XCTAssertTrue(store.item(id: id)?.isTitleExpanded == true)
    }

    private func makeStore() -> (TodayStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("today.json")
        return (TodayStore(stateURL: url, startsTimer: false), url)
    }
}
