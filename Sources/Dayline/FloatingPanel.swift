import AppKit
import Combine
import SwiftUI

final class FloatingPanel: NSPanel {
    var allowsKeyFocus = true

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}

private final class TodoHostingView<Content: View>: NSHostingView<Content> {
    override var needsPanelToBecomeKey: Bool {
        (window as? FloatingPanel)?.allowsKeyFocus == true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.insetBy(
            dx: DaylineLayout.pillWindowPadding,
            dy: DaylineLayout.pillWindowPadding
        ).contains(point) ? super.hitTest(point) : nil
    }
}

@MainActor
final class FloatingPanelController: NSWindowController {
    private struct TodoDragSession {
        let id: UUID
        let panelOrigin: NSPoint
        let pointerY: CGFloat
        let startMinute: Int
        var previewMinute: Int
    }

    private struct TaskStateInput: Equatable {
        let id: UUID
        let minute: Int
        let isCompleted: Bool
    }

    private let store: TimelineStore
    private let panel: FloatingPanel
    private let axisPanel: FloatingPanel
    private var todoPanels: [UUID: FloatingPanel] = [:]
    private var dragSession: TodoDragSession?
    private var timelineProjection: TimelineProjection?
    private weak var cachedTimelineScrollView: NSScrollView?
    private var subscriptions = Set<AnyCancellable>()
    private(set) var controlsAreVisible = true
    private var isSettingsPresented = false
    private var dockedScreen: NSScreen?
    private var pendingOverlayUpdate: Bool?
    private var autoReturnWorkItem: DispatchWorkItem?
    private(set) var autoReturnIsActive = false
    /// Set by "return to now"; first-todo follow tracks now until the next interaction.
    private var followsNow = false
    /// The pending scroll of the latest `reveal`; newer reveals and user input cancel it.
    private var revealWorkItem: DispatchWorkItem?

    private let collapsedSize = NSSize(width: 48, height: 44)
    private let edgeInset: CGFloat = 2
    private let verticalInset: CGFloat = 12

    private static func makePanel(size: NSSize = NSSize(width: 1, height: 1)) -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .floating
        panel.collectionBehavior = spacesBehavior(showsOverFullScreen: false)
        return panel
    }

    /// Auxiliary panels may appear in another app's full-screen Space.
    private static func spacesBehavior(showsOverFullScreen: Bool) -> NSWindow.CollectionBehavior {
        [.canJoinAllSpaces, showsOverFullScreen ? .fullScreenAuxiliary : .fullScreenNone]
    }

    init(store: TimelineStore) {
        self.store = store
        panel = Self.makePanel(
            size: NSSize(
                width: DaylineLayout.compactPanelWidth(for: CGFloat(store.compactTitleWidth)),
                height: 680
            )
        )
        axisPanel = Self.makePanel(
            size: NSSize(width: DaylineLayout.timelineHitWidth, height: 1)
        )
        super.init(window: panel)

        resolveFirstPlacementIfNeeded()
        configureAxisPanel()

        let hostingView = NSHostingView(
            rootView: RootView(
                store: store,
                onHandleClick: { [weak self] in self?.toggleExpanded() },
                onHandleDragChanged: { [weak self] point in self?.trackHandle(at: point) },
                onHandleDragEnded: { [weak self] point in self?.snap(to: point) },
                onSettingsPresented: { [weak self] in self?.setSettingsPresented($0) },
                onTimelineProjectionChanged: { [weak self] projection in
                    guard let self else { return }
                    let sizeChanged = self.timelineProjection?.fontSize != projection.fontSize
                    self.timelineProjection = projection
                    if sizeChanged { self.updateAxisFrame() }
                    self.updateOverlayPositions()
                },
                onTimelineScrollActivity: { [weak self] in
                    self?.registerTimelineInteraction()
                },
                onReturnToCurrentTime: { [weak self] in
                    self?.returnToCurrentTime()
                }
            )
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        observeLayoutInputs()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        refreshWindowLevels()
        scheduleOverlayUpdate(reconcile: true)
    }

    private func configureAxisPanel() {
        let view = AxisRecallView()
        view.autoresizingMask = [.width, .height]
        view.onSingleClick = { [weak self] in self?.togglePinnedWindowMode() }
        view.onDoubleClick = { [weak self] in self?.toggleControls() }
        view.onScroll = { [weak self] event in self?.scrollTimeline(with: event) }
        view.clickGuardDuration = { [weak self] in
            self?.store.clickGuardDuration ?? TimelineStore.defaultClickGuardDuration
        }
        axisPanel.contentView = view
        axisPanel.isMovable = false
    }

    private func resolveFirstPlacementIfNeeded() {
        let point = NSEvent.mouseLocation
        let screen = store.hasSavedPlacement
            ? (panel.screen ?? NSScreen.main ?? NSScreen.screens[0])
            : (screen(containing: point) ?? NSScreen.main ?? NSScreen.screens[0])
        dockedScreen = screen
        guard !store.hasSavedPlacement else { return }
        store.useInitialPlacement(
            edge: DockResolver.edge(for: point.x, screenMidX: screen.visibleFrame.midX),
            y: 0.52
        )
    }

    private func observeLayoutInputs() {
        Publishers.CombineLatest(store.$panelHeightRatio, store.$compactTitleWidth)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyFrame() }
            .store(in: &subscriptions)

        // Dock and expansion may change from the UI or from automation.
        Publishers.CombineLatest3(store.$dockEdge, store.$dockY, store.$isExpanded)
            .dropFirst()
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFrame()
                self?.refreshWindowLevels()
            }
            .store(in: &subscriptions)

        store.$items
            .map { $0.map(\.id) }
            .removeDuplicates()
            .sink { [weak self] _ in self?.scheduleOverlayUpdate(reconcile: true) }
            .store(in: &subscriptions)

        let taskStates = store.$items
            .map { items in
                items.map {
                    TaskStateInput(id: $0.id, minute: $0.minute, isCompleted: $0.isCompleted)
                }
            }
            .removeDuplicates()
        let clockMinute = Publishers.CombineLatest(store.$clockDate, store.$timelineEndMinute)
            .map { DayClock.minuteOfDay(for: $0, dayEndMinute: $1) }
            .removeDuplicates()
        Publishers.CombineLatest4(
            store.$pinsOnlyCurrentTask,
            store.$isExpanded,
            store.$editingID,
            Publishers.CombineLatest(taskStates, clockMinute)
        )
            .sink { [weak self] _, _, _, _ in
                self?.scheduleOverlayUpdate(reconcile: false)
            }
            .store(in: &subscriptions)

        Publishers.CombineLatest(
            store.$autoReturnMode,
            store.$autoReturnDelay
        )
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] mode, delay in
                self?.configureAutoReturn(mode: mode, delay: delay)
            }
            .store(in: &subscriptions)

        store.$clockDate
            .dropFirst()
            .sink { [weak self] date in
                guard let self,
                      self.autoReturnIsActive,
                      self.store.autoReturnMode != .off
                else { return }
                self.scrollAutoReturnTargetToAnchor(at: date)
            }
            .store(in: &subscriptions)

        taskStates
            .dropFirst()
            .sink { [weak self] _ in
                guard let self,
                      self.autoReturnIsActive,
                      self.store.autoReturnMode == .firstTodo
                else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.autoReturnIsActive,
                          self.store.autoReturnMode == .firstTodo
                    else { return }
                    self.scrollAutoReturnTargetToAnchor()
                }
            }
            .store(in: &subscriptions)

        store.$showsOverFullScreen
            .removeDuplicates()
            .sink { [weak self] shows in
                guard let self else { return }
                let behavior = Self.spacesBehavior(showsOverFullScreen: shows)
                ([self.panel, self.axisPanel] + Array(self.todoPanels.values))
                    .forEach { $0.collectionBehavior = behavior }
                self.refreshWindowLevels()
            }
            .store(in: &subscriptions)

        store.$editingID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.registerTimelineInteraction() }
            .store(in: &subscriptions)

        store.$timelineAnchorPosition
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.autoReturnIsActive else { return }
                DispatchQueue.main.async {
                    self.scrollAutoReturnTargetToAnchor()
                }
            }
            .store(in: &subscriptions)
    }

    private func toggleExpanded() {
        controlsAreVisible = true
        store.isExpanded.toggle()
        applyFrame()
        refreshWindowLevels()
    }

    private func toggleControls() {
        guard store.isExpanded else { return }
        controlsAreVisible.toggle()
        movePanelForControls()
    }

    private func togglePinnedWindowMode() {
        guard store.isExpanded else { return }
        store.pinsOnlyCurrentTask.toggle()
        refreshWindowLevels()
    }

    private func refreshWindowLevels() {
        let currentID = currentTaskID
        apply(
            isSettingsPresented ? .popUpMenu : (onlyCurrent ? .normal : .floating),
            to: panel,
            showingIfNeeded: true
        )
        for (id, taskPanel) in todoPanels where taskPanel.isVisible {
            apply(taskLevel(for: id, currentID: currentID), to: taskPanel)
        }
        if isSettingsPresented {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.panel.childWindows?
                    .filter(\.isVisible)
                    .forEach { self.apply(.popUpMenu, to: $0) }
            }
        }
        if store.isExpanded {
            axisPanel.orderFrontRegardless()
        } else {
            axisPanel.orderOut(nil)
        }
    }

    private func setSettingsPresented(_ visible: Bool) {
        isSettingsPresented = visible
        refreshWindowLevels()
    }

    private var onlyCurrent: Bool {
        store.pinsOnlyCurrentTask && store.isExpanded
    }

    private var currentTaskID: UUID? { store.nextTask?.id }

    private func taskLevel(for id: UUID, currentID: UUID?) -> NSWindow.Level {
        guard onlyCurrent else { return .floating }
        return id == currentID || id == store.editingID || id == dragSession?.id
            ? .floating
            : .normal
    }

    @discardableResult
    private func apply(
        _ level: NSWindow.Level,
        to window: NSWindow,
        showingIfNeeded: Bool = false
    ) -> Bool {
        let levelChanged = window.level != level
        if levelChanged { window.level = level }
        guard levelChanged || (showingIfNeeded && !window.isVisible) else { return false }
        if level == .normal { window.orderBack(nil) }
        else { window.orderFrontRegardless() }
        return true
    }

    private func scheduleOverlayUpdate(reconcile: Bool) {
        if let pendingOverlayUpdate {
            self.pendingOverlayUpdate = pendingOverlayUpdate || reconcile
            return
        }
        pendingOverlayUpdate = reconcile
        DispatchQueue.main.async { [weak self] in
            guard let self, let shouldReconcile = self.pendingOverlayUpdate else { return }
            self.pendingOverlayUpdate = nil
            if shouldReconcile {
                self.reconcileOverlays()
            } else {
                self.updateOverlayPositions()
                self.refreshWindowLevels()
                self.refreshTaskPanelKeyFocus()
            }
        }
    }

    private func reconcileOverlays() {
        guard store.isExpanded, panel.isVisible else {
            axisPanel.orderOut(nil)
            todoPanels.values.forEach { $0.orderOut(nil) }
            timelineProjection = nil
            dragSession = nil
            if store.projectionMinute != nil { store.projectionMinute = nil }
            return
        }

        let itemIDs = Set(store.items.map(\.id))
        if let session = dragSession, !itemIDs.contains(session.id) {
            dragSession = nil
            store.projectionMinute = nil
            registerTimelineInteraction()
        }
        for id in todoPanels.keys.filter({ !itemIDs.contains($0) }) {
            todoPanels.removeValue(forKey: id)?.orderOut(nil)
        }

        for item in store.items {
            _ = todoPanel(for: item)
            resizeTodoPanel(id: item.id)
        }

        updateOverlayPositions()
        updateAxisFrame()
        refreshWindowLevels()
        refreshTaskPanelKeyFocus()
    }

    private func updateOverlayPositions() {
        guard store.isExpanded, panel.isVisible else { return }
        let timelineFrame = FloatingItemGeometry.timelineFrame(
            in: panel.frame,
            edge: store.dockEdge
        )
        let currentID = currentTaskID
        var reorderedTask = false
        for item in store.items {
            guard let taskPanel = todoPanels[item.id] else { continue }
            guard dragSession?.id != item.id else { continue }
            let centerY = projectedTimelineCenterY(
                for: item.minute,
                viewportHeight: timelineFrame.height
            )
            let opacity = DaylineLayout.timelineEdgeOpacity(
                centerY: centerY,
                viewportHeight: timelineFrame.height,
                fontSize: timelineProjection?.fontSize ?? store.fontSize
            )
            guard opacity > 0, taskPanel.frame.width > 1 else {
                taskPanel.orderOut(nil)
                continue
            }
            let origin = FloatingItemGeometry.taskFrame(
                in: panel.frame,
                edge: store.dockEdge,
                centerY: centerY,
                taskSize: taskPanel.frame.size
            ).origin
            if taskPanel.frame.origin != origin { taskPanel.setFrameOrigin(origin) }
            if taskPanel.alphaValue != opacity { taskPanel.alphaValue = opacity }
            reorderedTask = apply(
                taskLevel(for: item.id, currentID: currentID),
                to: taskPanel,
                showingIfNeeded: true
            ) || reorderedTask
        }
        if reorderedTask { axisPanel.orderFrontRegardless() }
    }

    private func updateAxisFrame() {
        axisPanel.setFrame(
            FloatingItemGeometry.axisHitFrame(
                in: panel.frame,
                edge: store.dockEdge,
                edgeClearance: DaylineLayout.timelineFadeDistance(
                    for: timelineProjection?.fontSize ?? store.fontSize
                )
                    + DaylineLayout.currentTimeButtonHitSize / 2
            ),
            display: true
        )
    }

    private func todoPanel(for item: TodoItem) -> FloatingPanel {
        let id = item.id
        if let panel = todoPanels[id] { return panel }

        let todoPanel = Self.makePanel()
        todoPanel.allowsKeyFocus = false
        todoPanel.hasShadow = true
        todoPanel.collectionBehavior = Self.spacesBehavior(
            showsOverFullScreen: store.showsOverFullScreen
        )
        let hostingView = TodoHostingView(
            rootView: TodoPillView(
                store: store,
                item: item,
                onDragBegan: { [weak self] in self?.beginDragging(id, initialTranslation: $0) },
                onDragChanged: { [weak self] in self?.drag(id) },
                onDragEnded: { [weak self] in self?.endDragging(id) },
                onSizeChanged: { [weak self] in
                    DispatchQueue.main.async { self?.resizeTodoPanel(id: id) }
                }
            )
            .padding(DaylineLayout.pillWindowPadding)
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        todoPanel.contentView = hostingView
        todoPanels[id] = todoPanel
        return todoPanel
    }

    private func resizeTodoPanel(id: UUID) {
        guard dragSession?.id != id else { return }
        guard let item = store.item(id: id), let taskPanel = todoPanels[id] else { return }
        taskPanel.contentView?.layoutSubtreeIfNeeded()
        let size = taskPanel.contentView?.fittingSize ?? .zero
        guard size.width > 1, size.height > 1, taskPanel.frame.size != size else { return }
        let timelineFrame = FloatingItemGeometry.timelineFrame(
            in: panel.frame,
            edge: store.dockEdge
        )
        let frame = FloatingItemGeometry.taskFrame(
            in: panel.frame,
            edge: store.dockEdge,
            centerY: projectedTimelineCenterY(
                for: item.minute,
                viewportHeight: timelineFrame.height
            ),
            taskSize: size
        )
        taskPanel.setFrame(frame, display: true)
        taskPanel.invalidateShadow()
    }

    private func projectedTimelineCenterY(
        for minute: Int,
        viewportHeight: CGFloat
    ) -> CGFloat {
        (timelineProjection ?? store.unmeasuredProjection(viewportHeight: viewportHeight))
            .centerY(for: minute)
    }

    private func beginDragging(_ id: UUID, initialTranslation: CGFloat) {
        guard let panel = todoPanels[id], let item = store.item(id: id) else { return }
        registerTimelineInteraction()
        if store.editingID != id { store.commitEditing() }
        dragSession = TodoDragSession(
            id: id,
            panelOrigin: panel.frame.origin,
            pointerY: NSEvent.mouseLocation.y + initialTranslation,
            startMinute: item.minute,
            previewMinute: item.minute
        )
        panel.level = .floating
        panel.orderFrontRegardless()
    }

    private func refreshTaskPanelKeyFocus() {
        let editingID = store.editingID
        for (id, taskPanel) in todoPanels {
            taskPanel.allowsKeyFocus = id == editingID
        }

        if let editingID, let editingPanel = todoPanels[editingID] {
            if NSApp.isActive, !editingPanel.isKeyWindow { editingPanel.makeKey() }
        } else if NSApp.isActive, todoPanels.values.contains(where: \.isKeyWindow) {
            panel.makeKey()
        }
    }

    private func drag(_ id: UUID) -> Int? {
        guard var session = dragSession, session.id == id, let panel = todoPanels[id] else {
            return nil
        }
        let pointerY = NSEvent.mouseLocation.y
        let translation = session.pointerY - pointerY
        let minute = store.dragDestination(
            near: Double(session.startMinute)
                + Double(translation / DaylineLayout.slotHeight(for: store.fontSize)) * 15,
            excluding: id
        )
        panel.setFrameOrigin(
            NSPoint(
                x: session.panelOrigin.x,
                y: session.panelOrigin.y + pointerY - session.pointerY
            )
        )
        let timelineFrame = FloatingItemGeometry.timelineFrame(
            in: self.panel.frame,
            edge: store.dockEdge
        )
        panel.alphaValue = DaylineLayout.timelineEdgeOpacity(
            centerY: timelineFrame.maxY - panel.frame.midY,
            viewportHeight: timelineFrame.height,
            fontSize: store.fontSize
        )
        if session.previewMinute != minute {
            session.previewMinute = minute
            dragSession = session
        }
        return minute
    }

    private func endDragging(_ id: UUID) {
        guard let session = dragSession, session.id == id else { return }
        store.move(id: id, to: session.previewMinute)
        dragSession = nil
        registerTimelineInteraction()
        resizeTodoPanel(id: id)
        updateOverlayPositions()
        refreshWindowLevels()
    }

    private func scrollTimeline(with event: NSEvent) {
        registerTimelineInteraction()
        timelineScrollView()?.scrollWheel(with: event)
    }

    private func configureAutoReturn(mode: AutoReturnMode, delay: TimeInterval) {
        autoReturnWorkItem?.cancel()
        autoReturnWorkItem = nil
        autoReturnIsActive = false
        guard mode != .off else { return }
        scheduleAutoReturn(delay: delay)
    }

    /// Restarts the inactivity countdown; editing keeps it paused until it ends.
    private func registerTimelineInteraction() {
        followsNow = false
        revealWorkItem?.cancel()
        revealWorkItem = nil
        guard store.autoReturnMode != .off else { return }
        autoReturnIsActive = false
        scheduleAutoReturn()
    }

    private func scheduleAutoReturn(delay requestedDelay: TimeInterval? = nil) {
        autoReturnWorkItem?.cancel()
        let delay = requestedDelay ?? store.autoReturnDelay
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.store.autoReturnMode != .off else { return }
            self.autoReturnWorkItem = nil
            guard self.dragSession == nil, self.store.editingID == nil else { return }
            self.autoReturnIsActive = true
            self.scrollAutoReturnTargetToAnchor()
        }
        autoReturnWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func returnToCurrentTime() {
        registerTimelineInteraction()
        followsNow = true
        scrollToAnchor(store.clampToRange(store.minuteFraction(at: Date())))
    }

    private func scrollAutoReturnTargetToAnchor(at date: Date? = nil) {
        guard store.editingID == nil,
              let minute = autoReturnTargetMinute(at: date ?? store.clockDate) else { return }
        scrollToAnchor(minute)
    }

    private func scrollToAnchor(_ minute: Double) {
        guard store.isExpanded,
              dragSession == nil,
              let timelineProjection,
              let scrollView = timelineScrollView()
        else { return }

        Self.scrollToAnchor(
            minute,
            in: scrollView,
            projection: timelineProjection,
            viewportHeight: FloatingItemGeometry.timelineFrame(
                in: panel.frame,
                edge: store.dockEdge
            ).height,
            anchorPosition: store.timelineAnchorPosition
        )
    }

    static func scrollToAnchor(
        _ minute: Double,
        in scrollView: NSScrollView,
        projection: TimelineProjection,
        viewportHeight: CGFloat,
        anchorPosition: Double
    ) {
        let targetCenterY = DaylineLayout.timelineAnchorCenterY(
            viewportHeight: viewportHeight,
            fontSize: projection.fontSize,
            position: anchorPosition
        )
        let deltaY = projection.centerY(for: minute) - targetCenterY
        guard abs(deltaY) > 0.01 else { return }

        let clipView = scrollView.contentView
        let target = NSPoint(
            x: clipView.bounds.origin.x,
            y: clipView.bounds.origin.y + deltaY
        )
        clipView.scroll(to: target)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func timelineScrollView() -> NSScrollView? {
        if cachedTimelineScrollView == nil {
            cachedTimelineScrollView = panel.contentView?.firstDescendant(of: NSScrollView.self)
        }
        return cachedTimelineScrollView
    }

    func autoReturnTargetMinute(at date: Date) -> Double? {
        let minute = store.minuteFraction(at: date)
        let now = store.clampToRange(minute)
        switch store.autoReturnMode {
        case .off: return nil
        case .currentTime: return now
        case .firstTodo:
            if followsNow { return now }
            return store.currentTask(at: Int(minute)).map { Double($0.minute) } ?? now
        }
    }

    private func snap(to pointer: NSPoint) {
        let screen = screen(containing: pointer) ?? bestScreen()
        dockedScreen = screen
        controlsAreVisible = true
        let visible = screen.visibleFrame
        store.dockEdge = DockResolver.edge(for: pointer.x, screenMidX: visible.midX)
        let handleY = clampedHandleY(pointer.y, in: visible, expanded: store.isExpanded)
        store.dockY = (handleY - visible.minY) / visible.height
        applyFrame(on: screen)
    }

    private func trackHandle(at point: NSPoint) {
        let screen = screen(containing: point) ?? bestScreen()
        dockedScreen = screen
        let placement = verticalPlacement(
            for: point.y,
            in: screen.visibleFrame,
            height: panel.frame.height,
            expanded: store.isExpanded
        )
        store.railOffsetY = placement.railOffset
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: placement.frameY))
        updateOverlayPositions()
        updateAxisFrame()
    }

    private func applyFrame(on forcedScreen: NSScreen? = nil) {
        let screen = forcedScreen ?? bestScreen()
        dockedScreen = screen
        let visible = screen.visibleFrame
        let contentWidth = DaylineLayout.compactPanelWidth(
            for: CGFloat(store.compactTitleWidth)
        )
        let titleLimit = max(
            CGFloat(store.compactTitleWidth),
            visible.width - edgeInset * 2
                - (DaylineLayout.compactPanelWidth - DaylineLayout.defaultCompactTitleWidth)
        )
        if store.pillTitleLimit != titleLimit { store.pillTitleLimit = titleLimit }
        let width = store.isExpanded ? contentWidth : collapsedSize.width
        let height = store.isExpanded
            ? DaylineLayout.expandedPanelHeight(
                availableHeight: visible.height,
                ratio: store.panelHeightRatio
            )
            : collapsedSize.height
        let placement = verticalPlacement(
            for: visible.minY + visible.height * store.dockY,
            in: visible,
            height: height,
            expanded: store.isExpanded
        )
        store.railOffsetY = placement.railOffset
        let x = store.isExpanded
            ? ControlRailGeometry.frameX(
                edge: store.dockEdge,
                controlsAreVisible: controlsAreVisible,
                width: width,
                visibleFrame: visible,
                edgeInset: edgeInset
            )
            : (store.dockEdge == .left
                ? visible.minX + edgeInset
                : visible.maxX - width - edgeInset)
        setPanelFrame(NSRect(x: x, y: placement.frameY, width: width, height: height))
    }

    private func movePanelForControls() {
        let screen = bestScreen()
        var frame = panel.frame
        frame.origin.x = ControlRailGeometry.frameX(
            edge: store.dockEdge,
            controlsAreVisible: controlsAreVisible,
            width: frame.width,
            visibleFrame: screen.visibleFrame,
            edgeInset: edgeInset
        )
        setPanelFrame(frame)
    }

    private func setPanelFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        scheduleOverlayUpdate(reconcile: true)
    }

    private func verticalPlacement(
        for proposedHandleY: CGFloat,
        in visible: NSRect,
        height: CGFloat,
        expanded: Bool
    ) -> (frameY: CGFloat, railOffset: CGFloat) {
        let handleY = clampedHandleY(proposedHandleY, in: visible, expanded: expanded)
        let availableMargin = max(0, visible.height - height)
        let inset = min(verticalInset, availableMargin / 2)
        let lowestY = visible.minY + inset
        let highestY = max(lowestY, visible.maxY - inset - height)
        let frameY = min(max(handleY - height / 2, lowestY), highestY)
        return (frameY, frameY + height / 2 - handleY)
    }

    private func clampedHandleY(
        _ proposedY: CGFloat,
        in visible: NSRect,
        expanded: Bool
    ) -> CGFloat {
        let topClearance = DaylineLayout.controlSize / 2
        let bottomClearance = expanded
            ? topClearance + 2 * (DaylineLayout.controlSize + DaylineLayout.railButtonSpacing)
            : topClearance
        return min(
            max(proposedY, visible.minY + verticalInset + bottomClearance),
            visible.maxY - verticalInset - topClearance
        )
    }

    private func bestScreen() -> NSScreen {
        dockedScreen
            ?? panel.screen
            ?? screen(containing: panel.frame.center)
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        return subviews.lazy.compactMap { $0.firstDescendant(of: type) }.first
    }
}

extension FloatingPanelController: TimelinePanelControlling {
    func setControlsVisible(_ visible: Bool) {
        guard visible != controlsAreVisible else { return }
        controlsAreVisible = visible
        if store.isExpanded { movePanelForControls() }
    }

    func reveal(todo id: UUID?) {
        let wasExpanded = store.isExpanded
        if !wasExpanded {
            controlsAreVisible = true
            store.isExpanded = true
        }
        let minute = id.flatMap { store.item(id: $0)?.minute }
        store.focusMinute = minute ?? store.quarter(atOrAfter: store.currentMinute)
        refreshWindowLevels()
        revealWorkItem?.cancel()
        // A freshly expanded timeline needs one layout pass before direct scrolling.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let id, let minute = self.store.item(id: id)?.minute {
                self.registerTimelineInteraction()
                self.scrollToAnchor(Double(minute))
            } else {
                self.returnToCurrentTime()
            }
            // Explicit reveal brings the timeline forward even in pin-current mode;
            // the axis input window must stay in front of the main panel.
            self.panel.orderFrontRegardless()
            if let id { self.todoPanels[id]?.orderFrontRegardless() }
            self.axisPanel.orderFrontRegardless()
        }
        revealWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasExpanded ? 0 : 0.2), execute: work)
    }
}
