import AppKit
import Combine
import QuartzCore
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController: NSWindowController {
    private let store: TodayStore
    private let panel: FloatingPanel
    private var subscriptions = Set<AnyCancellable>()
    private var controlsAreVisible = true
    private var dockedScreen: NSScreen?

    private var normalWidth: CGFloat {
        DaylineLayout.compactPanelWidth(for: CGFloat(store.compactTitleWidth))
    }
    private let collapsedSize = NSSize(width: 48, height: 44)
    private let edgeInset: CGFloat = 2
    private let verticalInset: CGFloat = 12

    init(store: TodayStore) {
        self.store = store
        panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DaylineLayout.compactPanelWidth(for: CGFloat(store.compactTitleWidth)),
                height: 680
            ),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        resolveFirstPlacementIfNeeded()
        configurePanel()
        let hostingView = NSHostingView(
            rootView: RootView(
                store: store,
                onHandleClick: { [weak self] in self?.toggleExpanded() },
                onHandleDragChanged: { [weak self] point in self?.trackHandle(at: point) },
                onHandleDragEnded: { [weak self] point in self?.snap(to: point) },
                onControlsToggle: { [weak self] in self?.toggleControls() }
            )
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        observeLayoutInputs()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
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
        Publishers.CombineLatest(store.$items, store.$fontSize)
            .map { items, fontSize in
                items
                    .filter(\.isTitleExpanded)
                    .map { DaylineLayout.titleWidth($0.title, fontSize: fontSize) }
                    .max() ?? 0
            }
            .removeDuplicates()
            .sink { [weak self] titleWidth in
                self?.applyFrame(expandedTitleWidth: titleWidth)
            }
            .store(in: &subscriptions)

        store.$panelHeightRatio
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrame() }
            .store(in: &subscriptions)

        store.$compactTitleWidth
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyFrame() }
            .store(in: &subscriptions)
    }

    private func toggleExpanded() {
        controlsAreVisible = true
        store.isExpanded.toggle()
        applyFrame()
    }

    private func toggleControls() {
        guard store.isExpanded else { return }
        controlsAreVisible.toggle()
        movePanelForControls()
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
            .map { DaylineLayout.titleWidth($0.title, fontSize: store.fontSize) }
            .max() ?? 0
        let contentWidth = min(
            normalWidth + max(0, expandedTitleWidth - CGFloat(store.compactTitleWidth)),
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
            for:
            visible.minY + visible.height * store.dockY,
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
        setPanelFrame(
            NSRect(x: x, y: placement.frameY, width: width, height: height),
            animated: false
        )
    }

    private func movePanelForControls() {
        let screen = bestScreen()
        let x = ControlRailGeometry.frameX(
            edge: store.dockEdge,
            controlsAreVisible: controlsAreVisible,
            width: panel.frame.width,
            visibleFrame: screen.visibleFrame,
            edgeInset: edgeInset
        )
        var frame = panel.frame
        frame.origin.x = x
        setPanelFrame(frame, animated: true)
    }

    private func setPanelFrame(_ frame: NSRect, animated: Bool) {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func verticalPlacement(
        for proposedHandleY: CGFloat,
        in visible: NSRect,
        height: CGFloat,
        expanded: Bool
    ) -> (frameY: CGFloat, railOffset: CGFloat) {
        let handleY = clampedHandleY(proposedHandleY, in: visible, expanded: expanded)
        let availableMargin = max(0, visible.height - height)
        let edgeInset = min(verticalInset, availableMargin / 2)
        let lowestY = visible.minY + edgeInset
        let highestY = max(lowestY, visible.maxY - edgeInset - height)
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

struct WindowDragSurface: NSViewRepresentable {
    let onClick: () -> Void
    let onDragChanged: (NSPoint) -> Void
    let onDragEnded: (NSPoint) -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.onClick = onClick
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
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
            let centerInWindow = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            return window.convertPoint(toScreen: centerInWindow)
        }
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
