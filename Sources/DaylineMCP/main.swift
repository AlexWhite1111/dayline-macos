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
                "title": "今日待办",
                "version": "1.0.0",
                "description": "管理本机今日待办的本地 MCP 服务器"
            ],
            "instructions": "管理用户今天的待办。修改前先用 list_todos 获取 UUID；若目标不明确，先向用户确认。"
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
            guard title != nil || time != nil else {
                throw RPCError(code: -32602, message: "Provide title or time")
            }
            return DaylineAutomationRequest(action: .update, itemID: id, title: title, time: time)
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
        default:
            throw RPCError(code: -32602, message: "Unknown tool: \(tool)")
        }
    }

    private func string(_ name: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[name] as? String, !value.isEmpty else {
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
                title: "列出今日待办",
                description: "列出今天的全部待办及其 UUID、时间和完成状态。",
                properties: [:],
                required: [],
                readOnly: true
            ),
            tool(
                "add_todo",
                title: "添加今日待办",
                description: "添加一条今天的待办。time 可省略，格式为 HH:mm 且必须是 15 分钟刻度。",
                properties: [
                    "title": ["type": "string", "minLength": 1, "description": "待办标题"],
                    "time": timeSchema
                ],
                required: ["title"]
            ),
            tool(
                "update_todo",
                title: "修改今日待办",
                description: "按 UUID 修改待办标题、时间或两者。先调用 list_todos 获取 UUID。",
                properties: [
                    "id": idSchema,
                    "title": ["type": "string", "minLength": 1, "description": "新标题"],
                    "time": timeSchema
                ],
                required: ["id"]
            ),
            tool(
                "set_todo_completed",
                title: "设置完成状态",
                description: "按 UUID 将待办设为已完成或未完成。",
                properties: [
                    "id": idSchema,
                    "completed": ["type": "boolean", "description": "true 为完成，false 为恢复"]
                ],
                required: ["id", "completed"]
            ),
            tool(
                "delete_todo",
                title: "删除今日待办",
                description: "按 UUID 删除一条待办。",
                properties: ["id": idSchema],
                required: ["id"],
                destructive: true
            )
        ]
    }

    private func tool(
        _ name: String,
        title: String,
        description: String,
        properties: [String: Any],
        required: [String],
        readOnly: Bool = false,
        destructive: Bool = false
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
                "idempotentHint": readOnly,
                "openWorldHint": false
            ]
        ]
    }

    private var idSchema: [String: Any] {
        ["type": "string", "format": "uuid", "description": "list_todos 返回的待办 UUID"]
    }

    private var timeSchema: [String: Any] {
        [
            "type": "string",
            "pattern": "^(?:[0-2]?[0-9]|30):(?:00|15|30|45)$",
            "description": "24 小时制时间，如 10:15；次日凌晨也可写 01:00 或 25:00"
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
