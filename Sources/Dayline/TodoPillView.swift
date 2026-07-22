import AppKit
import SwiftUI

struct TodoPillView: View {
    @ObservedObject var store: TodayStore
    let item: TodoItem
    @Binding var editingID: UUID?
    let isNext: Bool
    let titleLimit: CGFloat
    let onDragBegan: () -> Void
    let onDragChanged: (Int) -> Void
    let onDragEnded: () -> Void

    @State private var isHovering = false
    @State private var previewMinute: Int?
    @GestureState private var dragOffset: CGFloat = 0
    @FocusState private var titleIsFocused: Bool

    private var currentItem: TodoItem { store.item(id: item.id) ?? item }
    private var visibleMinute: Int { previewMinute ?? currentItem.minute }
    private var pillHeight: CGFloat { DaylineLayout.pillHeight(for: store.fontSize) }
    private var slotHeight: CGFloat { DaylineLayout.slotHeight(for: store.fontSize) }
    private var naturalTitleWidth: CGFloat {
        DaylineLayout.titleWidth(currentItem.title, fontSize: store.fontSize)
    }
    private var titleOverflows: Bool {
        DaylineLayout.titleOverflowsCompact(currentItem.title, fontSize: store.fontSize)
    }
    private var displayedTitleWidth: CGFloat {
        if currentItem.isTitleExpanded {
            return min(naturalTitleWidth, titleLimit)
        }
        return min(naturalTitleWidth, DaylineLayout.compactTitleWidth)
    }

    var body: some View {
        HStack(spacing: 3) {
            Button { store.toggleCompleted(id: item.id) } label: {
                Image(systemName: currentItem.isCompleted ? "circle.fill" : "circle")
                    .font(.system(size: min(max(store.fontSize + 1, 14), 17), weight: .medium))
                    .foregroundStyle(completionColor)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
            .accessibilityLabel(currentItem.isCompleted ? "标记为未完成" : "标记完成")

            title
                .font(.custom("Songti SC", fixedSize: store.fontSize + 1.5).weight(.medium))
                .foregroundStyle(
                    currentItem.isCompleted
                        ? Color.secondary.opacity(0.5)
                        : Color.primary.opacity(0.92)
                )
                .strikethrough(currentItem.isCompleted, color: .secondary.opacity(0.72))

            if titleOverflows {
                Button { store.toggleTitleExpansion(id: item.id) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(daylineWarm.opacity(0.92))
                        .frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
                .accessibilityLabel(currentItem.isTitleExpanded ? "收起完整标题" : "展开完整标题")
            }

            if isHovering && editingID != item.id {
                Button { store.delete(id: item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 11, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("删除 \(currentItem.title)")
            }

            timeMenu
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: pillHeight)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Capsule())
        .glassCapsule(accentuated: isNext, shadowRadius: previewMinute == nil ? 12 : 17)
        .scaleEffect(previewMinute == nil ? 1 : 1.01)
        .overlay(alignment: store.dockEdge == .left ? .leading : .trailing) {
            if previewMinute != nil {
                ZStack {
                    Capsule().fill(.black.opacity(0.34)).frame(height: 3)
                    Capsule().fill(daylineWarm).frame(height: 1.4)
                }
                .frame(width: DaylineLayout.axisToPillGap, height: 4)
                .offset(
                    x: store.dockEdge == .left
                        ? -DaylineLayout.axisToPillGap
                        : DaylineLayout.axisToPillGap
                )
                .allowsHitTesting(false)
            }
        }
        .offset(y: dragOffset)
        .onHover { isHovering = $0 }
        .simultaneousGesture(dragGesture, including: editingID == item.id ? .none : .gesture)
        .onAppear(perform: updateFocus)
        .onChange(of: editingID) { _, _ in updateFocus() }
        .onChange(of: titleIsFocused) { _, focused in
            if !focused { commitEditing() }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var title: some View {
        if editingID == item.id {
            TextField("今天要做什么？", text: titleBinding)
                .textFieldStyle(.plain)
                .focused($titleIsFocused)
                .onSubmit(commitEditing)
                .onExitCommand(perform: commitEditing)
                .frame(width: displayedTitleWidth, alignment: .leading)
        } else {
            Text(currentItem.title.isEmpty ? "今天要做什么？" : currentItem.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: displayedTitleWidth, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditing)
        }
    }

    private var timeMenu: some View {
        Menu {
            ForEach(
                Array(stride(from: store.timelineStartMinute, through: store.timelineEndMinute - 15, by: 15)),
                id: \.self
            ) { minute in
                Button { store.move(id: item.id, to: minute) } label: {
                    if minute == currentItem.minute {
                        Label(DayClock.displayTime(minute), systemImage: "checkmark")
                    } else {
                        Text(DayClock.displayTime(minute))
                    }
                }
            }
        } label: {
            Text(DayClock.displayTime(visibleMinute))
                .font(
                    .system(
                        size: min(max(store.fontSize - 3, 10.5), 12),
                        weight: .semibold,
                        design: .rounded
                    )
                    .monospacedDigit()
                )
                .foregroundStyle(timeColor)
                .padding(.vertical, 1)
                .padding(.horizontal, 5)
                .overlay {
                    Capsule().stroke(
                        Color(nsColor: .separatorColor).opacity(0.48),
                        lineWidth: 0.6
                    )
                }
                .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("时间 \(DayClock.displayTime(visibleMinute))")
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
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($dragOffset) { value, state, transaction in
                transaction.animation = nil
                state = value.translation.height
            }
            .onChanged { value in
                if previewMinute == nil { onDragBegan() }
                let minute = dragMinute(for: value.translation.height)
                previewMinute = minute
                onDragChanged(minute)
            }
            .onEnded { value in
                store.move(id: item.id, to: dragMinute(for: value.translation.height))
                previewMinute = nil
                onDragEnded()
            }
    }

    private func dragMinute(for translation: CGFloat) -> Int {
        DayClock.quarterAtOrAfter(
            Double(currentItem.minute) + Double(translation / slotHeight) * 15,
            start: store.timelineStartMinute,
            end: store.timelineEndMinute
        )
    }

    private func beginEditing() {
        if let editingID, editingID != item.id { store.finalizeTitle(id: editingID) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.editingID = item.id
    }

    private func updateFocus() {
        guard editingID == item.id else {
            titleIsFocused = false
            return
        }
        DispatchQueue.main.async { titleIsFocused = true }
    }

    private func commitEditing() {
        guard editingID == item.id else { return }
        store.finalizeTitle(id: item.id)
        editingID = nil
    }
}
