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
    case "help", "--help", "-h":
        throw CLIError.usage(help)
    default:
        throw CLIError.usage("未知命令：\(command)\n\n\(help)")
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
"""

do {
    let response = try DaylineAutomationClient().perform(try request())
    FileHandle.standardOutput.write(try response.jsonData(pretty: true))
    FileHandle.standardOutput.write(Data([0x0A]))
    exit(response.ok ? EXIT_SUCCESS : EXIT_FAILURE)
} catch {
    writeJSON(["ok": false, "error": error.localizedDescription])
    exit(EXIT_FAILURE)
}
