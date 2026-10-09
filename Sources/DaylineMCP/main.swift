import Darwin
import DaylineAutomation
import Foundation

private final class MCPServer {
    private let client = DaylineAutomationClient()
    private let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    func run() {
        while let line = readLine() {
            guard !line.isEmpty else { continue }
            do {
                let data = Data(line.utf8)
                guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { throw RPCError(code: -32600, message: "Invalid Request") }
                handle(message)
            } catch let error as RPCError {
                write(errorResponse(id: NSNull(), error: error))
            } catch {
                write(errorResponse(id: NSNull(), error: RPCError(code: -32700, message: "Parse error")))
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            write(errorResponse(id: message["id"] ?? NSNull(), error: RPCError(code: -32600, message: "Invalid Request")))
            return
        }
        guard let id = message["id"] else { return }

        do {
            let result: [String: Any]
            switch method {
            case "initialize": result = initialize(message["params"] as? [String: Any])
            case "ping": result = [:]
            case "tools/list": result = ["tools": tools]
            case "tools/call": result = try callTool(message["params"] as? [String: Any])
            default: throw RPCError(code: -32601, message: "Method not found: \(method)")
            }
            write(["jsonrpc": "2.0", "id": id, "result": result])
        } catch let error as RPCError {
            write(errorResponse(id: id, error: error))
        } catch {
            write(errorResponse(id: id, error: RPCError(code: -32603, message: error.localizedDescription)))
        }
    }

    private func initialize(_ params: [String: Any]?) -> [String: Any] {
        let requested = params?["protocolVersion"] as? String ?? supportedVersions[0]
        let version = supportedVersions.contains(requested) ? requested : supportedVersions[0]
        return [
            "protocolVersion": version,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": [
                "name": "dayline-mcp",
                "title": "Dayline 待办",
                "version": "1.2.0",
                "description": "管理本机循环时间轴和待办"
            ],
            "instructions": "先调用 list_todos；time 是截止时间。《今日》只有一条循环时间轴，跨日不清空，“次日”仍在同一条轴上。list_todos 的 timeline.now 和 timeline.nextTodoID 已按 App 的循环规则算好，直接使用，不要自己推算。任务和完成状态持续保留，直到被明确修改或删除。界面能做的设置都能用 update_settings 完成；失败时看 errorCode。"
        ]
    }

    private func callTool(_ params: [String: Any]?) throws -> [String: Any] {
        guard let name = params?["name"] as? String else {
            throw RPCError(code: -32602, message: "Missing tool name")
        }
        let arguments = params?["arguments"] as? [String: Any] ?? [:]
        let request = try request(for: name, arguments: arguments)
        do {
            let response = try client.perform(request)
            let object = try response.jsonObject()
            return [
                "content": [["type": "text", "text": try response.jsonString()]],
                "structuredContent": object,
                "isError": !response.ok
            ]
        } catch {
            let object: [String: Any] = ["ok": false, "error": error.localizedDescription]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return [
                "content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
                "structuredContent": object,
                "isError": true
            ]
        }
    }

    private func request(
        for tool: String,
        arguments: [String: Any]
    ) throws -> DaylineAutomationRequest {
        switch tool {
        case "list_todos":
            return DaylineAutomationRequest(action: .list)
        case "add_todo":
            let title = try string("title", in: arguments)
            return DaylineAutomationRequest(
                action: .add,
                itemID: UUID(),
                title: title,
                time: arguments["time"] as? String
            )
        case "update_todo":
            let id = try uuid(in: arguments)
            let title = arguments["title"] as? String
            let time = arguments["time"] as? String
            return DaylineAutomationRequest(action: .update, itemID: id, title: title, time: time)
        case "set_timeline_range":
            return DaylineAutomationRequest(
                action: .setTimelineRange,
                start: try string("start", in: arguments),
                end: try string("end", in: arguments)
            )
        case "set_todo_completed":
            guard let completed = arguments["completed"] as? Bool else {
                throw RPCError(code: -32602, message: "Missing completed")
            }
            return DaylineAutomationRequest(
                action: .setCompleted,
                itemID: try uuid(in: arguments),
                completed: completed
            )
        case "delete_todo":
            return DaylineAutomationRequest(action: .delete, itemID: try uuid(in: arguments))
        case "add_todos":
            guard let items = arguments["todos"] as? [[String: Any]], !items.isEmpty else {
                throw RPCError(code: -32602, message: "Missing todos")
            }
            let todos = try items.map { item -> DaylineAutomationNewTodo in
                guard let title = item["title"] as? String else {
                    throw RPCError(code: -32602, message: "Each todo needs a title")
                }
                return DaylineAutomationNewTodo(title: title, time: item["time"] as? String)
            }
            return DaylineAutomationRequest(action: .addMany, todos: todos)
        case "get_settings":
            return DaylineAutomationRequest(action: .updateSettings, settings: DaylineAutomationSettings())
        case "update_settings":
            let data = try JSONSerialization.data(withJSONObject: arguments)
            guard let settings = try? JSONDecoder().decode(DaylineAutomationSettings.self, from: data) else {
                throw RPCError(code: -32602, message: "Invalid settings value type")
            }
            return DaylineAutomationRequest(action: .updateSettings, settings: settings)
        case "show_timeline":
            let id = try (arguments["id"] as? String).map { value -> UUID in
                guard let id = UUID(uuidString: value) else {
                    throw RPCError(code: -32602, message: "Invalid id")
                }
                return id
            }
            return DaylineAutomationRequest(action: .show, itemID: id)
        default:
            throw RPCError(code: -32602, message: "Unknown tool: \(tool)")
        }
    }

    private func string(_ name: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[name] as? String else {
            throw RPCError(code: -32602, message: "Missing \(name)")
        }
        return value
    }

    private func uuid(in arguments: [String: Any]) throws -> UUID {
        guard let value = arguments["id"] as? String, let id = UUID(uuidString: value) else {
            throw RPCError(code: -32602, message: "Missing or invalid id")
        }
        return id
    }

    private var tools: [[String: Any]] {
        [
            tool(
                "list_todos",
                title: "列出时间轴待办",
                description: "返回时间轴范围、15 分钟间隔和全部待办。",
                properties: [:],
                required: [],
                readOnly: true,
                destructive: false,
                idempotent: true
            ),
            tool(
                "set_timeline_range",
                title: "设置时间轴范围",
                description: "设置时间轴范围；现有待办会调整到新范围内。",
                properties: [
                    "start": startTimeSchema,
                    "end": endTimeSchema
                ],
                required: ["start", "end"],
                readOnly: false,
                destructive: true,
                idempotent: true
            ),
            tool(
                "add_todo",
                title: "添加时间轴待办",
                description: "添加待办；time 是截止时间，省略时由 App 选择空闲刻度。",
                properties: [
                    "title": ["type": "string", "minLength": 1, "description": "待办标题"],
                    "time": timeSchema
                ],
                required: ["title"],
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                "update_todo",
                title: "修改时间轴待办",
                description: "按 UUID 修改标题或截止时间。",
                properties: [
                    "id": idSchema,
                    "title": ["type": "string", "minLength": 1, "description": "新标题"],
                    "time": timeSchema
                ],
                required: ["id"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "set_todo_completed",
                title: "设置完成状态",
                description: "按 UUID 设置完成状态。",
                properties: [
                    "id": idSchema,
                    "completed": ["type": "boolean", "description": "true 为完成，false 为恢复"]
                ],
                required: ["id", "completed"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "add_todos",
                title: "批量添加待办",
                description: "一次添加多条待办，适合排一天的计划。全部校验通过才添加；空闲刻度不够时整组不加，返回 timeline_full。",
                properties: [
                    "todos": [
                        "type": "array",
                        "minItems": 1,
                        "items": [
                            "type": "object",
                            "properties": [
                                "title": ["type": "string", "minLength": 1, "description": "待办标题"],
                                "time": timeSchema
                            ],
                            "required": ["title"],
                            "additionalProperties": false
                        ]
                    ]
                ],
                required: ["todos"],
                readOnly: false,
                destructive: false,
                idempotent: false
            ),
            tool(
                "get_settings",
                title: "读取设置",
                description: "返回全部设置的当前值，字段与 update_settings 相同。",
                properties: [:],
                required: [],
                readOnly: true,
                destructive: false,
                idempotent: true
            ),
            tool(
                "update_settings",
                title: "修改设置",
                description: "修改界面中的任意设置，只传要改的字段；数值会限制在界面允许的范围内。返回修改后的全部设置。",
                properties: settingsSchema,
                required: [],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "show_timeline",
                title: "显示时间轴",
                description: "展开时间轴并移到最前，滚动到指定待办；不传 id 时回到现在。",
                properties: ["id": idSchema],
                required: [],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "delete_todo",
                title: "删除时间轴待办",
                description: "按 UUID 删除待办。",
                properties: ["id": idSchema],
                required: ["id"],
                readOnly: false,
                destructive: true,
                idempotent: false
            )
        ]
    }

    private func tool(
        _ name: String,
        title: String,
        description: String,
        properties: [String: Any],
        required: [String],
        readOnly: Bool,
        destructive: Bool,
        idempotent: Bool
    ) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false
            ],
            "annotations": [
                "readOnlyHint": readOnly,
                "destructiveHint": destructive,
                "idempotentHint": idempotent,
                "openWorldHint": false
            ]
        ]
    }

    private var settingsSchema: [String: Any] {
        func number(_ range: String, _ text: String) -> [String: Any] {
            ["type": "number", "description": "\(text)（\(range)）"]
        }
        func choice(_ values: [String], _ text: String) -> [String: Any] {
            ["type": "string", "enum": values, "description": text]
        }
        func flag(_ text: String) -> [String: Any] { ["type": "boolean", "description": text] }
        return [
            "fontSize": number("7–19", "尺寸"),
            "titleHeightRatio": number("0.4–0.75", "标题占胶囊高度的比例"),
            "compactTitleWidth": number("80–300", "标题最大宽度"),
            "panelHeightRatio": number("0.6–1", "时间轴占屏幕高度的比例"),
            "timelineAnchorPosition": number("0–1", "时间轴停靠位置，从底部向上"),
            "glassStyle": choice(["regular", "clear"], "玻璃材质"),
            "timeDisplay": choice(["absolute", "remaining"], "显示时刻或剩余时间"),
            "clockFormat": choice(["system", "twentyFourHour", "twelveHour"], "时钟制式"),
            "pinsOnlyCurrentTask": flag("只置顶当前任务"),
            "clickGuardDuration": number("0–0.6 秒", "单双击保护时间"),
            "autoReturn": choice(["off", "currentTime", "firstTodo"], "无操作后：保持原位、回到现在或首项任务"),
            "autoReturnDelay": number("5–300 秒", "无操作等待时间"),
            "showsOverFullScreen": flag("全屏应用上也显示"),
            "expanded": flag("展开时间轴"),
            "controlsVisible": flag("显示侧边控制栏"),
            "dockEdge": choice(["left", "right"], "停靠在屏幕左侧或右侧"),
            "dockPosition": number("0–1", "停靠的垂直位置，0 为屏幕底部"),
            "launchAtLogin": flag("开机自动启动")
        ]
    }

    private var idSchema: [String: Any] {
        ["type": "string", "format": "uuid", "description": "list_todos 返回的待办 UUID"]
    }

    private var timeSchema: [String: Any] {
        [
            "type": "string",
            "pattern": "^(?:(?:[0-2]?[0-9]):(?:00|15|30|45)|30:00)$",
            "description": "待办截止时间，使用 15 分钟刻度，如 10:15；次日凌晨可写 01:00 或 25:00"
        ]
    }

    private var startTimeSchema: [String: Any] {
        [
            "type": "string",
            "pattern": "^(?:[01]?[0-9]|2[0-3]):00$",
            "description": "时间轴开始整点，如 07:00"
        ]
    }

    private var endTimeSchema: [String: Any] {
        [
            "type": "string",
            "pattern": "^(?:(?:[01]?[0-9]|2[0-9]):00|30:00)$",
            "description": "时间轴结束整点，如 23:00；次日凌晨可写 01:00 或 25:00"
        ]
    }

    private func errorResponse(id: Any, error: RPCError) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": error.code, "message": error.message]
        ]
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private struct RPCError: Error {
        let code: Int
        let message: String
    }
}

MCPServer().run()
