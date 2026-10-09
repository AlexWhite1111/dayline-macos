import DaylineAutomation
import Foundation
import ServiceManagement

/// Window state that automation can drive; `FloatingPanelController` implements it.
@MainActor
protocol TimelinePanelControlling: AnyObject {
    var controlsAreVisible: Bool { get }
    func setControlsVisible(_ visible: Bool)
    /// Expands the timeline, brings it forward and scrolls to the todo, or to now.
    func reveal(todo id: UUID?)
}

@MainActor
final class AutomationController {
    private let store: TimelineStore
    private weak var panel: TimelinePanelControlling?

    init(store: TimelineStore, panel: TimelinePanelControlling? = nil) {
        self.store = store
        self.panel = panel
    }

    func execute(_ request: DaylineAutomationRequest) -> DaylineAutomationResponse {
        do {
            switch request.action {
            case .list:
                return success(request.action, todos: allTodos(), settings: settings())

            case .add:
                let title = try requiredTitle(request.title)
                let minute = try request.time.map(parseTime)
                guard store.freeSlotCount > 0 else {
                    throw Failure(.timelineFull, "时间轴已满，没有空闲的 15 分钟刻度。")
                }
                let id = request.itemID ?? UUID()
                store.addTask(id: id, title: title, at: minute)
                return success(request.action, todos: [todo(id)])

            case .addMany:
                guard let todos = request.todos, !todos.isEmpty else {
                    throw Failure(.invalidRequest, "缺少 todos。")
                }
                // Validate everything before adding anything.
                let parsed = try todos.map { (try requiredTitle($0.title), try $0.time.map(parseTime)) }
                guard parsed.count <= store.freeSlotCount else {
                    throw Failure(
                        .timelineFull,
                        "时间轴只剩 \(store.freeSlotCount) 个空闲刻度，放不下 \(parsed.count) 个待办。"
                    )
                }
                let ids = parsed.map { store.addTask(title: $0.0, at: $0.1) }
                return success(request.action, todos: ids.map(todo))

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
                    throw Failure(.rangeTooSmall, "这个范围放不下现有的 \(store.items.count) 个待办。")
                }
                return success(
                    request.action,
                    message: "时间轴范围已更新为 \(automationTime(start))–\(automationTime(end))。"
                )

            case .setCompleted:
                let id = try existingID(request.itemID)
                guard let completed = request.completed else {
                    throw Failure(.invalidRequest, "缺少 completed。")
                }
                store.setCompleted(id: id, completed: completed)
                return success(request.action, todos: [todo(id)])

            case .delete:
                let id = try existingID(request.itemID)
                let removed = todo(id)
                store.delete(id: id)
                return success(request.action, todos: [removed], message: "已删除待办。")

            case .updateSettings:
                guard let changes = request.settings else {
                    throw Failure(.invalidRequest, "缺少 settings。")
                }
                try apply(changes)
                return success(request.action, settings: settings())

            case .show:
                if let id = request.itemID { _ = try existingID(id) }
                panel?.reveal(todo: request.itemID)
                return success(request.action, todos: request.itemID.map { [todo($0)] } ?? [])
            }
        } catch let failure as Failure {
            return failureResponse(request.action, failure.message, code: failure.code)
        } catch {
            return failureResponse(request.action, error.localizedDescription, code: .invalidRequest)
        }
    }

    // MARK: Settings

    private func settings() -> DaylineAutomationSettings {
        var value = DaylineAutomationSettings()
        value.fontSize = store.fontSize
        value.titleHeightRatio = store.titleHeightRatio
        value.compactTitleWidth = store.compactTitleWidth
        value.panelHeightRatio = store.panelHeightRatio
        value.timelineAnchorPosition = store.timelineAnchorPosition
        value.glassStyle = store.nativeGlassStyle.rawValue
        value.timeDisplay = store.timeDisplayMode.rawValue
        value.clockFormat = store.clockFormat.rawValue
        value.pinsOnlyCurrentTask = store.pinsOnlyCurrentTask
        value.clickGuardDuration = store.clickGuardDuration
        value.autoReturn = store.autoReturnMode.rawValue
        value.autoReturnDelay = store.autoReturnDelay
        value.showsOverFullScreen = store.showsOverFullScreen
        value.expanded = store.isExpanded
        value.controlsVisible = panel?.controlsAreVisible ?? true
        value.dockEdge = store.dockEdge.rawValue
        value.dockPosition = store.dockY
        let status = SMAppService.mainApp.status
        value.launchAtLogin = status == .enabled || status == .requiresApproval
        return value
    }

    /// Validates every enum value first so a bad request changes nothing; numbers clamp
    /// to the ranges the Settings sliders allow.
    private func apply(_ changes: DaylineAutomationSettings) throws {
        let glass = try changes.glassStyle.map { try rawValue(NativeGlassStyle.self, $0, "glassStyle") }
        let display = try changes.timeDisplay.map { try rawValue(TimeDisplayMode.self, $0, "timeDisplay") }
        let clock = try changes.clockFormat.map { try rawValue(ClockFormat.self, $0, "clockFormat") }
        let autoReturn = try changes.autoReturn.map { try rawValue(AutoReturnMode.self, $0, "autoReturn") }
        let edge = try changes.dockEdge.map { try rawValue(DockEdge.self, $0, "dockEdge") }

        if let enabled = changes.launchAtLogin {
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                throw Failure(.invalidRequest, "开机启动设置失败：\(error.localizedDescription)")
            }
        }
        if let value = changes.fontSize { store.fontSize = value.clamped(to: DaylineLayout.fontSizeRange) }
        if let value = changes.titleHeightRatio {
            store.titleHeightRatio = value.clamped(to: DaylineLayout.titleHeightRatioRange)
        }
        if let value = changes.compactTitleWidth {
            store.compactTitleWidth = value.clamped(to: DaylineLayout.compactTitleWidthRange)
        }
        if let value = changes.panelHeightRatio {
            store.panelHeightRatio = value.clamped(to: DaylineLayout.panelHeightRatioRange)
        }
        if let value = changes.timelineAnchorPosition {
            store.timelineAnchorPosition = value.clamped(to: DaylineLayout.timelineAnchorPositionRange)
        }
        if let glass { store.nativeGlassStyle = glass }
        if let display { store.timeDisplayMode = display }
        if let clock { store.clockFormat = clock }
        if let value = changes.pinsOnlyCurrentTask { store.pinsOnlyCurrentTask = value }
        if let value = changes.clickGuardDuration {
            store.clickGuardDuration = value.clamped(to: TimelineStore.clickGuardDurationRange)
        }
        if let autoReturn { store.autoReturnMode = autoReturn }
        if let value = changes.autoReturnDelay {
            store.autoReturnDelay = value.clamped(to: TimelineStore.autoReturnDelayRange)
        }
        if let value = changes.showsOverFullScreen { store.showsOverFullScreen = value }
        if let edge { store.dockEdge = edge }
        if let value = changes.dockPosition { store.dockY = value.clamped(to: 0...1) }
        if let value = changes.expanded { store.isExpanded = value }
        if let value = changes.controlsVisible { panel?.setControlsVisible(value) }
    }

    private func rawValue<T: RawRepresentable>(
        _ type: T.Type,
        _ value: String,
        _ name: String
    ) throws -> T where T.RawValue == String {
        guard let parsed = T(rawValue: value) else {
            throw Failure(.invalidRequest, "\(name) 的值无效：\(value)。")
        }
        return parsed
    }

    // MARK: Responses

    private func success(
        _ action: DaylineAutomationAction,
        todos: [DaylineAutomationTodo] = [],
        settings: DaylineAutomationSettings? = nil,
        message: String? = nil
    ) -> DaylineAutomationResponse {
        DaylineAutomationResponse(
            ok: true,
            action: action,
            timeline: timeline(),
            todos: todos,
            settings: settings,
            message: message
        )
    }

    private func failureResponse(
        _ action: DaylineAutomationAction,
        _ message: String,
        code: DaylineAutomationErrorCode
    ) -> DaylineAutomationResponse {
        DaylineAutomationResponse(
            ok: false,
            action: action,
            timeline: timeline(),
            error: message,
            errorCode: code
        )
    }

    private func timeline() -> DaylineAutomationTimeline {
        let now = DayClock.minuteOfDay(for: Date(), dayEndMinute: store.timelineEndMinute)
        return DaylineAutomationTimeline(
            startMinute: store.timelineStartMinute,
            endMinute: store.timelineEndMinute,
            start: automationTime(store.timelineStartMinute),
            end: automationTime(store.timelineEndMinute),
            intervalMinutes: 15,
            nowMinute: now,
            now: automationTime(now),
            nextTodoID: store.currentTask(at: now)?.id
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

    // MARK: Parsing

    private func existingID(_ value: UUID?) throws -> UUID {
        guard let value else { throw Failure(.invalidRequest, "缺少有效的待办 ID。") }
        guard store.item(id: value) != nil else {
            throw Failure(.notFound, "找不到这个待办，请先 list。")
        }
        return value
    }

    private func requiredTitle(_ value: String?) throws -> String {
        guard let value else { throw Failure(.invalidRequest, "缺少 title。") }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure(.invalidRequest, "标题不能为空。") }
        return trimmed
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
            throw Failure(.invalidTime, "缺少 HH:mm 时间。")
        }
        return hour * 60 + minute
    }

    private func automationTime(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private struct Failure: Error {
        let code: DaylineAutomationErrorCode
        let message: String
        init(_ code: DaylineAutomationErrorCode, _ message: String) {
            self.code = code
            self.message = message
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
