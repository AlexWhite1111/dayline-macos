import Combine
import Foundation

@MainActor
final class TimelineStore: ObservableObject {
    static let defaultClickGuardDuration = 0.25
    static let clickGuardDurationRange = 0.0...0.6
    static let defaultAutoReturnDelay = 30.0
    static let autoReturnDelayRange = 5.0...300.0

    @Published var items: [TodoItem] = [] { didSet { saveWhenReady() } }
    @Published var fontSize: Double = 16 { didSet { saveWhenReady() } }
    @Published var titleHeightRatio = DaylineLayout.defaultTitleHeightRatio {
        didSet { saveWhenReady() }
    }
    @Published var compactTitleWidth = Double(DaylineLayout.defaultCompactTitleWidth) {
        didSet { saveWhenReady() }
    }
    @Published var panelHeightRatio: Double = 0.9 { didSet { saveWhenReady() } }
    @Published var timelineAnchorPosition = DaylineLayout.defaultTimelineAnchorPosition {
        didSet { saveWhenReady() }
    }
    @Published var nativeGlassStyle: NativeGlassStyle = .regular { didSet { saveWhenReady() } }
    @Published var timeDisplayMode: TimeDisplayMode = .absolute { didSet { saveWhenReady() } }
    @Published var pinsOnlyCurrentTask = false { didSet { saveWhenReady() } }
    @Published var clickGuardDuration = defaultClickGuardDuration { didSet { saveWhenReady() } }
    @Published var autoReturnMode: AutoReturnMode = .off { didSet { saveWhenReady() } }
    @Published var autoReturnDelay = defaultAutoReturnDelay { didSet { saveWhenReady() } }
    @Published var dockEdge: DockEdge = .left { didSet { saveWhenReady() } }
    @Published var dockY: Double = 0.52 { didSet { saveWhenReady() } }
    @Published var isExpanded = true { didSet { saveWhenReady() } }
    @Published var railOffsetY: CGFloat = 0
    @Published var timelineStartMinute = DayClock.startMinute { didSet { saveWhenReady() } }
    @Published var timelineEndMinute = DayClock.endMinute { didSet { saveWhenReady() } }
    @Published var focusMinute: Int?
    @Published var editingID: UUID?
    @Published var projectionMinute: Int?
    @Published var pillTitleLimit = DaylineLayout.defaultCompactTitleWidth
    @Published private(set) var clockDate = Date()

    private(set) var hasSavedPlacement = false
    private var isLoading = true
    private var clockTimer: Timer?
    private let stateURL: URL

    init(stateURL: URL? = nil, startsTimer: Bool = true) {
        self.stateURL = stateURL ?? Self.defaultStateURL
        restore()
        isLoading = false
        if startsTimer {
            clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) {
                [weak self] _ in
                Task { @MainActor in
                    self?.clockDate = Date()
                }
            }
        }
    }

    deinit { clockTimer?.invalidate() }

    @discardableResult
    func addTask(
        id: UUID = UUID(),
        title: String = "",
        at minute: Int? = nil
    ) -> UUID {
        guard item(id: id) == nil else { return id }
        let preferred = minute ?? DayClock.defaultTaskMinute(
            start: timelineStartMinute,
            end: timelineEndMinute
        )
        let item = TodoItem(
            id: id,
            title: title,
            minute: availableQuarter(near: preferred),
            createdAt: Date()
        )
        items.append(item)
        return item.id
    }

    func item(id: UUID) -> TodoItem? {
        items.first { $0.id == id }
    }

    func currentTask(at minute: Int) -> TodoItem? {
        let active = items.filter { !$0.isCompleted }.sorted {
            $0.minute == $1.minute ? $0.createdAt < $1.createdAt : $0.minute < $1.minute
        }
        return active.first { $0.minute >= minute } ?? active.first
    }

    func updateTitle(id: UUID, title: String) {
        mutate(id) { $0.title = title }
    }

    func finalizeTitle(id: UUID) {
        guard let value = item(id: id)?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        value.isEmpty ? delete(id: id) : updateTitle(id: id, title: value)
    }

    func commitEditing() {
        guard let editingID else { return }
        finalizeTitle(id: editingID)
        self.editingID = nil
    }

    func toggleTitleExpansion(id: UUID) {
        mutate(id) {
            guard DaylineLayout.titleOverflowsCompact(
                $0.title,
                fontSize: fontSize,
                titleHeightRatio: titleHeightRatio,
                maximumWidth: CGFloat(compactTitleWidth)
            ) else { return }
            $0.isTitleExpanded.toggle()
        }
    }

    func toggleCompleted(id: UUID) {
        mutate(id) { $0.isCompleted.toggle() }
    }

    func setCompleted(id: UUID, completed: Bool) {
        mutate(id) { $0.isCompleted = completed }
    }

    func move(id: UUID, to minute: Int) {
        let destination = availableQuarter(near: minute, excluding: id)
        mutate(id) { $0.minute = destination }
    }

    func dragDestination(near minute: Double, excluding id: UUID) -> Int {
        availableQuarter(
            near: DayClock.quarterAtOrAfter(
                minute,
                start: timelineStartMinute,
                end: timelineEndMinute
            ),
            excluding: id
        )
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func setTimelineStart(_ minute: Int) {
        setTimelineRange(
            start: min(max(0, minute), timelineEndMinute - 60),
            end: timelineEndMinute
        )
    }

    func setTimelineEnd(_ minute: Int) {
        setTimelineRange(
            start: timelineStartMinute,
            end: min(max(minute, timelineStartMinute + 60), 30 * 60)
        )
    }

    func setTimelineRange(start: Int, end: Int) {
        timelineStartMinute = min(max(start, 0), 23 * 60)
        timelineEndMinute = min(max(end, timelineStartMinute + 60), 30 * 60)
        clampItemsToRange()
    }

    func useInitialPlacement(edge: DockEdge, y: Double) {
        guard !hasSavedPlacement else { return }
        dockEdge = edge
        dockY = min(max(y, 0.08), 0.92)
        hasSavedPlacement = true
    }

    func persist() {
        let snapshot = SavedState(
            items: items,
            fontSize: fontSize,
            titleHeightRatio: titleHeightRatio,
            dockEdge: dockEdge,
            dockY: dockY,
            isExpanded: isExpanded,
            timelineStartMinute: timelineStartMinute,
            timelineEndMinute: timelineEndMinute,
            panelHeightRatio: panelHeightRatio,
            timelineAnchorPosition: timelineAnchorPosition,
            compactTitleWidth: compactTitleWidth,
            nativeGlassStyle: nativeGlassStyle,
            pinsOnlyCurrentTask: pinsOnlyCurrentTask,
            clickGuardDuration: clickGuardDuration,
            timeDisplayMode: timeDisplayMode,
            autoReturnMode: autoReturnMode,
            autoReturnDelay: autoReturnDelay
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
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
        do {
            let saved = try JSONDecoder.dayline.decode(
                SavedState.self,
                from: Data(contentsOf: stateURL)
            )
            fontSize = min(
                max(saved.fontSize, DaylineLayout.fontSizeRange.lowerBound),
                DaylineLayout.fontSizeRange.upperBound
            )
            titleHeightRatio = min(
                max(
                    saved.titleHeightRatio ?? DaylineLayout.defaultTitleHeightRatio,
                    DaylineLayout.titleHeightRatioRange.lowerBound
                ),
                DaylineLayout.titleHeightRatioRange.upperBound
            )
            compactTitleWidth = min(
                max(saved.compactTitleWidth ?? Double(DaylineLayout.defaultCompactTitleWidth),
                    DaylineLayout.compactTitleWidthRange.lowerBound),
                DaylineLayout.compactTitleWidthRange.upperBound
            )
            panelHeightRatio = min(max(saved.panelHeightRatio ?? 0.9, 0.6), 1)
            timelineAnchorPosition = min(
                max(
                    saved.timelineAnchorPosition ?? DaylineLayout.defaultTimelineAnchorPosition,
                    DaylineLayout.timelineAnchorPositionRange.lowerBound
                ),
                DaylineLayout.timelineAnchorPositionRange.upperBound
            )
            nativeGlassStyle = saved.nativeGlassStyle ?? .regular
            timeDisplayMode = saved.timeDisplayMode ?? .absolute
            pinsOnlyCurrentTask = saved.pinsOnlyCurrentTask ?? false
            clickGuardDuration = min(
                max(
                    saved.clickGuardDuration ?? Self.defaultClickGuardDuration,
                    Self.clickGuardDurationRange.lowerBound
                ),
                Self.clickGuardDurationRange.upperBound
            )
            autoReturnMode = saved.autoReturnMode
                ?? ((saved.autoReturnToCurrentTime ?? false) ? .currentTime : .off)
            autoReturnDelay = min(
                max(
                    saved.autoReturnDelay ?? Self.defaultAutoReturnDelay,
                    Self.autoReturnDelayRange.lowerBound
                ),
                Self.autoReturnDelayRange.upperBound
            )
            dockEdge = saved.dockEdge
            dockY = min(max(saved.dockY, 0.08), 0.92)
            isExpanded = saved.isExpanded
            timelineStartMinute = min(max(saved.timelineStartMinute ?? DayClock.startMinute, 0), 23 * 60)
            timelineEndMinute = min(
                max(saved.timelineEndMinute ?? DayClock.endMinute, timelineStartMinute + 60),
                30 * 60
            )
            hasSavedPlacement = true
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
            NSLog("Dayline restore failed: \(error.localizedDescription)")
        }
    }

    private func saveWhenReady() {
        if !isLoading { persist() }
    }

    private static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayline", isDirectory: true)
            .appendingPathComponent("timeline.json")
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
