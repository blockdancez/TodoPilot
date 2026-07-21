import Combine
import Foundation

@MainActor
final class AgentMonitorCoordinator: ObservableObject {
    static let lostInterval: TimeInterval = 24 * 60 * 60

    private enum TerminalReminderPolicy {
        case enqueue
        case suppress
    }

    @Published private(set) var isListening = false
    @Published private(set) var lastIntegrationError: String?

    private let taskStore: TaskStore
    private let runStore: AgentRunStore
    private let settingsStore: LocalSettingsStore
    private let reminderQueue: AgentCompletionReminderQueue
    private let bridgeServer: AgentBridgeServer
    private let logger: PrivacyLogger
    private var lostTimer: Timer?
    private var runObserver: AnyCancellable?

    init(
        taskStore: TaskStore,
        runStore: AgentRunStore,
        settingsStore: LocalSettingsStore,
        reminderQueue: AgentCompletionReminderQueue,
        bridgeServer: AgentBridgeServer = AgentBridgeServer(),
        logger: PrivacyLogger
    ) {
        self.taskStore = taskStore
        self.runStore = runStore
        self.settingsStore = settingsStore
        self.reminderQueue = reminderQueue
        self.bridgeServer = bridgeServer
        self.logger = logger
        self.runObserver = runStore.$runs.sink { [weak reminderQueue] runs in
            let overriddenRunIDs = runs
                .filter { $0.userOverride != .none && $0.reminderState != .none }
                .map(\.id)
            Task { @MainActor in
                for runID in overriddenRunIDs {
                    reminderQueue?.cancel(runID: runID)
                    _ = runStore.updateReminderState(runID: runID, state: .none)
                }
            }
        }
    }

    func recoverAfterUnexpectedTermination() {
        let reconciledCount = taskStore.reconcilePersistedCodeAgentTerminalRuns(runStore.runs)
        if reconciledCount > 0 {
            logger.info("agent_terminal_tasks_reconciled", metadata: [
                "count": .numeric(reconciledCount)
            ])
        }

        let activeRunCount = runStore.activeRuns.count
        if activeRunCount > 0 {
            logger.info("agent_active_runs_preserved", metadata: [
                "count": .numeric(activeRunCount)
            ])
        }
        reconcilePendingReminders()
    }

    func start() {
        guard settingsStore.settings.agentMonitoringEnabled else {
            return
        }
        reconcilePendingReminders()
        reminderQueue.resume()
        guard !isListening else {
            return
        }
        do {
            try bridgeServer.start { [weak self] envelope in
                Task { @MainActor in
                    self?.handle(envelope)
                }
            }
            isListening = true
            lastIntegrationError = nil
            startLostTimer()
            logger.info("agent_bridge_started")
        } catch {
            isListening = false
            lastIntegrationError = "bridge_unavailable"
            logger.error("agent_bridge_start_failed", metadata: [
                "error_type": .publicText(String(describing: type(of: error)))
            ])
        }
    }

    func stop(markActiveLost: Bool, at date: Date = Date()) {
        if markActiveLost {
            for run in runStore.activeRuns {
                finish(run: run, outcome: .lost, at: date)
            }
        }
        bridgeServer.stop()
        lostTimer?.invalidate()
        lostTimer = nil
        reminderQueue.stop()
        isListening = false
    }

    func prepareForApplicationTermination() {
        stop(markActiveLost: false)
    }

    func markProviderDisabled(_ provider: AgentProvider, at date: Date = Date()) {
        let runs = runStore.activeRuns.filter { $0.provider == provider }
        for run in runs {
            finish(run: run, outcome: .lost, at: date)
        }
    }

    func handle(_ envelope: AgentHookEnvelopeV1) {
        guard settingsStore.settings.agentMonitoringEnabled,
              providerIsEnabled(envelope.provider) else {
            return
        }

        settingsStore.updateAgentConnectionVerified(envelope.provider, verified: true)
        let startedAt = Date()
        switch envelope.event {
        case .started:
            handleStart(envelope)
        case .completed:
            handleTerminal(envelope, outcome: .completed)
        case .failed:
            handleTerminal(envelope, outcome: .failed)
        case .cancelled, .sessionEnded:
            handleTerminal(envelope, outcome: .cancelled)
        }
        logger.info("agent_event_processed", metadata: [
            "provider": .publicText(envelope.provider.rawValue),
            "event": .publicText(envelope.event.rawValue),
            "duration_ms": .numeric(Int(Date().timeIntervalSince(startedAt) * 1_000))
        ])
    }

    func expireLostRuns(at date: Date = Date()) {
        let cutoff = date.addingTimeInterval(-Self.lostInterval)
        let expired = runStore.activeRuns.filter { $0.lastEventAt <= cutoff }
        for run in expired {
            finish(run: run, outcome: .lost, at: date)
        }
        if !expired.isEmpty {
            logger.info("agent_runs_expired", metadata: [
                "count": .numeric(expired.count)
            ])
        }
    }

    private func handleStart(_ envelope: AgentHookEnvelopeV1) {
        let result = runStore.startRun(
            provider: envelope.provider,
            sessionIdentityHash: envelope.sessionHash,
            turnIdentityHash: envelope.turnHash,
            workspaceDisplayName: envelope.workspaceName,
            originBundleID: envelope.originBundleID,
            originProcessID: envelope.originProcessID,
            startedAt: envelope.occurredAt
        )
        guard result.wasInserted else {
            _ = runStore.touchRun(
                runID: result.run.id,
                lastEventAt: envelope.occurredAt,
                originProcessID: envelope.originProcessID
            )
            return
        }

        cancelSupersededCodexRuns(before: result.run, at: envelope.occurredAt)

        let detail = agentTaskDetail(provider: envelope.provider, workspaceName: envelope.workspaceName)
        _ = taskStore.ensureCodeAgentTask(
            for: result.run,
            title: envelope.title ?? fallbackTitle(for: envelope.provider),
            detail: detail
        )
    }

    private func cancelSupersededCodexRuns(before newRun: AgentRun, at date: Date) {
        // Codex emits TurnAborted when the user interrupts a turn, but that
        // path does not invoke the user-level Stop hook. A later root turn in
        // the same Codex session proves the previous root turn is no longer
        // running, because a session has at most one active root turn.
        guard newRun.provider == .codex, newRun.turnIdentityHash != nil else {
            return
        }
        let supersededRuns = runStore.activeRuns.filter {
            $0.id != newRun.id
                && $0.provider == .codex
                && $0.sessionIdentityHash == newRun.sessionIdentityHash
                && $0.turnIdentityHash != newRun.turnIdentityHash
                && $0.startedAt <= newRun.startedAt
        }
        for run in supersededRuns {
            finish(run: run, outcome: .cancelled, at: date, reminderPolicy: .suppress)
        }
        if !supersededRuns.isEmpty {
            logger.info("agent_runs_superseded", metadata: [
                "provider": .publicText(AgentProvider.codex.rawValue),
                "count": .numeric(supersededRuns.count)
            ])
        }
    }

    private func handleTerminal(_ envelope: AgentHookEnvelopeV1, outcome: AgentRunOutcome) {
        let matchingRuns = runStore.activeRuns.filter {
            $0.provider == envelope.provider && $0.sessionIdentityHash == envelope.sessionHash
        }
        let resolvedTurnHash: String?
        if let turnHash = envelope.turnHash {
            resolvedTurnHash = turnHash
        } else if matchingRuns.count == 1 {
            resolvedTurnHash = matchingRuns[0].turnIdentityHash
        } else if matchingRuns.count > 1 {
            lastIntegrationError = "ambiguous_root_turn"
            logger.error("agent_terminal_ambiguous", metadata: [
                "provider": .publicText(envelope.provider.rawValue),
                "active_count": .numeric(matchingRuns.count)
            ])
            return
        } else {
            resolvedTurnHash = nil
        }

        let result = runStore.finishRun(
            provider: envelope.provider,
            sessionIdentityHash: envelope.sessionHash,
            turnIdentityHash: resolvedTurnHash,
            outcome: outcome,
            endedAt: envelope.occurredAt
        )
        guard result.disposition == .updated, let run = result.run else {
            if result.disposition == .orphaned {
                lastIntegrationError = "orphan_terminal"
                logger.error("agent_terminal_orphaned", metadata: [
                    "provider": .publicText(envelope.provider.rawValue),
                    "outcome": .publicText(outcome.rawValue)
                ])
            }
            return
        }
        applyTerminal(run)
    }

    private func finish(
        run: AgentRun,
        outcome: AgentRunOutcome,
        at date: Date,
        reminderPolicy: TerminalReminderPolicy = .enqueue
    ) {
        let result = runStore.finishRun(
            provider: run.provider,
            sessionIdentityHash: run.sessionIdentityHash,
            turnIdentityHash: run.turnIdentityHash,
            outcome: outcome,
            endedAt: date
        )
        guard result.disposition == .updated, let updated = result.run else {
            return
        }
        applyTerminal(updated, reminderPolicy: reminderPolicy)
    }

    private func applyTerminal(
        _ run: AgentRun,
        reminderPolicy: TerminalReminderPolicy = .enqueue
    ) {
        guard run.userOverride == .none else {
            _ = runStore.updateReminderState(runID: run.id, state: .none)
            reminderQueue.cancel(runID: run.id)
            return
        }
        switch taskStore.applyCodeAgentTerminal(run) {
        case .updated:
            switch reminderPolicy {
            case .enqueue:
                reminderQueue.enqueue(run: run)
            case .suppress:
                _ = runStore.updateReminderState(runID: run.id, state: .none)
                reminderQueue.cancel(runID: run.id)
            }
        case .ignored:
            _ = runStore.updateReminderState(runID: run.id, state: .none)
        }
    }

    private func reconcilePendingReminders() {
        for run in runStore.pendingReminderRuns where run.userOverride == .none {
            reminderQueue.enqueue(run: run)
        }
    }

    private func startLostTimer() {
        lostTimer?.invalidate()
        lostTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.expireLostRuns()
            }
        }
    }

    private func providerIsEnabled(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .claudeCode:
            settingsStore.settings.claudeCodeMonitoringEnabled
        case .codex:
            settingsStore.settings.codexMonitoringEnabled
        case .cursor:
            settingsStore.settings.cursorMonitoringEnabled
        }
    }

    private func fallbackTitle(for provider: AgentProvider) -> String {
        switch provider {
        case .claudeCode: "Claude Code task"
        case .codex: "Codex task"
        case .cursor: "Cursor task"
        }
    }

    private func agentTaskDetail(provider: AgentProvider, workspaceName: String?) -> String {
        let providerName: String
        switch provider {
        case .claudeCode: providerName = "Claude Code"
        case .codex: providerName = "Codex"
        case .cursor: providerName = "Cursor"
        }
        guard let workspaceName, !workspaceName.isEmpty else {
            return providerName
        }
        return "\(providerName) · \(workspaceName)"
    }
}
