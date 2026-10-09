import AppKit
import SwiftUI

final class GuardedClickArbiter {
    private var sequence = 0

    func resolve(
        clickCount: Int,
        delay: TimeInterval,
        singleClick: @escaping () -> Void,
        doubleClick: @escaping () -> Void
    ) {
        guard clickCount > 0 else { return }
        sequence &+= 1
        if clickCount.isMultiple(of: 2) {
            doubleClick()
            return
        }

        let pendingSequence = sequence
        guard delay > 0 else {
            singleClick()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.sequence == pendingSequence else { return }
            singleClick()
        }
    }
}

final class AxisRecallView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    var clickGuardDuration = { TimelineStore.defaultClickGuardDuration }
    private let clickArbiter = GuardedClickArbiter()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.01).setFill()
        dirtyRect.fill()
    }

    override func scrollWheel(with event: NSEvent) { onScroll?(event) }

    override func mouseUp(with event: NSEvent) {
        clickArbiter.resolve(
            clickCount: event.clickCount,
            delay: max(0, clickGuardDuration()),
            singleClick: { [weak self] in self?.onSingleClick?() },
            doubleClick: { [weak self] in self?.onDoubleClick?() }
        )
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
