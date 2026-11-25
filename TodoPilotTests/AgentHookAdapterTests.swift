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
        let transcript = try makeCodexTranscript(sessionID: "thread-123")
        defer { try? FileManager.default.removeItem(at: transcript) }
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "transcript_path": transcript.path,
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
        let transcript = try makeCodexTranscript(sessionID: "session-root")
        defer { try? FileManager.default.removeItem(at: transcript) }
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
                    "transcript_path": transcript.path
                ]),
                provider: .codex
            )

            XCTAssertEqual(envelope.event, .started)
            XCTAssertEqual(envelope.title, prompt)
        }
    }

    func testCodexAttachmentWrapperUsesActualRequestAsTitle() throws {
        let transcript = try makeCodexTranscript(sessionID: "thread-with-attachment")
        defer { try? FileManager.default.removeItem(at: transcript) }
        let prompt = """
        # Files mentioned by the user:

        ## example.png: /private/tmp/example.png

        ## My request for Codex:
        修复 OCR 弹框的额度展示
        """
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "transcript_path": transcript.path,
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
        let transcript = try makeCodexTranscript(sessionID: "thread-with-incomplete-attachment")
        defer { try? FileManager.default.removeItem(at: transcript) }
        let envelope = try makeAdapter().envelope(
            from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "transcript_path": transcript.path,
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

    func testProvidersWithJSONResponseContractsEmitAnEmptyObject() {
        XCTAssertEqual(AgentHookProvider.codex.noOpSuccessOutput, Data("{}\n".utf8))
        XCTAssertEqual(AgentHookProvider.antigravity.noOpSuccessOutput, Data("{}\n".utf8))
        XCTAssertNil(AgentHookProvider.claudeCode.noOpSuccessOutput)
        XCTAssertNil(AgentHookProvider.cursor.noOpSuccessOutput)
    }

    func testAntigravityInvocationsUseOneConversationAndOnlyLocalDisplayFields() throws {
        var payload: [String: Any] = [
            "conversationId": "synthetic-conversation",
            "rootConversationId": "synthetic-conversation",
            "lastUserInput": "检查提醒\nsecond line stays local",
            "workspacePaths": ["/private/workspace/project", "/private/workspace/other"],
            "transcriptPath": "/private/transcript.jsonl",
            "artifactDirectoryPath": "/private/artifacts",
            "agentName": "named-root"
        ]
        for invocation in [0, 1, 7] {
            payload["invocationNum"] = invocation
            let envelope = try makeAdapter().envelope(
                from: jsonData(payload), provider: .antigravity, registeredEvent: "PreInvocation"
            )
            XCTAssertEqual(envelope.event, .started)
            XCTAssertEqual(envelope.sessionHash, AgentHookAdapter.sha256("synthetic-conversation"))
            XCTAssertNil(envelope.turnHash)
            XCTAssertEqual(envelope.title, "检查提醒")
            XCTAssertEqual(envelope.workspaceName, "project")
            let wire = String(decoding: try encodedEnvelope(envelope), as: UTF8.self)
            for excluded in ["/private", "transcript", "artifacts", "second line", "synthetic-conversation"] {
                XCTAssertFalse(wire.contains(excluded))
            }
        }
    }

    func testAntigravityIdleStopMapsKnownReasonsAndPreservesAnUnknownOutcome() throws {
        let cases: [(String, AgentHookEvent)] = [
            ("NO_TOOL_CALL", .completed), ("model_stop", .completed),
            ("USER_CANCELED", .cancelled), ("TERMINAL_CUSTOM_HOOK", .cancelled),
            ("ERROR", .failed), ("MAX_INVOCATIONS", .failed), ("max_steps_exceeded", .failed),
            ("MAX_FORCED_INVOCATIONS", .failed), ("MAX_TOKEN_BUDGET_EXCEEDED", .failed),
            ("TERMINAL_STEP_TYPE", .outcomeUnknown), ("INJECTED_RESPONSE", .outcomeUnknown),
            ("future_reason", .outcomeUnknown)
        ]
        for (reason, event) in cases {
            let data = try jsonData([
                "conversationId": "synthetic-conversation", "hookEventName": "Stop",
                "executionNum": 3, "terminationReason": reason, "fullyIdle": true,
                "lastUserInput": "This prompt is only for the start event"
            ])
            let envelope = try makeAdapter().envelope(from: data, provider: .antigravity)
            XCTAssertEqual(envelope.event, event, reason)
            XCTAssertNil(envelope.title)
            XCTAssertNil(envelope.turnHash)
            XCTAssertEqual(envelope.errorKind, event == .failed ? "providerFailure" : nil)
        }
        let failure = try makeAdapter().envelope(
            from: jsonData(["conversationId": "synthetic-conversation", "fullyIdle": true, "error": "private failure details"]),
            provider: .antigravity, registeredEvent: "Stop"
        )
        XCTAssertEqual(failure.event, .failed)
        XCTAssertFalse(String(decoding: try encodedEnvelope(failure), as: UTF8.self).contains("private failure details"))
    }

    func testAntigravityIgnoresIntermediateStopsToolCallsAndNestedConversations() throws {
        var stop: [String: Any] = ["conversationId": "synthetic-conversation", "terminationReason": "model_stop"]
        for invalidFlag: Any? in [nil, false, "true", 1] {
            stop["fullyIdle"] = invalidFlag
            XCTAssertThrowsError(try makeAdapter().envelope(from: jsonData(stop), provider: .antigravity, registeredEvent: "Stop")) {
                XCTAssertEqual($0 as? AgentHookAdapterError, .unsupportedEvent)
            }
        }
        for (event, fields): (String, [String: Any]) in [
            ("PreToolUse", [:]),
            ("PreInvocation", ["parentConversationId": "parent"]),
            ("Stop", ["rootConversationId": "other", "fullyIdle": true])
        ] {
            var payload = fields
            payload["conversationId"] = "synthetic-conversation"
            XCTAssertThrowsError(try makeAdapter().envelope(from: jsonData(payload), provider: .antigravity, registeredEvent: event)) {
                XCTAssertEqual($0 as? AgentHookAdapterError, .unsupportedEvent)
            }
        }
        XCTAssertThrowsError(try makeAdapter().envelope(from: jsonData([:]), provider: .antigravity, registeredEvent: "PreInvocation")) {
            XCTAssertEqual($0 as? AgentHookAdapterError, .missingSessionIdentifier)
        }
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

    func testCodexInternalSessionWithoutTranscriptIsNotImported() throws {
        for prompt in ["This is an app-generated synthetic task", "## Memory Writing synthetic task", "Consolidate synthetic summaries", "普通文字也不能作为来源依据"] {
            let payload: [String: Any] = [
                "hook_event_name": "UserPromptSubmit",
                "session_id": "synthetic-ephemeral",
                "turn_id": "synthetic-turn",
                "transcript_path": NSNull(),
                "prompt": prompt
            ]
            XCTAssertThrowsError(try makeAdapter().envelope(from: jsonData(payload), provider: .codex))
        }
    }

    func testCodexUserRequestWithInternalLookingTitleIsPreserved() throws {
        let transcript = try makeCodexTranscript(sessionID: "synthetic-user")
        defer { try? FileManager.default.removeItem(at: transcript) }
        for prompt in ["This is an app-generated synthetic task", "## Memory Writing synthetic task", "Consolidate synthetic summaries"] {
            let envelope = try makeAdapter().envelope(from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "session_id": "synthetic-user",
                "turn_id": "synthetic-turn",
                "transcript_path": transcript.path,
                "prompt": prompt
            ]), provider: .codex)
            XCTAssertEqual(envelope.title, prompt)
        }
    }

    func testCodexNestedTranscriptWithoutAgentIdentifierIsRejected() throws {
        let transcript = try makeCodexTranscript(
            sessionID: "synthetic-child",
            source: ["subagent": ["thread_spawn": ["parent_thread_id": "synthetic-parent"]]],
            threadSource: "subagent"
        )
        defer { try? FileManager.default.removeItem(at: transcript) }
        XCTAssertThrowsError(try makeAdapter().envelope(from: jsonData([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "synthetic-child",
            "transcript_path": transcript.path,
            "prompt": "合成子任务"
        ]), provider: .codex))
    }

    func testCodexMismatchedOrMissingMetadataCannotVerifyUserSession() throws {
        let transcript = try makeCodexTranscript(sessionID: "synthetic-other")
        defer { try? FileManager.default.removeItem(at: transcript) }
        for path in [transcript.path, "/nonexistent/synthetic-transcript.jsonl"] {
            XCTAssertThrowsError(try makeAdapter().envelope(from: jsonData([
                "hook_event_name": "UserPromptSubmit",
                "session_id": "synthetic-user",
                "transcript_path": path,
                "prompt": "合成请求"
            ]), provider: .codex))
        }
    }

    func testCodexInterruptAndSessionEndPreserveTheirTerminalMeaningWithoutTranscript() throws {
        for (name, event) in [("Interrupt", AgentHookEvent.cancelled), ("SessionEnd", AgentHookEvent.sessionEnded)] {
            let envelope = try makeAdapter().envelope(from: jsonData([
                "hook_event_name": name,
                "session_id": "synthetic-user",
                "turn_id": "synthetic-turn"
            ]), provider: .codex)
            XCTAssertEqual(envelope.event, event)
            XCTAssertNil(envelope.title)
        }
    }

    func testCodexCurrentAttachmentMarkerUsesActualRequest() throws {
        let transcript = try makeCodexTranscript(sessionID: "synthetic-user")
        defer { try? FileManager.default.removeItem(at: transcript) }
        let envelope = try makeAdapter().envelope(from: jsonData([
            "hook_event_name": "UserPromptSubmit",
            "session_id": "synthetic-user",
            "transcript_path": transcript.path,
            "prompt": "# Files mentioned by the user:\n## synthetic.png: /private/tmp/synthetic.png\n## My request:\n修复合成问题"
        ]), provider: .codex)
        XCTAssertEqual(envelope.title, "修复合成问题")
        let encoded = String(decoding: try encodedEnvelope(envelope), as: UTF8.self)
        XCTAssertFalse(encoded.contains("synthetic-codex"))
        XCTAssertFalse(encoded.contains("transcript"))
        XCTAssertFalse(encoded.contains("synthetic-body"))
    }

    func testCodexLegacyCLIAndUserOwnedAutomationRemainSupported() throws {
        for metadata in [
            ["id": "synthetic-user", "source": "cli"],
            ["id": "synthetic-user", "source": "exec"],
            ["id": "synthetic-user", "source": "vscode", "thread_source": "automation"],
            ["id": "synthetic-user", "source": "vscode", "thread_source": "realtime_voice"]
        ] {
            let transcript = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: transcript) }
            try jsonData(["type": "session_meta", "payload": metadata]).write(to: transcript)
            XCTAssertNoThrow(try makeAdapter().envelope(from: jsonData([
                "hook_event_name": "UserPromptSubmit", "session_id": "synthetic-user",
                "transcript_path": transcript.path, "prompt": "合成用户请求"
            ]), provider: .codex))
        }
    }

    func testCodexInvalidOversizedAndNonMetadataFilesAreRejected() throws {
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let payload = try jsonData([
            "hook_event_name": "UserPromptSubmit", "session_id": "synthetic-user",
            "transcript_path": transcript.path, "prompt": "合成请求"
        ])
        for data in [Data("invalid".utf8), Data(repeating: 32, count: 1024 * 1024 + 1),
                     try jsonData(["type": "response_item", "payload": ["id": "synthetic-user", "source": "cli"]]),
                     try jsonData(["type": "session_meta", "payload": ["id": "synthetic-user", "source": "future-source"]])] {
            try data.write(to: transcript)
            XCTAssertThrowsError(try makeAdapter().envelope(from: payload, provider: .codex))
        }
    }

    private func makeCodexTranscript(
        sessionID: String,
        source: Any = "vscode",
        threadSource: String = "user"
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-codex-\(UUID().uuidString).jsonl")
        var data = try JSONSerialization.data(withJSONObject: [
            "type": "session_meta",
            "payload": ["id": sessionID, "source": source, "thread_source": threadSource]
        ])
        data.append(Data("\n{\"type\":\"response_item\",\"payload\":\"synthetic-body-must-not-be-read\"}\n".utf8))
        try data.write(to: url)
        return url
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
