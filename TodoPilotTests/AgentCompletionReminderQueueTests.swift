import XCTest
@testable import TodoPilot

@MainActor
final class AgentCompletionReminderQueueTests: XCTestCase {
    func testAggregationGroupsOnlyItemsWithinTwoSecondsOfFirst() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = item(at: start, outcome: .completed)
        let second = item(at: start.addingTimeInterval(1.9), outcome: .failed)
        let third = item(at: start.addingTimeInterval(2.1), outcome: .completed)

        let batch = try XCTUnwrap(AgentReminderAggregationPolicy.nextBatch(from: [third, second, first]))

        XCTAssertEqual(batch.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(batch.completedCount, 1)
        XCTAssertEqual(batch.warningCount, 1)
    }

    func testConservativeDeferralExpiresAtThirtyMinutes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var reminder = item(at: start, outcome: .cancelled)
        reminder.firstDeferredAt = start

        XCTAssertFalse(AgentReminderAggregationPolicy.hasExpiredDeferral(
            reminder,
            now: start.addingTimeInterval(29 * 60 + 59)
        ))
        XCTAssertTrue(AgentReminderAggregationPolicy.hasExpiredDeferral(
            reminder,
            now: start.addingTimeInterval(30 * 60)
        ))
    }

    func testWarningCountIncludesFailedCancelledAndLost() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            item(at: start, outcome: .completed),
            item(at: start, outcome: .failed),
            item(at: start, outcome: .cancelled),
            item(at: start, outcome: .lost)
        ]

        let batch = try XCTUnwrap(AgentReminderAggregationPolicy.nextBatch(from: items))

        XCTAssertEqual(batch.completedCount, 1)
        XCTAssertEqual(batch.warningCount, 3)
    }

    func testAgentReminderBatchUsesProviderThemeWhenEveryItemMatches() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            AgentReminderBatch(items: [item(at: start, outcome: .completed, provider: .claudeCode)]).flagTheme,
            .claudeCode
        )
        XCTAssertEqual(
            AgentReminderBatch(items: [
                item(at: start, outcome: .completed, provider: .codex),
                item(at: start.addingTimeInterval(1), outcome: .failed, provider: .codex)
            ]).flagTheme,
            .codex
        )
        XCTAssertEqual(
            AgentReminderBatch(items: [item(at: start, outcome: .cancelled, provider: .cursor)]).flagTheme,
            .cursor
        )
    }

    func testAgentReminderBatchUsesMixedThemeAcrossProviders() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let batch = AgentReminderBatch(items: [
            item(at: start, outcome: .completed, provider: .claudeCode),
            item(at: start.addingTimeInterval(1), outcome: .completed, provider: .cursor)
        ])

        XCTAssertEqual(batch.flagTheme, .mixedAgents)
        XCTAssertEqual(batch.iconProviders, [.claudeCode, .cursor])
    }

    func testMutedReminderSettlesAsUnreadWithoutCallingFlightScheduler() async {
        let system = makeQueueSystem()
        system.settings.updateFlightRemindersEnabled(false)
        var scheduledCount = 0
        var reminderState: AgentRunReminderState?
        let queue = AgentCompletionReminderQueue(
            taskStore: system.taskStore,
            settingsStore: system.settings,
            logger: PrivacyLogger(),
            defaults: system.defaults,
            now: { system.now.value },
            schedule: { _, _, _ in
                scheduledCount += 1
                return .shown
            },
            stateHandler: { _, state in reminderState = state },
            activateSource: { _ in false }
        )

        queue.enqueue(run: system.run)
        await queue.processPendingNow()

        XCTAssertEqual(scheduledCount, 0)
        XCTAssertEqual(reminderState, .unread)
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testSuccessfulAgentReminderBypassesLimiterAndUsesSoundSetting() async {
        let system = makeQueueSystem(outcome: .completed)
        system.settings.updateFlightReminderSoundEnabled(false)
        var capturedTask: TodoTask?
        var capturedOptions: ReminderScheduleOptions?
        var capturedPresentation: FlightReminderPresentation?
        var reminderState: AgentRunReminderState?
        let queue = AgentCompletionReminderQueue(
            taskStore: system.taskStore,
            settingsStore: system.settings,
            logger: PrivacyLogger(),
            defaults: system.defaults,
            now: { system.now.value },
            schedule: { task, actions, options in
                capturedTask = task
                capturedPresentation = actions.presentation
                capturedOptions = options
                return .shown
            },
            stateHandler: { _, state in reminderState = state },
            activateSource: { _ in true }
        )

        queue.enqueue(run: system.run)
        await queue.processPendingNow()

        XCTAssertEqual(capturedOptions?.bypassLimiter, true)
        XCTAssertEqual(capturedOptions?.playSound, false)
        XCTAssertEqual(capturedOptions?.bannerStyle, .agentSuccess)
        XCTAssertEqual(capturedPresentation?.kind, .agentSuccess)
        XCTAssertEqual(capturedPresentation?.flagTheme, .codex)
        XCTAssertEqual(capturedPresentation?.agentProviders, [.codex])
        XCTAssertEqual(capturedTask?.title, "Agent fixture")
        XCTAssertEqual(reminderState, .delivered)
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testAggregatedAgentReminderUsesOnlyTaskCountAsTitle() async {
        let suite = "TodoPilot.AgentCompletionReminderQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = LocalSettingsStore(defaults: defaults)
        let now = MutableDate(Date(timeIntervalSince1970: 1_800_000_000))
        let completedRun = AgentRun(
            provider: .claudeCode,
            sessionIdentityHash: String(repeating: "a", count: 64),
            turnIdentityHash: String(repeating: "b", count: 64),
            state: .terminal,
            outcome: .completed,
            startedAt: now.value.addingTimeInterval(-12),
            endedAt: now.value,
            lastEventAt: now.value,
            reminderState: .pending
        )
        let failedRun = AgentRun(
            provider: .cursor,
            sessionIdentityHash: String(repeating: "c", count: 64),
            turnIdentityHash: String(repeating: "d", count: 64),
            state: .terminal,
            outcome: .failed,
            startedAt: now.value.addingTimeInterval(-8),
            endedAt: now.value,
            lastEventAt: now.value,
            reminderState: .pending
        )
        let taskStore = TaskStore(seed: [
            TodoTask(
                id: completedRun.taskID,
                title: "First agent task",
                priority: .medium,
                source: .codeAgent,
                sourceKey: completedRun.id.uuidString,
                status: .done
            ),
            TodoTask(
                id: failedRun.taskID,
                title: "Second agent task",
                priority: .medium,
                source: .codeAgent,
                sourceKey: failedRun.id.uuidString,
                status: .done
            )
        ])
        var capturedTask: TodoTask?
        var capturedPresentation: FlightReminderPresentation?
        let queue = AgentCompletionReminderQueue(
            taskStore: taskStore,
            settingsStore: settings,
            logger: PrivacyLogger(),
            defaults: defaults,
            now: { now.value },
            schedule: { task, actions, _ in
                capturedTask = task
                capturedPresentation = actions.presentation
                return .shown
            },
            stateHandler: { _, _ in },
            activateSource: { _ in false }
        )

        queue.enqueue(run: completedRun)
        queue.enqueue(run: failedRun)
        await queue.processPendingNow()

        XCTAssertEqual(capturedTask?.title, "2 个 Agent 任务")
        XCTAssertEqual(capturedPresentation?.kind, .agentWarning)
        XCTAssertEqual(capturedPresentation?.agentProviders, [.claudeCode, .cursor])
    }

    func testConservativePauseRetriesThenExpiresToUnreadAtThirtyMinutes() async {
        let system = makeQueueSystem(outcome: .failed)
        var scheduledCount = 0
        var reminderState: AgentRunReminderState?
        let queue = AgentCompletionReminderQueue(
            taskStore: system.taskStore,
            settingsStore: system.settings,
            logger: PrivacyLogger(),
            defaults: system.defaults,
            now: { system.now.value },
            schedule: { _, _, options in
                scheduledCount += 1
                XCTAssertFalse(options.bypassConservativePause)
                XCTAssertEqual(options.bannerStyle, .agentWarning)
                return .skipped(.conservativePause)
            },
            stateHandler: { _, state in reminderState = state },
            activateSource: { _ in false }
        )

        queue.enqueue(run: system.run)
        await queue.processPendingNow()
        XCTAssertEqual(queue.items.first?.firstDeferredAt, system.now.value)
        XCTAssertEqual(reminderState, .pending)

        system.now.value = system.now.value.addingTimeInterval(30 * 60)
        await queue.processPendingNow()

        XCTAssertEqual(scheduledCount, 2)
        XCTAssertEqual(reminderState, .unread)
        XCTAssertTrue(queue.items.isEmpty)
    }

    private func makeQueueSystem(
        outcome: AgentRunOutcome = .completed
    ) -> (
        settings: LocalSettingsStore,
        taskStore: TaskStore,
        defaults: UserDefaults,
        now: MutableDate,
        run: AgentRun
    ) {
        let suite = "TodoPilot.AgentCompletionReminderQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = LocalSettingsStore(defaults: defaults)
        let now = MutableDate(Date(timeIntervalSince1970: 1_800_000_000))
        let run = AgentRun(
            provider: .codex,
            sessionIdentityHash: String(repeating: "a", count: 64),
            turnIdentityHash: String(repeating: "b", count: 64),
            state: .terminal,
            outcome: outcome,
            startedAt: now.value.addingTimeInterval(-10),
            endedAt: now.value,
            lastEventAt: now.value,
            reminderState: .pending
        )
        let task = TodoTask(
            id: run.taskID,
            title: "Agent fixture",
            priority: .medium,
            source: .codeAgent,
            sourceKey: run.id.uuidString,
            status: .done
        )
        return (settings, TaskStore(seed: [task]), defaults, now, run)
    }

    private func item(
        at date: Date,
        outcome: AgentRunOutcome,
        provider: AgentProvider = .codex
    ) -> AgentCompletionReminderItem {
        AgentCompletionReminderItem(
            id: UUID(),
            runID: UUID(),
            taskID: UUID(),
            provider: provider,
            outcome: outcome,
            originBundleID: nil,
            originProcessID: nil,
            enqueuedAt: date,
            firstDeferredAt: nil
        )
    }
}

@MainActor
private final class MutableDate {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}
