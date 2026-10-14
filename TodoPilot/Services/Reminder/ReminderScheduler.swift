import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import SwiftUI

struct FlightReminderPresentation: Equatable {
    enum Kind: Equatable {
        case task
        case agentSuccess
        case agentWarning
    }

    let primaryTitle: String
    let kind: Kind
    let flagTheme: FlightReminderFlagTheme
    let agentProviders: [AgentProvider]

    init(
        primaryTitle: String,
        kind: Kind,
        flagTheme: FlightReminderFlagTheme = .standard,
        agentProviders: [AgentProvider] = []
    ) {
        self.primaryTitle = primaryTitle
        self.kind = kind
        self.flagTheme = flagTheme
        let requestedProviders = Set(agentProviders)
        self.agentProviders = flagTheme.isAgentTheme
            ? AgentProvider.allCases.filter(requestedProviders.contains)
            : []
    }

    static func task(primaryTitle: String) -> FlightReminderPresentation {
        FlightReminderPresentation(
            primaryTitle: primaryTitle,
            kind: .task,
            flagTheme: .standard,
            agentProviders: []
        )
    }

    var agentOutcomeBadge: AgentFlagOutcomeBadge? {
        guard flagTheme.isAgentTheme else {
            return nil
        }
        switch kind {
        case .task:
            return nil
        case .agentSuccess:
            return .success
        case .agentWarning:
            return .warning
        }
    }
}

enum AgentFlagOutcomeBadge: Equatable {
    case success
    case warning

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark"
        case .warning:
            return "exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .success:
            return FlightReminderBannerStyle.agentSuccess.ribbonPalette.color
        case .warning:
            return FlightReminderBannerStyle.agentWarning.ribbonPalette.color
        }
    }
}

struct FlightReminderActions {
    let completeTitle: String
    let snoozeTitle: String
    let presentation: FlightReminderPresentation
    let complete: (TodoTask.ID) -> Void
    let snooze10Minutes: (TodoTask.ID) -> Void
    let openDetails: (TodoTask.ID) -> Void
    let muteAll: () -> Void
    let dismiss: (String) -> Void

    init(
        completeTitle: String,
        snoozeTitle: String,
        presentation: FlightReminderPresentation? = nil,
        complete: @escaping (TodoTask.ID) -> Void,
        snooze10Minutes: @escaping (TodoTask.ID) -> Void,
        openDetails: @escaping (TodoTask.ID) -> Void,
        muteAll: @escaping () -> Void,
        dismiss: @escaping (String) -> Void
    ) {
        self.completeTitle = completeTitle
        self.snoozeTitle = snoozeTitle
        self.presentation = presentation ?? .task(primaryTitle: completeTitle)
        self.complete = complete
        self.snooze10Minutes = snooze10Minutes
        self.openDetails = openDetails
        self.muteAll = muteAll
        self.dismiss = dismiss
    }
}

struct FlightReminderBannerPalette: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

enum FlightReminderFlagTheme: Equatable, CaseIterable {
    case standard
    case claudeCode
    case codex
    case cursor
    case mixedAgents

    static func agent(_ provider: AgentProvider) -> FlightReminderFlagTheme {
        switch provider {
        case .claudeCode:
            return .claudeCode
        case .codex:
            return .codex
        case .cursor:
            return .cursor
        }
    }

    var isAgentTheme: Bool {
        self != .standard
    }

    func backgroundPalette(fallback: FlightReminderBannerStyle) -> FlightReminderBannerPalette {
        switch self {
        case .standard:
            return fallback.ribbonPalette
        case .claudeCode:
            return FlightReminderBannerPalette(red: 0.85, green: 0.47, blue: 0.34)
        case .codex:
            return FlightReminderBannerPalette(red: 0.10, green: 0.11, blue: 0.13)
        case .cursor:
            return FlightReminderBannerPalette(red: 0.08, green: 0.08, blue: 0.07)
        case .mixedAgents:
            return FlightReminderBannerPalette(red: 0.10, green: 0.30, blue: 0.82)
        }
    }

    var foregroundPalette: FlightReminderBannerPalette {
        switch self {
        case .standard:
            return FlightReminderBannerPalette(red: 1.00, green: 1.00, blue: 1.00)
        case .claudeCode:
            return FlightReminderBannerPalette(red: 0.14, green: 0.08, blue: 0.06)
        case .codex, .cursor, .mixedAgents:
            return FlightReminderBannerPalette(red: 0.98, green: 0.98, blue: 0.97)
        }
    }

}

enum FlightReminderBannerStyle: Equatable {
    case normal
    case deadline
    case agentSuccess
    case agentWarning

    var ribbonPalette: FlightReminderBannerPalette {
        switch self {
        case .normal:
            return FlightReminderBannerPalette(red: 0.10, green: 0.78, blue: 0.93)
        case .deadline:
            return FlightReminderBannerPalette(red: 1.00, green: 0.18, blue: 0.22)
        case .agentSuccess:
            return FlightReminderBannerPalette(red: 0.13, green: 0.79, blue: 0.59)
        case .agentWarning:
            return FlightReminderBannerPalette(red: 1.00, green: 0.52, blue: 0.12)
        }
    }

    var shadowPalette: FlightReminderBannerPalette {
        switch self {
        case .normal:
            return FlightReminderBannerPalette(red: 0.18, green: 0.42, blue: 1.00)
        case .deadline:
            return FlightReminderBannerPalette(red: 1.00, green: 0.18, blue: 0.22)
        case .agentSuccess:
            return FlightReminderBannerPalette(red: 0.10, green: 0.58, blue: 0.36)
        case .agentWarning:
            return FlightReminderBannerPalette(red: 0.90, green: 0.30, blue: 0.08)
        }
    }
}

struct ReminderScheduleOptions: Equatable {
    var bypassMute: Bool = false
    var bypassConservativePause: Bool = false
    var bypassLimiter: Bool = false
    var playSound: Bool = true
    var frequency: FlightReminderFrequency = .medium
    var bannerStyle: FlightReminderBannerStyle = .normal

    static let standard = ReminderScheduleOptions()
    static let demo = ReminderScheduleOptions(
        bypassMute: true,
        bypassConservativePause: true,
        bypassLimiter: true
    )
}

enum ReminderSkipReason: String, Equatable {
    case muted
    case conservativePause
    case rateLimited
    case unsupportedTrigger
}

enum ReminderScheduleOutcome: Equatable {
    case shown
    case skipped(ReminderSkipReason)
}

struct DueTaskReminderCandidate: Equatable {
    let task: TodoTask
    let triggerAt: Date
    let reminderKey: String
    let phase: DueTaskReminderPhase
}

enum DueTaskReminderPhase: String, Equatable, CaseIterable {
    case lead
    case deadline
}

enum DueTaskReminderPolicy {
    static func triggerDate(for dueAt: Date, leadTime: FlightReminderLeadTime) -> Date {
        dueAt.addingTimeInterval(-leadTime.interval)
    }

    static func effectiveLeadTriggerDate(
        for task: TodoTask,
        leadTime: FlightReminderLeadTime,
        deadlineReminderEnabled: Bool
    ) -> Date? {
        guard let dueAt = task.dueAt else {
            return nil
        }

        let preferredTriggerAt = triggerDate(for: dueAt, leadTime: leadTime)
        let latestUserChangeAt = max(task.createdAt, task.updatedAt)
        if latestUserChangeAt <= preferredTriggerAt {
            return preferredTriggerAt
        }

        guard !deadlineReminderEnabled else {
            return nil
        }

        return dueAt > latestUserChangeAt ? dueAt : nil
    }

    static func deadlineTriggerDate(for task: TodoTask) -> Date? {
        guard let dueAt = task.dueAt else {
            return nil
        }
        let latestUserChangeAt = max(task.createdAt, task.updatedAt)
        return dueAt > latestUserChangeAt ? dueAt : nil
    }

    static func reminderKey(
        for task: TodoTask,
        leadTime: FlightReminderLeadTime,
        phase: DueTaskReminderPhase = .lead
    ) -> String? {
        guard let dueAt = task.dueAt else {
            return nil
        }
        let dueTimestamp = Int(dueAt.timeIntervalSince1970.rounded())
        switch phase {
        case .lead:
            return "\(task.id.uuidString)|\(dueTimestamp)|\(leadTime.rawValue)|\(phase.rawValue)"
        case .deadline:
            return "\(task.id.uuidString)|\(dueTimestamp)|\(phase.rawValue)"
        }
    }

    static func taskID(fromReminderKey key: String) -> TodoTask.ID? {
        guard let idComponent = key.split(separator: "|").first else {
            return nil
        }
        return UUID(uuidString: String(idComponent))
    }

    static func dueCandidates(
        tasks: [TodoTask],
        leadTime: FlightReminderLeadTime,
        deadlineReminderEnabled: Bool = false,
        now: Date,
        hasReminded: (String) -> Bool
    ) -> [DueTaskReminderCandidate] {
        tasks.flatMap { task in
            reminderCandidates(
                for: task,
                leadTime: leadTime,
                deadlineReminderEnabled: deadlineReminderEnabled
            ).filter { candidate in
                candidate.triggerAt <= now &&
                    isCandidateRelevant(candidate, now: now, deadlineReminderEnabled: deadlineReminderEnabled) &&
                    !hasReminded(candidate.reminderKey)
            }
        }
        .sorted(by: reminderSort)
    }

    static func nextCheckDate(
        tasks: [TodoTask],
        leadTime: FlightReminderLeadTime,
        deadlineReminderEnabled: Bool = false,
        now: Date,
        hasReminded: (String) -> Bool
    ) -> Date? {
        tasks.flatMap { task in
            reminderCandidates(
                for: task,
                leadTime: leadTime,
                deadlineReminderEnabled: deadlineReminderEnabled
            ).compactMap { candidate in
                guard !hasReminded(candidate.reminderKey),
                      isCandidateRelevant(candidate, now: now, deadlineReminderEnabled: deadlineReminderEnabled) else {
                    return nil
                }
                return candidate.triggerAt
            }
        }
        .map { $0 > now ? $0 : now }
        .min()
    }

    private static func reminderCandidates(
        for task: TodoTask,
        leadTime: FlightReminderLeadTime,
        deadlineReminderEnabled: Bool
    ) -> [DueTaskReminderCandidate] {
        guard isEligible(task) else {
            return []
        }

        var candidates: [DueTaskReminderCandidate] = []
        if let triggerAt = effectiveLeadTriggerDate(
            for: task,
            leadTime: leadTime,
            deadlineReminderEnabled: deadlineReminderEnabled
        ),
           let reminderKey = reminderKey(for: task, leadTime: leadTime, phase: .lead) {
            candidates.append(DueTaskReminderCandidate(
                task: task,
                triggerAt: triggerAt,
                reminderKey: reminderKey,
                phase: .lead
            ))
        }

        if deadlineReminderEnabled,
           let triggerAt = deadlineTriggerDate(for: task),
           let reminderKey = reminderKey(for: task, leadTime: leadTime, phase: .deadline) {
            candidates.append(DueTaskReminderCandidate(
                task: task,
                triggerAt: triggerAt,
                reminderKey: reminderKey,
                phase: .deadline
            ))
        }

        return candidates
    }

    private static func isCandidateRelevant(
        _ candidate: DueTaskReminderCandidate,
        now: Date,
        deadlineReminderEnabled: Bool
    ) -> Bool {
        guard deadlineReminderEnabled,
              candidate.phase == .lead,
              let dueAt = candidate.task.dueAt else {
            return true
        }

        return now < dueAt
    }

    private static func isEligible(_ task: TodoTask) -> Bool {
        guard task.deletedAt == nil, task.dueAt != nil else {
            return false
        }
        switch task.status {
        case .todo, .doing, .snoozed:
            return true
        case .done, .archived:
            return false
        }
    }

    private static func reminderSort(_ lhs: DueTaskReminderCandidate, _ rhs: DueTaskReminderCandidate) -> Bool {
        if lhs.triggerAt != rhs.triggerAt {
            return lhs.triggerAt < rhs.triggerAt
        }
        let leftDue = lhs.task.dueAt ?? .distantFuture
        let rightDue = rhs.task.dueAt ?? .distantFuture
        if leftDue != rightDue {
            return leftDue < rightDue
        }
        if lhs.task.priority.sortRank != rhs.task.priority.sortRank {
            return lhs.task.priority.sortRank < rhs.task.priority.sortRank
        }
        if lhs.phase != rhs.phase {
            return lhs.phase == .lead
        }
        return lhs.task.createdAt < rhs.task.createdAt
    }
}

struct DueTaskReminderHistory {
    private struct Payload: Codable {
        var entries: [String: Date]
    }

    private static let storageKey = "flightReminders.dueTask.history.v1"
    private static let retention: TimeInterval = 30 * 24 * 60 * 60

    private let defaults: UserDefaults
    private var entries: [String: Date]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            entries = payload.entries
        } else {
            entries = [:]
        }
    }

    func hasReminded(_ key: String) -> Bool {
        entries[key] != nil
    }

    mutating func record(_ key: String, at date: Date) {
        entries[key] = date
        persist()
    }

    mutating func prune(activeTaskIDs: Set<TodoTask.ID>, now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        entries = entries.filter { key, remindedAt in
            guard remindedAt >= cutoff,
                  let taskID = DueTaskReminderPolicy.taskID(fromReminderKey: key) else {
                return false
            }
            return activeTaskIDs.contains(taskID)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Payload(entries: entries)) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

private struct DueTaskReminderSettingsSnapshot: Equatable {
    let enabled: Bool
    let leadTime: FlightReminderLeadTime
    let deadlineReminderEnabled: Bool
}

@MainActor
protocol ReminderScheduler {
    func scheduleReminder(
        for task: TodoTask,
        actions: FlightReminderActions,
        options: ReminderScheduleOptions
    ) async -> ReminderScheduleOutcome
    func muteAllReminders(_ muted: Bool)
}

extension ReminderScheduler {
    func scheduleReminder(for task: TodoTask, actions: FlightReminderActions) async -> ReminderScheduleOutcome {
        await scheduleReminder(for: task, actions: actions, options: .standard)
    }
}

@MainActor
final class LocalReminderScheduler: ReminderScheduler {
    private var muted = false
    private var limiter = FlightReminderLimiter()
    private let logger: PrivacyLogger?
    private let panelController: FlightReminderPanelController

    init(logger: PrivacyLogger? = nil) {
        self.logger = logger
        self.panelController = FlightReminderPanelController(logger: logger)
    }

    func scheduleReminder(
        for task: TodoTask,
        actions: FlightReminderActions,
        options: ReminderScheduleOptions = .standard
    ) async -> ReminderScheduleOutcome {
        let startedAt = Date()
        logger?.info("flight_reminder_schedule_started", metadata: [
            "bypass_limiter": .boolean(options.bypassLimiter)
        ])

        guard !muted || options.bypassMute else {
            logger?.info("flight_reminder_schedule_skipped", metadata: [
                "reason": .publicText(ReminderSkipReason.muted.rawValue)
            ])
            return .skipped(.muted)
        }

        guard options.bypassConservativePause || !ConservativeReminderContext.shouldPauseReminders() else {
            logger?.info("flight_reminder_schedule_skipped", metadata: [
                "reason": .publicText(ReminderSkipReason.conservativePause.rawValue)
            ])
            return .skipped(.conservativePause)
        }

        guard options.bypassLimiter || limiter.reserveSlot(for: task.id, frequency: options.frequency) else {
            logger?.info("flight_reminder_schedule_skipped", metadata: [
                "reason": .publicText(ReminderSkipReason.rateLimited.rawValue)
            ])
            return .skipped(.rateLimited)
        }

        panelController.show(
            task: task,
            actions: actions,
            playSound: options.playSound,
            bannerStyle: options.bannerStyle
        )
        logger?.info("flight_reminder_schedule_completed", metadata: [
            "duration_ms": .numeric(Int(Date().timeIntervalSince(startedAt) * 1000))
        ])
        return .shown
    }

    func muteAllReminders(_ muted: Bool) {
        self.muted = muted
        if muted {
            panelController.dismiss()
        }
    }
}

@MainActor
final class DueTaskReminderScheduler {
    private let taskStore: TaskStore
    private let settingsStore: LocalSettingsStore
    private let logger: PrivacyLogger?
    private let now: () -> Date
    private let scheduleReminder: @MainActor (TodoTask, DueTaskReminderPhase) async -> ReminderScheduleOutcome
    private var history: DueTaskReminderHistory
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isEvaluating = false
    private var needsEvaluation = false
    private var isStarted = false

    private let cascadeDelay: TimeInterval = FlightReminderTiming.flightDuration + FlightReminderTiming.autoDismissDelay + 1.0
    private let retryDelay: TimeInterval = 60

    init(
        taskStore: TaskStore,
        settingsStore: LocalSettingsStore,
        logger: PrivacyLogger? = nil,
        history: DueTaskReminderHistory = DueTaskReminderHistory(),
        now: @escaping () -> Date = { Date() },
        scheduleReminder: @escaping @MainActor (TodoTask, DueTaskReminderPhase) async -> ReminderScheduleOutcome
    ) {
        self.taskStore = taskStore
        self.settingsStore = settingsStore
        self.logger = logger
        self.history = history
        self.now = now
        self.scheduleReminder = scheduleReminder
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        bindChanges()
        scheduleEvaluation(after: 0.35)
        logger?.info("due_task_reminder_scheduler_started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        isStarted = false
        logger?.info("due_task_reminder_scheduler_stopped")
    }

    private func bindChanges() {
        taskStore.$tasks
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleEvaluation(after: 0.35)
                }
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map {
                DueTaskReminderSettingsSnapshot(
                    enabled: $0.flightRemindersEnabled,
                    leadTime: $0.flightReminderLeadTime,
                    deadlineReminderEnabled: $0.flightReminderAtDeadlineEnabled
                )
            }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleEvaluation(after: 0.35)
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleEvaluation(after delay: TimeInterval) {
        timer?.invalidate()
        let interval = max(0.05, delay)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluate()
            }
        }
        timer.tolerance = timerTolerance(for: interval)
        self.timer = timer
    }

    private func timerTolerance(for interval: TimeInterval) -> TimeInterval {
        if interval < 5 {
            return 0.1
        }
        if interval < 60 {
            return 1
        }
        return min(60, interval * 0.05)
    }

    private func evaluate() async {
        guard !isEvaluating else {
            needsEvaluation = true
            return
        }

        isEvaluating = true
        needsEvaluation = false
        defer {
            isEvaluating = false
            if needsEvaluation {
                scheduleEvaluation(after: 0.2)
            }
        }

        let settings = settingsStore.settings
        guard settings.flightRemindersEnabled else {
            logger?.info("due_task_reminder_scheduler_paused", metadata: [
                "reason": .publicText(ReminderSkipReason.muted.rawValue)
            ])
            return
        }

        let currentDate = now()
        let activeTaskIDs = Set(taskStore.activeTasks.map(\.id))
        history.prune(activeTaskIDs: activeTaskIDs, now: currentDate)

        let candidates = DueTaskReminderPolicy.dueCandidates(
            tasks: taskStore.tasks,
            leadTime: settings.flightReminderLeadTime,
            deadlineReminderEnabled: settings.flightReminderAtDeadlineEnabled,
            now: currentDate,
            hasReminded: history.hasReminded
        )

        if let candidate = candidates.first {
            logger?.info("due_task_reminder_candidate_found", metadata: [
                "candidate_count": .numeric(candidates.count),
                "lead_minutes": .numeric(settings.flightReminderLeadTime.minutes),
                "phase": .publicText(candidate.phase.rawValue)
            ])
            let outcome = await scheduleReminder(candidate.task, candidate.phase)
            handleReminderOutcome(outcome, candidate: candidate, now: currentDate)
            return
        }

        scheduleNextFutureCheck(
            leadTime: settings.flightReminderLeadTime,
            deadlineReminderEnabled: settings.flightReminderAtDeadlineEnabled,
            now: currentDate
        )
    }

    private func handleReminderOutcome(
        _ outcome: ReminderScheduleOutcome,
        candidate: DueTaskReminderCandidate,
        now: Date
    ) {
        switch outcome {
        case .shown:
            history.record(candidate.reminderKey, at: now)
            logger?.info("due_task_reminder_recorded", metadata: [
                "lead_minutes": .numeric(settingsStore.settings.flightReminderLeadTime.minutes),
                "phase": .publicText(candidate.phase.rawValue)
            ])
            scheduleEvaluation(after: cascadeDelay)
        case let .skipped(reason):
            logger?.info("due_task_reminder_deferred", metadata: [
                "reason": .publicText(reason.rawValue)
            ])
            scheduleEvaluation(after: retryDelay)
        }
    }

    private func scheduleNextFutureCheck(
        leadTime: FlightReminderLeadTime,
        deadlineReminderEnabled: Bool,
        now: Date
    ) {
        guard let nextCheckDate = DueTaskReminderPolicy.nextCheckDate(
            tasks: taskStore.tasks,
            leadTime: leadTime,
            deadlineReminderEnabled: deadlineReminderEnabled,
            now: now,
            hasReminded: history.hasReminded
        ) else {
            timer?.invalidate()
            timer = nil
            logger?.info("due_task_reminder_scheduler_idle")
            return
        }

        let delay = max(0.2, nextCheckDate.timeIntervalSince(now))
        logger?.info("due_task_reminder_next_check_scheduled", metadata: [
            "delay_seconds": .numeric(Int(delay)),
            "lead_minutes": .numeric(leadTime.minutes),
            "deadline_enabled": .boolean(deadlineReminderEnabled)
        ])
        scheduleEvaluation(after: delay)
    }
}

struct FlightReminderLimiter {
    private var perTaskShownAt: [TodoTask.ID: [Date]] = [:]
    private var allShownAt: [Date] = []

    mutating func reserveSlot(
        for taskID: TodoTask.ID,
        at now: Date = Date(),
        frequency: FlightReminderFrequency = .medium
    ) -> Bool {
        prune(now: now)

        let taskEvents = perTaskShownAt[taskID, default: []]
        guard taskEvents.count < frequency.perTaskLimitPerThirtyMinutes,
              allShownAt.count < frequency.globalLimitPerHour else {
            return false
        }

        perTaskShownAt[taskID, default: []].append(now)
        allShownAt.append(now)
        return true
    }

    private mutating func prune(now: Date) {
        let taskWindowStart = now.addingTimeInterval(-30 * 60)
        let globalWindowStart = now.addingTimeInterval(-60 * 60)

        perTaskShownAt = perTaskShownAt.mapValues { dates in
            dates.filter { $0 >= taskWindowStart }
        }
        allShownAt = allShownAt.filter { $0 >= globalWindowStart }
    }
}

private enum ConservativeReminderContext {
    static func shouldPauseReminders() -> Bool {
        let mainDisplayID = CGMainDisplayID()
        if CGDisplayIsInMirrorSet(mainDisplayID) != 0 {
            return true
        }

        let meetingAppBundleIDs: Set<String> = [
            "com.apple.FaceTime",
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "Cisco-Systems.Spark",
            "com.cisco.webexmeetingsapp"
        ]
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return frontmostBundleID.map(meetingAppBundleIDs.contains) ?? false
    }
}

// 生命周期由窗口控制器拥有，关闭时同步撤销，不能依赖 SwiftUI 延后的 onDisappear。
@MainActor
final class FlightReminderPresentationLifecycle {
    private(set) var isCancelled = false
    private var timer: Timer?
    private var startedAtUptime: TimeInterval?

    var hasScheduledTimer: Bool { timer?.isValid == true }

    @discardableResult
    func begin(at uptime: TimeInterval) -> Bool {
        guard !isCancelled else { return false }
        timer?.invalidate()
        timer = nil
        startedAtUptime = uptime
        return true
    }

    func register(_ timer: Timer) {
        guard !isCancelled, startedAtUptime != nil else {
            timer.invalidate()
            return
        }
        self.timer?.invalidate()
        self.timer = timer
    }

    func elapsed(at uptime: TimeInterval, visualLead: TimeInterval) -> TimeInterval {
        guard let startedAtUptime else { return 0 }
        return max(0, uptime - startedAtUptime) + visualLead
    }

    func cancel() {
        isCancelled = true
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class FlightReminderPanelController {
    private let logger: PrivacyLogger?
    private(set) var panel: NSPanel?
    private var activePresentationID: UUID?
    private(set) var activeLifecycle: FlightReminderPresentationLifecycle?

    init(logger: PrivacyLogger?) {
        self.logger = logger
    }

    func show(
        task: TodoTask,
        actions: FlightReminderActions,
        playSound: Bool,
        bannerStyle: FlightReminderBannerStyle
    ) {
        let startedAt = Date()
        dismiss()
        let presentationID = UUID()
        activePresentationID = presentationID
        let lifecycle = FlightReminderPresentationLifecycle()
        activeLifecycle = lifecycle

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let panelSize = CGSize(
            width: max(640, screenFrame.width),
            height: min(360, max(280, screenFrame.height * 0.42))
        )
        let panelY = screenFrame.maxY - panelSize.height - 74
        let panelX = screenFrame.minX
        let frame = CGRect(
            x: panelX,
            y: panelY,
            width: panelSize.width,
            height: panelSize.height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        // 飞行路径由内容动画控制，透明承载窗口不额外执行系统窗口变换。
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        let hostingView = NSHostingView(rootView: FlightReminderView(
            task: task,
            actions: actions,
            logger: logger,
            playSound: playSound,
            bannerStyle: bannerStyle,
            lifecycle: lifecycle,
            onProgress: { _ in },
            onDismiss: { [weak self] in
                // 旧提醒的延后回调不能关闭刚创建的新提醒。
                guard self?.activePresentationID == presentationID else { return }
                self?.dismiss()
            }
        ).frame(width: panelSize.width, height: panelSize.height))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        self.panel = panel
        panel.orderFrontRegardless()
        logger?.info("flight_panel_ordered_front", metadata: [
            "duration_ms": .numeric(Int(Date().timeIntervalSince(startedAt) * 1000)),
            "screen_count": .numeric(NSScreen.screens.count)
        ])
    }

    func dismiss() {
        activeLifecycle?.cancel()
        activeLifecycle = nil
        guard let panel else { return }
        // 先解除控制器引用，防止 SwiftUI 的卸载回调重入时操作同一窗口。
        self.panel = nil
        activePresentationID = nil
        // orderOut 只隐藏窗口；显式卸载可取消飞行计时器，并拆除合成动画与观察者。
        panel.contentView = nil
        panel.orderOut(nil)
        panel.close()
        // 空闲时 NSApplication 可能仍在同一轮等待事件，框架外层 Cocoa 池暂留已关闭窗口。
        // 只唤醒本应用进入下一事件边界排空该池，不激活窗口，也不产生键盘或鼠标输入。
        if let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, subtype: 0, data1: 0, data2: 0
        ) {
            NSApp.postEvent(event, atStart: false)
        }
    }
}

enum FlightReminderTiming {
    static let flightDuration: TimeInterval = 5.80
    static let autoDismissDelay: TimeInterval = 0.55
    static let initialVisualProgress = 0.025
    static let centerHoldStart = 0.36
    static let centerHoldEnd = 0.66
    static let engineAudioDuration = flightDuration + autoDismissDelay
}

private struct FlightReminderView: View {
    let task: TodoTask
    let actions: FlightReminderActions
    let logger: PrivacyLogger?
    let playSound: Bool
    let bannerStyle: FlightReminderBannerStyle
    let lifecycle: FlightReminderPresentationLifecycle
    let onProgress: (Double) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: Double = 0
    @State private var elapsed: TimeInterval = 0
    @State private var isHovering = false
    @State private var didPlayCenterCue = false

    private let flightDuration = FlightReminderTiming.flightDuration
    private let autoDismissDelay = FlightReminderTiming.autoDismissDelay
    private let initialVisualProgress = FlightReminderTiming.initialVisualProgress
    private let centerHoldStart = FlightReminderTiming.centerHoldStart
    private let centerHoldEnd = FlightReminderTiming.centerHoldEnd
    private let engineAudioDuration = FlightReminderTiming.engineAudioDuration

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let flightX = flightGroupX(in: width)
            let flightY = flightGroupY()
            let flightScale = min(1.0, max(0.72, width / 1180))

            ZStack(alignment: .topLeading) {
                FlightReminderAircraftGroup(
                    title: task.shortTitle,
                    progress: progress,
                    bannerStyle: bannerStyle,
                    flagTheme: actions.presentation.flagTheme,
                    agentProviders: actions.presentation.agentProviders,
                    agentOutcomeBadge: actions.presentation.agentOutcomeBadge
                )
                .scaleEffect(flightScale)
                .rotationEffect(.degrees(isHovering ? 0 : -0.8))
                .opacity(flightOpacity)
                .position(x: flightX, y: flightY)

                Button {
                    actions.complete(task.id)
                    actions.dismiss("primary_action")
                    onDismiss()
                } label: {
                    Label(actions.presentation.primaryTitle, systemImage: primaryActionSystemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(.black.opacity(0.78), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .opacity(primaryActionOpacity)
                .allowsHitTesting(primaryActionOpacity > 0.45)
                .position(x: width * 0.52, y: 292)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: startTimer)
        .onDisappear { lifecycle.cancel() }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
    }

    private var dueText: String {
        guard let dueAt = task.dueAt else {
            return "Next task"
        }
        return dueAt.formatted(date: .omitted, time: .shortened)
    }

    private var primaryActionSystemImage: String {
        switch actions.presentation.kind {
        case .task:
            "checkmark"
        case .agentSuccess, .agentWarning:
            "arrow.up.forward.app"
        }
    }

    private var primaryActionOpacity: Double {
        if reduceMotion {
            return 1
        }
        guard progress >= centerHoldStart, progress <= centerHoldEnd else {
            return 0
        }
        let fadeIn = min(1, (progress - centerHoldStart) / 0.06)
        let fadeOut = min(1, (centerHoldEnd - progress) / 0.06)
        return max(0, min(fadeIn, fadeOut))
    }

    private var flightOpacity: Double {
        guard !reduceMotion else {
            return 1
        }

        if progress < 0.02 {
            return progress / 0.02
        }

        if progress > 0.94 {
            return max(0, (1 - progress) / 0.06)
        }

        return 1
    }

    private func flightGroupX(in width: CGFloat) -> CGFloat {
        let restingX = width * 0.52
        guard !reduceMotion else {
            return restingX
        }

        if progress < centerHoldStart {
            let t = easeOut(progress / centerHoldStart)
            let startX: CGFloat = -540
            return startX + (restingX - startX) * CGFloat(t)
        }

        if progress < centerHoldEnd {
            return restingX
        }

        let t = easeIn((progress - centerHoldEnd) / (1 - centerHoldEnd))
        return restingX + (width + 620 - restingX) * CGFloat(t)
    }

    private func flightGroupY() -> CGFloat {
        guard !reduceMotion else {
            return 182
        }

        guard progress < centerHoldStart || progress >= centerHoldEnd else {
            return 182
        }

        return 182 + CGFloat(sin(progress * .pi * 5.2) * 5)
    }

    private func easeOut(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    private func easeIn(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return pow(clamped, 2)
    }

    private func startTimer() {
        // 重载下 onAppear 可能晚于面板关闭，已撤销的展示不能再次注册计时器或播放声音。
        guard lifecycle.begin(at: ProcessInfo.processInfo.systemUptime) else { return }
        didPlayCenterCue = false
        elapsed = reduceMotion ? 0 : flightDuration * initialVisualProgress
        progress = reduceMotion ? 1 : initialVisualProgress
        onProgress(progress)
        logger?.info("flight_animation_started", metadata: [
            "reduce_motion": .boolean(reduceMotion),
            "visual_lead_ms": .numeric(Int(elapsed * 1000))
        ])
        if playSound {
            if reduceMotion {
                didPlayCenterCue = true
                FlightSoundPlayer.shared.playHorn(logger: logger)
            } else {
                FlightSoundPlayer.shared.playEngine(duration: engineAudioDuration, logger: logger)
            }
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            Task { @MainActor in
                // 窗口卸载后，已排入主队列的旧 tick 也必须停止，避免触发过期的自动关闭。
                guard !lifecycle.isCancelled, timer.isValid else { return }
                // 按单调时钟计算真实经过时长，掉帧不能延长提醒寿命或拖慢飞行。
                elapsed = lifecycle.elapsed(
                    at: ProcessInfo.processInfo.systemUptime,
                    visualLead: reduceMotion ? 0 : flightDuration * initialVisualProgress
                )
                progress = reduceMotion ? 1 : min(elapsed / flightDuration, 1.0)
                onProgress(progress)
                if playSound, !didPlayCenterCue, progress >= centerHoldStart {
                    didPlayCenterCue = true
                    FlightSoundPlayer.shared.playHorn(logger: logger)
                }

                if elapsed >= flightDuration + autoDismissDelay {
                    timer.invalidate()
                    actions.dismiss("auto")
                    onDismiss()
                }
            }
        }
        lifecycle.register(timer)
    }
}

enum FlightSoundWaveform {
    static let sampleRate = 44_100
    static let hornDuration = 0.54
    static let carHornLowFrequency = 659.25
    static let carHornHighFrequency = 830.61
    static let carHornGapStart = 0.19
    static let carHornGapEnd = 0.29

    static func makeEngineSoundData(duration: TimeInterval) -> Data {
        let resolvedDuration = max(2.0, duration)
        let sampleCount = Int(Double(sampleRate) * resolvedDuration)
        var pcm = Data()
        pcm.reserveCapacity(sampleCount * 4)

        for sampleIndex in 0..<sampleCount {
            let t = Double(sampleIndex) / Double(sampleRate)
            let normalized = t / resolvedDuration
            let attack = min(1, t / 0.65)
            let release = min(1, max(0, (resolvedDuration - t) / 0.45))
            let envelope = attack * release

            // Keep the engine procedural so the full pass has one continuous source.
            let base = 92.0
            let saw1 = 2.0 * ((base * t).truncatingRemainder(dividingBy: 1)) - 1
            let saw2 = 2.0 * (((base * 1.012) * t).truncatingRemainder(dividingBy: 1)) - 1
            let wobble = 0.86 + 0.14 * sin(2 * Double.pi * 11.0 * t)
            let propPulse = 0.88 + 0.12 * sin(2 * Double.pi * 28.0 * t)
            let motor = 0.28 * (saw1 + saw2) * 0.5
                + 0.18 * sin(2 * Double.pi * base * 2.0 * t)
                + 0.06 * sin(2 * Double.pi * 620.0 * t)
            let value = max(-1, min(1, motor * wobble * propPulse * envelope * 0.82))

            let pan = -0.35 + 0.70 * normalized
            let leftGain = sqrt((1 - pan) / 2)
            let rightGain = sqrt((1 + pan) / 2)
            var left = Int16(value * leftGain * Double(Int16.max)).littleEndian
            var right = Int16(value * rightGain * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &left) { bytes in
                pcm.append(contentsOf: bytes)
            }
            withUnsafeBytes(of: &right) { bytes in
                pcm.append(contentsOf: bytes)
            }
        }

        return wavData(sampleRate: sampleRate, channels: 2, pcm: pcm)
    }

    static func makeHornSoundData() -> Data {
        let sampleCount = Int(Double(sampleRate) * hornDuration)
        var pcm = Data()
        pcm.reserveCapacity(sampleCount * 2)

        for sampleIndex in 0..<sampleCount {
            let t = Double(sampleIndex) / Double(sampleRate)
            let firstPulse = carHornPulse(
                t: t,
                start: 0.03,
                duration: 0.15
            )
            let secondPulse = carHornPulse(
                t: t,
                start: carHornGapEnd,
                duration: 0.15
            )
            let value = max(-1, min(1, firstPulse + secondPulse))
            var sample = Int16(value * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { bytes in
                pcm.append(contentsOf: bytes)
            }
        }

        return wavData(sampleRate: sampleRate, channels: 1, pcm: pcm)
    }

    private static func carHornPulse(
        t: Double,
        start: Double,
        duration: Double
    ) -> Double {
        let localT = t - start
        guard localT >= 0, localT <= duration else {
            return 0
        }

        let attack = min(1, localT / 0.006)
        let release = min(1, max(0, (duration - localT) / 0.046))
        let envelope = attack * release
        let pitchBend = 1 + 0.008 * exp(-localT * 10.0)
        let vibrato = 1 + 0.003 * sin(2 * Double.pi * 7.5 * localT)
        let low = carHornLowFrequency * pitchBend * vibrato
        let high = carHornHighFrequency * pitchBend * vibrato
        let tone = 0.48 * sin(2 * Double.pi * low * localT)
            + 0.42 * sin(2 * Double.pi * high * localT)
            + 0.12 * sin(2 * Double.pi * low * 2.0 * localT)
            + 0.08 * sin(2 * Double.pi * high * 2.0 * localT)
            + 0.03 * sin(2 * Double.pi * low * 3.0 * localT)
        let click = localT < 0.012
            ? 0.06 * sin(2 * Double.pi * 2_050.0 * localT) * (1 - localT / 0.012)
            : 0
        let brassyTone = tanh((tone + click) * 1.35)
        return max(-1, min(1, brassyTone * envelope * 0.94))
    }

    private static func wavData(sampleRate: Int, channels: UInt16, pcm: Data) -> Data {
        var data = Data()
        let bytesPerSample = UInt16(2)
        appendASCII("RIFF", to: &data)
        appendUInt32(UInt32(36 + pcm.count), to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(channels, to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(sampleRate * Int(channels) * Int(bytesPerSample)), to: &data)
        appendUInt16(channels * bytesPerSample, to: &data)
        appendUInt16(bytesPerSample * 8, to: &data)
        appendASCII("data", to: &data)
        appendUInt32(UInt32(pcm.count), to: &data)
        data.append(pcm)
        return data
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        guard let bytes = string.data(using: .ascii) else {
            return
        }
        data.append(bytes)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

@MainActor
private final class FlightSoundPlayer {
    static let shared = FlightSoundPlayer()

    private var activePlayers: [AVAudioPlayer] = []

    func playEngine(duration: TimeInterval, logger: PrivacyLogger?) {
        let retainFor = max(1.2, duration + 0.7)
        playSound(
            data: FlightSoundWaveform.makeEngineSoundData(duration: duration),
            logger: logger,
            event: "flight_sound_started",
            retainFor: retainFor
        )
    }

    func playHorn(logger: PrivacyLogger?) {
        duckActivePlayersForCue()
        playSound(
            data: FlightSoundWaveform.makeHornSoundData(),
            logger: logger,
            event: "flight_horn_started",
            retainFor: 1.4
        )
    }

    private func duckActivePlayersForCue() {
        let playingPlayers = activePlayers.filter(\.isPlaying)
        guard !playingPlayers.isEmpty else {
            return
        }

        playingPlayers.forEach { player in
            player.setVolume(0.22, fadeDuration: 0.05)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) { [weak self] in
            self?.activePlayers
                .filter(\.isPlaying)
                .forEach { player in
                    player.setVolume(1.0, fadeDuration: 0.16)
                }
        }
    }

    private func playSound(
        data: Data,
        logger: PrivacyLogger?,
        event: String,
        retainFor: TimeInterval
    ) {
        if play(data: data, logger: logger, event: event, retainFor: retainFor) {
            return
        }

        logger?.error("flight_sound_prepare_failed")
        NSSound.beep()
    }

    private func play(data: Data, logger: PrivacyLogger?, event: String, retainFor: TimeInterval) -> Bool {
        guard let player = try? AVAudioPlayer(data: data) else {
            return false
        }
        return play(player: player, logger: logger, event: event, retainFor: retainFor)
    }

    private func play(player: AVAudioPlayer, logger: PrivacyLogger?, event: String, retainFor: TimeInterval) -> Bool {
        player.volume = 1.0
        player.prepareToPlay()
        activePlayers.append(player)
        guard player.play() else {
            activePlayers.removeAll { $0 === player }
            logger?.error("flight_sound_play_failed")
            return false
        }

        logger?.info(event)
        DispatchQueue.main.asyncAfter(deadline: .now() + retainFor) { [weak self, weak player] in
            guard let player else {
                return
            }
            self?.activePlayers.removeAll { $0 === player }
        }
        return true
    }
}

private struct FlightReminderAircraftGroup: View {
    let title: String
    let progress: Double
    let bannerStyle: FlightReminderBannerStyle
    let flagTheme: FlightReminderFlagTheme
    let agentProviders: [AgentProvider]
    let agentOutcomeBadge: AgentFlagOutcomeBadge?

    var body: some View {
        let bannerFlutter = CGFloat(sin(progress * .pi * 12))
        let planeFlutter = CGFloat(sin(progress * .pi * 10))
        let bannerReveal = segment(from: 0.05, to: 0.18)
        let bannerColor = flagTheme.backgroundPalette(fallback: bannerStyle).color
        let shadowColor = bannerStyle.shadowPalette.color

        ZStack {
            PixelRibbonBanner(
                title: title,
                color: bannerColor,
                textColor: flagTheme.foregroundPalette.color,
                flagTheme: flagTheme,
                agentProviders: agentProviders,
                agentOutcomeBadge: agentOutcomeBadge,
                phase: progress
            )
                .frame(width: 374, height: 82)
                .rotationEffect(.degrees(-2.6 + Double(bannerFlutter) * 1.4))
                .offset(x: -260, y: -38 + bannerFlutter * 4)
                .scaleEffect(
                    x: 0.94 + CGFloat(bannerReveal) * 0.06,
                    y: flagTheme.isAgentTheme
                        ? 0.94 + CGFloat(bannerReveal) * 0.06
                        : 0.96 + bannerFlutter * 0.018
                )
                .opacity(bannerReveal)

            PixelTowLine()
                .frame(width: 126, height: 6)
                .opacity(bannerReveal)
                .offset(x: -46, y: -32 + bannerFlutter * 2)

            PixelPlaneMark(animated: true, variant: .flight)
                .frame(width: 310, height: 145)
                .rotationEffect(.degrees(Double(planeFlutter * 2.2)))
                .offset(x: 206, y: -48 + planeFlutter * 5)
                .shadow(color: shadowColor.opacity(0.28), radius: 18, y: 8)
        }
        .frame(width: 920, height: 220)
        .contentShape(Rectangle())
    }

    private func segment(from start: Double, to end: Double) -> Double {
        guard end > start else {
            return progress >= end ? 1 : 0
        }
        let value = min(max((progress - start) / (end - start), 0), 1)
        return value * value * (3 - 2 * value)
    }
}

private struct ReminderIconButton: View {
    let systemImage: String
    var tint: Color = Color(red: 0.18, green: 0.42, blue: 1)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.borderless)
    }
}

private struct PixelTowLine: View {
    var body: some View {
        GeometryReader { geometry in
            let count = max(6, Int(geometry.size.width / 12))
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.34))
                        .frame(width: 5, height: 3)
                }
            }
        }
    }
}

private struct PixelTowLineVertical: View {
    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { _ in
                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .frame(width: 3, height: 5)
            }
        }
    }
}

private struct FlightTaskCard: View {
    let title: String
    let dueText: String
    let completeTitle: String
    let snoozeTitle: String
    let complete: () -> Void
    let snooze: () -> Void
    let open: () -> Void
    let mute: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: 1, green: 0.30, blue: 0.31))
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button(action: mute) {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .buttonStyle(.plain)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(action: complete) {
                    Label(completeTitle, systemImage: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Color(red: 0.13, green: 0.79, blue: 0.59), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: snooze) {
                    Label(snoozeTitle, systemImage: "clock")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.74))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(.white.opacity(0.13), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: open) {
                    Text(dueText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 350, alignment: .leading)
        .background(Color.black.opacity(0.96), in: UnevenRoundedRectangle(
            topLeadingRadius: 8,
            bottomLeadingRadius: 22,
            bottomTrailingRadius: 22,
            topTrailingRadius: 8,
            style: .continuous
        ))
        .overlay(alignment: .top) {
            Triangle()
                .fill(Color.black.opacity(0.96))
                .frame(width: 26, height: 14)
                .offset(y: -12)
        }
        .shadow(color: .black.opacity(0.30), radius: 24, y: 14)
        .onTapGesture(perform: open)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PixelFlagBanner: View {
    let title: String
    let dueText: String
    let complete: () -> Void
    let snooze: () -> Void
    let open: () -> Void
    let mute: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PixelFlagMark()
                .frame(width: 22, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.14, blue: 0.16))
                    .lineLimit(1)

                Text(dueText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            ReminderIconButton(systemImage: "checkmark", tint: Color(red: 0.13, green: 0.79, blue: 0.59), action: complete)
                .help("Complete")
            ReminderIconButton(systemImage: "clock.arrow.circlepath", tint: Color(red: 0.98, green: 0.68, blue: 0.08), action: snooze)
                .help("Snooze 10 minutes")
            ReminderIconButton(systemImage: "arrow.up.forward.app", action: open)
                .help("Open")
            ReminderIconButton(systemImage: "speaker.slash", tint: Color(red: 0.48, green: 0.51, blue: 0.56), action: mute)
                .help("Mute")
            ReminderIconButton(systemImage: "xmark", tint: Color(red: 1, green: 0.30, blue: 0.31), action: close)
                .help("Close")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .onTapGesture(perform: open)
    }
}

struct PixelPlaneMark: View {
    var color: Color = Color(red: 0.18, green: 0.42, blue: 1)
    var animated: Bool = false
    var variant: PixelPlaneMarkVariant = .compact

    var body: some View {
        if let image = TodoPilotVisualAssets.flightPlaneDog {
            GeometryReader { geometry in
                let layout = PixelPlaneMarkLayout(
                    containerSize: geometry.size,
                    variant: variant,
                    animated: animated
                )

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .leading) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .antialiased(false)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                    }
                    .frame(
                        width: layout.planeBodyFrame.width,
                        height: layout.planeBodyFrame.height,
                        alignment: .leading
                    )
                    .clipped()
                    .position(x: layout.planeBodyFrame.midX, y: layout.planeBodyFrame.midY)

                    if let propellerFrame = layout.propellerFrame {
                        PixelPropellerSpinner(animated: animated)
                            .frame(width: propellerFrame.width, height: propellerFrame.height)
                            .position(x: propellerFrame.midX, y: propellerFrame.midY)
                            .opacity(layout.propellerOpacity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        } else {
            PixelPlaneFallbackMark(color: color, animated: animated)
        }
    }
}

enum PixelPlaneMarkVariant {
    case compact
    case statusIsland
    case flight
}

struct PixelPlaneMarkLayout: Equatable {
    static let assetAspectRatio = CGFloat(1155.0 / 646.0)

    let imageFrame: CGRect
    let planeBodyFrame: CGRect
    let propellerFrame: CGRect?
    let propellerOpacity: Double

    init(containerSize: CGSize, variant: PixelPlaneMarkVariant, animated: Bool) {
        guard containerSize.width > 0, containerSize.height > 0 else {
            imageFrame = .zero
            planeBodyFrame = .zero
            propellerFrame = nil
            propellerOpacity = 0
            return
        }

        let fittedSize = Self.aspectFitSize(for: containerSize)
        imageFrame = CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        planeBodyFrame = imageFrame

        guard animated || variant == .statusIsland else {
            propellerFrame = nil
            propellerOpacity = 0
            return
        }

        let propellerMetrics = Self.propellerMetrics(for: variant, imageFrame: imageFrame)
        propellerFrame = CGRect(
            x: propellerMetrics.center.x - propellerMetrics.size.width / 2,
            y: propellerMetrics.center.y - propellerMetrics.size.height / 2,
            width: propellerMetrics.size.width,
            height: propellerMetrics.size.height
        )
        propellerOpacity = propellerMetrics.opacity
    }

    private static func aspectFitSize(for containerSize: CGSize) -> CGSize {
        let containerAspectRatio = containerSize.width / containerSize.height
        if containerAspectRatio > assetAspectRatio {
            let height = containerSize.height
            return CGSize(width: height * assetAspectRatio, height: height)
        }

        let width = containerSize.width
        return CGSize(width: width, height: width / assetAspectRatio)
    }

    private static func propellerMetrics(
        for variant: PixelPlaneMarkVariant,
        imageFrame: CGRect
    ) -> (center: CGPoint, size: CGSize, opacity: Double) {
        let centerXRatio: CGFloat
        let centerYRatio: CGFloat
        let heightRatio: CGFloat
        let widthRatio: CGFloat
        let opacity: Double

        switch variant {
        case .compact:
            centerXRatio = 0.961
            centerYRatio = 0.630
            heightRatio = 0.58
            widthRatio = 0.14
            opacity = 0.88
        case .statusIsland:
            centerXRatio = 0.961
            centerYRatio = 0.630
            heightRatio = 0.56
            widthRatio = 0.13
            opacity = 0.82
        case .flight:
            centerXRatio = 0.961
            centerYRatio = 0.630
            heightRatio = 0.60
            widthRatio = 0.15
            opacity = 1
        }

        let propellerHeight = max(8, imageFrame.height * heightRatio)
        let propellerWidth = max(4, imageFrame.height * widthRatio)
        let center = CGPoint(
            x: imageFrame.minX + imageFrame.width * centerXRatio,
            y: imageFrame.minY + imageFrame.height * centerYRatio
        )
        return (center, CGSize(width: propellerWidth, height: propellerHeight), opacity)
    }
}

private enum TodoPilotVisualAssets {
    static let flightPlaneDog: NSImage? = {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "FlightPlaneDog", withExtension: "png"),
            Bundle.main.url(forResource: "FlightPlaneDog", withExtension: "png", subdirectory: "VisualAssets"),
            Bundle.main.url(forResource: "FlightPlaneDog", withExtension: "png", subdirectory: "Resources/VisualAssets")
        ]

        guard let url = candidates.compactMap({ $0 }).first else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

private struct PixelPlaneFallbackMark: View {
    var color: Color = Color(red: 0.18, green: 0.42, blue: 1)
    var animated: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width / 92, geometry.size.height / 54)
            let drawingWidth = 92 * unit
            let drawingHeight = 54 * unit

            ZStack(alignment: .topLeading) {
                Group {
                    PixelBlock(x: 18, y: 24, width: 48, height: 16, color: .black, unit: unit)
                    PixelBlock(x: 65, y: 27, width: 10, height: 10, color: .black, unit: unit)
                    PixelBlock(x: 8, y: 18, width: 13, height: 17, color: .black, unit: unit)
                    PixelBlock(x: 4, y: 10, width: 9, height: 12, color: .black, unit: unit)
                    PixelBlock(x: 36, y: 15, width: 26, height: 9, color: .black, unit: unit)
                    PixelBlock(x: 35, y: 39, width: 28, height: 9, color: .black, unit: unit)
                    PixelBlock(x: 50, y: 12, width: 15, height: 13, color: .black, unit: unit)
                }

                Group {
                    PixelBlock(x: 20, y: 26, width: 42, height: 12, color: Color(red: 0.98, green: 0.98, blue: 0.95), unit: unit)
                    PixelBlock(x: 62, y: 29, width: 9, height: 6, color: Color(red: 0.98, green: 0.98, blue: 0.95), unit: unit)
                    PixelBlock(x: 56, y: 26, width: 8, height: 12, color: color, unit: unit)
                    PixelBlock(x: 22, y: 30, width: 28, height: 3, color: Color(red: 0.48, green: 0.86, blue: 1.0), unit: unit)
                    PixelBlock(x: 10, y: 20, width: 10, height: 13, color: Color(red: 1.0, green: 0.28, blue: 0.30), unit: unit)
                    PixelBlock(x: 6, y: 12, width: 7, height: 8, color: Color(red: 1.0, green: 0.28, blue: 0.30), unit: unit)
                    PixelBlock(x: 39, y: 17, width: 22, height: 5, color: color.opacity(0.96), unit: unit)
                    PixelBlock(x: 37, y: 41, width: 24, height: 5, color: color.opacity(0.96), unit: unit)
                    PixelBlock(x: 44, y: 43, width: 10, height: 5, color: Color(red: 0.98, green: 0.98, blue: 0.95), unit: unit)
                }

                Group {
                    PixelBlock(x: 43, y: 7, width: 13, height: 10, color: Color(red: 0.98, green: 0.63, blue: 0.25), unit: unit)
                    PixelBlock(x: 40, y: 4, width: 5, height: 6, color: Color(red: 0.98, green: 0.63, blue: 0.25), unit: unit)
                    PixelBlock(x: 53, y: 4, width: 5, height: 6, color: Color(red: 0.98, green: 0.63, blue: 0.25), unit: unit)
                    PixelBlock(x: 47, y: 12, width: 7, height: 5, color: Color(red: 1.0, green: 0.84, blue: 0.58), unit: unit)
                    PixelBlock(x: 46, y: 10, width: 2, height: 2, color: .black, unit: unit)
                    PixelBlock(x: 54, y: 10, width: 2, height: 2, color: .black, unit: unit)
                    PixelBlock(x: 50, y: 15, width: 2, height: 1, color: .black, unit: unit)
                    PixelBlock(x: 57, y: 10, width: 4, height: 7, color: Color(red: 0.44, green: 0.62, blue: 1.0), unit: unit)
                }

                PixelPropellerMark(unit: unit, animated: animated)
                    .offset(x: 74 * unit, y: 15 * unit)
            }
            .frame(width: drawingWidth, height: drawingHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

private struct PixelPropellerMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let unit: CGFloat
    let animated: Bool

    var body: some View {
        let policy = PixelPropellerAnimationPolicy.pixelMark
        if policy.shouldAnimate(requested: animated, reduceMotion: reduceMotion) {
            PixelPropellerCompositorView(
                configuration: PixelPropellerFrameConfiguration(
                    size: CGSize(width: 18 * unit, height: 30 * unit),
                    bladeLong: 0,
                    bladeShort: 0,
                    horizontalLong: 0,
                    horizontalShort: 0,
                    pixelUnit: unit
                ),
                policy: policy
            )
            .frame(width: 18 * unit, height: 30 * unit)
        } else {
            PixelPropellerMarkFrame(frame: 0, unit: unit)
        }
    }
}

private struct PixelPropellerMarkFrame: View {
    let frame: Int
    let unit: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            PixelBlock(x: 0, y: 12, width: 4, height: 6, color: .black, unit: unit)
            PixelBlock(x: 2, y: 14, width: 3, height: 2, color: Color(red: 0.98, green: 0.98, blue: 0.95), unit: unit)

            if frame == 0 {
                PixelBlock(x: 5, y: 0, width: 2, height: 30, color: .black, unit: unit)
                PixelBlock(x: 3, y: 0, width: 6, height: 3, color: Color.white.opacity(0.86), unit: unit)
                PixelBlock(x: 3, y: 27, width: 6, height: 3, color: Color.white.opacity(0.86), unit: unit)
            } else {
                PixelBlock(x: -3, y: 6, width: 15, height: 3, color: .black, unit: unit)
                PixelBlock(x: -3, y: 21, width: 15, height: 3, color: .black, unit: unit)
                PixelBlock(x: -1, y: 7, width: 10, height: 1, color: Color.white.opacity(0.70), unit: unit)
                PixelBlock(x: -1, y: 22, width: 10, height: 1, color: Color.white.opacity(0.70), unit: unit)
            }
        }
        .frame(width: 18 * unit, height: 30 * unit)
    }
}

private struct PixelRibbonBanner: View {
    let title: String
    var color: Color
    let textColor: Color
    let flagTheme: FlightReminderFlagTheme
    let agentProviders: [AgentProvider]
    let agentOutcomeBadge: AgentFlagOutcomeBadge?
    var phase: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let flutter = CGFloat(sin(phase * .pi * 9))
            let innerRibbonHeightRatio = flagTheme.isAgentTheme ? 0.68 : 0.54

            ZStack {
                WavyRibbon()
                    .fill(Color.black.opacity(0.96))
                    .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)

                WavyRibbon()
                    .fill(color)
                    .frame(width: width * 0.90, height: height * innerRibbonHeightRatio)
                    .offset(x: flutter * 3, y: -height * 0.04 + flutter * 2)

                if flagTheme.isAgentTheme {
                    ZStack(alignment: .bottomTrailing) {
                        AgentFlagAppIconStack(providers: agentProviders)

                        if let agentOutcomeBadge {
                            AgentFlagOutcomeBadgeMark(badge: agentOutcomeBadge)
                                .offset(x: 2, y: 2)
                        }
                    }
                        .frame(width: agentProviders.count > 1 ? 64 : 42, height: 42)
                        .position(
                            x: width * (agentProviders.count > 1 ? 0.18 : 0.15) + flutter * 2,
                            y: height * 0.46 + flutter
                        )
                }

                WavyRibbon()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: width * 0.82, height: height * 0.20)
                    .offset(x: -flutter * 2, y: -height * 0.10 - flutter * 1.5)

                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .rotationEffect(.degrees(Double(-2 + flutter * 0.9)))
                    .padding(.leading, flagTheme.isAgentTheme ? 78 : 36)
                    .padding(.trailing, flagTheme.isAgentTheme ? 30 : 36)
                    .shadow(color: textShadowColor, radius: 1, x: 1, y: 1)
            }
        }
    }

    private var textShadowColor: Color {
        switch flagTheme {
        case .standard:
            return .black.opacity(0.18)
        case .claudeCode:
            return .white.opacity(0.20)
        case .codex, .cursor, .mixedAgents:
            return .black.opacity(0.30)
        }
    }
}

private struct AgentFlagOutcomeBadgeMark: View {
    let badge: AgentFlagOutcomeBadge

    var body: some View {
        Image(systemName: badge.systemImage)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(badge.color, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.68), lineWidth: 1.25)
            }
            .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

private struct AgentFlagAppIconStack: View {
    let providers: [AgentProvider]

    var body: some View {
        let visibleProviders = Array(providers.prefix(3))
        let iconSize: CGFloat = visibleProviders.count > 1 ? 30 : 40

        HStack(spacing: visibleProviders.count > 1 ? -10 : 0) {
            ForEach(visibleProviders, id: \.rawValue) { provider in
                if let image = AgentProviderIconResolver.shared.image(for: provider) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum PixelPropellerAnimationRenderingMode: Equatable {
    case coreAnimationKeyframes
}

struct PixelPropellerAnimationPolicy: Equatable {
    static let `default` = PixelPropellerAnimationPolicy(
        frameRate: 18,
        frameCount: 3,
        renderingMode: .coreAnimationKeyframes
    )

    static let pixelMark = PixelPropellerAnimationPolicy(
        frameRate: 10,
        frameCount: 2,
        renderingMode: .coreAnimationKeyframes
    )

    let frameRate: Double
    let frameCount: Int
    let renderingMode: PixelPropellerAnimationRenderingMode

    func shouldAnimate(requested: Bool, reduceMotion: Bool) -> Bool {
        requested && !reduceMotion
    }
}

private struct PixelPropellerSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animated: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let height = max(8, geometry.size.height)
            let width = max(5, geometry.size.width)
            let bladeLong = height * 0.92
            let bladeShort = max(1, width * 0.16)
            let horizontalLong = max(width * 0.86, height * 0.24)
            let horizontalShort = max(1, height * 0.040)
            let configuration = PixelPropellerFrameConfiguration(
                size: CGSize(width: width, height: height),
                bladeLong: bladeLong,
                bladeShort: bladeShort,
                horizontalLong: horizontalLong,
                horizontalShort: horizontalShort
            )
            let animationPolicy = PixelPropellerAnimationPolicy.default

            if animationPolicy.shouldAnimate(requested: animated, reduceMotion: reduceMotion) {
                PixelPropellerCompositorView(
                    configuration: configuration,
                    policy: animationPolicy
                )
                .frame(width: width, height: height, alignment: .center)
            } else {
                PixelPropellerFrameView(frame: 0, configuration: configuration)
                .frame(width: width, height: height, alignment: .center)
            }
        }
        .allowsHitTesting(false)
    }
}

struct PixelPropellerFrameConfiguration: Equatable {
    let size: CGSize
    let bladeLong: CGFloat
    let bladeShort: CGFloat
    let horizontalLong: CGFloat
    let horizontalShort: CGFloat
    var pixelUnit: CGFloat? = nil
}

private struct PixelPropellerFrameView: View {
    let frame: Int
    let configuration: PixelPropellerFrameConfiguration

    var body: some View {
        if let unit = configuration.pixelUnit {
            PixelPropellerMarkFrame(frame: frame, unit: unit)
        } else {
            spinnerFrame
        }
    }

    private var spinnerFrame: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.86))
                .frame(
                    width: frame == 0 ? configuration.bladeShort : configuration.horizontalLong,
                    height: frame == 0 ? configuration.bladeLong : configuration.horizontalShort
                )
            Capsule()
                .fill(Color.white.opacity(0.54))
                .frame(
                    width: frame == 0 ? max(1, configuration.bladeShort * 0.34) : configuration.horizontalLong * 0.86,
                    height: frame == 0 ? configuration.bladeLong * 0.88 : max(1, configuration.horizontalShort * 0.34)
                )
            if frame == 2 {
                Capsule()
                    .fill(Color.black.opacity(0.54))
                    .frame(width: configuration.bladeShort * 1.24, height: configuration.bladeLong * 0.82)
                    .rotationEffect(.degrees(22))
                Capsule()
                    .fill(Color.black.opacity(0.54))
                    .frame(width: configuration.bladeShort * 1.24, height: configuration.bladeLong * 0.82)
                    .rotationEffect(.degrees(-22))
            }

            Circle()
                .fill(Color.black.opacity(0.88))
                .frame(
                    width: max(2, configuration.bladeShort * 2.1),
                    height: max(2, configuration.bladeShort * 2.1)
                )
            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(
                    width: max(1, configuration.bladeShort * 0.9),
                    height: max(1, configuration.bladeShort * 0.9)
                )
        }
    }
}

private struct PixelPropellerCompositorView: NSViewRepresentable {
    let configuration: PixelPropellerFrameConfiguration
    let policy: PixelPropellerAnimationPolicy

    func makeNSView(context: Context) -> PixelPropellerAnimationView {
        PixelPropellerAnimationView()
    }

    func updateNSView(_ nsView: PixelPropellerAnimationView, context: Context) {
        nsView.update(configuration: configuration, policy: policy)
    }

    static func dismantleNSView(_ nsView: PixelPropellerAnimationView, coordinator: Void) {
        nsView.stopAnimating()
    }
}

// 只在外观改变时生成少量像素帧，循环交给合成器，避免每帧重算整个 SwiftUI 灵动岛。
@MainActor
final class PixelPropellerAnimationView: NSView {
    static let animationKey = "TodoPilot.PixelPropeller.frames"
    private var renderedConfiguration: PixelPropellerFrameConfiguration?
    private var renderedPolicy: PixelPropellerAnimationPolicy?
    private var renderedScale: CGFloat?
    private var renderedFrames: [CGImage] = []
    private var visibilityObservation: NSKeyValueObservation?
    private var observerTokens: [NSObjectProtocol] = []
    private(set) var frameRenderCount = 0

    var animationObserverCount: Int { observerTokens.count + (visibilityObservation == nil ? 0 : 1) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        visibilityObservation?.invalidate()
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopAnimating()
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        observerTokens.removeAll()
        if let window {
            // 单靠遮挡通知无法覆盖 orderOut；直接监听窗口显示状态，且不使用定时轮询。
            visibilityObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateAnimationVisibility() }
            }
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification,
                         NSWindow.didChangeBackingPropertiesNotification] {
                observe(name, object: window)
            }
            observe(NSApplication.didHideNotification, object: NSApp)
            observe(NSApplication.didUnhideNotification, object: NSApp)
        }
        if window != nil, let renderedConfiguration, let renderedPolicy {
            update(configuration: renderedConfiguration, policy: renderedPolicy)
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateAnimationVisibility()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimationVisibility()
    }

    private func observe(_ name: Notification.Name, object: AnyObject) {
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: name, object: object, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let configuration = self.renderedConfiguration,
                      let policy = self.renderedPolicy else { return }
                self.update(configuration: configuration, policy: policy)
            }
        })
    }

    func update(configuration: PixelPropellerFrameConfiguration, policy: PixelPropellerAnimationPolicy) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if renderedConfiguration != configuration || renderedPolicy != policy || renderedScale != scale {
            renderedConfiguration = configuration
            renderedPolicy = policy
            renderedScale = scale
            renderedFrames = (0..<policy.frameCount).compactMap { frame in
                let renderer = ImageRenderer(content:
                    PixelPropellerFrameView(frame: frame, configuration: configuration)
                        .frame(width: configuration.size.width, height: configuration.size.height)
                )
                renderer.scale = scale
                return renderer.cgImage
            }
            frameRenderCount += 1
            stopAnimating()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = scale
            layer?.contents = renderedFrames.first
            CATransaction.commit()
        }
        updateAnimationVisibility()
    }

    private func updateAnimationVisibility() {
        // orderOut 后视图仍有 window，必须同时检查实际可见性，遮挡/隐藏时撤销循环动画。
        guard let window, window.isVisible, !window.isMiniaturized,
              window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor,
              !NSApp.isHidden, let policy = renderedPolicy,
              renderedFrames.count == policy.frameCount else {
            stopAnimating()
            return
        }
        guard layer?.animation(forKey: Self.animationKey) == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = renderedFrames
        animation.keyTimes = (0..<renderedFrames.count).map {
            NSNumber(value: Double($0) / Double(renderedFrames.count))
        }
        animation.duration = Double(renderedFrames.count) / policy.frameRate
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        layer?.add(animation, forKey: Self.animationKey)
    }

    func stopAnimating() {
        layer?.removeAnimation(forKey: Self.animationKey)
    }
}

private struct WavyRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX + 10
        let right = rect.maxX - 10
        let top = rect.minY + rect.height * 0.24
        let mid = rect.midY
        let bottom = rect.maxY - rect.height * 0.20

        path.move(to: CGPoint(x: left, y: mid))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: top),
            control: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: right, y: rect.minY + rect.height * 0.30),
            control: CGPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.36)
        )
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: bottom + 5),
            control: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.maxY - rect.height * 0.28),
            control: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.38)
        )
        path.closeSubpath()
        return path
    }
}

private struct PixelBlock: View {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let color: Color
    let unit: CGFloat

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: width * unit, height: height * unit)
            .offset(x: x * unit, y: y * unit)
    }
}

struct PixelFlagMark: View {
    var color: Color = Color(red: 0.98, green: 0.68, blue: 0.08)

    var body: some View {
        PixelGrid(rows: [
            "1100",
            "1110",
            "1100",
            "1000",
            "1000"
        ], color: color)
    }
}

private struct PixelGrid: View {
    let rows: [String]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let rowCount = rows.count
            let columnCount = rows.map(\.count).max() ?? 1
            let size = min(geometry.size.width / CGFloat(columnCount), geometry.size.height / CGFloat(rowCount))

            ZStack(alignment: .topLeading) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, character in
                        if character == "1" {
                            Rectangle()
                                .fill(color)
                                .frame(width: size, height: size)
                                .offset(x: CGFloat(columnIndex) * size, y: CGFloat(rowIndex) * size)
                        }
                    }
                }
            }
        }
    }
}
