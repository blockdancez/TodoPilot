import Foundation

struct CodeAgentTaskStartResult: Equatable {
    let task: TodoTask
    let wasInserted: Bool
}

enum CodeAgentTerminalApplication: Equatable {
    case updated(TodoTaskStatus)
    case ignored
}

@MainActor
final class TaskStore: ObservableObject {
    typealias AgentUserOverrideObserver = @MainActor (UUID, AgentRunUserOverride) -> Void

    static let automaticCompletionGraceInterval: TimeInterval = 24 * 60 * 60
    static let historyDisplayLimit = 100

    @Published private(set) var tasks: [TodoTask] {
        didSet {
            persistence?.save(tasks)
        }
    }

    private let persistence: TaskStorePersistence?
    private let agentUserOverrideObserver: AgentUserOverrideObserver?

    init(
        seed: [TodoTask] = [],
        persistence: TaskStorePersistence? = nil,
        agentUserOverrideObserver: AgentUserOverrideObserver? = nil
    ) {
        self.persistence = persistence
        self.agentUserOverrideObserver = agentUserOverrideObserver
        self.tasks = persistence?.load() ?? seed
    }

    var activeTasks: [TodoTask] {
        activeTasks(asOf: Date())
    }

    func activeTasks(asOf now: Date) -> [TodoTask] {
        tasks
            .filter { $0.deletedAt == nil }
            .filter(\.status.isActive)
            .sorted { taskSort($0, $1, now: now) }
    }

    var todayTasks: [TodoTask] {
        todayTasks(asOf: Date())
    }

    func todayTasks(asOf now: Date) -> [TodoTask] {
        let calendar = Calendar.current
        return activeTasks(asOf: now).filter { task in
            guard let dueAt = task.dueAt else {
                return true
            }
            return calendar.isDate(dueAt, inSameDayAs: now) || dueAt < now
        }
    }

    var dueSoonTasks: [TodoTask] {
        dueSoonTasks(asOf: Date())
    }

    func dueSoonTasks(asOf now: Date) -> [TodoTask] {
        let windowEnd = now.addingTimeInterval(2 * 60 * 60)
        return activeTasks(asOf: now).filter { task in
            guard let dueAt = task.dueAt else {
                return false
            }
            return dueAt <= windowEnd
        }
    }

    var upcomingTasks: [TodoTask] {
        upcomingTasks(asOf: Date())
    }

    func upcomingTasks(asOf now: Date) -> [TodoTask] {
        let calendar = Calendar.current
        return activeTasks(asOf: now).filter { task in
            guard let dueAt = task.dueAt else {
                return false
            }
            return !calendar.isDate(dueAt, inSameDayAs: now) && dueAt >= now
        }
    }

    var overdueTasks: [TodoTask] {
        overdueTasks(asOf: Date())
    }

    func overdueTasks(asOf now: Date) -> [TodoTask] {
        activeTasks(asOf: now).filter { task in
            guard let dueAt = task.dueAt else {
                return false
            }
            return dueAt < now
        }
    }

    var completedTasks: [TodoTask] {
        tasks
            .filter { $0.deletedAt == nil }
            .filter { $0.status == .done }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var archivedTasks: [TodoTask] {
        tasks
            .filter { $0.deletedAt == nil }
            .filter { $0.status == .archived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var deletedTasks: [TodoTask] {
        tasks
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var recentHistoryTasks: [TodoTask] {
        Array(
            tasks
                .filter { task in
                    task.deletedAt != nil || (task.deletedAt == nil && task.status == .done)
                }
                .sorted { historyEventDate(for: $0) > historyEventDate(for: $1) }
                .prefix(Self.historyDisplayLimit)
        )
    }

    var nextAction: TodoTask? {
        nextAction(asOf: Date())
    }

    func nextAction(asOf now: Date) -> TodoTask? {
        activeTasks(asOf: now).first
    }

    @discardableResult
    func addManualTask(
        title: String,
        detail: String? = nil,
        priority: TodoTaskPriority = .medium,
        dueAt: Date? = nil
    ) -> TodoTask {
        let task = TodoTask(
            title: title,
            detail: detail,
            priority: priority,
            dueAt: dueAt
        )
        tasks.append(task)
        autoCompleteExpiredTasks()
        return task
    }

    @discardableResult
    func addImportedTaskIfNeeded(
        title: String,
        detail: String? = nil,
        priority: TodoTaskPriority = .medium,
        dueAt: Date? = nil,
        source: TodoTaskSource,
        sourceKey: String
    ) -> TodoTask? {
        let normalizedSourceKey = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSourceKey.isEmpty,
              !hasImportedTask(source: source, sourceKey: normalizedSourceKey) else {
            return nil
        }

        let task = TodoTask(
            title: title,
            detail: detail,
            priority: priority,
            dueAt: dueAt,
            source: source,
            sourceKey: normalizedSourceKey
        )
        tasks.append(task)
        autoCompleteExpiredTasks()
        return task
    }

    func hasImportedTask(source: TodoTaskSource, sourceKey: String) -> Bool {
        tasks.contains { task in
            task.source == source && task.sourceKey == sourceKey
        }
    }

    @discardableResult
    func ensureCodeAgentTask(
        for run: AgentRun,
        title: String,
        detail: String? = nil
    ) -> CodeAgentTaskStartResult {
        let sourceKey = run.id.uuidString
        if let existing = tasks.first(where: {
            ($0.source == .codeAgent && $0.sourceKey == sourceKey) || $0.id == run.taskID
        }) {
            return CodeAgentTaskStartResult(task: existing, wasInserted: false)
        }

        let task = TodoTask(
            id: run.taskID,
            title: title,
            detail: detail,
            priority: .medium,
            dueAt: nil,
            source: .codeAgent,
            sourceKey: sourceKey,
            status: .doing,
            createdAt: run.startedAt,
            updatedAt: run.startedAt
        )
        tasks.append(task)
        return CodeAgentTaskStartResult(task: task, wasInserted: true)
    }

    @discardableResult
    func applyCodeAgentTerminal(_ run: AgentRun) -> CodeAgentTerminalApplication {
        guard run.state == .terminal,
              run.outcome != nil,
              run.userOverride == .none,
              let index = tasks.firstIndex(where: {
                  $0.id == run.taskID
                      && $0.source == .codeAgent
                      && $0.sourceKey == run.id.uuidString
              }),
              tasks[index].deletedAt == nil,
              tasks[index].status == .doing else {
            return .ignored
        }

        let targetStatus: TodoTaskStatus = .done
        var updatedTasks = tasks
        updatedTasks[index].status = targetStatus
        updatedTasks[index].updatedAt = run.endedAt ?? run.lastEventAt
        tasks = updatedTasks
        return .updated(targetStatus)
    }

    @discardableResult
    func reconcilePersistedCodeAgentTerminalRuns(_ runs: [AgentRun]) -> Int {
        var updatedTasks = tasks
        var reconciledCount = 0

        for run in runs {
            guard run.state == .terminal,
                  run.outcome != nil,
                  run.userOverride == .none,
                  let index = updatedTasks.firstIndex(where: {
                      $0.id == run.taskID
                          && $0.source == .codeAgent
                          && $0.sourceKey == run.id.uuidString
                  }),
                  updatedTasks[index].deletedAt == nil,
                  updatedTasks[index].status.isActive else {
                continue
            }

            updatedTasks[index].status = .done
            updatedTasks[index].updatedAt = max(
                updatedTasks[index].updatedAt,
                run.endedAt ?? run.lastEventAt
            )
            reconciledCount += 1
        }

        if reconciledCount > 0 {
            tasks = updatedTasks
        }
        return reconciledCount
    }

    func complete(_ id: TodoTask.ID) {
        let isCodeAgentTask = taskIsCodeAgent(id)
        update(id) { task in
            task.status = .done
            task.updatedAt = Date()
        }
        if isCodeAgentTask {
            agentUserOverrideObserver?(id, .completed)
        }
    }

    func undoDone(_ id: TodoTask.ID) {
        let isCodeAgentTask = taskIsCodeAgent(id)
        update(id) { task in
            task.status = .todo
            task.updatedAt = Date()
        }
        if isCodeAgentTask {
            agentUserOverrideObserver?(id, .reopened)
        }
    }

    func snooze(_ id: TodoTask.ID, minutes: Int) {
        update(id) { task in
            task.status = .snoozed
            task.dueAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
            task.updatedAt = Date()
        }
    }

    func updateTaskDetails(
        _ id: TodoTask.ID,
        title: String,
        detail: String?,
        priority: TodoTaskPriority,
        dueAt: Date?
    ) {
        update(id) { task in
            task.title = title
            task.detail = detail
            task.priority = priority
            task.dueAt = dueAt
            task.updatedAt = Date()
        }
        autoCompleteExpiredTasks()
    }

    func autoCompleteExpiredTasks(asOf now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.automaticCompletionGraceInterval)
        var updatedTasks = tasks
        var changed = false

        for index in updatedTasks.indices {
            guard updatedTasks[index].deletedAt == nil,
                  updatedTasks[index].status.isActive,
                  let dueAt = updatedTasks[index].dueAt,
                  dueAt <= cutoff else {
                continue
            }

            updatedTasks[index].status = .done
            updatedTasks[index].updatedAt = now
            changed = true
        }

        if changed {
            tasks = updatedTasks
        }
    }

    func archive(_ id: TodoTask.ID) {
        update(id) { task in
            task.status = .archived
            task.updatedAt = Date()
        }
    }

    func softDelete(_ id: TodoTask.ID) {
        let isCodeAgentTask = taskIsCodeAgent(id)
        update(id) { task in
            let now = Date()
            task.deletedAt = now
            task.updatedAt = now
        }
        if isCodeAgentTask {
            agentUserOverrideObserver?(id, .deleted)
        }
    }

    func restoreDeleted(_ id: TodoTask.ID) {
        let isCodeAgentTask = taskIsCodeAgent(id)
        update(id) { task in
            task.deletedAt = nil
            task.updatedAt = Date()
            if task.status == .archived {
                task.status = .todo
            }
        }
        if isCodeAgentTask {
            agentUserOverrideObserver?(id, .reopened)
        }
    }

    func clearAllData() {
        tasks.removeAll()
    }

    private func update(_ id: TodoTask.ID, mutate: (inout TodoTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedTasks = tasks
        mutate(&updatedTasks[index])
        tasks = updatedTasks
    }

    private func taskIsCodeAgent(_ id: TodoTask.ID) -> Bool {
        tasks.contains { $0.id == id && $0.source == .codeAgent }
    }

    private func historyEventDate(for task: TodoTask) -> Date {
        task.deletedAt ?? task.updatedAt
    }

    private func taskSort(_ lhs: TodoTask, _ rhs: TodoTask, now: Date) -> Bool {
        let lhsOverdue = lhs.isOverdue(at: now)
        let rhsOverdue = rhs.isOverdue(at: now)
        if lhsOverdue != rhsOverdue {
            return lhsOverdue
        }

        if lhsOverdue, rhsOverdue {
            return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
        }

        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank < rhs.priority.sortRank
        }

        switch (lhs.dueAt, rhs.dueAt) {
        case let (.some(left), .some(right)):
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.createdAt < rhs.createdAt
        }
    }
}

@MainActor
protocol TaskStorePersistence {
    func load() -> [TodoTask]?
    func save(_ tasks: [TodoTask])
}

struct UserDefaultsTaskStorePersistence: TaskStorePersistence {
    private enum Keys {
        static let tasks = "todopilot.local.tasks.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [TodoTask]? {
        guard let data = defaults.data(forKey: Keys.tasks) else {
            return nil
        }
        return try? decoder.decode([TodoTask].self, from: data)
    }

    func save(_ tasks: [TodoTask]) {
        guard let data = try? encoder.encode(tasks) else {
            return
        }
        defaults.set(data, forKey: Keys.tasks)
    }
}
