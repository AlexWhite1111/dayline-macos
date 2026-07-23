import AppKit
import ServiceManagement
import SwiftUI

struct RootView: View {
    @ObservedObject var store: TodayStore
    let onHandleClick: () -> Void
    let onHandleDragChanged: (NSPoint) -> Void
    let onHandleDragEnded: (NSPoint) -> Void
    let onSettingsPresented: (Bool) -> Void
    let onTimelineFirstSlotCenterChanged: (CGFloat) -> Void

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
        .onAppear(perform: seedFocus)
        .onChange(of: store.timelineStartMinute) { _, _ in seedFocus() }
        .onChange(of: store.timelineEndMinute) { _, _ in seedFocus() }
    }

    private var rail: some View {
        SideRail(
            store: store,
            onHandleClick: {
                commitEditing()
                onHandleClick()
            },
            onHandleDragChanged: onHandleDragChanged,
            onHandleDragEnded: { point in
                commitEditing()
                onHandleDragEnded(point)
            },
            onSettingsPresented: onSettingsPresented,
            onBeforeAction: commitEditing,
            onAdd: addTask
        )
        .frame(width: DaylineLayout.controlSize)
        .offset(y: store.railOffsetY)
    }

    private var timeline: some View {
        TimelineView(
            store: store,
            focusMinute: $store.focusMinute,
            onFirstSlotCenterChanged: onTimelineFirstSlotCenterChanged
        )
    }

    private func seedFocus() {
        let preferred = store.focusMinute
            ?? DayClock.minuteOfDay(dayEndMinute: store.timelineEndMinute)
        store.focusMinute = DayClock.quarterAtOrAfter(
            preferred,
            start: store.timelineStartMinute,
            end: store.timelineEndMinute
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
        store.editingID = store.addTask(at: minute)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func commitEditing() {
        store.commitEditing()
    }
}

private struct SideRail: View {
    @ObservedObject var store: TodayStore
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
                sideButton("plus", label: "添加今天的待办") {
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
    @ObservedObject var store: TodayStore
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
            .help("点击收放 · 拖动停靠")
            .accessibilityLabel("今日还有 \(pendingCount) 项待办，点击收放，拖动改变位置")
    }
}

private struct SettingsPopover: View {
    @ObservedObject var store: TodayStore
    @State private var launchAtLoginStatus = SMAppService.mainApp.status
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今天")
                .font(.custom("Songti SC", fixedSize: 18).weight(.semibold))

            VStack(alignment: .leading, spacing: 7) {
                Text("尺寸").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    Text("A").font(.system(size: 11, weight: .medium))
                    Slider(value: $store.fontSize, in: 13...19, step: 0.5)
                        .controlSize(.small)
                    Text("A").font(.system(size: 18, weight: .medium))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("标题占高").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    Slider(
                        value: $store.titleHeightRatio,
                        in: DaylineLayout.titleHeightRatioRange,
                        step: 0.01
                    )
                    .controlSize(.small)
                    Text("\(Int((store.titleHeightRatio * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("标题最大宽度").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    Slider(
                        value: $store.compactTitleWidth,
                        in: DaylineLayout.compactTitleWidthRange,
                        step: 4
                    )
                    .controlSize(.small)
                    .accessibilityLabel("默认标题最大宽度")
                    Text("\(Int(store.compactTitleWidth.rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("时间轴高度").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    Slider(value: $store.panelHeightRatio, in: 0.6...1, step: 0.05)
                        .controlSize(.small)
                    Text("\(Int((store.panelHeightRatio * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("时间轴停靠位置").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    Slider(
                        value: $store.timelineAnchorPosition,
                        in: DaylineLayout.timelineAnchorPositionRange,
                        step: 0.01
                    )
                    .controlSize(.small)
                    .accessibilityLabel("时间轴停靠位置，从底部向上")
                    Text("\(Int((store.timelineAnchorPosition * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("单双击保护时间").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 9) {
                    Slider(
                        value: $store.clickGuardDuration,
                        in: TodayStore.clickGuardDurationRange,
                        step: 0.05
                    )
                    .controlSize(.small)
                    Text(String(format: "%.2f s", store.clickGuardDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Picker("玻璃材质", selection: $store.nativeGlassStyle) {
                Text("Regular").tag(NativeGlassStyle.regular)
                Text("Clear").tag(NativeGlassStyle.clear)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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

            Text("拖动侧边圆点自动贴到最近边缘。结束时间前都属于当天。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("退出今日") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(16)
        .frame(width: 238)
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
