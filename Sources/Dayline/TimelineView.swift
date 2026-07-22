import Combine
import SwiftUI

struct TimelineView: View {
    @ObservedObject var store: TodayStore
    @Binding var focusMinute: Int?
    @Binding var editingID: UUID?
    let onControlsToggle: () -> Void

    @State private var now = Date()
    @State private var draggingID: UUID?
    @State private var projectionMinute: Int?

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var sortedItems: [TodoItem] {
        store.items.sorted {
            $0.minute == $1.minute ? $0.createdAt < $1.createdAt : $0.minute < $1.minute
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let fadeDistance = DaylineLayout.pillHeight(for: store.fontSize) / 2
            let slotHeight = DaylineLayout.slotHeight(for: store.fontSize)
            let topInset = max(0, (geometry.size.height - slotHeight) * DaylineLayout.viewportAnchor)
            let bottomInset = max(0, (geometry.size.height - slotHeight) * (1 - DaylineLayout.viewportAnchor))
            let slots = Array(
                stride(
                    from: store.timelineStartMinute,
                    through: store.timelineEndMinute,
                    by: 15
                )
            )
            let itemsByMinute = Dictionary(uniqueKeysWithValues: sortedItems.map { ($0.minute, $0) })
            let currentMinute = DayClock.minuteOfDay(for: now, dayEndMinute: store.timelineEndMinute)
            let nextID = sortedItems.first {
                !$0.isCompleted && $0.minute >= currentMinute
            }?.id
            let anchor = focusMinute ?? DayClock.quarterAtOrAfter(
                currentMinute,
                start: store.timelineStartMinute,
                end: store.timelineEndMinute
            )
            let currentScreenY = geometry.size.height * DaylineLayout.viewportAnchor
                + CGFloat(currentMinute - anchor) / 15 * slotHeight
            let currentIsAbove = currentScreenY < -3
            let currentIsBelow = currentScreenY > geometry.size.height + 3

            ZStack {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: topInset)

                        LazyVStack(spacing: 0) {
                            ForEach(slots, id: \.self) { minute in
                                TimelineSlotRow(
                                    store: store,
                                    item: itemsByMinute[minute],
                                    editingID: $editingID,
                                    minute: minute,
                                    nowMinute: currentMinute,
                                    projectionMinute: projectionMinute,
                                    isNext: itemsByMinute[minute]?.id == nextID,
                                    isFirst: minute == store.timelineStartMinute,
                                    isLast: minute == store.timelineEndMinute,
                                    slotHeight: slotHeight,
                                    onControlsToggle: onControlsToggle,
                                    onDragBegan: { id in draggingID = id },
                                    onDragChanged: { projectionMinute = $0 },
                                    onDragEnded: {
                                        draggingID = nil
                                        projectionMinute = nil
                                    }
                                )
                                .frame(height: slotHeight)
                                .id(minute)
                                .zIndex(draggingID == itemsByMinute[minute]?.id ? 20 : 0)
                            }
                        }
                        .scrollTargetLayout()

                        Color.clear.frame(height: bottomInset)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollPosition(
                    id: $focusMinute,
                    anchor: UnitPoint(x: 0.5, y: DaylineLayout.viewportAnchor)
                )
                .mask(edgeFade(height: geometry.size.height, distance: fadeDistance))
                .accessibilityIdentifier("dayline.timeline")
                .accessibilityValue(focusMinute.map(DayClock.displayTime) ?? "")
                .task(id: RangeKey(start: store.timelineStartMinute, end: store.timelineEndMinute)) {
                    await Task.yield()
                    seedFocus(currentMinute)
                }

                if currentIsAbove || currentIsBelow {
                    Button { seedFocus(currentMinute) } label: {
                        Circle()
                            .fill(daylineWarm)
                            .frame(width: 4, height: 4)
                            .shadow(color: daylineWarm.opacity(0.56), radius: 1.5)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: store.dockEdge == .left
                            ? DaylineLayout.timelineAxisInset
                            : geometry.size.width - DaylineLayout.timelineAxisInset,
                        y: currentIsAbove
                            ? fadeDistance
                            : geometry.size.height - fadeDistance
                    )
                    .help("回到现在")
                    .accessibilityLabel("回到现在")
                    .zIndex(50)
                }
            }
        }
        .onReceive(clock) { now = $0 }
    }

    private func edgeFade(height: CGFloat, distance: CGFloat) -> some View {
        let edge = min(distance / max(height, 1), 0.5)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: edge),
                .init(color: .black, location: 1 - edge),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func seedFocus(_ minute: Int) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            focusMinute = DayClock.quarterAtOrAfter(
                minute,
                start: store.timelineStartMinute,
                end: store.timelineEndMinute
            )
        }
    }
}

private struct RangeKey: Hashable {
    let start: Int
    let end: Int
}

private struct TimelineSlotRow: View {
    @ObservedObject var store: TodayStore
    let item: TodoItem?
    @Binding var editingID: UUID?
    let minute: Int
    let nowMinute: Int
    let projectionMinute: Int?
    let isNext: Bool
    let isFirst: Bool
    let isLast: Bool
    let slotHeight: CGFloat
    let onControlsToggle: () -> Void
    let onDragBegan: (UUID) -> Void
    let onDragChanged: (Int) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let pillWidth = max(
                0,
                geometry.size.width - DaylineLayout.pillInset - DaylineLayout.pillOuterInset
            )
            let pillCenter = store.dockEdge == .left
                ? DaylineLayout.pillInset + pillWidth / 2
                : DaylineLayout.pillOuterInset + pillWidth / 2
            let titleLimit = max(
                DaylineLayout.compactTitleWidth,
                DaylineLayout.compactTitleWidth
                    + geometry.size.width
                    - DaylineLayout.compactTimelineWidth
            )

            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.001)
                    .frame(width: DaylineLayout.timelineHitWidth, height: slotHeight)
                    .position(
                        x: store.dockEdge == .left
                            ? DaylineLayout.timelineHitWidth / 2
                            : geometry.size.width - DaylineLayout.timelineHitWidth / 2,
                        y: slotHeight / 2
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: onControlsToggle)
                    .help("双击显示或隐藏控制")
                    .accessibilityHidden(true)

                SlotScale(
                    minute: minute,
                    nowMinute: nowMinute,
                    projectionMinute: projectionMinute,
                    dockEdge: store.dockEdge,
                    isFirst: isFirst,
                    isLast: isLast
                )
                .allowsHitTesting(false)

                if let item {
                    TodoPillView(
                        store: store,
                        item: item,
                        editingID: $editingID,
                        isNext: isNext,
                        titleLimit: titleLimit,
                        onDragBegan: { onDragBegan(item.id) },
                        onDragChanged: onDragChanged,
                        onDragEnded: onDragEnded
                    )
                    .frame(
                        width: pillWidth,
                        alignment: store.dockEdge == .left ? .leading : .trailing
                    )
                    .position(x: pillCenter, y: slotHeight / 2)
                }
            }
        }
    }
}

private struct SlotScale: View {
    let minute: Int
    let nowMinute: Int
    let projectionMinute: Int?
    let dockEdge: DockEdge
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        Canvas { context, size in
            let axisX: CGFloat = dockEdge == .left
                ? DaylineLayout.timelineAxisInset
                : size.width - DaylineLayout.timelineAxisInset
            let direction: CGFloat = dockEdge == .left ? 1 : -1
            let tickY = size.height / 2
            let lineStart = isFirst ? tickY : 0
            let lineEnd = isLast ? tickY : size.height

            var axis = Path()
            axis.move(to: CGPoint(x: axisX, y: lineStart))
            axis.addLine(to: CGPoint(x: axisX, y: lineEnd))
            context.stroke(axis, with: .color(.black.opacity(0.16)), lineWidth: 2.1)
            context.stroke(axis, with: .color(.white.opacity(0.34)), lineWidth: 0.65)

            let quarterIndex = minute / 15
            let isHour = quarterIndex.isMultiple(of: 4)
            let isHalfHour = quarterIndex.isMultiple(of: 2)
            let length: CGFloat = isHour ? 12 : (isHalfHour ? 8 : 4)
            let dark = isHour ? 0.24 : (isHalfHour ? 0.17 : 0.11)
            let light = isHour ? 0.42 : (isHalfHour ? 0.29 : 0.17)

            var tick = Path()
            tick.move(to: CGPoint(x: axisX, y: tickY))
            tick.addLine(to: CGPoint(x: axisX + direction * length, y: tickY))
            context.stroke(tick, with: .color(.black.opacity(dark)), lineWidth: 2)
            context.stroke(tick, with: .color(.white.opacity(light)), lineWidth: 0.7)

            let currentIsInsideRange = !(isFirst && nowMinute < minute)
                && !(isLast && nowMinute > minute)
            if currentIsInsideRange,
               let fraction = DaylineLayout.currentMarkerFraction(
                   currentMinute: nowMinute,
                   around: minute
               ) {
                drawMarker(
                    context: &context,
                    axisX: axisX,
                    y: fraction * size.height,
                    length: 14,
                    direction: direction,
                    opacity: 0.94
                )
            }

            if projectionMinute == minute {
                drawMarker(
                    context: &context,
                    axisX: axisX,
                    y: tickY,
                    length: 0,
                    direction: direction,
                    opacity: 1,
                    emphasizesLanding: true
                )
            }
        }
    }

    private func drawMarker(
        context: inout GraphicsContext,
        axisX: CGFloat,
        y: CGFloat,
        length: CGFloat,
        direction: CGFloat,
        opacity: Double,
        emphasizesLanding: Bool = false
    ) {
        if length > 0 {
            var line = Path()
            line.move(to: CGPoint(x: axisX, y: y))
            line.addLine(to: CGPoint(x: axisX + direction * length, y: y))
            context.stroke(line, with: .color(.black.opacity(0.36)), lineWidth: 2.8)
            context.stroke(line, with: .color(daylineWarm.opacity(opacity)), lineWidth: 1.2)
        }
        if emphasizesLanding {
            context.fill(
                Path(ellipseIn: CGRect(x: axisX - 4, y: y - 4, width: 8, height: 8)),
                with: .color(daylineWarm.opacity(0.18))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: axisX - 2.5, y: y - 2.5, width: 5, height: 5)),
                with: .color(daylineWarm)
            )
        } else {
            context.fill(
                Path(ellipseIn: CGRect(x: axisX - 3, y: y - 3, width: 6, height: 6)),
                with: .color(.black.opacity(0.34))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: axisX - 2, y: y - 2, width: 4, height: 4)),
                with: .color(daylineWarm.opacity(opacity))
            )
        }
    }
}
