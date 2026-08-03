import Foundation
import XCTest
@testable import TodoPilot

final class AgentHookAdapterTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testClaudeStartHashesIdentifiersAndMinimisesLocalFields() throws {
        let prompt = "\n\t\n  修复提醒状态\u{0007}  \n不应进入标题的第二行"
        let payload: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "raw-session-secret",
            "prompt_id": "raw-turn-secret",
            "prompt": prompt,
            "cwd": "/Users/private/work/TodoPilot",
            "transcript_path": "/Users/private/.claude/transcript.jsonl",
            "user_email": "private@example.com"
        ]

        let envelope = try makeAdapter().envelope(
            from: jsonData(payload),
            provider: .claudeCode
        )

        XCTAssertEqual(envelope.provider, .claudeCode)
        XCTAssertEqual(envelope.event, .started)
        XCTAssertEqual(envelope.sessionHash, AgentHookAdapter.sha256("raw-session-secret"))
        XCTAssertEqual(envelope.turnHash, AgentHookAdapter.sha256("raw-turn-secret"))
        XCTAssertEqual(envelope.title, "修复提醒状态")
        XCTAssertEqual(envelope.workspaceName, "TodoPilot")
        XCTAssertEqual(envelope.occurredAt, fixedDate)
        XCTAssertNil(envelope.errorKind)

        let encoded = try encodedEnvelope(envelope)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("raw-session-secret"))
        XCTAssertFalse(text.contains("raw-turn-secret"))
        XCTAssertFalse(text.contains("/Users/private"))
        XCTAssertFalse(text.contains("transcript"))
        XCTAssertFalse(text.contains("private@example.com"))
        XCTAssertFalse(text.contains("不应进入标题"))
        XCTAssertLessThanOrEqual(encoded.count, 16 * 1024)
    }

    func testClaudeLifecycleEvents() throws {
        let expectations: [(String, AgentHookEvent, String?)] = [
            ("Stop", .completed, nil),
            ("StopFailure", .failed, "providerFailure"),
            ("SessionEnd", .sessionEnded, nil)
        ]

        for (hookName, event, errorKind) in expectations {
            let envelope = try makeAdapter().envelope(
                from: jsonData([
                    "hook_event_name": hookName,
                    "session_id": "session",
                    "last_assistant_message": "Provider output must not become a title"
                ]),
                provider: .claudeCode
            )
            XCTAssertEqual(envelope.event, event)
            XCTAssertEqual(envelope.errorKind, errorKind)
            XCTAssertNil(envelope.title)
        }
    }

    func testClaudeSubagentPromptIsRejectedUsingOfficialAgentIdentifier() throws {
        let payload: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "session-root",
            "prompt_id": "prompt-child",
            "prompt": "synthetic child instruction",
            "agent_id": "agent-child",
            "agent_type": "Explore"
        ]

        XCTAssertThrowsError(
            try makeAdapter().envelope(from: jsonData(payload), provider: .claudeCode)
        ) { error in
            XCTAssertEqual(error as? AgentHookAdapterError, .unsupportedEvent)
        }
    }

    func testClaudeRootCustomAgentNamedWorkerIsAcceptedWithoutAgentIdentifier() throws {
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "session_id": "session-root",
                "prompt_id": "prompt-root",
                "prompt": "root instruction",
                "agent_type": "worker"
            ]),
            provider: .claudeCode
        )

        XCTAssertEqual(envelope.event, .started)
        XCTAssertEqual(envelope.title, "root instruction")
    }

    func testCodexUsesThreadAndTurnIdentifiers() throws {
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "thread_id": "thread-123",
                "turn_id": "turn-456",
                "prompt": "Review the installer\nwith all source included",
                "cwd": "/tmp/Workspace Name"
            ]),
            provider: .codex
        )

        XCTAssertEqual(envelope.event, .started)
        XCTAssertEqual(envelope.sessionHash, AgentHookAdapter.sha256("thread-123"))
        XCTAssertEqual(envelope.turnHash, AgentHookAdapter.sha256("turn-456"))
        XCTAssertEqual(envelope.title, "Review the installer")
        XCTAssertEqual(envelope.workspaceName, "Workspace Name")
    }

    func testCodexRootPromptTextIsNotUsedAsASubagentHeuristic() throws {
        for prompt in ["# Overview", "You are an expert at synthetic review"] {
            let envelope = try makeAdapter().envelope(
                from: jsonData([
                    "hook_event_name": "UserPromptSubmit",
                    "session_id": "session-root",
                    "turn_id": "turn-root-\(prompt)",
                    "prompt": prompt,
                    "cwd": "/tmp/project",
                    "model": "synthetic-model",
                    "permission_mode": "default",
                    "transcript_path": "/tmp/synthetic-transcript.jsonl"
                ]),
                provider: .codex
            )

            XCTAssertEqual(envelope.event, .started)
            XCTAssertEqual(envelope.title, prompt)
        }
    }

    func testCodexAttachmentWrapperUsesActualRequestAsTitle() throws {
        let prompt = """
        # Files mentioned by the user:

        ## example.png: /private/tmp/example.png

        ## My request for Codex:
        修复 OCR 弹框的额度展示
        """
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "thread_id": "thread-with-attachment",
                "turn_id": "turn-with-attachment",
                "prompt": prompt
            ]),
            provider: .codex
        )

        XCTAssertEqual(envelope.title, "修复 OCR 弹框的额度展示")
        let encoded = String(decoding: try encodedEnvelope(envelope), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Files mentioned by the user"))
        XCTAssertFalse(encoded.contains("/private/tmp/example.png"))
    }

    func testIncompleteCodexAttachmentWrapperDoesNotUseAttachmentMetadataAsTitle() throws {
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "thread_id": "thread-with-incomplete-attachment",
                "turn_id": "turn-with-incomplete-attachment",
                "prompt": "# Files mentioned by the user:\n\n## example.png: /private/tmp/example.png"
            ]),
            provider: .codex
        )

        XCTAssertNil(envelope.title)
        let encoded = String(decoding: try encodedEnvelope(envelope), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Files mentioned by the user"))
        XCTAssertFalse(encoded.contains("/private/tmp/example.png"))
    }

    func testCodexStopMapsToCompletedForMatchingTurn() throws {
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "Stop",
                "thread_id": "thread-123",
                "turn_id": "turn-456"
            ]),
            provider: .codex
        )

        XCTAssertEqual(envelope.event, .completed)
        XCTAssertEqual(envelope.sessionHash, AgentHookAdapter.sha256("thread-123"))
        XCTAssertEqual(envelope.turnHash, AgentHookAdapter.sha256("turn-456"))
    }

    func testCodexPromptFromAmbientSubagentIsRejected() throws {
        let payload: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "session-root",
            "turn_id": "turn-child",
            "prompt": "synthetic child instruction",
            "agent_id": "agent-child",
            "agent_type": "ambient"
        ]

        XCTAssertThrowsError(
            try makeAdapter().envelope(from: jsonData(payload), provider: .codex)
        ) { error in
            XCTAssertEqual(error as? AgentHookAdapterError, .unsupportedEvent)
        }
    }

    func testCursorStopStatusMapsToTerminalEvent() throws {
        let cases: [(String, AgentHookEvent)] = [
            ("completed", .completed),
            ("aborted", .cancelled),
            ("error", .failed),
            ("future_status", .failed)
        ]

        for (status, expectedEvent) in cases {
            let envelope = try makeAdapter().envelope(
                from: jsonData([
                    "hook_event_name": "stop",
                    "conversation_id": "cursor-conversation",
                    "generation_id": "generation",
                    "status": status,
                    "workspace_roots": ["/Users/private/project"]
                ]),
                provider: .cursor
            )
            XCTAssertEqual(envelope.event, expectedEvent)
            XCTAssertEqual(envelope.workspaceName, "project")
        }
    }

    func testCursorSessionEndReasonProvidesFallbackTerminalOutcome() throws {
        let cases: [(String, AgentHookEvent)] = [
            ("completed", .completed),
            ("aborted", .cancelled),
            ("error", .failed),
            ("window_close", .cancelled)
        ]

        for (reason, expectedEvent) in cases {
            let envelope = try makeAdapter().envelope(
                from: jsonData([
                    "hook_event_name": "sessionEnd",
                    "conversation_id": "cursor-conversation",
                    "generation_id": "generation",
                    "reason": reason,
                    "is_background_agent": false
                ]),
                provider: .cursor
            )
            XCTAssertEqual(envelope.event, expectedEvent)
        }
    }

    func testCursorBackgroundSessionEndIsRejected() throws {
        let payload: [String: Any] = [
            "hook_event_name": "sessionEnd",
            "conversation_id": "background-conversation",
            "reason": "completed",
            "is_background_agent": true
        ]

        XCTAssertThrowsError(
            try makeAdapter().envelope(from: jsonData(payload), provider: .cursor)
        ) { error in
            XCTAssertEqual(error as? AgentHookAdapterError, .unsupportedEvent)
        }
    }

    func testCursorPromptWithExplicitSubagentMetadataIsRejected() throws {
        let metadataCases: [[String: Any]] = [
            ["is_parallel_worker": true],
            ["parent_conversation_id": "parent-conversation"],
            ["subagent_id": "subagent-child"],
            ["subagent_type": "generalPurpose"]
        ]

        for metadata in metadataCases {
            var payload: [String: Any] = [
                "hook_event_name": "beforeSubmitPrompt",
                "conversation_id": "child-conversation",
                "generation_id": "child-generation",
                "prompt": "synthetic child instruction"
            ]
            metadata.forEach { payload[$0.key] = $0.value }

            XCTAssertThrowsError(
                try makeAdapter().envelope(from: jsonData(payload), provider: .cursor)
            ) { error in
                XCTAssertEqual(error as? AgentHookAdapterError, .unsupportedEvent)
            }
        }
    }

    func testOnlyCodexEmitsNoOpJSONForSuccessfulHookCompletion() {
        XCTAssertEqual(String(data: AgentHookProvider.codex.noOpSuccessOutput!, encoding: .utf8), "{}\n")
        XCTAssertNil(AgentHookProvider.claudeCode.noOpSuccessOutput)
        XCTAssertNil(AgentHookProvider.cursor.noOpSuccessOutput)
    }

    func testTitleLimitCountsSwiftCharacters() throws {
        let title = String(repeating: "👩🏽‍💻", count: 81)
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "beforeSubmitPrompt",
                "conversation_id": "cursor-conversation",
                "prompt": title
            ]),
            provider: .cursor
        )

        XCTAssertEqual(envelope.title?.count, 80)
    }

    func testMissingSessionAndUnsupportedEventsAreRejected() throws {
        XCTAssertThrowsError(
            try makeAdapter().envelope(
                from: jsonData(["hook_event_name": "Stop"]),
                provider: .codex
            )
        ) { error in
            XCTAssertEqual(error as? AgentHookAdapterError, .missingSessionIdentifier)
        }

        XCTAssertThrowsError(
            try makeAdapter().envelope(
                from: jsonData([
                    "hook_event_name": "PreToolUse",
                    "session_id": "session"
                ]),
                provider: .claudeCode
            )
        ) { error in
            XCTAssertEqual(error as? AgentHookAdapterError, .unsupportedEvent)
        }
    }

    func testExplicitSubagentSubmitIsRejected() throws {
        let payload: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "session-root",
            "turn_id": "turn-child",
            "prompt": "child work",
            "is_subagent": true
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try AgentHookAdapter().envelope(from: data, provider: .codex)) { error in
            XCTAssertEqual(error as? AgentHookAdapterError, .unsupportedEvent)
        }
    }

    private func makeAdapter() -> AgentHookAdapter {
        AgentHookAdapter(now: { self.fixedDate })
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func encodedEnvelope(_ envelope: AgentHookEnvelopeV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }
}
