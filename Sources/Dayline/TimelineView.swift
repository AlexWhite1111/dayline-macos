import SwiftUI

struct TimelineView: View {
    @ObservedObject var store: TodayStore
    @Binding var focusMinute: Int?
    let onFirstSlotCenterChanged: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            let fadeDistance = DaylineLayout.timelineFadeDistance(for: store.fontSize)
            let slotHeight = DaylineLayout.slotHeight(for: store.fontSize)
            let viewportAnchor = DaylineLayout.timelineViewportAnchor(
                position: store.timelineAnchorPosition
            )
            let anchorY = DaylineLayout.timelineAnchorCenterY(
                viewportHeight: geometry.size.height,
                fontSize: store.fontSize,
                position: store.timelineAnchorPosition
            )
            let topInset = max(0, (geometry.size.height - slotHeight) * viewportAnchor)
            let bottomInset = max(
                0,
                (geometry.size.height - slotHeight) * (1 - viewportAnchor)
            )
            let slots = Array(
                stride(
                    from: store.timelineStartMinute,
                    through: store.timelineEndMinute,
                    by: 15
                )
            )
            let currentMinute = DayClock.minuteOfDay(
                for: store.clockDate,
                dayEndMinute: store.timelineEndMinute
            )
            let anchor = focusMinute ?? DayClock.quarterAtOrAfter(
                currentMinute,
                start: store.timelineStartMinute,
                end: store.timelineEndMinute
            )
            let currentScreenY = DaylineLayout.timelineCenterY(
                minute: currentMinute,
                referenceMinute: anchor,
                referenceCenterY: anchorY,
                fontSize: store.fontSize
            )
            let currentIsAbove = currentScreenY < -3
            let currentIsBelow = currentScreenY > geometry.size.height + 3

            ZStack {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: topInset)

                        LazyVStack(spacing: 0) {
                            ForEach(slots, id: \.self) { minute in
                                SlotScale(
                                    minute: minute,
                                    nowMinute: currentMinute,
                                    projectionMinute: store.projectionMinute,
                                    dockEdge: store.dockEdge,
                                    isFirst: minute == store.timelineStartMinute,
                                    isLast: minute == store.timelineEndMinute
                                )
                                .frame(height: slotHeight)
                                .id(minute)
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
                    anchor: UnitPoint(x: 0.5, y: viewportAnchor)
                )
                .onScrollGeometryChange(
                    for: CGFloat.self,
                    of: { scrollGeometry in
                        topInset + slotHeight / 2 - scrollGeometry.contentOffset.y
                    },
                    action: { _, firstSlotCenterY in
                        onFirstSlotCenterChanged(firstSlotCenterY)
                    }
                )
                .mask(edgeFade(height: geometry.size.height, distance: fadeDistance))
                .accessibilityIdentifier("dayline.timeline")
                .accessibilityValue(focusMinute.map(DayClock.displayTime) ?? "")
                .task(id: [store.timelineStartMinute, store.timelineEndMinute]) {
                    await Task.yield()
                    seedFocus(currentMinute)
                }

                if currentIsAbove || currentIsBelow {
                    Button { seedFocus(currentMinute) } label: {
                        Circle()
                            .fill(daylineWarm)
                            .frame(width: 4, height: 4)
                            .shadow(color: daylineWarm.opacity(0.56), radius: 1.5)
                            .frame(
                                width: DaylineLayout.currentTimeButtonHitSize,
                                height: DaylineLayout.currentTimeButtonHitSize
                            )
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
