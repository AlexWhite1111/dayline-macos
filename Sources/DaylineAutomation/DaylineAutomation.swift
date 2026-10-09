import Foundation

public enum DaylineAutomationAction: String, Codable, Sendable {
    case list
    case add
    case update
    case setTimelineRange = "set-timeline-range"
    case setCompleted = "set-completed"
    case delete
    case addMany = "add-many"
    case updateSettings = "update-settings"
    case show
}

/// Machine-readable failure reasons carried in `DaylineAutomationResponse.errorCode`.
public enum DaylineAutomationErrorCode: String, Codable, Sendable {
    case invalidRequest = "invalid_request"
    case notFound = "not_found"
    case timelineFull = "timeline_full"
    case rangeTooSmall = "range_too_small"
    case invalidTime = "invalid_time"
}

public struct DaylineAutomationNewTodo: Codable, Sendable {
    public let title: String
    /// Deadline in `HH:mm`; omitted lets the app choose a free quarter.
    public let time: String?

    public init(title: String, time: String? = nil) {
        self.title = title
        self.time = time
    }
}

/// Every setting the UI exposes. Requests set only the fields to change; responses
/// return all of them. Enum-like strings use the app's raw values.
public struct DaylineAutomationSettings: Codable, Sendable, Equatable {
    public var fontSize: Double?
    public var titleHeightRatio: Double?
    public var compactTitleWidth: Double?
    public var panelHeightRatio: Double?
    public var timelineAnchorPosition: Double?
    /// `regular` or `clear`.
    public var glassStyle: String?
    /// `absolute` or `remaining`.
    public var timeDisplay: String?
    /// `system`, `twentyFourHour` or `twelveHour`.
    public var clockFormat: String?
    public var pinsOnlyCurrentTask: Bool?
    public var clickGuardDuration: Double?
    /// `off`, `currentTime` or `firstTodo`.
    public var autoReturn: String?
    public var autoReturnDelay: Double?
    public var showsOverFullScreen: Bool?
    public var expanded: Bool?
    public var controlsVisible: Bool?
    /// `left` or `right`.
    public var dockEdge: String?
    /// Vertical dock position, 0 at the bottom of the screen to 1 at the top.
    public var dockPosition: Double?
    public var launchAtLogin: Bool?

    public init() {}
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
    /// The todo deadline in `HH:mm` form on the configured cyclic timeline.
    public let time: String?
    public let start: String?
    public let end: String?
    public let completed: Bool?
    public let todos: [DaylineAutomationNewTodo]?
    public let settings: DaylineAutomationSettings?

    public init(
        requestID: UUID = UUID(),
        action: DaylineAutomationAction,
        itemID: UUID? = nil,
        title: String? = nil,
        time: String? = nil,
        start: String? = nil,
        end: String? = nil,
        completed: Bool? = nil,
        todos: [DaylineAutomationNewTodo]? = nil,
        settings: DaylineAutomationSettings? = nil
    ) {
        self.requestID = requestID
        self.action = action
        self.itemID = itemID
        self.title = title
        self.time = time
        self.start = start
        self.end = end
        self.completed = completed
        self.todos = todos
        self.settings = settings
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
        start = values["start"]
        end = values["end"]
        if let value = values["completed"] {
            switch value.lowercased() {
            case "true", "1": completed = true
            case "false", "0": completed = false
            default: throw DaylineAutomationError.invalidRequest("completed 必须是 true 或 false。")
            }
        } else {
            completed = nil
        }
        todos = try values["todos"].map { try Self.decodeJSON([DaylineAutomationNewTodo].self, $0) }
        settings = try values["settings"].map { try Self.decodeJSON(DaylineAutomationSettings.self, $0) }
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, _ value: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(value.utf8))
        } catch {
            throw DaylineAutomationError.invalidRequest("无法解析 JSON 参数：\(error.localizedDescription)")
        }
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
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
        if let start { query.append(URLQueryItem(name: "start", value: start)) }
        if let end { query.append(URLQueryItem(name: "end", value: end)) }
        if let completed {
            query.append(URLQueryItem(name: "completed", value: completed ? "true" : "false"))
        }
        if let todos { query.append(URLQueryItem(name: "todos", value: try Self.encodeJSON(todos))) }
        if let settings {
            query.append(URLQueryItem(name: "settings", value: try Self.encodeJSON(settings)))
        }
        components.queryItems = query
        guard let value = components.url else {
            throw DaylineAutomationError.invalidRequest("无法生成自动化 URL。")
        }
        return value
    }
}

public struct DaylineAutomationTimeline: Codable, Sendable {
    public let startMinute: Int
    public let endMinute: Int
    public let start: String
    public let end: String
    public let intervalMinutes: Int
    /// Current time on the cyclic timeline, including next-day overflow.
    public let nowMinute: Int
    public let now: String
    /// The next incomplete todo by the app's cyclic rule, wrapping past the end.
    public let nextTodoID: UUID?

    public init(
        startMinute: Int,
        endMinute: Int,
        start: String,
        end: String,
        intervalMinutes: Int,
        nowMinute: Int,
        now: String,
        nextTodoID: UUID?
    ) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.start = start
        self.end = end
        self.intervalMinutes = intervalMinutes
        self.nowMinute = nowMinute
        self.now = now
        self.nextTodoID = nextTodoID
    }
}

public struct DaylineAutomationTodo: Codable, Sendable {
    public let id: UUID
    public let title: String
    /// The deadline offset in minutes from midnight, including next-day overflow.
    public let minute: Int
    /// The todo deadline displayed on the configured cyclic timeline.
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
    public let timeline: DaylineAutomationTimeline?
    public let todos: [DaylineAutomationTodo]
    public let settings: DaylineAutomationSettings?
    public let message: String?
    public let error: String?
    public let errorCode: DaylineAutomationErrorCode?

    public init(
        ok: Bool,
        action: DaylineAutomationAction,
        timeline: DaylineAutomationTimeline? = nil,
        todos: [DaylineAutomationTodo] = [],
        settings: DaylineAutomationSettings? = nil,
        message: String? = nil,
        error: String? = nil,
        errorCode: DaylineAutomationErrorCode? = nil
    ) {
        self.ok = ok
        self.action = action
        self.timeline = timeline
        self.todos = todos
        self.settings = settings
        self.message = message
        self.error = error
        self.errorCode = errorCode
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
