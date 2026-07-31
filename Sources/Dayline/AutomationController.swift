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
                guard store.item(id: id) == nil else { throw Failure("待办 ID 已存在。") }
                store.addTask(id: id, title: title, at: minute)
                return success(request.action, todos: [todo(id)])

            case .update:
                let id = try requiredID(request.itemID)
                guard store.item(id: id) != nil else { throw Failure("没有找到这条待办。") }
                guard request.title != nil || request.time != nil else {
                    throw Failure("至少提供 title 或 time 中的一项。")
                }
                if let title = request.title { store.updateTitle(id: id, title: try requiredTitle(title)) }
                if let time = request.time { store.move(id: id, to: try parseTime(time)) }
                return success(request.action, todos: [todo(id)])

            case .setTimelineRange:
                let start = try parseRangeStart(request.start)
                let end = try parseRangeEnd(request.end, after: start)
                store.setTimelineRange(start: start, end: end)
                return success(
                    request.action,
                    message: "时间轴范围已更新为 \(automationTime(start))–\(automationTime(end))。"
                )

            case .setCompleted:
                let id = try requiredID(request.itemID)
                guard store.item(id: id) != nil else { throw Failure("没有找到这条待办。") }
                guard let completed = request.completed else { throw Failure("缺少 completed。") }
                store.setCompleted(id: id, completed: completed)
                return success(request.action, todos: [todo(id)])

            case .delete:
                let id = try requiredID(request.itemID)
                guard store.item(id: id) != nil else { throw Failure("没有找到这条待办。") }
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
        store.items
            .sorted { $0.minute == $1.minute ? $0.createdAt < $1.createdAt : $0.minute < $1.minute }
            .map(makeTodo)
    }

    private func makeTodo(_ item: TodoItem) -> DaylineAutomationTodo {
        DaylineAutomationTodo(
            id: item.id,
            title: item.title,
            minute: item.minute,
            time: DayClock.displayRangeTime(item.minute),
            completed: item.isCompleted,
            createdAt: item.createdAt
        )
    }

    private func requiredID(_ value: UUID?) throws -> UUID {
        guard let value else { throw Failure("缺少有效的待办 ID。") }
        return value
    }

    private func requiredTitle(_ value: String?) throws -> String {
        let title = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { throw Failure("待办标题不能为空。") }
        return title
    }

    private func parseTime(_ value: String) throws -> Int {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...30).contains(hour),
            (0..<60).contains(minute),
            minute.isMultiple(of: 15)
        else { throw Failure("截止时间使用 HH:mm 格式和 15 分钟刻度。") }

        var result = hour * 60 + minute
        let overflow = max(0, store.timelineEndMinute - 24 * 60)
        if result < store.timelineStartMinute, result < overflow { result += 24 * 60 }
        guard (store.timelineStartMinute..<store.timelineEndMinute).contains(result) else {
            throw Failure(
                "可用截止时间范围为 \(DayClock.displayRangeTime(store.timelineStartMinute))–"
                    + "\(DayClock.displayRangeTime(store.timelineEndMinute))。"
            )
        }
        return result
    }

    private func parseRangeStart(_ value: String?) throws -> Int {
        let result = try parseWholeHour(value, field: "start")
        guard result <= 23 * 60 else {
            throw Failure("start 使用 00:00–23:00 的整点格式。")
        }
        return result
    }

    private func parseRangeEnd(_ value: String?, after start: Int) throws -> Int {
        let rawEnd = try parseWholeHour(value, field: "end")
        let end = rawEnd < 24 * 60 && rawEnd <= start ? rawEnd + 24 * 60 : rawEnd
        guard end <= 30 * 60 else {
            throw Failure("end 使用 01:00–30:00 的整点格式，并位于 start 之后。")
        }
        guard end >= start + 60 else {
            throw Failure("时间轴范围至少包含 1 小时。")
        }
        return end
    }

    private func parseWholeHour(_ value: String?, field: String) throws -> Int {
        let parts = value?.split(separator: ":", omittingEmptySubsequences: false) ?? []
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...30).contains(hour),
            minute == 0
        else {
            throw Failure("\(field) 使用 HH:00 格式。")
        }
        return hour * 60
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
