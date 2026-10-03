import XCTest
@testable import Dayline

@MainActor
final class TimelineStoreTitleExpansionTests: XCTestCase {
    func testTitleExpansionDoesNotResizeTheTimelinePanel() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let id = store.addTask()
        store.updateTitle(id: id, title: String(repeating: "长标题", count: 12))
        let controller = FloatingPanelController(store: store)
        let compactWidth = try! XCTUnwrap(controller.window).frame.width

        store.toggleTitleExpansion(id: id)
        XCTAssertEqual(try! XCTUnwrap(controller.window).frame.width, compactWidth, accuracy: 0.5)

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
        store.fontSize = DaylineLayout.fontSizeRange.lowerBound
        store.compactTitleWidth = 164
        store.titleHeightRatio = 0.58
        store.timelineAnchorPosition = 0.82
        store.timeDisplayMode = .remaining
        store.clickGuardDuration = 0.35
        store.autoReturnMode = .firstTodo
        store.autoReturnDelay = 45
        store.persist()

        let restored = TimelineStore(stateURL: url, startsTimer: false)
        XCTAssertEqual(restored.fontSize, DaylineLayout.fontSizeRange.lowerBound)
        XCTAssertEqual(restored.compactTitleWidth, 164)
        XCTAssertEqual(restored.titleHeightRatio, 0.58)
        XCTAssertEqual(restored.timelineAnchorPosition, 0.82)
        XCTAssertEqual(restored.timeDisplayMode, .remaining)
        XCTAssertEqual(restored.clickGuardDuration, 0.35)
        XCTAssertEqual(restored.autoReturnMode, .firstTodo)
        XCTAssertEqual(restored.autoReturnDelay, 45)
    }

    func testAutoReturnSettingsUseDefaultsAndRestoreSavedValue() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(store.autoReturnMode, .off)
        XCTAssertEqual(store.autoReturnDelay, TimelineStore.defaultAutoReturnDelay)

        store.autoReturnMode = .firstTodo
        store.autoReturnDelay = 90
        store.persist()

        let restored = TimelineStore(stateURL: url, startsTimer: false)
        XCTAssertEqual(restored.autoReturnMode, .firstTodo)
        XCTAssertEqual(restored.autoReturnDelay, 90)
    }

    func testLegacyEnabledAutoReturnMigratesToCurrentTimeMode() throws {
        let (_, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let legacyState = SavedState(
            items: [],
            fontSize: 16,
            dockEdge: .left,
            dockY: 0.52,
            isExpanded: true,
            autoReturnToCurrentTime: true,
            autoReturnDelay: 40
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(legacyState).write(to: url)

        let restored = TimelineStore(stateURL: url, startsTimer: false)

        XCTAssertEqual(restored.autoReturnMode, .currentTime)
        XCTAssertEqual(restored.autoReturnDelay, 40)
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

    func testTasksPersistAcrossStoreRestart() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = store.addTask(title: "循环保留", at: 9 * 60)
        store.persist()

        let restored = TimelineStore(stateURL: url, startsTimer: false)
        XCTAssertEqual(restored.item(id: id)?.title, "循环保留")
        XCTAssertEqual(restored.item(id: id)?.minute, 9 * 60)
    }

    private func makeStore() -> (TimelineStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("timeline.json")
        return (TimelineStore(stateURL: url, startsTimer: false), url)
    }
}
