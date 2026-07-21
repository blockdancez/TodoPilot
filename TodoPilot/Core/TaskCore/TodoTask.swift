import Foundation

enum TodoTaskStatus: String, CaseIterable, Codable, Equatable {
    case todo = "TODO"
    case doing = "DOING"
    case done = "DONE"
    case snoozed = "SNOOZED"
    case archived = "ARCHIVED"

    var isActive: Bool {
        switch self {
        case .todo, .doing, .snoozed:
            true
        case .done, .archived:
            false
        }
    }
}

enum TodoTaskPriority: String, CaseIterable, Codable, Equatable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"

    var title: String {
        switch self {
        case .high:
            "High"
        case .medium:
            "Medium"
        case .low:
            "Low"
        }
    }

    var sortRank: Int {
        switch self {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
    }
}

enum TodoTaskSource: String, CaseIterable, Codable, Equatable {
    case manual = "MANUAL"
    case localCalendar = "LOCAL_CALENDAR"
    case codeAgent = "CODE_AGENT"

    init(storedValue: String?) {
        switch storedValue {
        case Self.localCalendar.rawValue, "CALENDAR", "REMINDER":
            self = .localCalendar
        case Self.codeAgent.rawValue:
            self = .codeAgent
        default:
            self = .manual
        }
    }
}

struct TodoTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var detail: String?
    var priority: TodoTaskPriority
    var dueAt: Date?
    var sourceQuote: String?
    var source: TodoTaskSource
    var sourceKey: String?
    var status: TodoTaskStatus
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        priority: TodoTaskPriority = .medium,
        dueAt: Date? = nil,
        sourceQuote: String? = nil,
        source: TodoTaskSource = .manual,
        sourceKey: String? = nil,
        status: TodoTaskStatus = .todo,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.priority = priority
        self.dueAt = dueAt
        self.sourceQuote = sourceQuote
        self.source = source
        self.sourceKey = sourceKey
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case priority
        case dueAt
        case sourceQuote
        case source
        case sourceKey
        case status
        case createdAt
        case updatedAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        priority = try container.decode(TodoTaskPriority.self, forKey: .priority)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        sourceQuote = try container.decodeIfPresent(String.self, forKey: .sourceQuote)
        if let storedSource = try container.decodeIfPresent(TodoTaskSource.self, forKey: .source) {
            source = storedSource
        } else {
            source = .manual
        }
        sourceKey = try container.decodeIfPresent(String.self, forKey: .sourceKey)
        status = try container.decode(TodoTaskStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encodeIfPresent(sourceQuote, forKey: .sourceQuote)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(sourceKey, forKey: .sourceKey)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    var shortTitle: String {
        if title.count <= 18 {
            return title
        }
        return String(title.prefix(18)) + "..."
    }

    func deadlineState(
        at now: Date = Date(),
        dueSoonInterval: TimeInterval = 2 * 60 * 60
    ) -> TodoTaskDeadlineState {
        guard deletedAt == nil, status.isActive, let dueAt else {
            return .none
        }

        if dueAt < now {
            return .overdue
        }

        if dueAt <= now.addingTimeInterval(dueSoonInterval) {
            return .dueSoon
        }

        return .scheduled
    }

    func isOverdue(at now: Date = Date()) -> Bool {
        deadlineState(at: now) == .overdue
    }

    func displayDeadlineState(
        at now: Date = Date(),
        dueSoonInterval: TimeInterval = 2 * 60 * 60
    ) -> TodoTaskDeadlineState {
        guard deletedAt == nil, let dueAt else {
            return .none
        }

        if dueAt < now {
            return .overdue
        }

        guard status.isActive else {
            return .scheduled
        }

        if dueAt <= now.addingTimeInterval(dueSoonInterval) {
            return .dueSoon
        }

        return .scheduled
    }
}

enum TodoTaskDeadlineState: Equatable {
    case none
    case scheduled
    case dueSoon
    case overdue
}

extension TodoTask {
    static let previewTasks: [TodoTask] = [
        TodoTask(
            title: "Freeze MVP scope",
            detail: "Align the first Alpha scope before P0 implementation.",
            priority: .high,
            dueAt: Date().addingTimeInterval(60 * 60)
        ),
        TodoTask(
            title: "Review privacy logging",
            detail: "Confirm OCR and task text stay out of logs.",
            priority: .high,
            dueAt: Date().addingTimeInterval(2 * 60 * 60)
        ),
        TodoTask(
            title: "Prepare capture milestone",
            priority: .medium,
            dueAt: Date().addingTimeInterval(4 * 60 * 60)
        )
    ]
}
