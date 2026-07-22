import Foundation
import XCTest
@testable import Dayline

final class TodoItemCodableTests: XCTestCase {
    func testLegacyItemWithoutCompletionOrExpansionDecodesAsActiveAndCompact() throws {
        let legacyJSON = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "title": "旧待办",
              "minute": 555,
              "createdAt": "2026-07-22T01:00:00Z"
            }
            """.utf8
        )

        let item = try decoder.decode(TodoItem.self, from: legacyJSON)

        XCTAssertFalse(item.isCompleted)
        XCTAssertFalse(item.isTitleExpanded)
        XCTAssertEqual(item.title, "旧待办")
        XCTAssertEqual(item.minute, 555)
    }

    func testSavedStateRoundTripPreservesCompletionAndExpansion() throws {
        let item = TodoItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "需要横向展开查看的长待办",
            minute: 13 * 60 + 45,
            isTitleExpanded: true,
            isCompleted: true,
            createdAt: Date(timeIntervalSince1970: 1_753_147_800)
        )
        let state = SavedState(
            dayKey: "2026-07-22",
            items: [item],
            fontSize: 16,
            dockEdge: .left,
            dockY: 0.42,
            isExpanded: true,
            panelHeightRatio: 0.85
        )

        let restored = try decoder.decode(SavedState.self, from: encoder.encode(state))
        let restoredItem = try XCTUnwrap(restored.items.first)

        XCTAssertEqual(restored.items.count, 1)
        XCTAssertEqual(restoredItem.id, item.id)
        XCTAssertEqual(restoredItem.title, item.title)
        XCTAssertEqual(restoredItem.minute, item.minute)
        XCTAssertTrue(restoredItem.isTitleExpanded)
        XCTAssertTrue(restoredItem.isCompleted)
        XCTAssertEqual(restored.dockEdge, .left)
        XCTAssertEqual(restored.panelHeightRatio, 0.85)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
