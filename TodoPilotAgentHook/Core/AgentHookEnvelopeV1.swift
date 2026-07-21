import Foundation

enum AgentHookProvider: String, Codable, CaseIterable {
    case claudeCode = "CLAUDE_CODE"
    case codex = "CODEX"
    case cursor = "CURSOR"

    /// Codex Stop hooks require JSON on stdout when a command exits 0. An
    /// empty object is a no-op response and prevents Codex from reporting an
    /// otherwise successful TodoPilot delivery as a malformed hook result.
    var noOpSuccessOutput: Data? {
        self == .codex ? Data("{}\n".utf8) : nil
    }
}

enum AgentHookEvent: String, Codable, CaseIterable {
    case started
    case completed
    case failed
    case cancelled
    case sessionEnded
}

/// Privacy-minimised wire payload sent by the provider hook helper.
///
/// The payload intentionally has no field capable of carrying a full prompt,
/// response, transcript, source path, or arbitrary provider error message.
struct AgentHookEnvelopeV1: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let provider: AgentHookProvider
    let event: AgentHookEvent
    let sessionHash: String
    let turnHash: String?
    let title: String?
    let workspaceName: String?
    let occurredAt: Date
    let originBundleID: String?
    let originProcessID: Int32?
    let errorKind: String?

    init(
        provider: AgentHookProvider,
        event: AgentHookEvent,
        sessionHash: String,
        turnHash: String? = nil,
        title: String? = nil,
        workspaceName: String? = nil,
        occurredAt: Date,
        originBundleID: String? = nil,
        originProcessID: Int32? = nil,
        errorKind: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.provider = provider
        self.event = event
        self.sessionHash = sessionHash
        self.turnHash = turnHash
        self.title = title
        self.workspaceName = workspaceName
        self.occurredAt = occurredAt
        self.originBundleID = originBundleID
        self.originProcessID = originProcessID
        self.errorKind = errorKind
    }
}
