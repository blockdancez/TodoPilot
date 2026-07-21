import Foundation

struct AgentCompletionReminderItem: Codable, Equatable, Identifiable {
    let id: UUID
    let runID: UUID
    let taskID: UUID
    let provider: AgentProvider
    let outcome: AgentRunOutcome
    let originBundleID: String?
    let originProcessID: Int32?
    let enqueuedAt: Date
    var firstDeferredAt: Date?
}

struct AgentReminderBatch: Equatable {
    let items: [AgentCompletionReminderItem]

    var completedCount: Int {
        items.filter { $0.outcome == .completed }.count
    }

    var warningCount: Int {
        items.count - completedCount
    }

    var runIDs: [UUID] {
        items.map(\.runID)
    }

    var flagTheme: FlightReminderFlagTheme {
        let providers = Set(items.map(\.provider))
        guard providers.count == 1, let provider = providers.first else {
            return .mixedAgents
        }
        return .agent(provider)
    }

    var iconProviders: [AgentProvider] {
        let providers = Set(items.map(\.provider))
        return AgentProvider.allCases.filter(providers.contains)
    }
}

enum AgentReminderAggregationPolicy {
    static let aggregationWindow: TimeInterval = 2
    static let conservativeRetryInterval: TimeInterval = 60
    static let maximumConservativeDeferral: TimeInterval = 30 * 60

    static func nextBatch(from items: [AgentCompletionReminderItem]) -> AgentReminderBatch? {
        guard let first = items.min(by: { $0.enqueuedAt < $1.enqueuedAt }) else {
            return nil
        }
        let cutoff = first.enqueuedAt.addingTimeInterval(aggregationWindow)
        return AgentReminderBatch(items: items
            .filter { $0.enqueuedAt <= cutoff }
            .sorted { $0.enqueuedAt < $1.enqueuedAt })
    }

    static func hasExpiredDeferral(_ item: AgentCompletionReminderItem, now: Date) -> Bool {
        guard let firstDeferredAt = item.firstDeferredAt else {
            return false
        }
        return now.timeIntervalSince(firstDeferredAt) >= maximumConservativeDeferral
    }
}

@MainActor
final class AgentCompletionReminderQueue: ObservableObject {
    typealias Schedule = @MainActor (TodoTask, FlightReminderActions, ReminderScheduleOptions) async -> ReminderScheduleOutcome
    typealias ReminderStateHandler = @MainActor ([UUID], AgentRunReminderState) -> Void
    typealias SourceActivation = @MainActor (AgentCompletionReminderItem) -> Bool

    @Published private(set) var items: [AgentCompletionReminderItem]

    private let defaults: UserDefaults
    private let taskStore: TaskStore
    private let settingsStore: LocalSettingsStore
    private let logger: PrivacyLogger
    private let schedule: Schedule
    private let stateHandler: ReminderStateHandler
    private let activateSource: SourceActivation
    private let now: () -> Date
    private var processingTask: Task<Void, Never>?
    private var isProcessing = false

    init(
        taskStore: TaskStore,
        settingsStore: LocalSettingsStore,
        logger: PrivacyLogger,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Schedule,
        stateHandler: @escaping ReminderStateHandler,
        activateSource: @escaping SourceActivation
    ) {
        self.taskStore = taskStore
        self.settingsStore = settingsStore
        self.logger = logger
        self.defaults = defaults
        self.now = now
        self.schedule = schedule
        self.stateHandler = stateHandler
        self.activateSource = activateSource
        if let data = defaults.data(forKey: Self.storageKey),
           let restored = try? JSONDecoder().decode([AgentCompletionReminderItem].self, from: data) {
            self.items = restored
        } else {
            self.items = []
        }
    }

    deinit {
        processingTask?.cancel()
    }

    func resume() {
        scheduleProcessing(after: delayUntilOldestBatchIsReady())
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }

    /// Processes the current oldest batch immediately. Settings diagnostics
    /// and deterministic tests can use this without waiting for the normal
    /// aggregation/retry timer; production enqueueing still uses the timer.
    func processPendingNow() async {
        processingTask?.cancel()
        processingTask = nil
        await processNextBatch()
    }

    func enqueue(run: AgentRun) {
        guard let outcome = run.outcome,
              run.state == .terminal,
              run.userOverride == .none,
              !items.contains(where: { $0.runID == run.id }) else {
            return
        }
        items.append(AgentCompletionReminderItem(
            id: UUID(),
            runID: run.id,
            taskID: run.taskID,
            provider: run.provider,
            outcome: outcome,
            originBundleID: run.originBundleID,
            originProcessID: run.originProcessID,
            enqueuedAt: now(),
            firstDeferredAt: nil
        ))
        persist()
        stateHandler([run.id], .pending)
        logger.info("agent_reminder_enqueued", metadata: [
            "provider": .publicText(run.provider.rawValue),
            "outcome": .publicText(outcome.rawValue),
            "pending_count": .numeric(items.count)
        ])
        scheduleProcessing(after: AgentReminderAggregationPolicy.aggregationWindow)
    }

    func cancel(runID: UUID) {
        let previousCount = items.count
        items.removeAll { $0.runID == runID }
        guard items.count != previousCount else {
            return
        }
        persist()
        if items.isEmpty {
            processingTask?.cancel()
            processingTask = nil
        }
    }

    private func scheduleProcessing(after delay: TimeInterval) {
        guard processingTask == nil else {
            return
        }
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self.processingTask = nil
            await self.processNextBatch()
        }
    }

    private func processNextBatch() async {
        guard !isProcessing, let batch = AgentReminderAggregationPolicy.nextBatch(from: items) else {
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        guard settingsStore.settings.flightRemindersEnabled else {
            settle(batch, state: .unread)
            scheduleFollowingBatch()
            return
        }

        let displayTask = makeDisplayTask(for: batch)
        var options = ReminderScheduleOptions.standard
        options.playSound = settingsStore.settings.flightReminderSoundEnabled
        options.bypassLimiter = true
        options.bannerStyle = batch.warningCount > 0 ? .agentWarning : .agentSuccess
        if !settingsStore.settings.conservativeFlightSilenceEnabled {
            options.bypassConservativePause = true
        }

        let actions = makeActions(for: batch)
        let outcome = await schedule(displayTask, actions, options)
        switch outcome {
        case .shown:
            settle(batch, state: .delivered)
            logger.info("agent_reminder_batch_completed", metadata: [
                "outcome": .publicText("shown"),
                "completed_count": .numeric(batch.completedCount),
                "warning_count": .numeric(batch.warningCount)
            ])
            scheduleProcessing(after: FlightReminderTiming.flightDuration + FlightReminderTiming.autoDismissDelay + 1)
        case .skipped(.conservativePause):
            let currentDate = now()
            let batchIDs = Set(batch.items.map(\.id))
            for index in items.indices where batchIDs.contains(items[index].id) {
                if items[index].firstDeferredAt == nil {
                    items[index].firstDeferredAt = currentDate
                }
            }
            let expired = batch.items.allSatisfy { item in
                let updated = items.first(where: { $0.id == item.id }) ?? item
                return AgentReminderAggregationPolicy.hasExpiredDeferral(updated, now: currentDate)
            }
            if expired {
                settle(batch, state: .unread)
                scheduleFollowingBatch()
            } else {
                persist()
                scheduleProcessing(after: AgentReminderAggregationPolicy.conservativeRetryInterval)
            }
        case .skipped(.muted):
            settle(batch, state: .unread)
            scheduleFollowingBatch()
        case .skipped:
            settle(batch, state: .unread)
            scheduleFollowingBatch()
        }
    }

    private func makeDisplayTask(for batch: AgentReminderBatch) -> TodoTask {
        if batch.items.count == 1,
           let item = batch.items.first,
           let task = taskStore.tasks.first(where: { $0.id == item.taskID }) {
            return TodoTask(
                id: task.id,
                title: task.title,
                priority: .medium,
                source: .codeAgent,
                sourceKey: task.sourceKey
            )
        }

        return TodoTask(
            id: batch.items.first?.taskID ?? UUID(),
            title: "\(batch.items.count) 个 Agent 任务",
            priority: .medium,
            source: .codeAgent,
            sourceKey: batch.items.first?.runID.uuidString
        )
    }

    private func makeActions(for batch: AgentReminderBatch) -> FlightReminderActions {
        let primaryTitle = batch.items.count == 1 ? "打开来源 Agent" : "打开 Agent 任务"
        let presentation = FlightReminderPresentation(
            primaryTitle: primaryTitle,
            kind: batch.warningCount > 0 ? .agentWarning : .agentSuccess,
            flagTheme: batch.flagTheme,
            agentProviders: batch.iconProviders
        )
        return FlightReminderActions(
            completeTitle: primaryTitle,
            snoozeTitle: "稍后",
            presentation: presentation,
            complete: { [weak self] _ in
                guard let self else { return }
                if batch.items.count == 1,
                   let item = batch.items.first,
                   self.activateSource(item) {
                    return
                }
                NotificationCenter.default.post(name: .requestOpenAgentTasks, object: nil)
            },
            snooze10Minutes: { _ in },
            openDetails: { _ in
                NotificationCenter.default.post(name: .requestOpenAgentTasks, object: nil)
            },
            muteAll: { [weak self] in
                self?.settingsStore.updateFlightRemindersEnabled(false)
            },
            dismiss: { _ in }
        )
    }

    private func settle(_ batch: AgentReminderBatch, state: AgentRunReminderState) {
        let ids = Set(batch.items.map(\.id))
        items.removeAll { ids.contains($0.id) }
        persist()
        stateHandler(batch.runIDs, state)
    }

    private func scheduleFollowingBatch() {
        guard !items.isEmpty else {
            return
        }
        scheduleProcessing(after: delayUntilOldestBatchIsReady())
    }

    private func delayUntilOldestBatchIsReady() -> TimeInterval {
        guard let oldest = items.map(\.enqueuedAt).min() else {
            return 0
        }
        return max(0, oldest.addingTimeInterval(AgentReminderAggregationPolicy.aggregationWindow).timeIntervalSince(now()))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static let storageKey = "agentMonitoring.reminderQueue.v1"
}
