import Combine
import XCTest
@testable import TodoPilot

@MainActor
final class AgentRunStoreTests: XCTestCase {
    func testRepeatedStartForSameProviderSessionAndTurnReturnsExistingRun() {
        let store = AgentRunStore()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let first = store.startRun(
            provider: .codex,
            sessionIdentityHash: "session-hash",
            turnIdentityHash: "turn-hash",
            workspaceDisplayName: "TodoPilot",
            originBundleID: "com.openai.codex",
            originProcessID: 101,
            startedAt: startedAt
        )
        let repeated = store.startRun(
            provider: .codex,
            sessionIdentityHash: "session-hash",
            turnIdentityHash: "turn-hash",
            workspaceDisplayName: "Changed display name must not replace user-visible data",
            originBundleID: "com.openai.codex",
            originProcessID: 202,
            startedAt: startedAt.addingTimeInterval(5)
        )

        XCTAssertTrue(first.wasInserted)
        XCTAssertFalse(repeated.wasInserted)
        XCTAssertEqual(repeated.run, first.run)
        XCTAssertEqual(store.runs, [first.run])
    }

    func testMissingTurnIdentifierDeduplicatesOnlyTheActiveRootTurn() {
        let store = AgentRunStore()
        let first = store.startRun(
            provider: .claudeCode,
            sessionIdentityHash: "session",
            startedAt: Date(timeIntervalSince1970: 100)
        )
        let duplicate = store.startRun(
            provider: .claudeCode,
            sessionIdentityHash: "session",
            startedAt: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(duplicate.run.id, first.run.id)
        XCTAssertFalse(duplicate.wasInserted)
        XCTAssertEqual(
            store.finishRun(
                provider: .claudeCode,
                sessionIdentityHash: "session",
                outcome: .completed,
                endedAt: Date(timeIntervalSince1970: 102)
            ).disposition,
            .updated
        )

        let second = store.startRun(
            provider: .claudeCode,
            sessionIdentityHash: "session",
            startedAt: Date(timeIntervalSince1970: 103)
        )
        XCTAssertTrue(second.wasInserted)
        XCTAssertNotEqual(second.run.id, first.run.id)
        XCTAssertEqual(store.runs.count, 2)
        XCTAssertEqual(
            store.finishRun(
                provider: .claudeCode,
                sessionIdentityHash: "session",
                outcome: .failed,
                endedAt: Date(timeIntervalSince1970: 104)
            ).run?.id,
            second.run.id
        )
    }

    func testFinishingActiveRunRecordsOutcomeAndQueuesReminderOnce() {
        let store = AgentRunStore()
        let start = store.startRun(
            provider: .claudeCode,
            sessionIdentityHash: "session-hash",
            turnIdentityHash: "turn-hash",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let endedAt = Date(timeIntervalSince1970: 1_800_000_030)

        let finished = store.finishRun(
            provider: .claudeCode,
            sessionIdentityHash: "session-hash",
            turnIdentityHash: "turn-hash",
            outcome: .completed,
            endedAt: endedAt
        )
        let repeated = store.finishRun(
            provider: .claudeCode,
            sessionIdentityHash: "session-hash",
            turnIdentityHash: "turn-hash",
            outcome: .completed,
            endedAt: endedAt.addingTimeInterval(5)
        )

        XCTAssertEqual(finished.disposition, .updated)
        XCTAssertEqual(finished.run?.id, start.run.id)
        XCTAssertEqual(finished.run?.state, .terminal)
        XCTAssertEqual(finished.run?.outcome, .completed)
        XCTAssertEqual(finished.run?.endedAt, endedAt)
        XCTAssertEqual(finished.run?.reminderState, .pending)
        XCTAssertEqual(repeated.disposition, .duplicate)
        XCTAssertEqual(repeated.run, finished.run)
        XCTAssertTrue(store.activeRuns.isEmpty)
        XCTAssertEqual(store.pendingReminderRuns.map(\.id), [start.run.id])
    }

    func testAllProvidersCanRunInParallelWithTheSameNativeHashes() {
        let store = AgentRunStore()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let runs = AgentProvider.allCases.map { provider in
            store.startRun(
                provider: provider,
                sessionIdentityHash: "shared-session-hash",
                turnIdentityHash: "shared-turn-hash",
                startedAt: startedAt
            ).run
        }

        XCTAssertEqual(Set(runs.map(\.provider)), Set(AgentProvider.allCases))
        XCTAssertEqual(Set(runs.map(\.id)).count, 3)
        XCTAssertEqual(Set(runs.map(\.taskID)).count, 3)
        XCTAssertEqual(store.activeRuns.count, 3)
    }

    func testEveryTerminalOutcomeIsStoredWithoutChangingItsMeaning() {
        let store = AgentRunStore()

        for (index, outcome) in AgentRunOutcome.allCases.enumerated() {
            let hash = "session-\(index)"
            _ = store.startRun(
                provider: .cursor,
                sessionIdentityHash: hash,
                startedAt: Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + index))
            )
            let result = store.finishRun(
                provider: .cursor,
                sessionIdentityHash: hash,
                outcome: outcome,
                endedAt: Date(timeIntervalSince1970: TimeInterval(1_800_000_100 + index))
            )

            XCTAssertEqual(result.run?.outcome, outcome)
        }

        XCTAssertEqual(Set(store.runs.compactMap(\.outcome)), Set(AgentRunOutcome.allCases))
    }

    func testTerminalWithoutMatchingStartIsCountedAsContentFreeDiagnostic() {
        let store = AgentRunStore()
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let result = store.finishRun(
            provider: .codex,
            sessionIdentityHash: "unknown-session-hash",
            outcome: .lost,
            endedAt: observedAt
        )

        XCTAssertEqual(result.disposition, .orphaned)
        XCTAssertNil(result.run)
        XCTAssertEqual(store.orphanTerminalEventCount, 1)
        XCTAssertEqual(
            store.lastOrphanTerminalEvent,
            AgentOrphanTerminalEvent(provider: .codex, outcome: .lost, observedAt: observedAt)
        )
    }

    func testReminderAndUserOverrideUpdatesArePersistedOnTheRun() {
        let store = AgentRunStore()
        let run = store.startRun(
            provider: .codex,
            sessionIdentityHash: "session-hash",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ).run

        _ = store.recordUserOverride(taskID: run.taskID, override: .reopened)
        _ = store.updateReminderState(runID: run.id, state: .unread)

        XCTAssertEqual(store.run(taskID: run.taskID)?.userOverride, .reopened)
        XCTAssertEqual(store.run(taskID: run.taskID)?.reminderState, .unread)
        XCTAssertEqual(store.unreadReminderRuns.map(\.id), [run.id])
    }

    func testOpeningAgentSurfaceCanClearUnreadReminderMarkers() {
        let store = AgentRunStore()
        let run = store.startRun(
            provider: .codex,
            sessionIdentityHash: "session",
            turnIdentityHash: "turn",
            startedAt: Date(timeIntervalSince1970: 100)
        ).run
        _ = store.finishRun(
            provider: .codex,
            sessionIdentityHash: "session",
            turnIdentityHash: "turn",
            outcome: .completed,
            endedAt: Date(timeIntervalSince1970: 101)
        )
        _ = store.updateReminderState(runID: run.id, state: .unread)

        store.markUnreadRemindersRead()

        XCTAssertTrue(store.unreadReminderRuns.isEmpty)
        XCTAssertEqual(store.runs.first?.reminderState, AgentRunReminderState.none)
    }

    func testOpeningAgentSurfacePublishesOneUpdateForMultipleUnreadReminders() {
        let store = AgentRunStore()
        for index in 0..<3 {
            let run = store.startRun(
                provider: .codex,
                sessionIdentityHash: "session-\(index)",
                turnIdentityHash: "turn-\(index)",
                startedAt: Date(timeIntervalSince1970: TimeInterval(100 + index))
            ).run
            _ = store.updateReminderState(runID: run.id, state: .unread)
        }

        var publishedRuns: [[AgentRun]] = []
        var cancellables = Set<AnyCancellable>()
        store.$runs
            .dropFirst()
            .sink { publishedRuns.append($0) }
            .store(in: &cancellables)

        store.markUnreadRemindersRead()

        XCTAssertEqual(publishedRuns.count, 1)
        XCTAssertTrue(store.unreadReminderRuns.isEmpty)
        XCTAssertTrue(store.runs.allSatisfy { $0.reminderState == .none })
    }

    func testCoreDataRoundTripPreservesOnlyTheAgentRunMetadataModel() {
        let suiteName = "AgentRunStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistence = CoreDataLocalStore(
            inMemory: true,
            defaults: defaults,
            migratesLegacyUserDefaults: false
        )
        let firstStore = AgentRunStore(persistence: persistence)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let run = firstStore.startRun(
            provider: .cursor,
            sessionIdentityHash: "hashed-session",
            turnIdentityHash: "hashed-turn",
            workspaceDisplayName: "TodoPilot",
            originBundleID: "com.todesktop.cursor",
            originProcessID: 4321,
            startedAt: startedAt
        ).run
        _ = firstStore.finishRun(
            provider: .cursor,
            sessionIdentityHash: "hashed-session",
            turnIdentityHash: "hashed-turn",
            outcome: .failed,
            endedAt: startedAt.addingTimeInterval(20)
        )
        _ = firstStore.recordUserOverride(taskID: run.taskID, override: .reopened)
        _ = firstStore.updateReminderState(runID: run.id, state: .unread)

        let restored = AgentRunStore(persistence: persistence)

        XCTAssertEqual(restored.runs, firstStore.runs)
        XCTAssertEqual(restored.runs.first?.sessionIdentityHash, "hashed-session")
        XCTAssertEqual(restored.runs.first?.turnIdentityHash, "hashed-turn")
        XCTAssertEqual(restored.runs.first?.originProcessID, 4321)
    }
}
