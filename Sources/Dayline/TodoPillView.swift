import AppKit
import SwiftUI

struct TodoPillView: View {
    @ObservedObject var store: TimelineStore
    let item: TodoItem
    let onDragBegan: (CGFloat) -> Void
    let onDragChanged: () -> Int?
    let onDragEnded: () -> Void
    let onSizeChanged: () -> Void

    @State private var isHovering = false
    @State private var previewMinute: Int?
    @FocusState private var titleIsFocused: Bool

    private enum Metrics {
        static let leadingPadding: CGFloat = 7
        static let trailingPadding: CGFloat = 4
        static let controlGap: CGFloat = 3
        static let completionWidth: CGFloat = 20
        static let expansionWidth: CGFloat = 16
        static let deleteWidth: CGFloat = 11
        static let timeWidth: CGFloat = 44
        static let dragActivationDistance: CGFloat = 3
    }

    private struct LayoutSignature: Equatable {
        let titleWidth: CGFloat
        let showsExpansion: Bool
        let height: CGFloat
    }

    private var currentItem: TodoItem { store.item(id: item.id) ?? item }
    private var isNext: Bool { store.nextTask?.id == item.id }
    private var visibleMinute: Int { previewMinute ?? currentItem.minute }
    private var timeLabel: String {
        switch store.timeDisplayMode {
        case .absolute:
            return DayClock.displayTime(visibleMinute)
        case .remaining:
            return DayClock.displayRemaining(
                taskMinute: visibleMinute,
                currentMinute: store.currentMinute
            )
        }
    }
    private var pillHeight: CGFloat { DaylineLayout.pillHeight(for: store.fontSize) }
    private var compactTitleWidth: CGFloat { CGFloat(store.compactTitleWidth) }
    private var naturalTitleWidth: CGFloat {
        DaylineLayout.titleWidth(
            currentItem.title,
            fontSize: store.fontSize,
            titleHeightRatio: store.titleHeightRatio
        )
    }
    private var titleOverflows: Bool {
        !currentItem.title.isEmpty && naturalTitleWidth > compactTitleWidth
    }
    private var displayedTitleWidth: CGFloat {
        if currentItem.isTitleExpanded {
            return min(naturalTitleWidth, store.pillTitleLimit)
        }
        return min(naturalTitleWidth, compactTitleWidth)
    }
    private var isEditing: Bool { store.editingID == item.id }
    private var showsDelete: Bool { isHovering && !isEditing }
    private var layoutSignature: LayoutSignature {
        LayoutSignature(
            titleWidth: displayedTitleWidth,
            showsExpansion: titleOverflows,
            height: pillHeight
        )
    }

    var body: some View {
        pill
            .onDisappear {
                commitEditing()
                guard previewMinute != nil else { return }
                previewMinute = nil
                store.projectionMinute = nil
                onDragEnded()
            }
            .accessibilityElement(children: .contain)
    }

    private var pill: some View {
        HStack(spacing: 0) {
            Button {
                performAfterCommittingEdit { store.toggleCompleted(id: item.id) }
            } label: {
                Image(systemName: currentItem.isCompleted ? "circle.fill" : "circle")
                    .font(.system(size: min(max(store.fontSize + 1, 14), 17), weight: .medium))
                    .foregroundStyle(completionColor)
                    .frame(width: Metrics.completionWidth, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
            .accessibilityLabel(currentItem.isCompleted ? "标记为未完成" : "标记完成")

            Color.clear.frame(width: Metrics.controlGap)

            title
                .font(
                    .custom(
                        "Songti SC",
                        fixedSize: DaylineLayout.titleFontSize(
                            for: store.fontSize,
                            heightRatio: store.titleHeightRatio
                        )
                    )
                    .weight(.medium)
                )
                .foregroundStyle(
                    currentItem.isCompleted
                        ? Color.secondary.opacity(0.5)
                        : Color.primary.opacity(0.92)
                )
                .strikethrough(currentItem.isCompleted, color: .secondary.opacity(0.72))

            if titleOverflows {
                Color.clear.frame(width: Metrics.controlGap)

                Button {
                    performAfterCommittingEdit { store.toggleTitleExpansion(id: item.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(daylineWarm.opacity(0.92))
                        .frame(width: Metrics.expansionWidth, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
                .accessibilityLabel(currentItem.isTitleExpanded ? "收起完整标题" : "展开完整标题")
            }

            deleteControl
                .frame(width: DaylineLayout.pillDeleteWidth, alignment: .trailing)
                .opacity(showsDelete ? 1 : 0)
                .allowsHitTesting(showsDelete)
                .accessibilityHidden(!showsDelete)

            Color.clear.frame(width: Metrics.controlGap)

            timeMenu
        }
        .padding(.leading, Metrics.leadingPadding)
        .padding(.trailing, Metrics.trailingPadding)
        .frame(height: pillHeight)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Capsule())
        .glassCapsule(nativeGlassStyle: store.nativeGlassStyle)
        .overlay(alignment: store.dockEdge == .left ? .leading : .trailing) {
            if previewMinute != nil {
                Capsule()
                    .fill(daylineWarm)
                    .frame(width: DaylineLayout.axisToPillGap, height: 1.4)
                    .offset(
                        x: store.dockEdge == .left
                            ? -DaylineLayout.axisToPillGap
                            : DaylineLayout.axisToPillGap
                    )
                    .allowsHitTesting(false)
            }
        }
        .onHover { isHovering = $0 }
        .onChange(of: layoutSignature) { _, _ in onSizeChanged() }
        .simultaneousGesture(
            dragGesture,
            including: isEditing ? .subviews : .all
        )
        .onAppear(perform: updateFocus)
        .onChange(of: store.editingID) { _, _ in updateFocus() }
        .onChange(of: titleIsFocused) { _, focused in
            if !focused { commitEditing() }
        }
    }

    private var title: some View {
        ZStack(alignment: .leading) {
            Text(currentItem.title.isEmpty ? "要做什么？" : currentItem.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: displayedTitleWidth, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)
                .accessibilityHidden(isEditing)
                .onTapGesture(count: 2, perform: beginEditing)
                .accessibilityAction(named: Text("编辑标题"), beginEditing)
                .help("双击编辑标题")

            TextField("要做什么？", text: titleBinding)
                .textFieldStyle(.plain)
                .focused($titleIsFocused)
                .onSubmit(commitEditing)
                .onExitCommand(perform: commitEditing)
                .frame(width: displayedTitleWidth, alignment: .leading)
                .opacity(isEditing ? 1 : 0)
                .allowsHitTesting(isEditing)
                .disabled(!isEditing)
                .accessibilityHidden(!isEditing)
        }
        .frame(width: displayedTitleWidth, alignment: .leading)
    }

    private var deleteControl: some View {
        Button {
            performAfterCommittingEdit { store.delete(id: item.id) }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: Metrics.deleteWidth, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .padding(.leading, Metrics.controlGap)
        .accessibilityLabel("删除 \(currentItem.title)")
    }

    private var timeMenu: some View {
        Text(timeLabel)
            .font(
                .system(
                    size: min(max(store.fontSize - 3, 10.5), 12),
                    weight: .semibold,
                    design: .rounded
                )
                .monospacedDigit()
            )
            .foregroundStyle(timeColor)
            .frame(width: Metrics.timeWidth)
            .padding(.vertical, 1)
            .contentShape(Capsule())
            .accessibilityHidden(true)
            .overlay {
                TimeMenuInteraction(
                    startMinute: store.timelineStartMinute,
                    endMinute: store.timelineEndMinute,
                    selectedMinute: currentItem.minute,
                    clickGuardDuration: store.clickGuardDuration,
                    onSelectMinute: { minute in
                        performAfterCommittingEdit { store.move(id: item.id, to: minute) }
                    },
                    onDoubleClick: {
                        performAfterCommittingEdit {
                            store.timeDisplayMode = store.timeDisplayMode == .absolute
                                ? .remaining
                                : .absolute
                        }
                    }
                )
            }
            .fixedSize()
            .help("单击调整截止时间 · 双击切换时间显示")
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.item(id: item.id)?.title ?? item.title },
            set: { store.updateTitle(id: item.id, title: $0) }
        )
    }

    private var completionColor: Color {
        if currentItem.isCompleted { return daylineWarm.opacity(0.78) }
        return isNext ? daylineWarm.opacity(0.9) : .primary.opacity(0.52)
    }

    private var timeColor: Color {
        if currentItem.isCompleted { return .secondary.opacity(0.48) }
        return isNext ? daylineWarm.opacity(0.96) : .secondary.opacity(0.88)
    }

    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: Metrics.dragActivationDistance,
            coordinateSpace: .global
        )
            .onChanged { value in
                guard value.translation.height != 0 else { return }
                if previewMinute == nil { onDragBegan(value.translation.height) }
                guard let minute = onDragChanged() else { return }
                if previewMinute != minute { previewMinute = minute }
                if store.projectionMinute != minute { store.projectionMinute = minute }
            }
            .onEnded { _ in
                guard previewMinute != nil else { return }
                previewMinute = nil
                store.projectionMinute = nil
                onDragEnded()
            }
    }

    private func beginEditing() {
        if store.editingID != item.id { store.commitEditing() }
        NSApplication.shared.activate(ignoringOtherApps: true)
        store.editingID = item.id
    }

    private func updateFocus() {
        guard store.editingID == item.id else {
            titleIsFocused = false
            return
        }
        DispatchQueue.main.async {
            guard store.editingID == item.id else { return }
            titleIsFocused = true
        }
    }

    private func commitEditing() {
        guard store.editingID == item.id else { return }
        store.commitEditing()
    }

    private func performAfterCommittingEdit(_ action: () -> Void) {
        store.commitEditing()
        action()
    }
}

private struct TimeMenuInteraction: NSViewRepresentable {
    let startMinute: Int
    let endMinute: Int
    let selectedMinute: Int
    let clickGuardDuration: TimeInterval
    let onSelectMinute: (Int) -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.popUpButton)
        view.setAccessibilityLabel("截止时间")
        return view
    }

    func updateNSView(_ view: InteractionView, context: Context) {
        view.startMinute = startMinute
        view.endMinute = endMinute
        view.selectedMinute = selectedMinute
        view.setAccessibilityValue(DayClock.displayRangeTime(selectedMinute))
        view.clickGuardDuration = clickGuardDuration
        view.onSelectMinute = onSelectMinute
        view.onDoubleClick = onDoubleClick
    }

    final class InteractionView: NSView {
        var startMinute = DayClock.startMinute
        var endMinute = DayClock.endMinute
        var selectedMinute = DayClock.startMinute
        var clickGuardDuration = TimelineStore.defaultClickGuardDuration
        var onSelectMinute: ((Int) -> Void)?
        var onDoubleClick: (() -> Void)?
        private let clickArbiter = GuardedClickArbiter()

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseUp(with event: NSEvent) {
            let anchor = convert(event.locationInWindow, from: nil)
            clickArbiter.resolve(
                clickCount: event.clickCount,
                delay: max(0, clickGuardDuration),
                singleClick: { [weak self] in self?.presentMenu(at: anchor) },
                doubleClick: { [weak self] in self?.onDoubleClick?() }
            )
        }

        override func accessibilityPerformPress() -> Bool {
            presentMenu(at: NSPoint(x: bounds.midX, y: bounds.midY))
            return true
        }

        @objc private func selectMinute(_ sender: NSMenuItem) {
            onSelectMinute?(sender.tag)
        }

        private func presentMenu(at anchor: NSPoint) {
            guard window != nil else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            var selectedItem: NSMenuItem?
            for minute in stride(from: startMinute, through: endMinute - 15, by: 15) {
                let item = NSMenuItem(
                    title: DayClock.displayTime(minute),
                    action: #selector(selectMinute(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = minute
                item.state = minute == selectedMinute ? .on : .off
                if item.state == .on { selectedItem = item }
                menu.addItem(item)
            }
            menu.popUp(positioning: selectedItem, at: anchor, in: self)
        }
    }
}
