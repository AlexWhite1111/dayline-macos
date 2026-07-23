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

    func testCompactTitleWidthControlsWhenExpansionBecomesAvailable() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = store.addTask()
        store.updateTitle(id: id, title: "一二三四五六七八")

        store.compactTitleWidth = DaylineLayout.compactTitleWidthRange.upperBound
        store.toggleTitleExpansion(id: id)
        XCTAssertFalse(store.item(id: id)?.isTitleExpanded == true)

        store.compactTitleWidth = DaylineLayout.compactTitleWidthRange.lowerBound
        store.toggleTitleExpansion(id: id)
        XCTAssertTrue(store.item(id: id)?.isTitleExpanded == true)
    }

    func testLayoutSettingsPersist() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        store.compactTitleWidth = 164
        store.titleHeightRatio = 0.58
        store.timelineAnchorPosition = 0.82
        store.persist()

        let restored = TodayStore(stateURL: url, startsTimer: false)
        XCTAssertEqual(restored.compactTitleWidth, 164)
        XCTAssertEqual(restored.titleHeightRatio, 0.58)
        XCTAssertEqual(restored.timelineAnchorPosition, 0.82)
    }

    func testCommitEditingFinalizesTheActiveTitleAndClearsEditing() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = store.addTask(title: "  修改内容  ")
        store.editingID = id

        store.commitEditing()

        XCTAssertEqual(store.item(id: id)?.title, "修改内容")
        XCTAssertNil(store.editingID)
    }

    private func makeStore() -> (TodayStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("today.json")
        return (TodayStore(stateURL: url, startsTimer: false), url)
    }
}
