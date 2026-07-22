import Combine
import Foundation

@MainActor
final class TodayStore: ObservableObject {
    @Published var items: [TodoItem] = [] { didSet { saveWhenReady() } }
    @Published var fontSize: Double = 16 { didSet { saveWhenReady() } }
    @Published var panelHeightRatio: Double = 0.9 { didSet { saveWhenReady() } }
    @Published var dockEdge: DockEdge = .left { didSet { saveWhenReady() } }
    @Published var dockY: Double = 0.52 { didSet { saveWhenReady() } }
    @Published var isExpanded = true { didSet { saveWhenReady() } }
    @Published var railOffsetY: CGFloat = 0
    @Published var timelineStartMinute = DayClock.startMinute { didSet { saveWhenReady() } }
    @Published var timelineEndMinute = DayClock.endMinute { didSet { saveWhenReady() } }

    private(set) var hasSavedPlacement = false
    private var currentDayKey = ""
    private var isLoading = true
    private var rolloverTimer: Timer?
    private let stateURL: URL

    init(stateURL: URL? = nil, startsTimer: Bool = true) {
        self.stateURL = stateURL ?? Self.defaultStateURL
        restore()
        isLoading = false
        rolloverIfNeeded()
        if startsTimer {
            rolloverTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) {
                [weak self] _ in
                Task { @MainActor in self?.rolloverIfNeeded() }
            }
        }
    }

    deinit { rolloverTimer?.invalidate() }

    @discardableResult
    func addTask(at minute: Int? = nil) -> UUID {
        rolloverIfNeeded()
        let preferred = minute ?? DayClock.defaultTaskMinute(
            start: timelineStartMinute,
            end: timelineEndMinute
        )
        let item = TodoItem(
            id: UUID(),
            title: "",
            minute: availableQuarter(near: preferred),
            createdAt: Date()
        )
        items.append(item)
        return item.id
    }

    func item(id: UUID) -> TodoItem? {
        items.first { $0.id == id }
    }

    func updateTitle(id: UUID, title: String) {
        mutate(id) { $0.title = title }
    }

    func finalizeTitle(id: UUID) {
        guard let value = item(id: id)?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        value.isEmpty ? delete(id: id) : updateTitle(id: id, title: value)
    }

    func toggleTitleExpansion(id: UUID) {
        mutate(id) {
            guard DaylineLayout.titleOverflowsCompact($0.title, fontSize: fontSize) else { return }
            $0.isTitleExpanded.toggle()
        }
    }

    func toggleCompleted(id: UUID) {
        mutate(id) { $0.isCompleted.toggle() }
    }

    func move(id: UUID, to minute: Int) {
        let destination = availableQuarter(near: minute, excluding: id)
        mutate(id) { $0.minute = destination }
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func setTimelineStart(_ minute: Int) {
        timelineStartMinute = min(max(0, minute), timelineEndMinute - 60)
        clampItemsToRange()
    }

    func setTimelineEnd(_ minute: Int) {
        let end = min(max(minute, timelineStartMinute + 60), 30 * 60)
        currentDayKey = DayClock.dayKey(dayEndMinute: end)
        timelineEndMinute = end
        clampItemsToRange()
    }

    func useInitialPlacement(edge: DockEdge, y: Double) {
        guard !hasSavedPlacement else { return }
        dockEdge = edge
        dockY = min(max(y, 0.08), 0.92)
        hasSavedPlacement = true
    }

    func rolloverIfNeeded(now: Date = Date()) {
        let key = DayClock.dayKey(for: now, dayEndMinute: timelineEndMinute)
        guard key != currentDayKey else { return }
        currentDayKey = key
        items = []
    }

    func persist() {
        let snapshot = SavedState(
            dayKey: currentDayKey,
            items: items,
            fontSize: fontSize,
            dockEdge: dockEdge,
            dockY: dockY,
            isExpanded: isExpanded,
            timelineStartMinute: timelineStartMinute,
            timelineEndMinute: timelineEndMinute,
            panelHeightRatio: panelHeightRatio
        )
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder.dayline.encode(snapshot).write(to: stateURL, options: .atomic)
        } catch {
            NSLog("Dayline save failed: \(error.localizedDescription)")
        }
    }

    private func mutate(_ id: UUID, _ change: (inout TodoItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func clampItemsToRange() {
        items = items.map { item in
            var copy = item
            copy.minute = DayClock.quarterAtOrAfter(
                item.minute,
                start: timelineStartMinute,
                end: timelineEndMinute
            )
            return copy
        }
    }

    private func availableQuarter(near minute: Int, excluding id: UUID? = nil) -> Int {
        let target = DayClock.quarterAtOrAfter(
            minute,
            start: timelineStartMinute,
            end: timelineEndMinute
        )
        let occupied = Set(items.compactMap { item in
            item.id == id ? nil : item.minute
        })
        for candidate in stride(from: target, through: timelineEndMinute - 15, by: 15)
        where !occupied.contains(candidate) {
            return candidate
        }
        if target > timelineStartMinute {
            for candidate in stride(from: target - 15, through: timelineStartMinute, by: -15)
            where !occupied.contains(candidate) {
                return candidate
            }
        }
        return target
    }

    private func restore() {
        do {
            let saved = try JSONDecoder.dayline.decode(
                SavedState.self,
                from: Data(contentsOf: stateURL)
            )
            fontSize = min(max(saved.fontSize, 13), 19)
            panelHeightRatio = min(max(saved.panelHeightRatio ?? 0.9, 0.6), 1)
            dockEdge = saved.dockEdge
            dockY = min(max(saved.dockY, 0.08), 0.92)
            isExpanded = saved.isExpanded
            timelineStartMinute = min(max(saved.timelineStartMinute ?? DayClock.startMinute, 0), 23 * 60)
            timelineEndMinute = min(
                max(saved.timelineEndMinute ?? DayClock.endMinute, timelineStartMinute + 60),
                30 * 60
            )
            hasSavedPlacement = true
            currentDayKey = DayClock.dayKey(dayEndMinute: timelineEndMinute)
            guard saved.dayKey == currentDayKey else { return }
            items = saved.items.map { item in
                TodoItem(
                    id: item.id,
                    title: item.title,
                    minute: DayClock.quarterAtOrAfter(
                        item.minute,
                        start: timelineStartMinute,
                        end: timelineEndMinute
                    ),
                    isTitleExpanded: item.isTitleExpanded,
                    isCompleted: item.isCompleted,
                    createdAt: item.createdAt
                )
            }
        } catch {
            currentDayKey = DayClock.dayKey(dayEndMinute: timelineEndMinute)
        }
    }

    private func saveWhenReady() {
        if !isLoading { persist() }
    }

    private static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayline", isDirectory: true)
            .appendingPathComponent("today.json")
    }
}

private extension JSONEncoder {
    static var dayline: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }
}

private extension JSONDecoder {
    static var dayline: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }
}
