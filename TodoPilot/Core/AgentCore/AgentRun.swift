import Foundation

enum AgentProvider: String, CaseIterable, Codable, Hashable, Sendable {
    case claudeCode = "CLAUDE_CODE"
    case codex = "CODEX"
    case cursor = "CURSOR"
}

enum AgentRunState: String, Codable, Equatable, Sendable {
    case running = "RUNNING"
    case terminal = "TERMINAL"
}

enum AgentRunOutcome: String, CaseIterable, Codable, Hashable, Sendable {
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case lost = "LOST"
}

enum AgentRunReminderState: String, CaseIterable, Codable, Equatable, Sendable {
    case none = "NONE"
    case pending = "PENDING"
    case unread = "UNREAD"
    case delivered = "DELIVERED"
    case expired = "EXPIRED"
}

enum AgentRunUserOverride: String, CaseIterable, Codable, Equatable, Sendable {
    case none = "NONE"
    case completed = "COMPLETED"
    case reopened = "REOPENED"
    case deleted = "DELETED"
}

struct AgentRun: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let provider: AgentProvider
    let sessionIdentityHash: String
    let turnIdentityHash: String?
    let workspaceDisplayName: String?
    let originBundleID: String?
    var originProcessID: Int32?
    var state: AgentRunState
    var outcome: AgentRunOutcome?
    let startedAt: Date
    var endedAt: Date?
    var lastEventAt: Date
    var userOverride: AgentRunUserOverride
    var reminderState: AgentRunReminderState

    init(
        id: UUID = UUID(),
        taskID: UUID = UUID(),
        provider: AgentProvider,
        sessionIdentityHash: String,
        turnIdentityHash: String? = nil,
        workspaceDisplayName: String? = nil,
        originBundleID: String? = nil,
        originProcessID: Int32? = nil,
        state: AgentRunState = .running,
        outcome: AgentRunOutcome? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        lastEventAt: Date,
        userOverride: AgentRunUserOverride = .none,
        reminderState: AgentRunReminderState = .none
    ) {
        self.id = id
        self.taskID = taskID
        self.provider = provider
        self.sessionIdentityHash = sessionIdentityHash
        self.turnIdentityHash = turnIdentityHash
        self.workspaceDisplayName = workspaceDisplayName
        self.originBundleID = originBundleID
        self.originProcessID = originProcessID
        self.state = state
        self.outcome = outcome
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastEventAt = lastEventAt
        self.userOverride = userOverride
        self.reminderState = reminderState
    }
}

struct AgentRunStartResult: Equatable {
    let run: AgentRun
    let wasInserted: Bool
}

enum AgentRunTerminalDisposition: Equatable {
    case updated
    case duplicate
    case orphaned
}

struct AgentRunTerminalResult: Equatable {
    let run: AgentRun?
    let disposition: AgentRunTerminalDisposition
}

struct AgentOrphanTerminalEvent: Equatable, Sendable {
    let provider: AgentProvider
    let outcome: AgentRunOutcome
    let observedAt: Date
}
