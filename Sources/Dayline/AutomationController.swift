import DaylineAutomation
import Foundation

@MainActor
final class AutomationController {
    private let store: TimelineStore

    init(store: TimelineStore) {
        self.store = store
    }

    func execute(_ request: DaylineAutomationRequest) -> DaylineAutomationResponse {
        do {
            switch request.action {
            case .list:
                return success(request.action, todos: allTodos())

            case .add:
                let title = try requiredTitle(request.title)
                let minute = try request.time.map(parseTime)
                let id = request.itemID ?? UUID()
                guard store.hasFreeSlot else { throw Failure("时间轴已满，没有空闲的 15 分钟刻度。") }
                store.addTask(id: id, title: title, at: minute)
                return success(request.action, todos: [todo(id)])

            case .update:
                let id = try existingID(request.itemID)
                if let title = request.title { store.updateTitle(id: id, title: try requiredTitle(title)) }
                if let time = request.time { store.move(id: id, to: try parseTime(time)) }
                return success(request.action, todos: [todo(id)])

            case .setTimelineRange:
                let start = try parseClock(request.start)
                let rawEnd = try parseClock(request.end)
                let end = rawEnd < 24 * 60 && rawEnd <= start ? rawEnd + 24 * 60 : rawEnd
                guard store.setTimelineRange(start: start, end: end) else {
                    throw Failure("这个范围放不下现有的 \(store.items.count) 个待办。")
                }
                return success(
                    request.action,
                    message: "时间轴范围已更新为 \(automationTime(start))–\(automationTime(end))。"
                )

            case .setCompleted:
                let id = try existingID(request.itemID)
                guard let completed = request.completed else { throw Failure("缺少 completed。") }
                store.setCompleted(id: id, completed: completed)
                return success(request.action, todos: [todo(id)])

            case .delete:
                let id = try existingID(request.itemID)
                store.delete(id: id)
                return success(request.action, message: "已删除待办。")
            }
        } catch {
            return DaylineAutomationResponse(
                ok: false,
                action: request.action,
                timeline: timeline(),
                error: error.localizedDescription
            )
        }
    }

    private func success(
        _ action: DaylineAutomationAction,
        todos: [DaylineAutomationTodo] = [],
        message: String? = nil
    ) -> DaylineAutomationResponse {
        DaylineAutomationResponse(
            ok: true,
            action: action,
            timeline: timeline(),
            todos: todos,
            message: message
        )
    }

    private func timeline() -> DaylineAutomationTimeline {
        DaylineAutomationTimeline(
            startMinute: store.timelineStartMinute,
            endMinute: store.timelineEndMinute,
            start: automationTime(store.timelineStartMinute),
            end: automationTime(store.timelineEndMinute),
            intervalMinutes: 15
        )
    }

    private func todo(_ id: UUID) -> DaylineAutomationTodo {
        makeTodo(store.item(id: id)!)
    }

    private func allTodos() -> [DaylineAutomationTodo] {
        store.itemsByDeadline.map(makeTodo)
    }

    private func makeTodo(_ item: TodoItem) -> DaylineAutomationTodo {
        DaylineAutomationTodo(
            id: item.id,
            title: item.title,
            minute: item.minute,
            time: automationTime(item.minute),
            completed: item.isCompleted,
            createdAt: item.createdAt
        )
    }

    private func existingID(_ value: UUID?) throws -> UUID {
        guard let value else { throw Failure("缺少有效的待办 ID。") }
        guard store.item(id: value) != nil else { throw Failure("找不到这个待办，请先 list。") }
        return value
    }

    private func requiredTitle(_ value: String?) throws -> String {
        guard let value else { throw Failure("缺少 title。") }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseTime(_ value: String) throws -> Int {
        var result = try parseClock(value)
        let overflow = max(0, store.timelineEndMinute - 24 * 60)
        if result < store.timelineStartMinute, result < overflow { result += 24 * 60 }
        return result
    }

    private func parseClock(_ value: String?) throws -> Int {
        let parts = value?.split(separator: ":", omittingEmptySubsequences: false) ?? []
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            throw Failure("缺少 HH:mm 时间。")
        }
        return hour * 60 + minute
    }

    private func automationTime(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
