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
    @Published var panelHeightRatio = Double(DaylineLayout.defaultExpandedPanelHeightRatio) {
        didSet { saveWhenReady() }
    }
    @Published var timelineAnchorPosition = DaylineLayout.defaultTimelineAnchorPosition {
        didSet { saveWhenReady() }
    }
    @Published var nativeGlassStyle: NativeGlassStyle = .regular { didSet { saveWhenReady() } }
    @Published var timeDisplayMode: TimeDisplayMode = .absolute { didSet { saveWhenReady() } }
    @Published var clockFormat: ClockFormat = .system { didSet { saveWhenReady() } }
    @Published var showsOverFullScreen = false { didSet { saveWhenReady() } }
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
    @Published var editingID: UUID? {
        didSet {
            guard editingID != oldValue else { return }
            editingOriginalTitle = editingID.flatMap { item(id: $0)?.title }
        }
    }
    /// The last deleted titled task, offered for undo for a few seconds.
    @Published private(set) var recentlyDeleted: TodoItem?
    @Published var projectionMinute: Int?
    @Published var pillTitleLimit = DaylineLayout.defaultCompactTitleWidth
    @Published private(set) var clockDate = Date()

    private(set) var hasSavedPlacement = false
    private var savesChanges = false
    private var pendingSave: DispatchWorkItem?
    private var editingOriginalTitle: String?
    private var undoExpiry: DispatchWorkItem?
    private var clockTimer: Timer?
    private let stateURL: URL

    init(stateURL: URL? = nil, startsTimer: Bool = true) {
        self.stateURL = stateURL ?? Self.defaultStateURL
        restore()
        savesChanges = true
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
        let preferred = minute ?? DayClock.defaultTaskMinute(
            start: timelineStartMinute,
            end: timelineEndMinute
        )
        let item = TodoItem(
            id: id,
            title: title,
            minute: availableQuarter(near: preferred) ?? quarter(atOrAfter: preferred),
            createdAt: Date()
        )
        items.append(item)
        return item.id
    }

    /// Callers check this before `addTask`; every task owns a distinct quarter.
    var hasFreeSlot: Bool { items.count < (timelineEndMinute - timelineStartMinute) / 15 }

    func item(id: UUID) -> TodoItem? {
        items.first { $0.id == id }
    }

    var itemsByDeadline: [TodoItem] {
        items.sorted {
            $0.minute == $1.minute ? $0.createdAt < $1.createdAt : $0.minute < $1.minute
        }
    }

    func currentTask(at minute: Int) -> TodoItem? {
        let active = itemsByDeadline.filter { !$0.isCompleted }
        return active.first { $0.minute >= minute } ?? active.first
    }

    var currentMinute: Int {
        DayClock.minuteOfDay(for: clockDate, dayEndMinute: timelineEndMinute)
    }

    var nextTask: TodoItem? { currentTask(at: currentMinute) }

    var usesTwelveHourClock: Bool {
        switch clockFormat {
        case .twelveHour: true
        case .twentyFourHour: false
        case .system:
            DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent)?
                .contains("a") ?? false
        }
    }

    func minuteFraction(at date: Date) -> Double {
        DayClock.minuteOfDayFraction(for: date, dayEndMinute: timelineEndMinute)
    }

    func quarter(atOrAfter minute: Int) -> Int {
        DayClock.quarterAtOrAfter(minute, start: timelineStartMinute, end: timelineEndMinute)
    }

    func quarter(atOrAfter minute: Double) -> Int {
        DayClock.quarterAtOrAfter(minute, start: timelineStartMinute, end: timelineEndMinute)
    }

    func clampToRange(_ minute: Double) -> Double {
        DayClock.clamp(minute, start: timelineStartMinute, end: timelineEndMinute)
    }

    func updateTitle(id: UUID, title: String) {
        mutate(id) { $0.title = title }
    }

    /// Trims the edited title. An emptied task is deleted; undo restores its old title.
    func commitEditing() {
        guard let id = editingID,
              let value = item(id: id)?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        if value.isEmpty {
            updateTitle(id: id, title: editingOriginalTitle ?? "")
            delete(id: id)
        } else {
            updateTitle(id: id, title: value)
        }
        editingID = nil
    }

    /// Esc: restore the title from before editing. A new untitled task is removed.
    func cancelEditing() {
        guard let id = editingID else { return }
        updateTitle(id: id, title: editingOriginalTitle ?? "")
        commitEditing()
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
        guard let destination = availableQuarter(near: minute, excluding: id) else { return }
        mutate(id) { $0.minute = destination }
    }

    /// Drag previews snap to the nearest quarter; new tasks still round up.
    func dragDestination(near minute: Double, excluding id: UUID) -> Int {
        let nearest = DayClock.clamp(
            Int((minute / 15).rounded()) * 15,
            start: timelineStartMinute,
            end: timelineEndMinute
        )
        return availableQuarter(near: nearest, excluding: id) ?? nearest
    }

    func delete(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        guard !removed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        recentlyDeleted = removed
        undoExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in self?.recentlyDeleted = nil }
        undoExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: expiry)
    }

    func undoDelete() {
        guard var item = recentlyDeleted,
              let minute = availableQuarter(near: item.minute)
        else { return }
        undoExpiry?.cancel()
        recentlyDeleted = nil
        item.minute = minute
        items.append(item)
    }

    @discardableResult
    func setTimelineStart(_ minute: Int) -> Bool {
        setTimelineRange(
            start: min(max(0, minute), timelineEndMinute - 60),
            end: timelineEndMinute
        )
    }

    @discardableResult
    func setTimelineEnd(_ minute: Int) -> Bool {
        setTimelineRange(
            start: timelineStartMinute,
            end: min(max(minute, timelineStartMinute + 60), 30 * 60)
        )
    }

    /// Refuses a range with fewer quarters than tasks.
    @discardableResult
    func setTimelineRange(start: Int, end: Int) -> Bool {
        let start = min(max(start, 0), 23 * 60)
        let end = min(max(end, start + 60), 30 * 60)
        guard items.count <= (end - start) / 15 else { return false }
        timelineStartMinute = start
        timelineEndMinute = end
        clampItemsToRange()
        return true
    }

    func useInitialPlacement(edge: DockEdge, y: Double) {
        guard !hasSavedPlacement else { return }
        dockEdge = edge
        dockY = min(max(y, 0.08), 0.92)
        hasSavedPlacement = true
    }

    /// Writes immediately. Property changes call `saveWhenReady`, which coalesces bursts.
    func persist() {
        pendingSave?.cancel()
        pendingSave = nil
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
            clockFormat: clockFormat,
            showsOverFullScreen: showsOverFullScreen,
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

    /// In-range tasks keep their slots; the farthest outliers claim edge slots first,
    /// so tasks pushed in from outside keep their relative order without colliding.
    private func clampItemsToRange() {
        let lastSlot = timelineEndMinute - 15
        func overflow(_ minute: Int) -> Int {
            max(timelineStartMinute - minute, minute - lastSlot, 0)
        }
        let placementOrder = items.sorted {
            let (a, b) = (overflow($0.minute), overflow($1.minute))
            return (a == 0) != (b == 0) ? a == 0 : a > b
        }
        var occupied = Set<Int>()
        var placed: [UUID: Int] = [:]
        for item in placementOrder {
            let minute = availableQuarter(near: item.minute, occupied: occupied) ?? item.minute
            occupied.insert(minute)
            placed[item.id] = minute
        }
        items = items.map { item in
            var copy = item
            copy.minute = placed[item.id] ?? item.minute
            return copy
        }
    }

    private func availableQuarter(near minute: Int, excluding id: UUID? = nil) -> Int? {
        availableQuarter(
            near: minute,
            occupied: Set(items.compactMap { $0.id == id ? nil : $0.minute })
        )
    }

    private func availableQuarter(near minute: Int, occupied: Set<Int>) -> Int? {
        let target = quarter(atOrAfter: minute)
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
        return nil
    }

    private func restore() {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
        do {
            let saved = try JSONDecoder.dayline.decode(
                SavedState.self,
                from: Data(contentsOf: stateURL)
            )
            // Absent fields keep the property defaults declared above.
            fontSize = saved.fontSize
            titleHeightRatio = saved.titleHeightRatio ?? titleHeightRatio
            compactTitleWidth = saved.compactTitleWidth ?? compactTitleWidth
            panelHeightRatio = saved.panelHeightRatio ?? panelHeightRatio
            timelineAnchorPosition = saved.timelineAnchorPosition ?? timelineAnchorPosition
            nativeGlassStyle = saved.nativeGlassStyle ?? nativeGlassStyle
            timeDisplayMode = saved.timeDisplayMode ?? timeDisplayMode
            clockFormat = saved.clockFormat ?? clockFormat
            showsOverFullScreen = saved.showsOverFullScreen ?? showsOverFullScreen
            pinsOnlyCurrentTask = saved.pinsOnlyCurrentTask ?? pinsOnlyCurrentTask
            clickGuardDuration = saved.clickGuardDuration ?? clickGuardDuration
            autoReturnMode = saved.autoReturnMode
                ?? ((saved.autoReturnToCurrentTime ?? false) ? .currentTime : .off)
            autoReturnDelay = saved.autoReturnDelay ?? autoReturnDelay
            dockEdge = saved.dockEdge
            dockY = saved.dockY
            isExpanded = saved.isExpanded
            timelineStartMinute = saved.timelineStartMinute ?? timelineStartMinute
            timelineEndMinute = saved.timelineEndMinute ?? timelineEndMinute
            hasSavedPlacement = true
            items = saved.items
            clampItemsToRange()
        } catch {
            NSLog("Dayline restore failed: \(error.localizedDescription)")
        }
    }

    private func saveWhenReady() {
        guard savesChanges else { return }
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in self?.persist() }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: save)
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
