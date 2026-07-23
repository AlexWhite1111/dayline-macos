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

    private struct PanelLayoutInput: Equatable {
        let expandedTitleWidth: CGFloat
        let fontSize: Double
        let titleHeightRatio: Double
    }

    private let store: TodayStore
    private let panel: FloatingPanel
    private let axisPanel: FloatingPanel
    private var todoPanels: [UUID: FloatingPanel] = [:]
    private var dragSession: TodoDragSession?
    private var timelineFirstSlotCenterY: CGFloat?
    private var subscriptions = Set<AnyCancellable>()
    private var controlsAreVisible = true
    private var isSettingsPresented = false
    private var dockedScreen: NSScreen?
    private var layoutUpdateIsScheduled = false
    private var overlayStateUpdateIsScheduled = false

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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    init(store: TodayStore) {
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
                onTimelineFirstSlotCenterChanged: { [weak self] firstSlotCenterY in
                    self?.timelineFirstSlotCenterY = firstSlotCenterY
                    self?.updateOverlayPositions()
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
        reconcileOverlaysSoon()
    }

    private func configureAxisPanel() {
        let view = AxisRecallView()
        view.autoresizingMask = [.width, .height]
        view.onSingleClick = { [weak self] in self?.togglePinnedWindowMode() }
        view.onDoubleClick = { [weak self] in self?.toggleControls() }
        view.onScroll = { [weak self] event in self?.scrollTimeline(with: event) }
        view.clickGuardDuration = { [weak self] in
            self?.store.clickGuardDuration ?? TodayStore.defaultClickGuardDuration
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
        Publishers.CombineLatest3(store.$items, store.$fontSize, store.$titleHeightRatio)
            .map { items, fontSize, titleHeightRatio in
                let expandedTitleWidth = items
                    .filter(\.isTitleExpanded)
                    .map {
                        DaylineLayout.titleWidth(
                            $0.title,
                            fontSize: fontSize,
                            titleHeightRatio: titleHeightRatio
                        )
                    }
                    .max() ?? 0
                return PanelLayoutInput(
                    expandedTitleWidth: expandedTitleWidth,
                    fontSize: fontSize,
                    titleHeightRatio: titleHeightRatio
                )
            }
            .removeDuplicates()
            .sink { [weak self] input in
                self?.applyFrame(expandedTitleWidth: input.expandedTitleWidth)
            }
            .store(in: &subscriptions)

        Publishers.CombineLatest(store.$panelHeightRatio, store.$compactTitleWidth)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyFrame() }
            .store(in: &subscriptions)

        store.$items
            .map { $0.map(\.id) }
            .removeDuplicates()
            .sink { [weak self] _ in self?.reconcileOverlaysSoon() }
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
                self?.refreshOverlayStateSoon()
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

    private var currentTaskID: UUID? {
        store.currentTask(
            at: DayClock.minuteOfDay(
                for: store.clockDate,
                dayEndMinute: store.timelineEndMinute
            )
        )?.id
    }

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

    private func reconcileOverlaysSoon() {
        guard !layoutUpdateIsScheduled else { return }
        layoutUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutUpdateIsScheduled = false
            self.reconcileOverlays()
        }
    }

    private func refreshOverlayStateSoon() {
        guard !overlayStateUpdateIsScheduled else { return }
        overlayStateUpdateIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlayStateUpdateIsScheduled = false
            self.updateOverlayPositions()
            self.refreshWindowLevels()
            self.refreshTaskPanelKeyFocus()
        }
    }

    private func reconcileOverlays() {
        guard store.isExpanded, panel.isVisible else {
            axisPanel.orderOut(nil)
            todoPanels.values.forEach { $0.orderOut(nil) }
            timelineFirstSlotCenterY = nil
            dragSession = nil
            if store.projectionMinute != nil { store.projectionMinute = nil }
            return
        }

        let itemIDs = Set(store.items.map(\.id))
        for id in todoPanels.keys.filter({ !itemIDs.contains($0) }) {
            todoPanels.removeValue(forKey: id)?.orderOut(nil)
        }

        store.items.forEach(resizeTodoPanel)

        updateOverlayPositions()
        updateAxisFrame()
        axisPanel.orderFrontRegardless()
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
                fontSize: store.fontSize
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
                edgeClearance: DaylineLayout.timelineFadeDistance(for: store.fontSize)
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

    private func resizeTodoPanel(_ item: TodoItem) {
        _ = todoPanel(for: item)
        resizeTodoPanel(id: item.id)
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
        if let timelineFirstSlotCenterY {
            return DaylineLayout.timelineCenterY(
                minute: minute,
                referenceMinute: store.timelineStartMinute,
                referenceCenterY: timelineFirstSlotCenterY,
                fontSize: store.fontSize
            )
        }
        let currentMinute = DayClock.minuteOfDay(
            for: store.clockDate,
            dayEndMinute: store.timelineEndMinute
        )
        let anchorMinute = store.focusMinute ?? DayClock.quarterAtOrAfter(
            currentMinute,
            start: store.timelineStartMinute,
            end: store.timelineEndMinute
        )
        return DaylineLayout.timelineCenterY(
            minute: minute,
            referenceMinute: anchorMinute,
            referenceCenterY: DaylineLayout.timelineAnchorCenterY(
                viewportHeight: viewportHeight,
                fontSize: store.fontSize,
                position: store.timelineAnchorPosition
            ),
            fontSize: store.fontSize
        )
    }

    private func beginDragging(_ id: UUID, initialTranslation: CGFloat) {
        guard let panel = todoPanels[id], let item = store.item(id: id) else { return }
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
        resizeTodoPanel(id: id)
        updateOverlayPositions()
        refreshWindowLevels()
    }

    private func scrollTimeline(with event: NSEvent) {
        panel.contentView?.firstDescendant(of: NSScrollView.self)?.scrollWheel(with: event)
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

    private func applyFrame(
        on forcedScreen: NSScreen? = nil,
        expandedTitleWidth publishedTitleWidth: CGFloat? = nil
    ) {
        let screen = forcedScreen ?? bestScreen()
        dockedScreen = screen
        let visible = screen.visibleFrame
        let expandedTitleWidth = publishedTitleWidth ?? store.items
            .filter(\.isTitleExpanded)
            .map {
                DaylineLayout.titleWidth(
                    $0.title,
                    fontSize: store.fontSize,
                    titleHeightRatio: store.titleHeightRatio
                )
            }
            .max() ?? 0
        let contentWidth = min(
            DaylineLayout.compactPanelWidth(for: CGFloat(store.compactTitleWidth))
                + max(0, expandedTitleWidth - CGFloat(store.compactTitleWidth)),
            visible.width - 4
        )
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
        updatePillTitleLimit(for: frame)
        panel.setFrame(frame, display: true)
        reconcileOverlaysSoon()
    }

    private func updatePillTitleLimit(for panelFrame: NSRect) {
        let timelineWidth = FloatingItemGeometry.timelineFrame(
            in: panelFrame,
            edge: store.dockEdge
        ).width
        let compactWidth = CGFloat(store.compactTitleWidth)
        let limit = compactWidth + max(
            0,
            timelineWidth - DaylineLayout.compactTimelineWidth(for: compactWidth)
        )
        if store.pillTitleLimit != limit { store.pillTitleLimit = limit }
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

private final class AxisRecallView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    var clickGuardDuration = { TodayStore.defaultClickGuardDuration }
    private var clickSequence = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.01).setFill()
        dirtyRect.fill()
    }

    override func scrollWheel(with event: NSEvent) { onScroll?(event) }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount > 0 else { return }
        clickSequence &+= 1
        if event.clickCount.isMultiple(of: 2) {
            onDoubleClick?()
            return
        }

        let sequence = clickSequence
        let delay = max(0, clickGuardDuration())
        guard delay > 0 else {
            onSingleClick?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.clickSequence == sequence else { return }
            self.onSingleClick?()
        }
    }
}

struct WindowDragSurface: NSViewRepresentable {
    let onClick: () -> Void
    let onDragChanged: (NSPoint) -> Void
    let onDragEnded: (NSPoint) -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DragHandleView, context: Context) {
        view.onClick = onClick
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }

    final class DragHandleView: NSView {
        var onClick: (() -> Void)?
        var onDragChanged: ((NSPoint) -> Void)?
        var onDragEnded: ((NSPoint) -> Void)?
        private var startPointer: NSPoint?
        private var startOrigin: NSPoint?
        private var startHandleCenter: NSPoint?
        private var isDragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            startPointer = NSEvent.mouseLocation
            startOrigin = window?.frame.origin
            startHandleCenter = handleCenterOnScreen()
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startPointer, let startOrigin, let startHandleCenter, let window else { return }
            let pointer = NSEvent.mouseLocation
            let dx = pointer.x - startPointer.x
            let dy = pointer.y - startPointer.y
            guard isDragging || hypot(dx, dy) >= 5 else { return }
            isDragging = true
            window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: window.frame.minY))
            onDragChanged?(NSPoint(x: startHandleCenter.x + dx, y: startHandleCenter.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            let pointer = NSEvent.mouseLocation
            if isDragging, let startPointer, let startHandleCenter {
                onDragEnded?(
                    NSPoint(
                        x: startHandleCenter.x + pointer.x - startPointer.x,
                        y: startHandleCenter.y + pointer.y - startPointer.y
                    )
                )
            } else {
                onClick?()
            }
            startPointer = nil
            startOrigin = nil
            startHandleCenter = nil
            isDragging = false
        }

        private func handleCenterOnScreen() -> NSPoint? {
            guard let window else { return nil }
            let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            return window.convertPoint(toScreen: center)
        }
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
