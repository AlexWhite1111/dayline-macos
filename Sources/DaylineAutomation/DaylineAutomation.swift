import Foundation

public enum DaylineAutomationAction: String, Codable, Sendable {
    case list
    case add
    case update
    case setCompleted = "set-completed"
    case delete
}

public enum DaylineAutomationError: LocalizedError {
    case invalidRequest(String)
    case launchFailed
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): message
        case .launchFailed: "无法打开今日 App。"
        case .timeout: "今日 App 没有及时返回结果。"
        }
    }
}

public struct DaylineAutomationRequest: Codable, Sendable {
    public let requestID: UUID
    public let action: DaylineAutomationAction
    public let itemID: UUID?
    public let title: String?
    public let time: String?
    public let completed: Bool?

    public init(
        requestID: UUID = UUID(),
        action: DaylineAutomationAction,
        itemID: UUID? = nil,
        title: String? = nil,
        time: String? = nil,
        completed: Bool? = nil
    ) {
        self.requestID = requestID
        self.action = action
        self.itemID = itemID
        self.title = title
        self.time = time
        self.completed = completed
    }

    public init(url: URL) throws {
        guard
            url.scheme?.lowercased() == "dayline",
            url.host?.lowercased() == "automation",
            url.path == "/v1",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw DaylineAutomationError.invalidRequest("不支持的自动化 URL。")
        }

        var values: [String: String] = [:]
        components.queryItems?.forEach { item in
            if let value = item.value { values[item.name] = value }
        }
        guard let requestValue = values["request"], let requestID = UUID(uuidString: requestValue)
        else { throw DaylineAutomationError.invalidRequest("缺少有效的 request。") }
        guard let actionValue = values["action"], let action = DaylineAutomationAction(rawValue: actionValue)
        else { throw DaylineAutomationError.invalidRequest("缺少有效的 action。") }

        self.requestID = requestID
        self.action = action
        itemID = values["id"].flatMap(UUID.init(uuidString:))
        title = values["title"]
        time = values["time"]
        if let value = values["completed"] {
            switch value.lowercased() {
            case "true", "1": completed = true
            case "false", "0": completed = false
            default: throw DaylineAutomationError.invalidRequest("completed 必须是 true 或 false。")
            }
        } else {
            completed = nil
        }
    }

    public func url() throws -> URL {
        var components = URLComponents()
        components.scheme = "dayline"
        components.host = "automation"
        components.path = "/v1"
        var query = [
            URLQueryItem(name: "request", value: requestID.uuidString),
            URLQueryItem(name: "action", value: action.rawValue)
        ]
        if let itemID { query.append(URLQueryItem(name: "id", value: itemID.uuidString)) }
        if let title { query.append(URLQueryItem(name: "title", value: title)) }
        if let time { query.append(URLQueryItem(name: "time", value: time)) }
        if let completed {
            query.append(URLQueryItem(name: "completed", value: completed ? "true" : "false"))
        }
        components.queryItems = query
        guard let value = components.url else {
            throw DaylineAutomationError.invalidRequest("无法生成自动化 URL。")
        }
        return value
    }
}

public struct DaylineAutomationTodo: Codable, Sendable {
    public let id: UUID
    public let title: String
    public let minute: Int
    public let time: String
    public let completed: Bool
    public let createdAt: Date

    public init(
        id: UUID,
        title: String,
        minute: Int,
        time: String,
        completed: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.minute = minute
        self.time = time
        self.completed = completed
        self.createdAt = createdAt
    }
}

public struct DaylineAutomationResponse: Codable, Sendable {
    public let ok: Bool
    public let action: DaylineAutomationAction
    public let todos: [DaylineAutomationTodo]
    public let message: String?
    public let error: String?

    public init(
        ok: Bool,
        action: DaylineAutomationAction,
        todos: [DaylineAutomationTodo] = [],
        message: String? = nil,
        error: String? = nil
    ) {
        self.ok = ok
        self.action = action
        self.todos = todos
        self.message = message
        self.error = error
    }

    public func jsonData(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(self)
    }

    public func jsonString(pretty: Bool = false) throws -> String {
        String(decoding: try jsonData(pretty: pretty), as: UTF8.self)
    }

    public func jsonObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: jsonData())
        guard let dictionary = object as? [String: Any] else {
            throw DaylineAutomationError.invalidRequest("无法生成 JSON 结果。")
        }
        return dictionary
    }
}

public enum DaylineAutomationResponses {
    public static func write(_ response: DaylineAutomationResponse, for requestID: UUID) throws {
        let directory = responseDirectory
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try response.jsonData().write(to: url(for: requestID), options: .atomic)
    }

    fileprivate static func take(for requestID: UUID) throws -> DaylineAutomationResponse? {
        let responseURL = url(for: requestID)
        guard FileManager.default.fileExists(atPath: responseURL.path) else { return nil }
        let data = try Data(contentsOf: responseURL)
        try? FileManager.default.removeItem(at: responseURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DaylineAutomationResponse.self, from: data)
    }

    fileprivate static func discard(_ requestID: UUID) {
        try? FileManager.default.removeItem(at: url(for: requestID))
    }

    private static func url(for requestID: UUID) -> URL {
        responseDirectory.appendingPathComponent(requestID.uuidString + ".json")
    }

    private static var responseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayline", isDirectory: true)
            .appendingPathComponent("AutomationResponses", isDirectory: true)
    }
}

public struct DaylineAutomationClient {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    public func perform(_ request: DaylineAutomationRequest) throws -> DaylineAutomationResponse {
        DaylineAutomationResponses.discard(request.requestID)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", try request.url().absoluteString]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DaylineAutomationError.launchFailed }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let response = try DaylineAutomationResponses.take(for: request.requestID) {
                return response
            }
            Thread.sleep(forTimeInterval: 0.02)
        } while Date() < deadline

        throw DaylineAutomationError.timeout
    }
}
