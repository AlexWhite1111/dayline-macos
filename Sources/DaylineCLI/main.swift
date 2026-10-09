import Darwin
import DaylineAutomation
import Foundation

private enum CLIError: LocalizedError {
    case usage(String)
    var errorDescription: String? {
        switch self { case .usage(let message): message }
    }
}

private let arguments = Array(CommandLine.arguments.dropFirst())

private func option(_ name: String) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard arguments.indices.contains(index + 1) else {
        throw CLIError.usage("\(name) 缺少值。")
    }
    return arguments[index + 1]
}

private func itemID(at index: Int) throws -> UUID {
    guard arguments.indices.contains(index), let value = UUID(uuidString: arguments[index]) else {
        throw CLIError.usage("缺少有效的待办 UUID。")
    }
    return value
}

private func request() throws -> DaylineAutomationRequest {
    guard let command = arguments.first else { throw CLIError.usage(help) }
    switch command {
    case "list":
        return DaylineAutomationRequest(action: .list)
    case "add":
        guard let title = try option("--title") else { throw CLIError.usage("add 需要 --title。") }
        return DaylineAutomationRequest(
            action: .add,
            itemID: UUID(),
            title: title,
            time: try option("--time")
        )
    case "update":
        return DaylineAutomationRequest(
            action: .update,
            itemID: try itemID(at: 1),
            title: try option("--title"),
            time: try option("--time")
        )
    case "complete":
        return DaylineAutomationRequest(
            action: .setCompleted,
            itemID: try itemID(at: 1),
            completed: true
        )
    case "reopen":
        return DaylineAutomationRequest(
            action: .setCompleted,
            itemID: try itemID(at: 1),
            completed: false
        )
    case "delete":
        return DaylineAutomationRequest(action: .delete, itemID: try itemID(at: 1))
    case "add-many":
        let json = arguments.count > 1
            ? arguments[1]
            : String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        guard let todos = try? JSONDecoder().decode([DaylineAutomationNewTodo].self, from: Data(json.utf8))
        else { throw CLIError.usage("add-many 需要 JSON 数组，如 '[{\"title\":\"读书\",\"time\":\"21:00\"}]'。") }
        return DaylineAutomationRequest(action: .addMany, todos: todos)
    case "range":
        guard arguments.count == 3 else { throw CLIError.usage("range 需要开始和结束整点，如 range 07:00 25:00。") }
        return DaylineAutomationRequest(action: .setTimelineRange, start: arguments[1], end: arguments[2])
    case "settings":
        return DaylineAutomationRequest(action: .updateSettings, settings: DaylineAutomationSettings())
    case "set":
        return DaylineAutomationRequest(action: .updateSettings, settings: try settingsFromPairs())
    case "show":
        let target = arguments.count > 1 && arguments[1] != "now" ? try itemID(at: 1) : nil
        return DaylineAutomationRequest(action: .show, itemID: target)
    default:
        throw CLIError.usage("未知命令：\(command)\n\n\(help)")
    }
}

/// `set key value [key value …]`: values parse as booleans or numbers when they can.
private func settingsFromPairs() throws -> DaylineAutomationSettings {
    let pairs = Array(arguments.dropFirst())
    guard !pairs.isEmpty, pairs.count.isMultiple(of: 2) else {
        throw CLIError.usage("set 需要成对的 <设置项> <值>。\n\n\(help)")
    }
    let known = Set(Mirror(reflecting: DaylineAutomationSettings()).children.compactMap(\.label))
    var object: [String: Any] = [:]
    for index in stride(from: 0, to: pairs.count, by: 2) {
        let key = pairs[index], raw = pairs[index + 1]
        guard known.contains(key) else {
            throw CLIError.usage("未知设置项：\(key)。可用：\(known.sorted().joined(separator: ", "))")
        }
        let value: Any = raw == "true" ? true : raw == "false" ? false : (Double(raw).map { $0 as Any } ?? raw)
        object[key] = value
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    do {
        return try JSONDecoder().decode(DaylineAutomationSettings.self, from: data)
    } catch {
        throw CLIError.usage("设置值类型不对：\(error.localizedDescription)")
    }
}

private func writeJSON(_ object: Any) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private let help = """
用法：
  dayline list --json
  dayline add --title <标题> [--time HH:mm]
  dayline update <UUID> [--title <标题>] [--time HH:mm]
  dayline complete <UUID>
  dayline reopen <UUID>
  dayline delete <UUID>
  dayline add-many '<JSON 数组>'        （或从标准输入读取）
  dayline range <开始 HH:00> <结束 HH:00>
  dayline show [<UUID>|now]
  dayline settings
  dayline set <设置项> <值> [<设置项> <值> …]

设置项：fontSize titleHeightRatio compactTitleWidth panelHeightRatio
  timelineAnchorPosition glassStyle(regular|clear) timeDisplay(absolute|remaining)
  clockFormat(system|twentyFourHour|twelveHour) pinsOnlyCurrentTask clickGuardDuration
  autoReturn(off|currentTime|firstTodo) autoReturnDelay showsOverFullScreen expanded
  controlsVisible dockEdge(left|right) dockPosition(0–1) launchAtLogin

规则：“今日”是应用名；单轴循环，跨日不清空；任务持续保留，直到明确修改或删除。
"""

if let command = arguments.first, ["help", "--help", "-h"].contains(command) {
    print(help)
    exit(EXIT_SUCCESS)
}

do {
    let response = try DaylineAutomationClient().perform(try request())
    FileHandle.standardOutput.write(try response.jsonData(pretty: true))
    FileHandle.standardOutput.write(Data([0x0A]))
    exit(response.ok ? EXIT_SUCCESS : EXIT_FAILURE)
} catch {
    writeJSON(["ok": false, "error": error.localizedDescription])
    exit(EXIT_FAILURE)
}
