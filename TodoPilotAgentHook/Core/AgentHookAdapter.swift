import CryptoKit
import Foundation

enum AgentHookAdapterError: Error, Equatable {
    case invalidJSON
    case unsupportedEvent
    case missingSessionIdentifier
}

struct AgentHookAdapter {
    static let maximumTitleCharacters = 80

    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func envelope(from data: Data, provider: AgentHookProvider) throws -> AgentHookEnvelopeV1 {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any]
        else {
            throw AgentHookAdapterError.invalidJSON
        }

        guard let event = normalizedEvent(provider: provider, payload: payload) else {
            throw AgentHookAdapterError.unsupportedEvent
        }
        guard !Self.isExplicitNestedAgent(payload) else {
            throw AgentHookAdapterError.unsupportedEvent
        }
        guard let rawSessionID = sessionIdentifier(provider: provider, payload: payload) else {
            throw AgentHookAdapterError.missingSessionIdentifier
        }

        let rawTurnID = turnIdentifier(provider: provider, payload: payload)
        let title = localTitle(provider: provider, event: event, payload: payload)

        return AgentHookEnvelopeV1(
            provider: provider,
            event: event,
            sessionHash: Self.sha256(rawSessionID),
            turnHash: rawTurnID.map(Self.sha256),
            title: title,
            workspaceName: workspaceName(provider: provider, payload: payload),
            occurredAt: now(),
            errorKind: event == .failed ? "providerFailure" : nil
        )
    }

    private func normalizedEvent(
        provider: AgentHookProvider,
        payload: [String: Any]
    ) -> AgentHookEvent? {
        guard let hookName = Self.firstString(in: payload, keys: ["hook_event_name", "event_name", "event"]) else {
            return nil
        }

        switch provider {
        case .claudeCode:
            switch hookName.lowercased() {
            case "userpromptsubmit": return .started
            case "stop": return .completed
            case "stopfailure": return .failed
            case "sessionend": return .sessionEnded
            default: return nil
            }

        case .codex:
            switch hookName.lowercased() {
            case "userpromptsubmit": return .started
            case "stop": return .completed
            default: return nil
            }

        case .cursor:
            switch hookName.lowercased() {
            case "beforesubmitprompt": return .started
            case "sessionend":
                return Self.cursorTerminalEvent(
                    Self.firstString(in: payload, keys: ["reason", "final_status", "status"]),
                    unknown: .cancelled
                )
            case "stop":
                return Self.cursorTerminalEvent(
                    Self.firstString(in: payload, keys: ["status"]),
                    unknown: .failed
                )
            default:
                return nil
            }
        }
    }

    private func sessionIdentifier(
        provider: AgentHookProvider,
        payload: [String: Any]
    ) -> String? {
        let keys: [String]
        switch provider {
        case .claudeCode:
            keys = ["session_id"]
        case .codex:
            keys = ["session_id", "thread_id", "conversation_id"]
        case .cursor:
            keys = ["conversation_id", "session_id"]
        }
        return Self.firstString(in: payload, keys: keys)
    }

    private func turnIdentifier(
        provider: AgentHookProvider,
        payload: [String: Any]
    ) -> String? {
        switch provider {
        case .claudeCode:
            return Self.firstString(in: payload, keys: ["prompt_id", "turn_id"])
        case .codex:
            return Self.firstString(in: payload, keys: ["turn_id", "prompt_id"])
        case .cursor:
            return Self.firstString(in: payload, keys: ["generation_id", "turn_id"])
        }
    }

    private func localTitle(
        provider: AgentHookProvider,
        event: AgentHookEvent,
        payload: [String: Any]
    ) -> String? {
        // A title is derived only from a locally submitted prompt. Provider
        // output/error text is never used as a fallback.
        guard event == .started else { return nil }

        let promptKeys: [String]
        switch provider {
        case .claudeCode, .codex, .cursor:
            promptKeys = ["prompt", "user_prompt"]
        }

        guard let prompt = Self.firstString(in: payload, keys: promptKeys) else {
            return nil
        }
        return Self.firstNonemptySanitisedLine(prompt, maximumCharacters: Self.maximumTitleCharacters)
    }

    private func workspaceName(
        provider: AgentHookProvider,
        payload: [String: Any]
    ) -> String? {
        let rawPath: String?
        if provider == .cursor,
           let roots = payload["workspace_roots"] as? [Any] {
            rawPath = roots.compactMap { $0 as? String }.first(where: { !$0.isEmpty })
        } else {
            rawPath = Self.firstString(in: payload, keys: ["cwd", "workspace"])
        }

        guard let rawPath else { return nil }
        let basename = URL(fileURLWithPath: rawPath).lastPathComponent
        guard !basename.isEmpty, basename != "/" else { return nil }
        return Self.firstNonemptySanitisedLine(
            basename,
            maximumCharacters: Self.maximumTitleCharacters
        )
    }

    private static func firstString(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func cursorTerminalEvent(
        _ rawStatus: String?,
        unknown: AgentHookEvent
    ) -> AgentHookEvent {
        switch rawStatus?.lowercased() {
        case "completed": return .completed
        case "aborted", "cancelled", "canceled", "window_close", "user_close": return .cancelled
        case "error", "failed": return .failed
        default: return unknown
        }
    }

    private static func isExplicitNestedAgent(_ payload: [String: Any]) -> Bool {
        if payload["is_subagent"] as? Bool == true {
            return true
        }
        if firstString(in: payload, keys: ["parent_agent_id", "subagent_id"]) != nil {
            return true
        }
        if let agentType = firstString(in: payload, keys: ["agent_type", "agent_role"])?
            .lowercased(),
           agentType.contains("subagent") || agentType == "worker" {
            return true
        }
        return false
    }

    static func firstNonemptySanitisedLine(
        _ value: String,
        maximumCharacters: Int
    ) -> String? {
        for line in value.components(separatedBy: .newlines) {
            let withoutControls = String(
                line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            )
            let trimmed = withoutControls.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return String(trimmed.prefix(maximumCharacters))
        }
        return nil
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
