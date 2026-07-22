import AppKit

enum DockEdge: String, Codable {
    case left
    case right
}

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var minute: Int
    var isTitleExpanded: Bool
    var isCompleted: Bool
    let createdAt: Date

    init(
        id: UUID,
        title: String,
        minute: Int,
        isTitleExpanded: Bool = false,
        isCompleted: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.minute = minute
        self.isTitleExpanded = isTitleExpanded
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, minute, isTitleExpanded, isCompleted, createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        minute = try values.decode(Int.self, forKey: .minute)
        isTitleExpanded = try values.decodeIfPresent(Bool.self, forKey: .isTitleExpanded) ?? false
        isCompleted = try values.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }
}

struct SavedState: Codable {
    var dayKey: String
    var items: [TodoItem]
    var fontSize: Double
    var dockEdge: DockEdge
    var dockY: Double
    var isExpanded: Bool
    var timelineStartMinute: Int? = nil
    var timelineEndMinute: Int? = nil
    var panelHeightRatio: Double? = nil
    var usesNativeGlass: Bool? = nil
}

enum DayClock {
    static let startMinute = 7 * 60
    static let endMinute = 25 * 60
    static let lastTaskMinute = endMinute - 15
    static let quarterHours = Array(stride(from: startMinute, through: lastTaskMinute, by: 15))

    static func dayKey(for date: Date = Date(), dayEndMinute: Int = endMinute) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let overflow = max(0, dayEndMinute - 24 * 60)
        let shifted = calendar.date(byAdding: .minute, value: -overflow, to: date) ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    static func minuteOfDay(for date: Date = Date(), dayEndMinute: Int = endMinute) -> Int {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let overflow = max(0, dayEndMinute - 24 * 60)
        return minute < overflow ? minute + 24 * 60 : minute
    }

    static func defaultTaskMinute(
        for date: Date = Date(),
        start: Int = startMinute,
        end: Int = endMinute
    ) -> Int {
        quarterAtOrAfter(minuteOfDay(for: date, dayEndMinute: end), start: start, end: end)
    }

    static func quarterAtOrAfter(
        _ minute: Int,
        start: Int = startMinute,
        end: Int = endMinute
    ) -> Int {
        quarterAtOrAfter(Double(minute), start: start, end: end)
    }

    static func quarterAtOrAfter(
        _ minute: Double,
        start: Int = startMinute,
        end: Int = endMinute
    ) -> Int {
        clamp(Int(ceil(minute / 15)) * 15, start: start, end: end)
    }

    static func clamp(
        _ minute: Int,
        start: Int = startMinute,
        end: Int = endMinute
    ) -> Int {
        min(max(minute, start), end - 15)
    }

    static func displayTime(_ minute: Int) -> String {
        let safeMinute = max(0, minute)
        return String(format: "%02d:%02d", (safeMinute / 60) % 24, safeMinute % 60)
    }

    static func displayRangeTime(_ minute: Int) -> String {
        (minute >= 24 * 60 ? "次日 " : "") + displayTime(minute)
    }
}

enum DaylineLayout {
    static let compactPanelWidth: CGFloat = 398
    static let defaultExpandedPanelHeightRatio: CGFloat = 0.9
    static let controlSize: CGFloat = 36
    static let timelineHitWidth: CGFloat = 10
    static let panelHorizontalPadding: CGFloat = 6
    static let railSpacing: CGFloat = 4
    static let railButtonSpacing: CGFloat = 6
    static let timelineAxisInset: CGFloat = 7
    static let pillInset: CGFloat = 18
    static let pillOuterInset: CGFloat = 8
    static let compactTitleWidth: CGFloat = 112
    static let viewportAnchor: CGFloat = 0.35

    static var axisToPillGap: CGFloat { pillInset - timelineAxisInset }

    static func currentMarkerFraction(currentMinute: Int, around tickMinute: Int) -> CGFloat? {
        let fraction = 0.5 + CGFloat(currentMinute - tickMinute) / 15
        return (0..<1).contains(fraction) ? fraction : nil
    }

    static var compactTimelineWidth: CGFloat {
        compactPanelWidth
            - panelHorizontalPadding * 2
            - controlSize
            - railSpacing
    }

    static func titleWidth(_ title: String, fontSize: Double) -> CGFloat {
        let value = title.isEmpty ? "今天要做什么？" : title
        let size = fontSize + 1.5
        let font = NSFont(name: "Songti SC", size: size) ?? NSFont.systemFont(ofSize: size)
        return ceil((value as NSString).size(withAttributes: [.font: font]).width) + 3
    }

    static func titleOverflowsCompact(_ title: String, fontSize: Double) -> Bool {
        !title.isEmpty && titleWidth(title, fontSize: fontSize) > compactTitleWidth
    }

    static func pillHeight(for fontSize: Double) -> CGFloat {
        34 + CGFloat(fontSize - 13) * 1.2
    }

    static func slotHeight(for fontSize: Double) -> CGFloat {
        pillHeight(for: fontSize) + 4
    }

    static func hourHeight(for fontSize: Double) -> CGFloat {
        slotHeight(for: fontSize) * 4
    }

    static func expandedPanelHeight(
        availableHeight: CGFloat,
        ratio: CGFloat = defaultExpandedPanelHeightRatio
    ) -> CGFloat {
        let safeRatio = min(max(ratio, 0.6), 1)
        return min(
            availableHeight,
            max(480, availableHeight * safeRatio)
        )
    }
}

enum ControlRailGeometry {
    static let restingAxisInset: CGFloat = 3

    static func frameX(
        edge: DockEdge,
        controlsAreVisible: Bool,
        width: CGFloat,
        visibleFrame: NSRect,
        edgeInset: CGFloat
    ) -> CGFloat {
        if controlsAreVisible {
            return edge == .left
                ? visibleFrame.minX + edgeInset
                : visibleFrame.maxX - width - edgeInset
        }

        let axisOffset = DaylineLayout.panelHorizontalPadding
            + DaylineLayout.controlSize
            + DaylineLayout.railSpacing
            + DaylineLayout.timelineAxisInset
        return edge == .left
            ? visibleFrame.minX + restingAxisInset - axisOffset
            : visibleFrame.maxX - restingAxisInset - width + axisOffset
    }

}

enum DockResolver {
    static func edge(for x: CGFloat, screenMidX: CGFloat) -> DockEdge {
        x < screenMidX ? .left : .right
    }
}
