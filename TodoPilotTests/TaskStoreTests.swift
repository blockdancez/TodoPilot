import Combine
import CoreGraphics
import CoreData
import XCTest
@testable import TodoPilot

@MainActor
final class TaskStoreTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "TaskStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testCompleteMovesTaskToDone() {
        let task = TodoTask(title: "A", priority: .medium)
        let store = TaskStore(seed: [task])

        store.complete(task.id)

        XCTAssertEqual(store.activeTasks.count, 0)
        XCTAssertEqual(store.completedTasks.map(\.id), [task.id])
    }

    func testTodayProjectionExcludesLargeCompletedHistory() {
        let completedTasks = (0..<500).map { index in
            TodoTask(title: "Completed \(index)", status: .done)
        }
        let activeTasks = (0..<25).map { index in
            TodoTask(title: "Active \(index)", status: .todo)
        }
        let deletedTask = TodoTask(
            title: "Deleted",
            status: .todo,
            deletedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let projectedTasks = TodayTaskListProjection.activeTasks(
            from: completedTasks + activeTasks + [deletedTask],
            matching: nil
        )

        XCTAssertEqual(projectedTasks.map(\.id), activeTasks.map(\.id))
    }

    func testTodayProjectionIncludesCompletedTasksFromTheLastThreeDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = TodoTask(
            title: "Recent completion",
            status: .done,
            updatedAt: now.addingTimeInterval(-60)
        )
        let boundary = TodoTask(
            title: "Completion at three-day boundary",
            status: .done,
            updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60)
        )
        let older = TodoTask(
            title: "Older completion",
            status: .done,
            updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60 - 1)
        )
        let deleted = TodoTask(
            title: "Deleted recent completion",
            status: .done,
            updatedAt: now.addingTimeInterval(-30),
            deletedAt: now.addingTimeInterval(-10)
        )

        let projectedTasks = TodayTaskListProjection.recentCompletedTasks(
            from: [older, boundary, recent, deleted],
            matching: nil,
            now: now
        )

        XCTAssertEqual(projectedTasks.map(\.id), [recent.id, boundary.id])
    }

    func testAutoCompleteExpiredTasksMarksActiveTasksPastTwentyFourHoursDone() {
        let now = Date(timeIntervalSince1970: 100_000)
        let expired = TodoTask(title: "Expired", priority: .medium, dueAt: now.addingTimeInterval(-24 * 3600))
        let stillOpen = TodoTask(title: "Still open", priority: .medium, dueAt: now.addingTimeInterval(-23 * 3600 - 59))
        let noDueDate = TodoTask(title: "No due date", priority: .medium)
        let archived = TodoTask(title: "Archived", priority: .medium, dueAt: now.addingTimeInterval(-48 * 3600), status: .archived)
        let store = TaskStore(seed: [expired, stillOpen, noDueDate, archived])

        store.autoCompleteExpiredTasks(asOf: now)

        XCTAssertEqual(store.tasks.first { $0.id == expired.id }?.status, .done)
        XCTAssertEqual(store.tasks.first { $0.id == stillOpen.id }?.status, .todo)
        XCTAssertEqual(store.tasks.first { $0.id == noDueDate.id }?.status, .todo)
        XCTAssertEqual(store.tasks.first { $0.id == archived.id }?.status, .archived)
        XCTAssertEqual(store.activeTasks(asOf: now).map(\.id), [stillOpen.id, noDueDate.id])
        XCTAssertEqual(store.completedTasks.map(\.id), [expired.id])
    }

    func testCompletedPastDueTaskKeepsOverdueDisplayState() {
        let now = Date(timeIntervalSince1970: 100_000)
        let task = TodoTask(title: "Done but late", dueAt: now.addingTimeInterval(-25 * 3600), status: .done)

        XCTAssertEqual(task.deadlineState(at: now), .none)
        XCTAssertEqual(task.displayDeadlineState(at: now), .overdue)
        XCTAssertFalse(task.isOverdue(at: now))
    }

    func testUndoDoneReturnsTaskToOpenList() {
        let task = TodoTask(title: "A", priority: .medium, status: .done)
        let store = TaskStore(seed: [task])

        store.undoDone(task.id)

        XCTAssertEqual(store.activeTasks.map(\.id), [task.id])
        XCTAssertEqual(store.completedTasks.count, 0)
    }

    func testSnoozeKeepsTaskActiveWithFutureDueDate() {
        let task = TodoTask(title: "A", priority: .medium)
        let store = TaskStore(seed: [task])

        store.snooze(task.id, minutes: 10)

        let updated = store.activeTasks.first
        XCTAssertEqual(updated?.status, .snoozed)
        XCTAssertNotNil(updated?.dueAt)
    }

    func testUpdateTaskDetailsChangesPriorityAndDueDate() {
        let low = TodoTask(title: "Low", priority: .low, dueAt: Date().addingTimeInterval(3600))
        let medium = TodoTask(title: "Medium", priority: .medium, dueAt: Date().addingTimeInterval(7200))
        let store = TaskStore(seed: [low, medium])

        store.updateTaskDetails(
            low.id,
            title: "Edited",
            detail: "Updated detail",
            priority: .high,
            dueAt: nil
        )

        let updated = store.tasks.first { $0.id == low.id }
        XCTAssertEqual(updated?.title, "Edited")
        XCTAssertEqual(updated?.detail, "Updated detail")
        XCTAssertEqual(updated?.priority, .high)
        XCTAssertNil(updated?.dueAt)
        XCTAssertEqual(store.nextAction?.id, low.id)
    }

    func testUpdateTaskDetailsPublishesChangesForSwiftUIRefresh() {
        let task = TodoTask(title: "A", priority: .medium)
        let store = TaskStore(seed: [task])
        var didPublish = false
        let cancellable = store.objectWillChange.sink {
            didPublish = true
        }

        store.updateTaskDetails(
            task.id,
            title: "Edited",
            detail: nil,
            priority: .high,
            dueAt: nil
        )

        XCTAssertTrue(didPublish)
        cancellable.cancel()
    }

    func testTasksPersistAcrossStoreRecreation() {
        let persistence = UserDefaultsTaskStorePersistence(defaults: defaults)
        let store = TaskStore(seed: [], persistence: persistence)

        store.addManualTask(title: "Persist me")

        let restored = TaskStore(seed: [], persistence: persistence)
        XCTAssertEqual(restored.tasks.map(\.title), ["Persist me"])
    }

    func testLoadingDuplicateTaskIDsKeepsNewestTaskAndRepairsPersistence() {
        let taskID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let older = TodoTask(
            id: taskID,
            title: "Older copy",
            status: .doing,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let newer = TodoTask(
            id: taskID,
            title: "Newest copy",
            status: .done,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(30)
        )
        let persistence = RecordingTaskStorePersistence(loadedTasks: [older, newer, older])

        let store = TaskStore(seed: [], persistence: persistence)

        XCTAssertEqual(store.tasks, [newer])
        XCTAssertEqual(persistence.savedSnapshots, [[newer]])
    }

    func testCoreDataStoreDeduplicatesTaskIDsBeforePersisting() {
        let persistence = CoreDataLocalStore(
            inMemory: true,
            defaults: defaults,
            migratesLegacyUserDefaults: false
        )
        let taskID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let older = TodoTask(
            id: taskID,
            title: "Older copy",
            status: .doing,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let newer = TodoTask(
            id: taskID,
            title: "Newest copy",
            status: .done,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(30)
        )

        persistence.save([older, newer, older])

        XCTAssertEqual(persistence.load(), [newer])
    }

    func testImportedTaskDedupesBySourceAndSourceKey() {
        let store = TaskStore(seed: [])
        let dueAt = Date(timeIntervalSince1970: 1_783_074_800)

        let first = store.addImportedTaskIfNeeded(
            title: "Calendar event",
            dueAt: dueAt,
            source: .localCalendar,
            sourceKey: "calendar:event-1:2026-07-03T18:00:00+08:00"
        )
        let second = store.addImportedTaskIfNeeded(
            title: "Calendar event",
            dueAt: dueAt,
            source: .localCalendar,
            sourceKey: "calendar:event-1:2026-07-03T18:00:00+08:00"
        )

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.source, .localCalendar)
        XCTAssertEqual(store.tasks.first?.sourceKey, "calendar:event-1:2026-07-03T18:00:00+08:00")
    }

    func testCoreDataStorePersistsImportedTaskSource() {
        let persistence = CoreDataLocalStore(
            inMemory: true,
            defaults: defaults,
            migratesLegacyUserDefaults: false
        )
        let store = TaskStore(seed: [], persistence: persistence)
        let sourceKey = "calendar:event-1:1783074800"

        store.addImportedTaskIfNeeded(
            title: "产品评审会",
            dueAt: Date(timeIntervalSince1970: 1_783_074_800),
            source: .localCalendar,
            sourceKey: sourceKey
        )

        let restored = TaskStore(seed: [], persistence: persistence)
        XCTAssertEqual(restored.tasks.count, 1)
        XCTAssertEqual(restored.tasks.first?.source, .localCalendar)
        XCTAssertEqual(restored.tasks.first?.sourceKey, sourceKey)
    }

    func testCoreDataStoreMigratesLegacyUserDefaultsTasksOnce() {
        let legacy = UserDefaultsTaskStorePersistence(defaults: defaults)
        let legacyTask = TodoTask(title: "Legacy task", sourceQuote: "Legacy source")
        legacy.save([legacyTask])
        let persistence = CoreDataLocalStore(
            inMemory: true,
            defaults: defaults,
            legacyPersistence: legacy
        )

        let migrated = TaskStore(seed: [], persistence: persistence)
        XCTAssertEqual(migrated.tasks.map(\.id), [legacyTask.id])
        XCTAssertEqual(migrated.tasks.first?.sourceQuote, "Legacy source")

        migrated.clearAllData()
        let restoredAfterClear = TaskStore(seed: [legacyTask], persistence: persistence)
        XCTAssertTrue(restoredAfterClear.tasks.isEmpty)
    }

    func testCoreDataStoreRecordsCaptureSessions() {
        let persistence = CoreDataLocalStore(
            inMemory: true,
            defaults: defaults,
            migratesLegacyUserDefaults: false
        )
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let completedAt = startedAt.addingTimeInterval(2)

        let id = persistence.startCaptureSession(
            surface: "test",
            screenCount: 2,
            startedAt: startedAt
        )
        persistence.completeCaptureSession(
            id,
            completedAt: completedAt,
            displayID: 1,
            bounds: CGRect(x: 10, y: 20, width: 300, height: 180)
        )

        let sessions = persistence.loadCaptureSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, id)
        XCTAssertEqual(sessions.first?.status, "COMPLETED")
        XCTAssertEqual(sessions.first?.screenCount, 2)
        XCTAssertEqual(sessions.first?.startedAt, startedAt)
        XCTAssertEqual(sessions.first?.completedAt, completedAt)
        XCTAssertNotNil(sessions.first?.selectionHash)
    }

    func testAddManualTaskStoresEditableFields() {
        let dueAt = Date().addingTimeInterval(3600)
        let store = TaskStore(seed: [])

        let task = store.addManualTask(
            title: "Write release note",
            detail: "Include the Alpha checklist.",
            priority: .high,
            dueAt: dueAt
        )

        XCTAssertEqual(store.tasks.map(\.id), [task.id])
        XCTAssertEqual(store.tasks.first?.title, "Write release note")
        XCTAssertEqual(store.tasks.first?.detail, "Include the Alpha checklist.")
        XCTAssertEqual(store.tasks.first?.priority, .high)
        XCTAssertEqual(store.tasks.first?.dueAt, dueAt)
    }

    func testSoftDeletePersistsAcrossStoreRecreation() {
        let persistence = UserDefaultsTaskStorePersistence(defaults: defaults)
        let task = TodoTask(title: "Delete me", priority: .medium)
        let store = TaskStore(seed: [task], persistence: persistence)

        store.softDelete(task.id)

        let restored = TaskStore(seed: [], persistence: persistence)
        XCTAssertEqual(restored.activeTasks.count, 0)
        XCTAssertEqual(restored.deletedTasks.map(\.id), [task.id])
    }

    func testSoftDeletePublishesChangesForSwiftUIRefresh() {
        let task = TodoTask(title: "Delete me", priority: .medium)
        let store = TaskStore(seed: [task])
        var didPublish = false
        let cancellable = store.objectWillChange.sink {
            didPublish = true
        }

        store.softDelete(task.id)

        XCTAssertTrue(didPublish)
        XCTAssertTrue(store.activeTasks.isEmpty)
        XCTAssertEqual(store.deletedTasks.map(\.id), [task.id])
        cancellable.cancel()
    }

    func testClearAllDataPersistsEmptyList() {
        let persistence = UserDefaultsTaskStorePersistence(defaults: defaults)
        let store = TaskStore(seed: [TodoTask(title: "A")], persistence: persistence)

        store.clearAllData()

        let restored = TaskStore(seed: TodoTask.previewTasks, persistence: persistence)
        XCTAssertTrue(restored.tasks.isEmpty)
    }

    func testNextActionPrefersHighPriorityThenDueDate() {
        let laterHigh = TodoTask(
            title: "High later",
            priority: .high,
            dueAt: Date().addingTimeInterval(3600)
        )
        let earlyMedium = TodoTask(
            title: "Medium early",
            priority: .medium,
            dueAt: Date().addingTimeInterval(60)
        )
        let store = TaskStore(seed: [earlyMedium, laterHigh])

        XCTAssertEqual(store.nextAction?.id, laterHigh.id)
    }

    func testDeadlineStateMarksOnlyActivePastDueTasksAsOverdue() {
        let now = Date(timeIntervalSince1970: 10_000)
        let overdue = TodoTask(title: "Overdue", dueAt: now.addingTimeInterval(-60))
        let completedPastDue = TodoTask(title: "Done", dueAt: now.addingTimeInterval(-60), status: .done)
        let future = TodoTask(title: "Future", dueAt: now.addingTimeInterval(60))

        XCTAssertEqual(overdue.deadlineState(at: now), .overdue)
        XCTAssertFalse(completedPastDue.isOverdue(at: now))
        XCTAssertEqual(future.deadlineState(at: now), .dueSoon)
    }

    func testNextActionPromotesOverdueTaskAheadOfFutureHighPriorityTask() {
        let now = Date(timeIntervalSince1970: 20_000)
        let overdueMedium = TodoTask(
            title: "Overdue medium",
            priority: .medium,
            dueAt: now.addingTimeInterval(-60)
        )
        let futureHigh = TodoTask(
            title: "Future high",
            priority: .high,
            dueAt: now.addingTimeInterval(60)
        )
        let store = TaskStore(seed: [futureHigh, overdueMedium])

        XCTAssertEqual(store.nextAction(asOf: now)?.id, overdueMedium.id)
        XCTAssertEqual(store.activeTasks(asOf: now).map(\.id), [overdueMedium.id, futureHigh.id])
    }

    func testSoftDeleteMovesTaskToDeletedHistory() {
        let task = TodoTask(title: "A", priority: .medium)
        let store = TaskStore(seed: [task])

        store.softDelete(task.id)

        XCTAssertEqual(store.activeTasks.count, 0)
        XCTAssertEqual(store.deletedTasks.map(\.id), [task.id])
        XCTAssertNotNil(store.deletedTasks.first?.deletedAt)
    }

    func testRecentHistoryCombinesCompletedAndDeletedTasksAndLimitsToOneHundred() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let oldestCompleted = TodoTask(
            title: "Oldest completed",
            status: .done,
            updatedAt: base.addingTimeInterval(1)
        )
        let fillerCompleted = (2...99).map { offset in
            TodoTask(
                title: "Completed \(offset)",
                status: .done,
                updatedAt: base.addingTimeInterval(TimeInterval(offset))
            )
        }
        let newestCompleted = TodoTask(
            title: "Newest completed",
            status: .done,
            updatedAt: base.addingTimeInterval(200)
        )
        let newestDeleted = TodoTask(
            title: "Newest deleted",
            updatedAt: base.addingTimeInterval(300),
            deletedAt: base.addingTimeInterval(300)
        )
        let active = TodoTask(
            title: "Active task",
            updatedAt: base.addingTimeInterval(400)
        )
        let store = TaskStore(seed: [
            oldestCompleted,
            active,
            newestDeleted,
            newestCompleted
        ] + fillerCompleted)

        let history = store.recentHistoryTasks

        XCTAssertEqual(history.count, 100)
        XCTAssertEqual(Array(history.prefix(2).map(\.id)), [newestDeleted.id, newestCompleted.id])
        XCTAssertFalse(history.contains { $0.id == oldestCompleted.id })
        XCTAssertFalse(history.contains { $0.id == active.id })
    }

    func testSoftDeleteCompletedTaskMovesToDeletedAndRestoreKeepsCompletion() {
        let task = TodoTask(title: "Completed", priority: .medium, status: .done)
        let store = TaskStore(seed: [task])

        store.softDelete(task.id)

        XCTAssertTrue(store.completedTasks.isEmpty)
        XCTAssertEqual(store.deletedTasks.map(\.id), [task.id])
        XCTAssertEqual(store.deletedTasks.first?.status, .done)

        store.restoreDeleted(task.id)

        XCTAssertTrue(store.deletedTasks.isEmpty)
        XCTAssertEqual(store.completedTasks.map(\.id), [task.id])
        XCTAssertEqual(store.completedTasks.first?.status, .done)
    }

    func testRestoreDeletedReturnsTaskToActiveList() {
        let task = TodoTask(title: "A", priority: .medium, deletedAt: Date())
        let store = TaskStore(seed: [task])

        store.restoreDeleted(task.id)

        XCTAssertEqual(store.activeTasks.map(\.id), [task.id])
        XCTAssertEqual(store.deletedTasks.count, 0)
    }

    func testClearAllDataRemovesEveryTask() {
        let store = TaskStore(seed: [
            TodoTask(title: "A", priority: .medium),
            TodoTask(title: "B", priority: .low, status: .done),
            TodoTask(title: "C", priority: .high, deletedAt: Date())
        ])

        store.clearAllData()

        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testTodayUpcomingAndOverdueGroups() {
        let now = Date(timeIntervalSince1970: 30_000)
        let overdue = TodoTask(title: "Overdue", priority: .high, dueAt: now.addingTimeInterval(-60))
        let today = TodoTask(title: "Today", priority: .medium, dueAt: now.addingTimeInterval(3600))
        let upcoming = TodoTask(title: "Upcoming", priority: .low, dueAt: now.addingTimeInterval(48 * 3600))
        let noDueDate = TodoTask(title: "No due", priority: .medium)
        let store = TaskStore(seed: [upcoming, noDueDate, overdue, today])

        XCTAssertEqual(Set(store.overdueTasks(asOf: now).map(\.id)), Set([overdue.id]))
        XCTAssertTrue(store.dueSoonTasks(asOf: now).map(\.id).contains(overdue.id))
        XCTAssertTrue(store.dueSoonTasks(asOf: now).map(\.id).contains(today.id))
        XCTAssertTrue(store.todayTasks(asOf: now).map(\.id).contains(overdue.id))
        XCTAssertTrue(store.todayTasks(asOf: now).map(\.id).contains(today.id))
        XCTAssertTrue(store.todayTasks(asOf: now).map(\.id).contains(noDueDate.id))
        XCTAssertEqual(store.upcomingTasks(asOf: now).map(\.id), [upcoming.id])
    }

    func testCodeAgentStartCreatesDoingTaskOnceWithoutDueDate() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let run = AgentRun(
            provider: .codex,
            sessionIdentityHash: "session-hash",
            workspaceDisplayName: "TodoPilot",
            startedAt: startedAt,
            lastEventAt: startedAt
        )
        let store = TaskStore(seed: [])

        let first = store.ensureCodeAgentTask(for: run, title: "Codex · TodoPilot")
        store.updateTaskDetails(
            run.taskID,
            title: "User renamed task",
            detail: "Keep this detail",
            priority: .high,
            dueAt: startedAt.addingTimeInterval(600)
        )
        let repeated = store.ensureCodeAgentTask(for: run, title: "Must not replace user edit")

        XCTAssertTrue(first.wasInserted)
        XCTAssertFalse(repeated.wasInserted)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(first.task.id, run.taskID)
        XCTAssertEqual(first.task.status, .doing)
        XCTAssertEqual(first.task.priority, .medium)
        XCTAssertNil(first.task.dueAt)
        XCTAssertEqual(first.task.source, .codeAgent)
        XCTAssertEqual(first.task.sourceKey, run.id.uuidString)
        XCTAssertEqual(repeated.task.title, "User renamed task")
        XCTAssertEqual(repeated.task.detail, "Keep this detail")
    }

    func testCodeAgentTerminalOutcomesCompleteOnlyDoingTasks() {
        for (index, outcome) in AgentRunOutcome.allCases.enumerated() {
            let startedAt = Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + index))
            var run = AgentRun(
                provider: .cursor,
                sessionIdentityHash: "session-\(index)",
                startedAt: startedAt,
                lastEventAt: startedAt
            )
            let store = TaskStore(seed: [])
            _ = store.ensureCodeAgentTask(for: run, title: "Agent task", detail: "Original")
            store.updateTaskDetails(
                run.taskID,
                title: "Edited title",
                detail: "Edited detail",
                priority: .high,
                dueAt: nil
            )
            run.state = .terminal
            run.outcome = outcome
            run.endedAt = startedAt.addingTimeInterval(10)

            let application = store.applyCodeAgentTerminal(run)
            let expectedStatus: TodoTaskStatus = .done
            let updated = store.tasks.first

            XCTAssertEqual(application, .updated(expectedStatus))
            XCTAssertEqual(updated?.status, expectedStatus)
            XCTAssertEqual(updated?.title, "Edited title")
            XCTAssertEqual(updated?.detail, "Edited detail")
            XCTAssertEqual(updated?.priority, .high)
        }
    }

    func testCodeAgentManualOverridesPreventTerminalResurrection() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var run = AgentRun(
            provider: .claudeCode,
            sessionIdentityHash: "session-hash",
            startedAt: startedAt,
            lastEventAt: startedAt
        )
        var overrides: [AgentRunUserOverride] = []
        let store = TaskStore(seed: [], agentUserOverrideObserver: { _, override in
            overrides.append(override)
        })
        _ = store.ensureCodeAgentTask(for: run, title: "Agent task")
        run.state = .terminal
        run.outcome = .completed
        run.endedAt = startedAt.addingTimeInterval(10)

        store.complete(run.taskID)
        XCTAssertEqual(store.applyCodeAgentTerminal(run), .ignored)
        XCTAssertEqual(store.tasks.first?.status, .done)

        store.undoDone(run.taskID)
        XCTAssertEqual(store.applyCodeAgentTerminal(run), .ignored)
        XCTAssertEqual(store.tasks.first?.status, .todo)

        store.softDelete(run.taskID)
        XCTAssertEqual(store.applyCodeAgentTerminal(run), .ignored)
        XCTAssertEqual(overrides, [.completed, .reopened, .deleted])
        XCTAssertEqual(store.deletedTasks.map(\.id), [run.taskID])
        XCTAssertEqual(store.tasks.first?.status, .todo)
    }

    func testStartupTerminalReconciliationCompletesEveryOutcomeAndRespectsUserOverrides() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let terminalRuns = AgentRunOutcome.allCases.enumerated().map { index, outcome in
            AgentRun(
                provider: .codex,
                sessionIdentityHash: "terminal-session-\(index)",
                turnIdentityHash: "terminal-turn-\(index)",
                state: .terminal,
                outcome: outcome,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(TimeInterval(index + 1)),
                lastEventAt: startedAt.addingTimeInterval(TimeInterval(index + 1))
            )
        }
        let reopenedRun = AgentRun(
            provider: .cursor,
            sessionIdentityHash: "reopened-session",
            state: .terminal,
            outcome: .cancelled,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(10),
            lastEventAt: startedAt.addingTimeInterval(10),
            userOverride: .reopened
        )
        let deletedRun = AgentRun(
            provider: .claudeCode,
            sessionIdentityHash: "deleted-session",
            state: .terminal,
            outcome: .lost,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(10),
            lastEventAt: startedAt.addingTimeInterval(10)
        )
        let tasks = terminalRuns.map { run in
            TodoTask(
                id: run.taskID,
                title: "Legacy terminal task",
                source: .codeAgent,
                sourceKey: run.id.uuidString,
                status: .todo,
                createdAt: startedAt,
                updatedAt: startedAt
            )
        } + [
            TodoTask(
                id: reopenedRun.taskID,
                title: "User reopened task",
                source: .codeAgent,
                sourceKey: reopenedRun.id.uuidString,
                status: .todo,
                createdAt: startedAt,
                updatedAt: startedAt
            ),
            TodoTask(
                id: deletedRun.taskID,
                title: "Deleted terminal task",
                source: .codeAgent,
                sourceKey: deletedRun.id.uuidString,
                status: .todo,
                createdAt: startedAt,
                updatedAt: startedAt,
                deletedAt: startedAt.addingTimeInterval(5)
            )
        ]
        let store = TaskStore(seed: tasks)

        let reconciledCount = store.reconcilePersistedCodeAgentTerminalRuns(
            terminalRuns + [reopenedRun, deletedRun]
        )
        let secondPassCount = store.reconcilePersistedCodeAgentTerminalRuns(
            terminalRuns + [reopenedRun, deletedRun]
        )

        XCTAssertEqual(reconciledCount, AgentRunOutcome.allCases.count)
        XCTAssertEqual(secondPassCount, 0)
        XCTAssertTrue(terminalRuns.allSatisfy { run in
            store.tasks.first { $0.id == run.taskID }?.status == .done
        })
        XCTAssertEqual(store.tasks.first { $0.id == reopenedRun.taskID }?.status, .todo)
        XCTAssertEqual(store.tasks.first { $0.id == deletedRun.taskID }?.status, .todo)
        XCTAssertNotNil(store.tasks.first { $0.id == deletedRun.taskID }?.deletedAt)
    }

    func testCoreDataPersistsCodeAgentTaskSource() {
        let persistence = CoreDataLocalStore(
            inMemory: true,
            defaults: defaults,
            migratesLegacyUserDefaults: false
        )
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let run = AgentRun(
            provider: .codex,
            sessionIdentityHash: "session-hash",
            startedAt: startedAt,
            lastEventAt: startedAt
        )
        let store = TaskStore(seed: [], persistence: persistence)

        _ = store.ensureCodeAgentTask(for: run, title: "Agent task")
        let restored = TaskStore(seed: [], persistence: persistence)

        XCTAssertEqual(restored.tasks.first?.source, .codeAgent)
        XCTAssertEqual(restored.tasks.first?.sourceKey, run.id.uuidString)
        XCTAssertEqual(restored.tasks.first?.status, .doing)
    }

    func testStatusIslandSnapshotToleratesDuplicateTaskIDs() {
        let taskID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let older = TodoTask(
            id: taskID,
            title: "Older title",
            source: .codeAgent,
            status: .doing,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let newer = TodoTask(
            id: taskID,
            title: "Newest title",
            source: .codeAgent,
            status: .doing,
            createdAt: startedAt,
            updatedAt: startedAt.addingTimeInterval(10)
        )
        let run = AgentRun(
            taskID: taskID,
            provider: .codex,
            sessionIdentityHash: "duplicate-task-regression",
            startedAt: startedAt,
            lastEventAt: startedAt
        )

        let snapshot = StatusIslandTaskSnapshot(activeTasks: [older, newer, older], runs: [run])

        XCTAssertEqual(snapshot.runningAgentTasks, [newer])
        XCTAssertEqual(snapshot.orderedActiveTasks, [newer])
    }
    func testCoreDataSQLiteSingleEditKeepsObjectIDsAndNoopDoesNotCommit() throws {
        try withSQLiteStore { persistence, url in
            let stamp = Date(timeIntervalSince1970: 1_800_000_000)
            var tasks = (0..<250).map { index in
                TodoTask(title: "Synthetic \(index)", createdAt: stamp, updatedAt: stamp)
            }
            persistence.save(tasks)
            let taskIDs = try storageObjectIDs(persistence, entity: "TaskRecord", key: "localID")
            let sourceIDs = try storageObjectIDs(persistence, entity: "TaskSourceRecord", key: "taskLocalID")
            let sourceLocalIDs = try storageRecords(persistence, entity: "TaskSourceRecord").map {
                $0.value(forKey: "localID") as? UUID
            }
            let observer = PersistenceSaveRecorder(context: persistence.storageTestContext)

            tasks[0].status = .done
            tasks[0].updatedAt = stamp.addingTimeInterval(10)
            persistence.save(tasks)

            XCTAssertEqual(observer.commitCount, 1)
            XCTAssertEqual(observer.insertedCount, 0)
            XCTAssertEqual(observer.updatedCount, 1)
            XCTAssertEqual(observer.deletedCount, 0)
            XCTAssertEqual(try storageObjectIDs(persistence, entity: "TaskRecord", key: "localID"), taskIDs)
            XCTAssertEqual(try storageObjectIDs(persistence, entity: "TaskSourceRecord", key: "taskLocalID"), sourceIDs)
            XCTAssertEqual(try storageRecords(persistence, entity: "TaskSourceRecord").map {
                $0.value(forKey: "localID") as? UUID
            }, sourceLocalIDs)

            observer.clear()
            persistence.save(tasks)
            XCTAssertEqual(observer.commitCount, 0)
            XCTAssertFalse(persistence.storageTestContext.hasChanges)
            let reopened = CoreDataLocalStore(storeURL: url, defaults: defaults, migratesLegacyUserDefaults: false)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: reopened.load()!.map { ($0.id, $0) }), Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) }))
            XCTAssertEqual(reopened.load()?.first { $0.id == tasks[0].id }, tasks[0])
            XCTAssertEqual(try storageObjectIDs(reopened, entity: "TaskRecord", key: "localID").mapValues { $0.uriRepresentation() }, taskIDs.mapValues { $0.uriRepresentation() })
        }
    }

    func testCoreDataSourceFieldsAndQuoteClearingDoNotDependOnUpdatedAt() throws {
        try withSQLiteStore { persistence, url in
            let stamp = Date(timeIntervalSince1970: 1_800_000_000)
            var task = TodoTask(title: "Synthetic source", detail: "Synthetic detail", dueAt: stamp,
                                sourceQuote: "Synthetic quote", source: .localCalendar, sourceKey: "synthetic-key",
                                createdAt: stamp, updatedAt: stamp)
            persistence.save([task])
            let source = try XCTUnwrap(storageRecords(persistence, entity: "TaskSourceRecord").first)
            let sourceID = source.objectID
            let localID = source.value(forKey: "localID") as? UUID
            source.setValue("synthetic-reference", forKey: "ocrTextRef")
            try persistence.storageTestContext.save()
            let observer = PersistenceSaveRecorder(context: persistence.storageTestContext)

            task.source = .codeAgent
            task.sourceKey = "synthetic-new-key"
            task.sourceQuote = "Synthetic updated quote"
            task.createdAt = stamp.addingTimeInterval(-10)
            task.detail = nil
            task.priority = .high
            task.dueAt = nil
            persistence.save([task])

            XCTAssertEqual(observer.updatedCount, 2)
            XCTAssertEqual(persistence.load(), [task])
            XCTAssertEqual(source.objectID, sourceID)
            XCTAssertEqual(source.value(forKey: "localID") as? UUID, localID)
            XCTAssertEqual(source.value(forKey: "sourceType") as? String, task.source.rawValue)
            XCTAssertEqual(source.value(forKey: "sourceHash") as? String, task.sourceKey)
            XCTAssertEqual(source.value(forKey: "createdAt") as? Date, task.createdAt)
            XCTAssertNil(source.value(forKey: "ocrTextRef"))

            task.sourceQuote = nil
            task.sourceKey = nil
            task.source = .manual
            persistence.save([task])
            XCTAssertNil(source.value(forKey: "sourceQuote"))
            XCTAssertNil(try storageRecords(persistence, entity: "TaskRecord").first?.value(forKey: "sourceQuote"))
            let reopened = CoreDataLocalStore(storeURL: url, defaults: defaults, migratesLegacyUserDefaults: false)
            XCTAssertEqual(reopened.load(), [task])
        }
    }

    func testCoreDataSoftDeleteRestoreDoneArchiveAndClearKeepSnapshotSemantics() throws {
        try withSQLiteStore { persistence, url in
            let task = TodoTask(title: "Synthetic lifecycle")
            persistence.save([task])
            let originalIDs = try storageObjectIDs(persistence, entity: "TaskRecord", key: "localID")
            let originalSources = try storageObjectIDs(persistence, entity: "TaskSourceRecord", key: "taskLocalID")
            let store = TaskStore(seed: [], persistence: persistence)
            store.complete(task.id)
            store.softDelete(task.id)
            XCTAssertEqual(persistence.load()?.first?.status, .done)
            XCTAssertNotNil(persistence.load()?.first?.deletedAt)
            store.restoreDeleted(task.id)
            XCTAssertEqual(persistence.load()?.first?.status, .done)
            XCTAssertNil(persistence.load()?.first?.deletedAt)
            var archived = try XCTUnwrap(persistence.load()?.first)
            archived.status = .archived
            persistence.save([archived])
            XCTAssertEqual(try storageObjectIDs(persistence, entity: "TaskRecord", key: "localID"), originalIDs)
            XCTAssertEqual(try storageObjectIDs(persistence, entity: "TaskSourceRecord", key: "taskLocalID"), originalSources)
            XCTAssertEqual(CoreDataLocalStore(storeURL: url, defaults: defaults, migratesLegacyUserDefaults: false).load(), [archived])
            store.clearAllData()
            XCTAssertEqual(persistence.load(), [])
            XCTAssertTrue(try storageRecords(persistence, entity: "TaskRecord").isEmpty)
            XCTAssertTrue(try storageRecords(persistence, entity: "TaskSourceRecord").isEmpty)
            XCTAssertEqual(CoreDataLocalStore(storeURL: url, defaults: defaults, migratesLegacyUserDefaults: false).load(), [])
        }
    }

    func testCoreDataRepairsDuplicateMissingAndOrphanRecordsWithoutReplacingUnaffectedTasks() throws {
        try withSQLiteStore { persistence, _ in
            let a = TodoTask(title: "Synthetic duplicate", sourceQuote: "Synthetic quote")
            let b = TodoTask(title: "Synthetic missing source")
            let removed = TodoTask(title: "Synthetic removed")
            let added = TodoTask(title: "Synthetic added")
            persistence.save([a, b, removed])
            let context = persistence.storageTestContext
            let taskRecords = try storageRecords(persistence, entity: "TaskRecord")
            let sourceRecords = try storageRecords(persistence, entity: "TaskSourceRecord")
            let aRecord = try XCTUnwrap(taskRecords.first { $0.value(forKey: "localID") as? UUID == a.id })
            let bRecord = try XCTUnwrap(taskRecords.first { $0.value(forKey: "localID") as? UUID == b.id })
            let aSource = try XCTUnwrap(sourceRecords.first { $0.value(forKey: "taskLocalID") as? UUID == a.id })
            let bSource = try XCTUnwrap(sourceRecords.first { $0.value(forKey: "taskLocalID") as? UUID == b.id })
            let bID = bRecord.objectID
            let duplicateTask = duplicateStorageRecord(aRecord, in: context)
            duplicateTask.setValue("Synthetic stale duplicate", forKey: "title")
            _ = duplicateStorageRecord(aSource, in: context)
            context.delete(bSource)
            let orphan = duplicateStorageRecord(aSource, in: context)
            orphan.setValue(UUID(), forKey: "localID")
            orphan.setValue(UUID(), forKey: "taskLocalID")
            let addedOrphan = duplicateStorageRecord(aSource, in: context)
            addedOrphan.setValue(UUID(), forKey: "localID")
            addedOrphan.setValue(added.id, forKey: "taskLocalID")
            try context.save()
            let orphanID = addedOrphan.objectID

            persistence.save([a, b, added])

            XCTAssertEqual(Set(persistence.load()?.map(\.id) ?? []), Set([a.id, b.id, added.id]))
            XCTAssertEqual(persistence.load()?.first { $0.id == a.id }, a)
            XCTAssertEqual(try storageRecords(persistence, entity: "TaskRecord").count, 3)
            let repairedSources = try storageRecords(persistence, entity: "TaskSourceRecord")
            XCTAssertEqual(repairedSources.count, 3)
            XCTAssertEqual(Set(repairedSources.compactMap { $0.value(forKey: "taskLocalID") as? UUID }), Set([a.id, b.id, added.id]))
            XCTAssertEqual(try storageObjectIDs(persistence, entity: "TaskRecord", key: "localID")[b.id], bID)
            XCTAssertFalse(repairedSources.contains { $0.objectID == orphanID })
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testCoreDataFailedSaveRollsBackAndOnlySuccessfulSaveMarksFlags() throws {
        try withSQLiteStore { persistence, url in
            let initialized = "coreData.local.tasks.storeInitialized.v1"
            let migrated = "coreData.local.tasks.legacyMigrationCompleted.v1"
            let original = TodoTask(title: "Synthetic original", sourceQuote: "Synthetic original quote")
            persistence.persistenceFaultInjector = { stage in
                if stage == .save { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError) }
            }
            persistence.save([original])
            XCTAssertFalse(defaults.bool(forKey: initialized))
            XCTAssertFalse(defaults.bool(forKey: migrated))
            XCTAssertFalse(persistence.storageTestContext.hasChanges)
            XCTAssertTrue(try storageRecords(persistence, entity: "TaskRecord").isEmpty)
            persistence.persistenceFaultInjector = nil
            persistence.save([original])
            XCTAssertTrue(defaults.bool(forKey: initialized))
            XCTAssertTrue(defaults.bool(forKey: migrated))

            var changed = original
            changed.title = "Synthetic uncommitted"
            changed.sourceQuote = nil
            let inserted = TodoTask(title: "Synthetic uncommitted insert")
            persistence.persistenceFaultInjector = { stage in
                if stage == .save { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError) }
            }
            persistence.save([changed, inserted])
            XCTAssertFalse(persistence.storageTestContext.hasChanges)
            persistence.persistenceFaultInjector = nil
            let run = AgentRun(provider: .codex, sessionIdentityHash: "synthetic-session", startedAt: Date(timeIntervalSince1970: 1_800_000_000), lastEventAt: Date(timeIntervalSince1970: 1_800_000_000))
            persistence.saveAgentRun(run)
            XCTAssertEqual(persistence.load(), [original])
            XCTAssertEqual(CoreDataLocalStore(storeURL: url, defaults: defaults, migratesLegacyUserDefaults: false).load(), [original])
            persistence.save([changed, inserted])
            XCTAssertEqual(Set(persistence.load()?.map(\.id) ?? []), Set([changed.id, inserted.id]))
            persistence.persistenceFaultInjector = { stage in
                if stage == .save { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError) }
            }
            persistence.save([])
            XCTAssertFalse(persistence.storageTestContext.hasChanges)
            persistence.persistenceFaultInjector = nil
            XCTAssertEqual(persistence.load()?.count, 2)
            persistence.save([])
            XCTAssertEqual(persistence.load(), [])
        }
    }

    func testCoreDataFetchFailureCannotOverwriteTasksUntilSuccessfulReload() throws {
        try withSQLiteStore { persistence, url in
            let original = TodoTask(title: "Synthetic protected")
            persistence.save([original])
            for entity in ["TaskRecord", "TaskSourceRecord"] {
                persistence.persistenceFaultInjector = { stage in
                    if stage == .fetch(entity) { throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError) }
                }
                persistence.save([])
                XCTAssertFalse(persistence.storageTestContext.hasChanges)
                XCTAssertNil(persistence.load())
                persistence.persistenceFaultInjector = nil
                // 失败 load 后，即使 fetch 已恢复，也不能用调用方的空快照覆盖真实数据。
                persistence.save([])
                let run = AgentRun(provider: .cursor, sessionIdentityHash: "synthetic-independent", startedAt: Date(timeIntervalSince1970: 1_800_000_000), lastEventAt: Date(timeIntervalSince1970: 1_800_000_000))
                persistence.saveAgentRun(run)
                let capture = persistence.startCaptureSession(surface: "synthetic", screenCount: 1)
                persistence.cancelCaptureSession(capture)
                XCTAssertEqual(CoreDataLocalStore(storeURL: url, defaults: defaults, migratesLegacyUserDefaults: false).load(), [original])
                XCTAssertEqual(persistence.load(), [original])
            }
            persistence.save([])
            XCTAssertEqual(persistence.load(), [])
        }
    }

    func testCoreDataFailedLegacyMigrationLeavesFlagsUnsetAndRetriesAfterReload() throws {
        try withSQLiteStore { persistence, _ in
            let task = TodoTask(title: "Synthetic legacy", createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
            let legacy = UserDefaultsTaskStorePersistence(defaults: defaults)
            legacy.save([task])
            let context = persistence.storageTestContext
            let url = try XCTUnwrap(context.persistentStoreCoordinator?.persistentStores.first?.url)
            let migrating = CoreDataLocalStore(storeURL: url, defaults: defaults, legacyPersistence: legacy)
            migrating.persistenceFaultInjector = { stage in
                if stage == .save { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError) }
            }
            XCTAssertNil(migrating.load())
            XCTAssertFalse(defaults.bool(forKey: "coreData.local.tasks.storeInitialized.v1"))
            XCTAssertFalse(defaults.bool(forKey: "coreData.local.tasks.legacyMigrationCompleted.v1"))
            XCTAssertFalse(migrating.storageTestContext.hasChanges)
            migrating.persistenceFaultInjector = nil
            migrating.save([])
            XCTAssertTrue(try storageRecords(migrating, entity: "TaskRecord").isEmpty)
            XCTAssertEqual(migrating.load(), [task])
            XCTAssertTrue(defaults.bool(forKey: "coreData.local.tasks.storeInitialized.v1"))
            XCTAssertTrue(defaults.bool(forKey: "coreData.local.tasks.legacyMigrationCompleted.v1"))
        }
    }

    func testCoreDataAgentAndCaptureFailuresDoNotLeakIntoNextTransaction() throws {
        try withSQLiteStore { persistence, _ in
            let task = TodoTask(title: "Synthetic shared context")
            persistence.save([task])
            var run = AgentRun(provider: .codex, sessionIdentityHash: "synthetic-run", startedAt: Date(timeIntervalSince1970: 1_800_000_000), lastEventAt: Date(timeIntervalSince1970: 1_800_000_000))
            persistence.saveAgentRun(run)
            let capture = persistence.startCaptureSession(surface: "synthetic", screenCount: 1)
            persistence.persistenceFaultInjector = { stage in
                if stage == .save { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError) }
            }
            run.state = .terminal
            persistence.saveAgentRun(run)
            persistence.saveAgentRun(AgentRun(provider: .cursor, sessionIdentityHash: "synthetic-not-committed", startedAt: Date(timeIntervalSince1970: 1_800_000_000), lastEventAt: Date(timeIntervalSince1970: 1_800_000_000)))
            persistence.deleteAgentRun(run.id)
            let failedCapture = persistence.startCaptureSession(surface: "synthetic-failure", screenCount: 1)
            persistence.completeCaptureSession(capture, displayID: 1, bounds: CGRect(x: 1, y: 2, width: 3, height: 4))
            XCTAssertFalse(persistence.storageTestContext.hasChanges)
            persistence.persistenceFaultInjector = nil
            persistence.save([task])
            XCTAssertEqual(persistence.loadAgentRuns().count, 1)
            XCTAssertNotEqual(persistence.loadAgentRuns().first?.state, .terminal)
            XCTAssertEqual(persistence.loadCaptureSessions().map(\.id), [capture])
            XCTAssertFalse(persistence.loadCaptureSessions().contains { $0.id == failedCapture })
            XCTAssertEqual(persistence.loadCaptureSessions().first?.status, "STARTED")

            var fetches = 0
            persistence.persistenceFaultInjector = { stage in
                if stage == .fetch("AgentRunRecord") {
                    fetches += 1
                    if fetches == 2 { throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError) }
                }
            }
            persistence.saveAgentRuns([run, AgentRun(provider: .cursor, sessionIdentityHash: "synthetic-batch", startedAt: Date(timeIntervalSince1970: 1_800_000_000), lastEventAt: Date(timeIntervalSince1970: 1_800_000_000))])
            XCTAssertFalse(persistence.storageTestContext.hasChanges)
            persistence.persistenceFaultInjector = nil
            persistence.save([task])
            XCTAssertEqual(persistence.loadAgentRuns().count, 1)
            XCTAssertNotEqual(persistence.loadAgentRuns().first?.state, .terminal)
            persistence.saveAgentRun(run)
            persistence.completeCaptureSession(capture, displayID: 1, bounds: CGRect(x: 1, y: 2, width: 3, height: 4))
            XCTAssertEqual(persistence.loadAgentRuns().first?.state, .terminal)
            XCTAssertEqual(persistence.loadCaptureSessions().first?.status, "COMPLETED")
            persistence.deleteAgentRun(run.id)
            XCTAssertTrue(persistence.loadAgentRuns().isEmpty)
            XCTAssertEqual(persistence.load(), [task])
        }
    }

    private func withSQLiteStore(_ body: (CoreDataLocalStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TodoPilotStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try autoreleasepool {
            let url = directory.appendingPathComponent("fixture.sqlite")
            let persistence = CoreDataLocalStore(storeURL: url, defaults: defaults, migratesLegacyUserDefaults: false)
            try body(persistence, url)
        }
    }

    private func storageRecords(_ persistence: CoreDataLocalStore, entity: String) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.sortDescriptors = [NSSortDescriptor(key: "localID", ascending: true)]
        return try persistence.storageTestContext.fetch(request)
    }

    private func storageObjectIDs(_ persistence: CoreDataLocalStore, entity: String, key: String) throws -> [UUID: NSManagedObjectID] {
        try storageRecords(persistence, entity: entity).reduce(into: [:]) { result, object in
            if let id = object.value(forKey: key) as? UUID { result[id] = object.objectID }
        }
    }

    private func duplicateStorageRecord(_ original: NSManagedObject, in context: NSManagedObjectContext) -> NSManagedObject {
        let object = NSEntityDescription.insertNewObject(forEntityName: original.entity.name!, into: context)
        for key in original.entity.attributesByName.keys {
            object.setValue(original.value(forKey: key), forKey: key)
        }
        return object
    }
}

@MainActor
private final class RecordingTaskStorePersistence: TaskStorePersistence {
    private let loadedTasks: [TodoTask]?
    private(set) var savedSnapshots: [[TodoTask]] = []

    init(loadedTasks: [TodoTask]?) {
        self.loadedTasks = loadedTasks
    }

    func load() -> [TodoTask]? {
        loadedTasks
    }

    func save(_ tasks: [TodoTask]) {
        savedSnapshots.append(tasks)
    }
}

private final class PersistenceSaveRecorder {
    private var token: NSObjectProtocol?
    private(set) var commitCount = 0
    private(set) var insertedCount = 0
    private(set) var updatedCount = 0
    private(set) var deletedCount = 0

    init(context: NSManagedObjectContext) {
        token = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: context, queue: nil) { [weak self] notification in
            guard let self else { return }
            commitCount += 1
            insertedCount += (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
            updatedCount += (notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
            deletedCount += (notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
        }
    }

    func clear() {
        commitCount = 0
        insertedCount = 0
        updatedCount = 0
        deletedCount = 0
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
