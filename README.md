# 今日（Dayline）

一个使用单根循环时间轴的原生 macOS 悬浮待办工具。

## 使用方式

- 点击加号，输入待办并按 Return；点击其他区域也会自动保存。
- 拖动胶囊可调整截止时间，自动吸附到 15 分钟刻度。
- 点击胶囊上的时间，可选择时间轴内的截止时间。
- 点击圆圈完成；待办会淡化并添加删除线。
- 点击边缘圆点收起或展开；拖动圆点可改变高度并自动贴到左右边缘。
- 单击时间轴窄带可切换“完整置顶 / 仅当前任务置顶”。
- 双击时间轴窄带可显示控制按钮；完整置顶时仍可显示或隐藏控制按钮。
- 设置中可调整整体尺寸、标题占高、收起标题最大宽度、时间轴高度、时间轴停靠位置、循环时间范围和开机自启动。

每条待办的时间都是截止时间，胶囊在时间轴上的位置就是它的截止刻度。
任务只保存在本机，并始终保持在时间轴的相对位置上。

### 核心规则

- “今日”是应用名，不是日期列表。
- 只有一条循环时间轴；跨日不清空，“次日”仍在同一条轴上。
- 任务和完成状态持续保留，直到被明确修改或删除。

## 本地构建

```zsh
scripts/make-icon.sh
scripts/build-app.sh
```

构建结果位于 `outputs/今日.app`。

## AI 与自动化接口

界面上能做的事都能通过 `dayline` 命令或 MCP 完成，不需要手动操作：

```zsh
dayline list --json                       # 待办、时间轴范围、现在、下一项、全部设置
dayline add --title "准备面试" --time 10:15
dayline add-many '[{"title":"写报告","time":"09:15"},{"title":"开会"}]'
dayline update <UUID> --title "进行模拟面试" --time 11:30
dayline complete <UUID>
dayline reopen <UUID>
dayline delete <UUID>
dayline range 07:00 25:00
dayline show [<UUID>|now]                 # 展开并滚到待办或现在
dayline settings                          # 读取全部设置
dayline set clockFormat twelveHour showsOverFullScreen true dockEdge right
```

可用设置项与取值见 `dayline help`。数值会限制在界面滑块的范围内；只要有一个
取值无效，整次修改都不生效。

App 内置标准输入输出 MCP 服务器 `dayline-mcp`，提供 `list_todos`、`add_todo`、
`add_todos`、`update_todo`、`set_todo_completed`、`delete_todo`、
`set_timeline_range`、`get_settings`、`update_settings` 和 `show_timeline`。

- `time` 一律表示截止时间，使用 15 分钟刻度；次日凌晨可写 `01:00` 或 `25:00`。
- `list_todos` 返回的 `timeline.now` 和 `timeline.nextTodoID` 已按 App 的循环规则
  算好，AI 修改任务前先调用它。
- `add_todos` 全部校验通过才添加；空闲刻度不够时整组不加。
- 失败的响应带 `errorCode`：`invalid_request`、`not_found`、`timeline_full`、
  `range_too_small`、`invalid_time`。删除成功会返回被删的待办，便于恢复。
- 接口始终使用 24 小时制，与界面的时钟设置无关。

CLI 与 MCP 都通过本地 `dayline://automation/v1` 协议交给运行中的 App 处理，
由 App 统一串行保存。

## 技术结构

- SwiftUI：胶囊、时间轴、编辑和设置界面
- AppKit `NSPanel`：透明悬浮窗口、跨桌面显示和窗口层级
- SwiftUI Liquid Glass：Regular / Clear 原生玻璃材质
- 本地 URL RPC + stdio MCP：AI 自动化接口
- 本地 JSON：保存当前循环时间轴任务与少量显示设置

开发入口与验证命令见 [开发指南](docs/DEVELOPMENT.md)。
