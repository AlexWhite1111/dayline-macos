import AppKit
import ServiceManagement
import SwiftUI

struct RootView: View {
    @ObservedObject var store: TimelineStore
    let onHandleClick: () -> Void
    let onHandleDragChanged: (NSPoint) -> Void
    let onHandleDragEnded: (NSPoint) -> Void
    let onSettingsPresented: (Bool) -> Void
    let onTimelineProjectionChanged: (TimelineProjection) -> Void
    let onTimelineScrollActivity: () -> Void
    let onReturnToCurrentTime: () -> Void

    var body: some View {
        Group {
            if store.isExpanded {
                HStack(spacing: DaylineLayout.railSpacing) {
                    if store.dockEdge == .left {
                        rail
                        timeline
                    } else {
                        timeline
                        rail
                    }
                }
                .padding(.vertical, DaylineLayout.panelVerticalPadding)
                .padding(.horizontal, DaylineLayout.panelHorizontalPadding)
            } else {
                rail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rail: some View {
        SideRail(
            store: store,
            onHandleClick: {
                store.commitEditing()
                onHandleClick()
            },
            onHandleDragChanged: onHandleDragChanged,
            onHandleDragEnded: { point in
                store.commitEditing()
                onHandleDragEnded(point)
            },
            onSettingsPresented: onSettingsPresented,
            onBeforeAction: store.commitEditing,
            onAdd: addTask
        )
        .frame(width: DaylineLayout.controlSize)
        .offset(y: store.railOffsetY)
    }

    private var timeline: some View {
        TimelineView(
            store: store,
            focusMinute: $store.focusMinute,
            onProjectionChanged: onTimelineProjectionChanged,
            onUserScrollActivity: onTimelineScrollActivity,
            onReturnToCurrentTime: onReturnToCurrentTime
        )
    }

    private func addTask() {
        let minute = DayClock.quarterAtOrAfter(
            store.focusMinute ?? DayClock.defaultTaskMinute(
                start: store.timelineStartMinute,
                end: store.timelineEndMinute
            ),
            start: store.timelineStartMinute,
            end: store.timelineEndMinute
        )
        let id = store.addTask(at: minute)
        store.focusMinute = store.item(id: id)!.minute
        store.editingID = id
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

}

private struct SideRail: View {
    @ObservedObject var store: TimelineStore
    let onHandleClick: () -> Void
    let onHandleDragChanged: (NSPoint) -> Void
    let onHandleDragEnded: (NSPoint) -> Void
    let onSettingsPresented: (Bool) -> Void
    let onBeforeAction: () -> Void
    let onAdd: () -> Void

    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: DaylineLayout.railButtonSpacing) {
            EdgeHandle(
                store: store,
                onClick: onHandleClick,
                onDragChanged: onHandleDragChanged,
                onDragEnded: onHandleDragEnded
            )

            if store.isExpanded {
                sideButton("plus", label: "添加待办") {
                    onBeforeAction()
                    onAdd()
                }
                .keyboardShortcut("n", modifiers: .command)

                sideButton("slider.horizontal.3", label: "设置") {
                    onBeforeAction()
                    showsSettings.toggle()
                }
                .popover(isPresented: $showsSettings) {
                    SettingsPopover(store: store)
                }
            }
        }
        .onChange(of: showsSettings) { _, visible in
            onSettingsPresented(visible)
        }
        .alignmentGuide(VerticalAlignment.center) { dimensions in
            dimensions[.top] + DaylineLayout.controlSize / 2
        }
    }

    private func sideButton(
        _ icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.84))
                .frame(width: DaylineLayout.controlSize, height: DaylineLayout.controlSize)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .glassCircle(nativeGlassStyle: store.nativeGlassStyle)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct EdgeHandle: View {
    @ObservedObject var store: TimelineStore
    let onClick: () -> Void
    let onDragChanged: (NSPoint) -> Void
    let onDragEnded: (NSPoint) -> Void

    private var pendingCount: Int {
        store.items.lazy.filter { !$0.isCompleted }.count
    }

    var body: some View {
        Text("\(pendingCount)")
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary.opacity(0.84))
            .frame(width: DaylineLayout.controlSize, height: DaylineLayout.controlSize)
            .glassCircle(nativeGlassStyle: store.nativeGlassStyle)
            .overlay {
                WindowDragSurface(
                    onClick: onClick,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onClick() }
            .help("点击收放 · 拖动停靠")
            .accessibilityLabel("时间轴还有 \(pendingCount) 项待办，点击收放，拖动改变位置")
    }
}

private struct SettingsPopover: View {
    @ObservedObject var store: TimelineStore
    @State private var launchAtLoginStatus = SMAppService.mainApp.status
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView { settingsContent }
            .frame(width: 238, height: 600)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("时间轴")
                .font(.custom("Songti SC", fixedSize: 18).weight(.semibold))

            VStack(alignment: .leading, spacing: 7) {
                Text("尺寸").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    Text("A").font(.system(size: 11, weight: .medium))
                    Slider(value: $store.fontSize, in: DaylineLayout.fontSizeRange, step: 0.5)
                        .controlSize(.small)
                        .accessibilityLabel("尺寸")
                    Text("A").font(.system(size: 18, weight: .medium))
                }
            }

            sliderSetting(
                "标题占高",
                value: $store.titleHeightRatio,
                in: DaylineLayout.titleHeightRatioRange,
                step: 0.01,
                text: "\(Int((store.titleHeightRatio * 100).rounded()))%"
            )

            sliderSetting(
                "标题最大宽度",
                value: $store.compactTitleWidth,
                in: DaylineLayout.compactTitleWidthRange,
                step: 4,
                text: "\(Int(store.compactTitleWidth.rounded()))",
                textWidth: 28,
                accessibilityLabel: "默认标题最大宽度"
            )

            sliderSetting(
                "时间轴高度",
                value: $store.panelHeightRatio,
                in: 0.6...1,
                step: 0.05,
                text: "\(Int((store.panelHeightRatio * 100).rounded()))%"
            )

            sliderSetting(
                "时间轴停靠位置",
                value: $store.timelineAnchorPosition,
                in: DaylineLayout.timelineAnchorPositionRange,
                step: 0.01,
                text: "\(Int((store.timelineAnchorPosition * 100).rounded()))%",
                accessibilityLabel: "时间轴停靠位置，从底部向上"
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("无操作后").font(.caption).foregroundStyle(.secondary)

                Picker("无操作后", selection: $store.autoReturnMode) {
                    Text("保持原位").tag(AutoReturnMode.off)
                    Text("回到现在").tag(AutoReturnMode.currentTime)
                    Text("首项任务").tag(AutoReturnMode.firstTodo)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(autoReturnDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    Slider(
                        value: $store.autoReturnDelay,
                        in: TimelineStore.autoReturnDelayRange,
                        step: 5
                    )
                    .controlSize(.small)
                    .accessibilityLabel("无操作后的等待秒数")
                    Text("\(Int(store.autoReturnDelay.rounded())) 秒")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                .disabled(store.autoReturnMode == .off)
                .opacity(store.autoReturnMode == .off ? 0.45 : 1)
            }

            sliderSetting(
                "单双击保护时间",
                value: $store.clickGuardDuration,
                in: TimelineStore.clickGuardDurationRange,
                step: 0.05,
                text: String(format: "%.2f s", store.clickGuardDuration)
            )

            Picker("玻璃材质", selection: $store.nativeGlassStyle) {
                Text("Regular").tag(NativeGlassStyle.regular)
                Text("Clear").tag(NativeGlassStyle.clear)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 7) {
                Text("时间显示").font(.caption).foregroundStyle(.secondary)
                Picker("时间显示", selection: $store.timeDisplayMode) {
                    Text("时刻").tag(TimeDisplayMode.absolute)
                    Text("剩余").tag(TimeDisplayMode.remaining)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("开机自动启动", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if let launchAtLoginNote {
                    Text(launchAtLoginNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                launchAtLoginError = nil
                refreshLaunchAtLogin()
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("时间范围").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Picker("开始", selection: startBinding) {
                        ForEach(Array(stride(from: 0, through: 23 * 60, by: 60)), id: \.self) {
                            Text(DayClock.displayRangeTime($0)).tag($0)
                        }
                    }
                    Picker("结束", selection: endBinding) {
                        ForEach(
                            Array(stride(from: store.timelineStartMinute + 60, through: 30 * 60, by: 60)),
                            id: \.self
                        ) {
                            Text(DayClock.displayRangeTime($0)).tag($0)
                        }
                    }
                }
                .labelsHidden()
            }

            Text("单轴循环 · 跨日不清空 · 任务持续保留")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("退出今日") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(16)
    }

    private func sliderSetting(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        text: String,
        textWidth: CGFloat = 42,
        accessibilityLabel: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 9) {
                Slider(value: value, in: range, step: step)
                    .controlSize(.small)
                    .accessibilityLabel(accessibilityLabel ?? title)
                Text(text)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: textWidth, alignment: .trailing)
            }
        }
    }

    private var autoReturnDescription: String {
        switch store.autoReturnMode {
        case .off:
            "时间轴保持在手动滚动后的位置"
        case .currentTime:
            "回到停靠位置，并随当前时间缓慢上移"
        case .firstTodo:
            "将下一项未完成任务吸附到停靠位置；无任务时回到现在"
        }
    }

    private var startBinding: Binding<Int> {
        Binding(get: { store.timelineStartMinute }, set: store.setTimelineStart)
    }

    private var endBinding: Binding<Int> {
        Binding(get: { store.timelineEndMinute }, set: store.setTimelineEnd)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
            },
            set: setLaunchAtLogin
        )
    }

    private var launchAtLoginNote: String? {
        if let launchAtLoginError { return launchAtLoginError }
        switch launchAtLoginStatus {
        case .requiresApproval:
            return "需要在系统设置的登录项中允许。"
        case .notFound:
            return "系统没有找到当前应用。"
        default:
            return nil
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    private func refreshLaunchAtLogin() {
        launchAtLoginStatus = SMAppService.mainApp.status
    }
}
