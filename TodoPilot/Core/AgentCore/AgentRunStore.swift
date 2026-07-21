import Combine
import Foundation

@MainActor
protocol AgentRunPersistence {
    func loadAgentRuns() -> [AgentRun]
    func saveAgentRun(_ run: AgentRun)
    func saveAgentRuns(_ runs: [AgentRun])
    func deleteAgentRun(_ runID: UUID)
}

extension AgentRunPersistence {
    func saveAgentRuns(_ runs: [AgentRun]) {
        for run in runs {
            saveAgentRun(run)
        }
    }
}

@MainActor
final class AgentRunStore: ObservableObject {
    @Published private(set) var runs: [AgentRun]
    @Published private(set) var orphanTerminalEventCount = 0
    @Published private(set) var lastOrphanTerminalEvent: AgentOrphanTerminalEvent?

    private let persistence: AgentRunPersistence?

    init(persistence: AgentRunPersistence? = nil) {
        self.persistence = persistence
        self.runs = persistence?.loadAgentRuns() ?? []
    }

    var activeRuns: [AgentRun] {
        runs
            .filter { $0.state == .running }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var pendingReminderRuns: [AgentRun] {
        reminderRuns(in: .pending)
    }

    var unreadReminderRuns: [AgentRun] {
        reminderRuns(in: .unread)
    }

    var deliveredReminderRuns: [AgentRun] {
        reminderRuns(in: .delivered)
    }

    var expiredReminderRuns: [AgentRun] {
        reminderRuns(in: .expired)
    }

    @discardableResult
    func startRun(
        provider: AgentProvider,
        sessionIdentityHash: String,
        turnIdentityHash: String? = nil,
        workspaceDisplayName: String? = nil,
        originBundleID: String? = nil,
        originProcessID: Int32? = nil,
        startedAt: Date = Date()
    ) -> AgentRunStartResult {
        let normalizedTurnHash = normalizedOptionalHash(turnIdentityHash)
        let existing: AgentRun?
        if normalizedTurnHash == nil {
            // Claude Code does not currently provide a stable root turn id.
            // Only the one active root turn in the session is idempotent; a
            // later prompt in the same session must create a fresh run.
            existing = runs.last {
                $0.provider == provider
                    && $0.sessionIdentityHash == sessionIdentityHash
                    && $0.turnIdentityHash == nil
                    && $0.state == .running
            }
        } else {
            existing = run(
                provider: provider,
                sessionIdentityHash: sessionIdentityHash,
                turnIdentityHash: normalizedTurnHash
            )
        }
        if let existing {
            return AgentRunStartResult(run: existing, wasInserted: false)
        }

        let run = AgentRun(
            provider: provider,
            sessionIdentityHash: sessionIdentityHash,
            turnIdentityHash: normalizedOptionalHash(turnIdentityHash),
            workspaceDisplayName: workspaceDisplayName,
            originBundleID: originBundleID,
            originProcessID: originProcessID,
            startedAt: startedAt,
            lastEventAt: startedAt
        )
        runs.append(run)
        persistence?.saveAgentRun(run)
        return AgentRunStartResult(run: run, wasInserted: true)
    }

    func run(
        provider: AgentProvider,
        sessionIdentityHash: String,
        turnIdentityHash: String? = nil
    ) -> AgentRun? {
        let normalizedTurnHash = normalizedOptionalHash(turnIdentityHash)
        let candidates = runs.filter {
            $0.provider == provider
                && $0.sessionIdentityHash == sessionIdentityHash
                && $0.turnIdentityHash == normalizedTurnHash
        }
        if normalizedTurnHash == nil {
            return candidates.last(where: { $0.state == .running }) ?? candidates.last
        }
        return candidates.first
    }

    @discardableResult
    func finishRun(
        provider: AgentProvider,
        sessionIdentityHash: String,
        turnIdentityHash: String? = nil,
        outcome: AgentRunOutcome,
        endedAt: Date = Date()
    ) -> AgentRunTerminalResult {
        guard let index = indexOfRun(
            provider: provider,
            sessionIdentityHash: sessionIdentityHash,
            turnIdentityHash: turnIdentityHash
        ) else {
            orphanTerminalEventCount += 1
            lastOrphanTerminalEvent = AgentOrphanTerminalEvent(
                provider: provider,
                outcome: outcome,
                observedAt: endedAt
            )
            return AgentRunTerminalResult(run: nil, disposition: .orphaned)
        }

        guard runs[index].state == .running else {
            return AgentRunTerminalResult(run: runs[index], disposition: .duplicate)
        }

        var updated = runs[index]
        updated.state = .terminal
        updated.outcome = outcome
        updated.endedAt = endedAt
        updated.lastEventAt = max(updated.lastEventAt, endedAt)
        updated.reminderState = .pending
        runs[index] = updated
        persistence?.saveAgentRun(updated)
        return AgentRunTerminalResult(run: updated, disposition: .updated)
    }

    @discardableResult
    func touchRun(
        runID: UUID,
        lastEventAt: Date,
        originProcessID: Int32? = nil
    ) -> AgentRun? {
        guard let index = runs.firstIndex(where: { $0.id == runID }), runs[index].state == .running else {
            return nil
        }
        guard lastEventAt > runs[index].lastEventAt else {
            return runs[index]
        }

        var updated = runs[index]
        updated.lastEventAt = lastEventAt
        if let originProcessID {
            updated.originProcessID = originProcessID
        }
        runs[index] = updated
        persistence?.saveAgentRun(updated)
        return updated
    }

    func run(taskID: UUID) -> AgentRun? {
        runs.first { $0.taskID == taskID }
    }

    @discardableResult
    func recordUserOverride(
        taskID: UUID,
        override: AgentRunUserOverride
    ) -> AgentRun? {
        guard let index = runs.firstIndex(where: { $0.taskID == taskID }) else {
            return nil
        }
        var updated = runs[index]
        updated.userOverride = override
        runs[index] = updated
        persistence?.saveAgentRun(updated)
        return updated
    }

    @discardableResult
    func updateReminderState(
        runID: UUID,
        state: AgentRunReminderState
    ) -> AgentRun? {
        guard let index = runs.firstIndex(where: { $0.id == runID }) else {
            return nil
        }
        var updated = runs[index]
        updated.reminderState = state
        runs[index] = updated
        persistence?.saveAgentRun(updated)
        return updated
    }

    func markUnreadRemindersRead() {
        let unreadIndices = runs.indices.filter { runs[$0].reminderState == .unread }
        guard !unreadIndices.isEmpty else { return }

        var updatedRuns = runs
        var changedRuns: [AgentRun] = []
        changedRuns.reserveCapacity(unreadIndices.count)
        for index in unreadIndices {
            var updated = updatedRuns[index]
            updated.reminderState = .none
            updatedRuns[index] = updated
            changedRuns.append(updated)
        }
        runs = updatedRuns
        persistence?.saveAgentRuns(changedRuns)
    }

    private func reminderRuns(in state: AgentRunReminderState) -> [AgentRun] {
        runs
            .filter { $0.reminderState == state }
            .sorted { $0.lastEventAt < $1.lastEventAt }
    }

    private func indexOfRun(
        provider: AgentProvider,
        sessionIdentityHash: String,
        turnIdentityHash: String?
    ) -> Int? {
        let normalizedTurnHash = normalizedOptionalHash(turnIdentityHash)
        let matchingIndices = runs.indices.filter {
            runs[$0].provider == provider
                && runs[$0].sessionIdentityHash == sessionIdentityHash
                && runs[$0].turnIdentityHash == normalizedTurnHash
        }
        if normalizedTurnHash == nil {
            return matchingIndices.last(where: { runs[$0].state == .running }) ?? matchingIndices.last
        }
        return matchingIndices.first
    }

    private func normalizedOptionalHash(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
