import XCTest
@testable import TodoPilot

@MainActor
final class AgentMonitorCoordinatorTests: XCTestCase {
    func testStartCreatesDoingTodoAndCompletedFinishesOnce() throws {
        let system = makeSystem()
        let start = envelope(event: .started, title: "实现状态机")

        system.coordinator.handle(start)

        let task = try XCTUnwrap(system.taskStore.tasks.first)
        XCTAssertEqual(task.status, .doing)
        XCTAssertEqual(task.source, .codeAgent)
        XCTAssertEqual(task.title, "实现状态机")

        system.coordinator.handle(envelope(event: .completed))
        system.coordinator.handle(envelope(event: .completed))

        XCTAssertEqual(system.taskStore.tasks.first?.status, .done)
        XCTAssertEqual(system.runStore.runs.count, 1)
        XCTAssertEqual(system.queue.items.count, 1)
    }

    func testCodexContinuationForCompletedTurnDoesNotCreateAnotherTask() throws {
        let system = makeSystem()
        let sessionHash = String(repeating: "a", count: 64)
        let turnHash = String(repeating: "1", count: 64)

        system.coordinator.handle(envelope(
            event: .started,
            title: "Original root request",
            sessionHash: sessionHash,
            turnHash: turnHash
        ))
        system.coordinator.handle(envelope(
            event: .completed,
            sessionHash: sessionHash,
            turnHash: turnHash
        ))
        system.coordinator.handle(envelope(
            event: .started,
            title: "Synthetic continuation",
            sessionHash: sessionHash,
            turnHash: turnHash
        ))

        let task = try XCTUnwrap(system.taskStore.tasks.first)
        XCTAssertEqual(system.taskStore.tasks.count, 1)
        XCTAssertEqual(task.title, "Original root request")
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(system.runStore.runs.count, 1)
        XCTAssertEqual(system.runStore.runs.first?.state, .terminal)
        XCTAssertEqual(system.runStore.runs.first?.outcome, .completed)
        XCTAssertEqual(system.queue.items.count, 1)
    }

    func testNewCodexTurnInSameSessionCancelsInterruptedPreviousTurn() throws {
        let system = makeSystem()
        let firstTurnHash = String(repeating: "1", count: 64)
        let secondTurnHash = String(repeating: "2", count: 64)

        system.coordinator.handle(envelope(
            event: .started,
            title: "首次回合",
            turnHash: firstTurnHash
        ))
        system.coordinator.handle(envelope(
            event: .started,
            title: "编辑后重试",
            turnHash: secondTurnHash
        ))

        XCTAssertEqual(system.taskStore.tasks.count, 2)
        let firstRun = try XCTUnwrap(system.runStore.runs.first {
            $0.turnIdentityHash == firstTurnHash
        })
        let secondRun = try XCTUnwrap(system.runStore.runs.first {
            $0.turnIdentityHash == secondTurnHash
        })
        XCTAssertEqual(firstRun.state, .terminal)
        XCTAssertEqual(firstRun.outcome, .cancelled)
        XCTAssertEqual(firstRun.reminderState, .none)
        XCTAssertEqual(system.taskStore.tasks.first { $0.id == firstRun.taskID }?.status, .done)
        XCTAssertEqual(secondRun.state, .running)
        XCTAssertEqual(system.taskStore.tasks.first { $0.id == secondRun.taskID }?.status, .doing)
        XCTAssertEqual(system.runStore.activeRuns.map(\.id), [secondRun.id])
        XCTAssertTrue(system.queue.items.isEmpty)

        system.coordinator.handle(envelope(event: .completed, turnHash: secondTurnHash))
        system.coordinator.handle(envelope(event: .completed, turnHash: firstTurnHash))

        XCTAssertTrue(system.runStore.activeRuns.isEmpty)
        XCTAssertEqual(system.runStore.run(taskID: firstRun.taskID)?.outcome, .cancelled)
        XCTAssertEqual(system.runStore.run(taskID: secondRun.taskID)?.outcome, .completed)
        XCTAssertEqual(system.taskStore.tasks.first { $0.id == firstRun.taskID }?.status, .done)
        XCTAssertEqual(system.taskStore.tasks.first { $0.id == secondRun.taskID }?.status, .done)
        XCTAssertEqual(system.queue.items.map(\.outcome), [.completed])
    }

    func testParallelCodexSessionsDoNotCancelEachOther() {
        let system = makeSystem()

        system.coordinator.handle(envelope(
            event: .started,
            sessionHash: String(repeating: "a", count: 64),
            turnHash: String(repeating: "1", count: 64)
        ))
        system.coordinator.handle(envelope(
            event: .started,
            sessionHash: String(repeating: "b", count: 64),
            turnHash: String(repeating: "2", count: 64)
        ))

        XCTAssertEqual(system.runStore.activeRuns.count, 2)
        XCTAssertTrue(system.runStore.runs.allSatisfy { $0.outcome == nil })
        XCTAssertTrue(system.queue.items.isEmpty)
    }

    func testSessionEndClosesEarlierRunsInOnlyTheMatchingProviderAndSession() {
        let system = makeSystem()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionHash = String(repeating: "e", count: 64)
        let first = seedRunningTask(
            taskStore: system.taskStore, runStore: system.runStore,
            sessionHash: sessionHash, turnHash: "first", startedAt: startedAt
        )
        let second = seedRunningTask(
            taskStore: system.taskStore, runStore: system.runStore,
            sessionHash: sessionHash, turnHash: "second", startedAt: startedAt.addingTimeInterval(20)
        )
        let later = seedRunningTask(
            taskStore: system.taskStore, runStore: system.runStore,
            sessionHash: sessionHash, turnHash: "later", startedAt: startedAt.addingTimeInterval(30)
        )
        let otherSession = seedRunningTask(
            taskStore: system.taskStore, runStore: system.runStore,
            sessionHash: "other-session", turnHash: "first", startedAt: startedAt
        )
        let otherProvider = seedRunningTask(
            taskStore: system.taskStore, runStore: system.runStore, provider: .claudeCode,
            sessionHash: sessionHash, turnHash: "first", startedAt: startedAt
        )
        let sessionEnd = envelope(
            event: .sessionEnded, sessionHash: sessionHash, turnHash: nil,
            occurredAt: startedAt.addingTimeInterval(20)
        )

        system.coordinator.handle(sessionEnd)
        system.coordinator.handle(sessionEnd)

        for run in [first, second] {
            XCTAssertEqual(system.runStore.run(taskID: run.taskID)?.outcome, .cancelled)
            XCTAssertEqual(system.taskStore.tasks.first { $0.id == run.taskID }?.status, .done)
        }
        XCTAssertEqual(
            Set(system.runStore.activeRuns.map(\.id)),
            Set([later.id, otherSession.id, otherProvider.id])
        )
        XCTAssertEqual(Set(system.queue.items.map(\.runID)), Set([first.id, second.id]))
        XCTAssertEqual(system.queue.items.count, 2)
        XCTAssertEqual(system.runStore.orphanTerminalEventCount, 0)
    }

    func testDelayedSessionEndDoesNotCancelANewerTurn() {
        let system = makeSystem()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        system.coordinator.handle(envelope(event: .started, occurredAt: startedAt))

        system.coordinator.handle(envelope(
            event: .sessionEnded, turnHash: nil, occurredAt: startedAt.addingTimeInterval(-1)
        ))

        XCTAssertEqual(system.runStore.activeRuns.count, 1)
        XCTAssertEqual(system.taskStore.tasks.first?.status, .doing)
        XCTAssertTrue(system.queue.items.isEmpty)
        XCTAssertEqual(system.runStore.orphanTerminalEventCount, 0)
    }

    func testSameSecondDelayedSessionEndPreservesNewerTurnAcrossBridgeDecoding() throws {
        let system = makeSystem()
        func decodedEnvelope(event: TodoPilot.AgentHookEvent, timestamp: String) throws -> TodoPilot.AgentHookEnvelopeV1 {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let source = envelope(event: event, turnHash: event == .sessionEnded ? nil : String(repeating: "1", count: 64))
            var payload = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any]
            )
            payload["occurredAt"] = timestamp
            return try AgentBridgeEnvelopeValidator.decode(JSONSerialization.data(withJSONObject: payload))
        }
        let newerStart = try decodedEnvelope(event: .started, timestamp: "2027-01-15T08:00:00.875Z")
        let earlierSessionEnd = try decodedEnvelope(event: .sessionEnded, timestamp: "2027-01-15T08:00:00.125Z")

        system.coordinator.handle(newerStart)
        system.coordinator.handle(earlierSessionEnd)

        XCTAssertEqual(system.runStore.activeRuns.count, 1)
        XCTAssertEqual(system.runStore.activeRuns.first?.startedAt, newerStart.occurredAt)
        XCTAssertEqual(system.taskStore.tasks.first?.status, .doing)
        XCTAssertTrue(system.queue.items.isEmpty)
    }

    func testSessionEndRespectsEveryManualTaskOverride() throws {
        for override in [AgentRunUserOverride.completed, .reopened, .deleted] {
            let system = makeSystem()
            system.coordinator.handle(envelope(event: .started))
            let taskID = try XCTUnwrap(system.taskStore.tasks.first?.id)
            switch override {
            case .completed:
                system.taskStore.complete(taskID)
            case .reopened:
                system.taskStore.complete(taskID)
                system.taskStore.undoDone(taskID)
            case .deleted:
                system.taskStore.softDelete(taskID)
            case .none:
                XCTFail("回归用例必须指定人工接管方式")
            }
            let taskBeforeSessionEnd = system.taskStore.tasks.first { $0.id == taskID }

            system.coordinator.handle(envelope(event: .sessionEnded, turnHash: nil))

            XCTAssertEqual(system.taskStore.tasks.first { $0.id == taskID }, taskBeforeSessionEnd)
            XCTAssertEqual(system.runStore.run(taskID: taskID)?.userOverride, override)
            XCTAssertEqual(system.runStore.run(taskID: taskID)?.outcome, .cancelled)
            XCTAssertEqual(system.runStore.run(taskID: taskID)?.reminderState, AgentRunReminderState.none)
            XCTAssertTrue(system.queue.items.isEmpty)
        }
    }

    func testCancellationFinishesOnlyItsMatchingTurn() {
        let system = makeSystem()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionHash = String(repeating: "e", count: 64)
        let interrupted = seedRunningTask(
            taskStore: system.taskStore, runStore: system.runStore,
            sessionHash: sessionHash, turnHash: "interrupted", startedAt: startedAt
        )
        let newer = seedRunningTask(
            taskStore: system.taskStore, runStore: system.runStore,
            sessionHash: sessionHash, turnHash: "newer", startedAt: startedAt.addingTimeInterval(10)
        )

        system.coordinator.handle(envelope(
            event: .cancelled, sessionHash: sessionHash, turnHash: "interrupted",
            occurredAt: startedAt.addingTimeInterval(20)
        ))

        XCTAssertEqual(system.runStore.run(taskID: interrupted.taskID)?.outcome, .cancelled)
        XCTAssertEqual(system.runStore.activeRuns.map(\.id), [newer.id])
        XCTAssertEqual(system.queue.items.map(\.runID), [interrupted.id])
    }

    func testFailedCompletesTaskAndOrphanDoesNotBackfill() throws {
        let system = makeSystem()
        system.coordinator.handle(envelope(event: .started, title: "运行测试"))
        system.coordinator.handle(envelope(event: .failed))

        XCTAssertEqual(system.taskStore.tasks.first?.status, .done)
        XCTAssertEqual(system.runStore.runs.first?.outcome, .failed)

        let orphan = envelope(
            event: .completed,
            sessionHash: String(repeating: "f", count: 64)
        )
        system.coordinator.handle(orphan)

        XCTAssertEqual(system.taskStore.tasks.count, 1)
        XCTAssertEqual(system.runStore.orphanTerminalEventCount, 1)
    }

    func testManualCompletionOverridesLaterFailureAndSuppressesReminder() throws {
        let system = makeSystem()
        system.coordinator.handle(envelope(event: .started, title: "人工接管"))
        let taskID = try XCTUnwrap(system.taskStore.tasks.first?.id)

        system.taskStore.complete(taskID)
        system.coordinator.handle(envelope(event: .failed))

        XCTAssertEqual(system.taskStore.tasks.first?.status, .done)
        XCTAssertEqual(system.runStore.runs.first?.userOverride, .completed)
        XCTAssertTrue(system.queue.items.isEmpty)
        XCTAssertEqual(system.runStore.runs.first?.reminderState, AgentRunReminderState.none)
    }

    func testStartupRecoveryPreservesRunningTurnWithoutReminder() throws {
        let system = makeSystem()
        system.coordinator.handle(envelope(event: .started, title: "长任务"))

        system.coordinator.recoverAfterUnexpectedTermination(
            at: Date(timeIntervalSince1970: 1_800_000_010)
        )

        XCTAssertEqual(system.taskStore.tasks.first?.status, .doing)
        XCTAssertEqual(system.runStore.runs.first?.state, .running)
        XCTAssertNil(system.runStore.runs.first?.outcome)
        XCTAssertEqual(system.runStore.runs.first?.reminderState, AgentRunReminderState.none)
        XCTAssertTrue(system.queue.items.isEmpty)
    }

    func testStartupRecoveryImmediatelyExpiresPersistedStaleRunsWithoutHistoricalReminders() throws {
        let suite = "TodoPilot.AgentMonitorCoordinatorTests.StaleRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = CoreDataLocalStore(
            inMemory: true, defaults: defaults, migratesLegacyUserDefaults: false
        )
        let originalRunStore = AgentRunStore(persistence: persistence)
        let originalTaskStore = TaskStore(persistence: persistence)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let recoveryDate = startedAt.addingTimeInterval(AgentMonitorCoordinator.lostInterval)
        let expired = seedRunningTask(
            taskStore: originalTaskStore, runStore: originalRunStore,
            sessionHash: "expired-session", turnHash: "expired-turn", startedAt: startedAt
        )
        let recent = seedRunningTask(
            taskStore: originalTaskStore, runStore: originalRunStore,
            sessionHash: "recent-session", turnHash: "recent-turn",
            startedAt: recoveryDate.addingTimeInterval(-1)
        )
        let recentlyTouched = seedRunningTask(
            taskStore: originalTaskStore, runStore: originalRunStore,
            sessionHash: "touched-session", turnHash: "touched-turn", startedAt: startedAt
        )
        _ = originalRunStore.touchRun(runID: recentlyTouched.id, lastEventAt: recoveryDate.addingTimeInterval(-1))
        let restoredRunStore = AgentRunStore(persistence: persistence)
        let system = makeSystem(
            taskStore: TaskStore(persistence: persistence), runStore: restoredRunStore
        )

        system.coordinator.recoverAfterUnexpectedTermination(at: recoveryDate)
        system.coordinator.recoverAfterUnexpectedTermination(at: recoveryDate)

        XCTAssertEqual(system.runStore.run(taskID: expired.taskID)?.outcome, .lost)
        XCTAssertEqual(system.runStore.run(taskID: expired.taskID)?.reminderState, AgentRunReminderState.none)
        XCTAssertEqual(system.taskStore.tasks.first { $0.id == expired.taskID }?.status, .done)
        XCTAssertEqual(
            Set(system.runStore.activeRuns.map(\.id)), Set([recent.id, recentlyTouched.id])
        )
        XCTAssertTrue(system.queue.items.isEmpty)
        XCTAssertEqual(AgentRunStore(persistence: persistence).run(taskID: expired.taskID)?.outcome, .lost)
        XCTAssertEqual(TaskStore(persistence: persistence).tasks.first { $0.id == expired.taskID }?.status, .done)
    }

    func testApplicationTerminationPreservesRunningTurnWithoutReminder() {
        let system = makeSystem()
        system.coordinator.handle(envelope(event: .started, title: "退出前仍在运行"))

        system.coordinator.prepareForApplicationTermination()

        XCTAssertEqual(system.runStore.runs.first?.state, .running)
        XCTAssertNil(system.runStore.runs.first?.outcome)
        XCTAssertEqual(system.taskStore.tasks.first?.status, .doing)
        XCTAssertTrue(system.queue.items.isEmpty)
    }

    func testRecoveredTurnStillCompletesAndRemindsOnMatchingStop() {
        let system = makeSystem()
        system.coordinator.handle(envelope(event: .started, title: "重启后继续运行"))
        system.coordinator.recoverAfterUnexpectedTermination(
            at: Date(timeIntervalSince1970: 1_800_000_010)
        )

        system.coordinator.handle(envelope(event: .completed))

        XCTAssertEqual(system.runStore.runs.first?.state, .terminal)
        XCTAssertEqual(system.runStore.runs.first?.outcome, .completed)
        XCTAssertEqual(system.taskStore.tasks.first?.status, .done)
        XCTAssertEqual(system.queue.items.map(\.outcome), [.completed])
    }

    func testTwentyFourHourInactivityMarksRunLostAndEnqueuesWarning() {
        let system = makeSystem()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        system.coordinator.handle(envelope(event: .started, title: "失联任务"))

        system.coordinator.expireLostRuns(
            at: startedAt.addingTimeInterval(AgentMonitorCoordinator.lostInterval - 1)
        )

        XCTAssertEqual(system.runStore.runs.first?.state, .running)
        XCTAssertTrue(system.queue.items.isEmpty)

        system.coordinator.expireLostRuns(
            at: startedAt.addingTimeInterval(AgentMonitorCoordinator.lostInterval)
        )

        XCTAssertEqual(system.runStore.runs.first?.state, .terminal)
        XCTAssertEqual(system.runStore.runs.first?.outcome, .lost)
        XCTAssertEqual(system.taskStore.tasks.first?.status, .done)
        XCTAssertEqual(system.queue.items.map(\.outcome), [.lost])
    }

    func testStartupReconcilesPersistedTerminalTaskFromLegacyTodoStatusWithoutReplayingReminder() throws {
        let suite = "TodoPilot.AgentMonitorCoordinatorTests.LegacyTerminal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = CoreDataLocalStore(
            inMemory: true,
            defaults: defaults,
            migratesLegacyUserDefaults: false
        )
        let originalRunStore = AgentRunStore(persistence: persistence)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let run = originalRunStore.startRun(
            provider: .codex,
            sessionIdentityHash: "persisted-session",
            turnIdentityHash: "persisted-turn",
            startedAt: startedAt
        ).run
        _ = originalRunStore.finishRun(
            provider: .codex,
            sessionIdentityHash: "persisted-session",
            turnIdentityHash: "persisted-turn",
            outcome: .cancelled,
            endedAt: startedAt.addingTimeInterval(10)
        )
        _ = originalRunStore.updateReminderState(runID: run.id, state: .delivered)
        persistence.save([
            TodoTask(
                id: run.taskID,
                title: "Legacy terminal task",
                priority: .medium,
                source: .codeAgent,
                sourceKey: run.id.uuidString,
                status: .todo,
                createdAt: startedAt,
                updatedAt: startedAt.addingTimeInterval(10)
            )
        ])

        let restoredRunStore = AgentRunStore(persistence: persistence)
        let restoredTaskStore = TaskStore(
            persistence: persistence,
            agentUserOverrideObserver: { taskID, override in
                _ = restoredRunStore.recordUserOverride(taskID: taskID, override: override)
            }
        )
        let system = makeSystem(taskStore: restoredTaskStore, runStore: restoredRunStore)

        system.coordinator.recoverAfterUnexpectedTermination()

        XCTAssertEqual(system.taskStore.tasks.first?.status, .done)
        XCTAssertEqual(system.runStore.runs.first?.outcome, .cancelled)
        XCTAssertEqual(system.runStore.runs.first?.reminderState, .delivered)
        XCTAssertTrue(system.queue.items.isEmpty)
        XCTAssertEqual(TaskStore(persistence: persistence).tasks.first?.status, .done)
    }

    func testDisabledProviderEventIsIgnored() {
        let system = makeSystem()
        system.settings.updateCodexMonitoringEnabled(false)

        system.coordinator.handle(envelope(event: .started, title: "不应入库"))

        XCTAssertTrue(system.taskStore.tasks.isEmpty)
        XCTAssertTrue(system.runStore.runs.isEmpty)
        XCTAssertFalse(system.settings.isAgentConnectionVerified(.codex))
    }

    func testValidStartMarksProviderConnectionVerified() {
        let system = makeSystem()
        XCTAssertFalse(system.settings.isAgentConnectionVerified(.codex))

        system.coordinator.handle(envelope(event: .started, title: "验证连接"))

        XCTAssertTrue(system.settings.isAgentConnectionVerified(.codex))
    }

    func testGloballyDisabledEventDoesNotVerifyConnection() {
        let system = makeSystem()
        system.settings.updateAgentMonitoringEnabled(false)

        system.coordinator.handle(envelope(event: .started, title: "不应验证"))

        XCTAssertTrue(system.taskStore.tasks.isEmpty)
        XCTAssertTrue(system.runStore.runs.isEmpty)
        XCTAssertFalse(system.settings.isAgentConnectionVerified(.codex))
    }

    private func makeSystem(
        taskStore providedTaskStore: TaskStore? = nil,
        runStore providedRunStore: AgentRunStore? = nil
    ) -> (
        coordinator: AgentMonitorCoordinator,
        taskStore: TaskStore,
        runStore: AgentRunStore,
        queue: AgentCompletionReminderQueue,
        settings: LocalSettingsStore
    ) {
        let suite = "TodoPilot.AgentMonitorCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = LocalSettingsStore(defaults: defaults)
        settings.updateAgentMonitoringEnabled(true)
        let runStore = providedRunStore ?? AgentRunStore()
        let taskStore = providedTaskStore ?? TaskStore(agentUserOverrideObserver: { taskID, override in
            _ = runStore.recordUserOverride(taskID: taskID, override: override)
        })
        let logger = PrivacyLogger()
        let queue = AgentCompletionReminderQueue(
            taskStore: taskStore,
            settingsStore: settings,
            logger: logger,
            defaults: defaults,
            schedule: { _, _, _ in .shown },
            stateHandler: { runIDs, state in
                for runID in runIDs {
                    _ = runStore.updateReminderState(runID: runID, state: state)
                }
            },
            activateSource: { _ in false }
        )
        let coordinator = AgentMonitorCoordinator(
            taskStore: taskStore,
            runStore: runStore,
            settingsStore: settings,
            reminderQueue: queue,
            logger: logger
        )
        return (coordinator, taskStore, runStore, queue, settings)
    }

    private func envelope(
        event: TodoPilot.AgentHookEvent,
        title: String? = nil,
        sessionHash: String = String(repeating: "e", count: 64),
        turnHash: String? = String(repeating: "1", count: 64),
        occurredAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> TodoPilot.AgentHookEnvelopeV1 {
        TodoPilot.AgentHookEnvelopeV1(
            schemaVersion: 1,
            provider: .codex,
            event: event,
            sessionHash: sessionHash,
            turnHash: turnHash,
            title: title,
            workspaceName: "TodoPilot",
            occurredAt: occurredAt,
            originBundleID: nil,
            originProcessID: nil,
            errorKind: event == .failed ? "providerFailure" : nil
        )
    }

    private func seedRunningTask(
        taskStore: TaskStore,
        runStore: AgentRunStore,
        provider: AgentProvider = .codex,
        sessionHash: String,
        turnHash: String,
        startedAt: Date
    ) -> AgentRun {
        let run = runStore.startRun(
            provider: provider,
            sessionIdentityHash: sessionHash,
            turnIdentityHash: turnHash,
            startedAt: startedAt
        ).run
        _ = taskStore.ensureCodeAgentTask(for: run, title: "合成会话任务")
        return run
    }
}
