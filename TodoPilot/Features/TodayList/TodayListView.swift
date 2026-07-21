import AppKit
import SwiftUI

enum TodayTaskListProjection {
    static let recentCompletionRetentionInterval: TimeInterval = 3 * 24 * 60 * 60

    static func activeTasks(
        from tasks: [TodoTask],
        matching source: TodoTaskSource?
    ) -> [TodoTask] {
        tasks.filter { task in
            task.deletedAt == nil
                && task.status.isActive
                && (source == nil || task.source == source)
        }
    }

    static func recentCompletedTasks(
        from tasks: [TodoTask],
        matching source: TodoTaskSource?,
        now: Date
    ) -> [TodoTask] {
        let cutoff = now.addingTimeInterval(-recentCompletionRetentionInterval)
        return tasks
            .filter { task in
                task.deletedAt == nil
                    && task.status == .done
                    && task.updatedAt >= cutoff
                    && (source == nil || task.source == source)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

struct TodayListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var calendarImport: CalendarImportService

    @State private var selectedTaskSourceTab: TaskSourceTab = .all
    @State private var taskSheet: TaskSheet?
    @State private var feedback: TaskFeedback?
    @State private var pendingTaskIDs: Set<TodoTask.ID> = []
    @State private var sortMode: DefaultTodaySortMode = .priority
    @State private var currentDate = Date()

    private let deadlineClock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private let calendarRefreshClock = Timer.publish(every: 10 * 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let copy = environment.copy
        let now = currentDate

        GeometryReader { geometry in
            let contentWidth = TodayListLayout.contentWidth(for: geometry.size.width)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    header(copy, now: now)
                    taskScroll(copy, now: now)
                }
                .frame(width: contentWidth, alignment: .topLeading)
                .padding(.top, TodayListLayout.topPadding)
                .padding(.leading, TodayListLayout.leadingPadding)
                .padding(.trailing, TodayListLayout.trailingPadding)
                .padding(.bottom, TodayListLayout.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(TodoPilotTheme.appBackground)
            .overlay(alignment: .bottomLeading) {
                feedbackBar(copy)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.leading, TodayListLayout.leadingPadding)
                    .padding(.bottom, TodayListLayout.bottomPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .applicationTerminationRequested)) { _ in
            taskSheet = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .applicationTerminationRequested)) { _ in
            taskSheet = nil
        }
        .sheet(item: $taskSheet) { sheet in
            switch sheet {
            case .create:
                TaskEditorSheet(mode: .create) { edited in
                    let task = taskStore.addManualTask(
                        title: edited.title,
                        detail: edited.detail,
                        priority: edited.priority,
                        dueAt: edited.dueAt
                    )
                    environment.telemetry.track(.taskCreated, properties: [
                        "source": .publicText("manual")
                    ])
                    Task {
                        await environment.scheduleFlightReminder(
                            for: task,
                            reason: FlightReminderTriggerPolicy.manualTaskCreated
                        )
                    }
                }
                .environmentObject(environment)
            case let .edit(task):
                TaskEditorSheet(mode: .edit, task: task) { edited in
                    mutate(task.id) {
                        taskStore.updateTaskDetails(
                            task.id,
                            title: edited.title,
                            detail: edited.detail,
                            priority: edited.priority,
                            dueAt: edited.dueAt
                        )
                    }
                    environment.telemetry.track(.taskEdited, properties: [
                        "surface": .publicText("today_list"),
                        "priority": .publicText(edited.priority.rawValue)
                    ])
                    Task {
                        await environment.scheduleNextFlightReminder(reason: FlightReminderTriggerPolicy.taskEdited)
                    }
                }
                .environmentObject(environment)
            }
        }
        .onChange(of: taskStore.nextAction?.id) {
            Task {
                await environment.scheduleNextFlightReminder(reason: FlightReminderTriggerPolicy.nextActionChanged)
            }
        }
        .onAppear {
            currentDate = Date()
            taskStore.autoCompleteExpiredTasks(asOf: currentDate)
            sortMode = environment.settingsStore.settings.defaultTodaySortMode
            Task {
                await refreshCalendarImportsAutomaticallyIfNeeded(at: currentDate)
            }
        }
        .onReceive(deadlineClock) { date in
            taskStore.autoCompleteExpiredTasks(asOf: date)
            currentDate = date
        }
        .onReceive(calendarRefreshClock) { date in
            Task {
                await refreshCalendarImportsAutomaticallyIfNeeded(at: date)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAgentTasks)) { _ in
            selectedTaskSourceTab = .agent
            environment.agentRunStore.markUnreadRemindersRead()
        }
        .onChange(of: selectedTaskSourceTab) {
            if selectedTaskSourceTab == .agent {
                environment.agentRunStore.markUnreadRemindersRead()
            }
        }
        .onChange(of: environment.agentRunStore.unreadReminderRuns.count) {
            if selectedTaskSourceTab == .agent {
                environment.agentRunStore.markUnreadRemindersRead()
            }
        }
    }

    private func header(_ copy: AppCopy, now: Date) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(copy.todayTodo)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                    .lineLimit(1)
                Text(todaySubtitle(copy, now: now))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TodoPilotTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer()

            HStack(alignment: .top, spacing: 14) {
                Button {
                    environment.requestStartCapturePipeline(source: "today_toolbar")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "viewfinder")
                        Text(copy.frameCapture)
                        ShortcutKeyChordView(
                            environment.settingsStore.settings.captureHotKey,
                            style: .prominent
                        )
                    }
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 18)
                    .frame(minWidth: 210, minHeight: 42)
                    .foregroundStyle(.white)
                    .background(TodoPilotTheme.accent, in: Capsule())
                    .shadow(color: TodoPilotTheme.accent.opacity(0.28), radius: 14, y: 8)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .help(copy.startCapture)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        Task {
                            let outcome = await environment.showDemoFlightReminder()
                            if case let .skipped(reason)? = outcome {
                                await MainActor.run {
                                    showFeedback(message: environment.copy.demoFlightSkipped(reason))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "airplane")
                            Text(copy.demoFlight)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TodoPilotTheme.secondaryText)
                    .help(copy.flightReminders)

                    Picker("", selection: Binding(
                        get: { sortMode },
                        set: { mode in
                            sortMode = mode
                            environment.updateDefaultTodaySortMode(mode)
                            showFeedback(message: environment.copy.sortedBy(mode.title(environment.copy)))
                        }
                    )) {
                        ForEach(DefaultTodaySortMode.allCases) { mode in
                            Text(mode.title(copy)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 118)
                    .controlSize(.large)
                }
                .help(copy.byPriority)

                Button {
                    taskSheet = .create(UUID())
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help(copy.createManualTask)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func taskScroll(_ copy: AppCopy, now: Date) -> some View {
        let sourceActiveTasks = activeTasks(for: selectedTaskSourceTab, now: now)
        let nextAction = sourceActiveTasks.first
        let activeTasks = sourceActiveTasks.filter { task in
            task.id != nextAction?.id
        }
        let recentCompletedTasks = TodayTaskListProjection.recentCompletedTasks(
            from: taskStore.tasks,
            matching: selectedTaskSourceTab.taskSource,
            now: now
        )
        let tableTasks = activeTasks + recentCompletedTasks

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                TaskSourceTabBar(selectedTab: $selectedTaskSourceTab)
                .environmentObject(environment)

                if selectedTaskSourceTab == .localCalendar {
                    CalendarSourceToolbar(
                        service: calendarImport,
                        onRefresh: {
                            Task {
                                await refreshCalendarImports(reason: .manual, showUserFeedback: true)
                            }
                        },
                        onRequestCalendarAccess: {
                            requestCalendarAccess(preferredPane: .calendar)
                        },
                        onRequestRemindersAccess: {
                            requestCalendarAccess(preferredPane: .reminders)
                        }
                    )
                    .environmentObject(environment)
                }

                if selectedTaskSourceTab == .agent {
                    AgentSourceToolbar()
                        .environmentObject(environment)
                }

                Text(copy.recentTodo)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                    .padding(.top, selectedTaskSourceTab == .all || selectedTaskSourceTab == .manual ? 8 : 2)

                if let task = nextAction {
                    NextActionCard(
                        task: task,
                        now: now,
                        isLoading: pendingTaskIDs.contains(task.id),
                        onComplete: { toggleTask(task) },
                        onEdit: { showEditor(task) },
                        onDelete: { deleteTask(task) }
                    )
                    .environmentObject(environment)
                } else {
                    EmptyTaskCard(text: emptyStateText(copy, tab: selectedTaskSourceTab))
                }

                TaskListTable(
                    title: copy.taskListTitle(selectedTaskSourceTab.title(copy)),
                    tasks: tableTasks,
                    now: now,
                    isSourceScoped: selectedTaskSourceTab == .localCalendar,
                    pendingTaskIDs: pendingTaskIDs,
                    onToggle: toggleTask,
                    onEdit: showEditor,
                    onSnooze: snoozeTask,
                    onDelete: deleteTask
                )
                .environmentObject(environment)

                Color.clear
                    .frame(height: 56)
            }
            .padding(.trailing, 14)
        }
        .scrollIndicators(.visible)
    }

    @ViewBuilder
    private func feedbackBar(_ copy: AppCopy) -> some View {
        if let feedback {
            HStack(spacing: 12) {
                Text(feedback.message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(TodoPilotTheme.primaryText)

                Spacer()

                if let action = feedback.action {
                    Button(copy.undo) {
                        runFeedbackAction(action)
                        clearFeedback()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
        }
    }

    private var highlightedTaskIDs: Set<TodoTask.ID> {
        var ids = Set<TodoTask.ID>()
        if let nextAction = taskStore.nextAction {
            ids.insert(nextAction.id)
        }
        ids.formUnion(taskStore.dueSoonTasks.map(\.id))
        return ids
    }

    private var dueSoonTasks: [TodoTask] {
        taskStore.dueSoonTasks.filter { task in
            task.id != taskStore.nextAction?.id
        }
    }

    private var todayTasks: [TodoTask] {
        taskStore.todayTasks.filter { task in
            !highlightedTaskIDs.contains(task.id)
        }
    }

    private var upcomingTasks: [TodoTask] {
        taskStore.upcomingTasks.filter { task in
            !highlightedTaskIDs.contains(task.id)
        }
    }

    private func todaySubtitle(_ copy: AppCopy, now: Date) -> String {
        let activeCount = taskStore.activeTasks(asOf: now).count
        let overdueCount = taskStore.overdueTasks(asOf: now).count
        if copy.language == .chinese {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日EEEE"
            let base = "\(formatter.string(from: now)) · \(activeCount)件待处理"
            return overdueCount > 0 ? "\(base) · \(overdueCount)件已逾期" : base
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMM d"
        let base = "\(formatter.string(from: now)) · \(activeCount) pending"
        return overdueCount > 0 ? "\(base) · \(overdueCount) overdue" : base
    }

    private func activeTasks(for tab: TaskSourceTab, now: Date) -> [TodoTask] {
        let filtered = arranged(
            TodayTaskListProjection.activeTasks(
                from: taskStore.tasks,
                matching: tab.taskSource
            ),
            now: now
        )
        guard tab == .agent else {
            return filtered
        }
        let runningIDs = Set(environment.agentRunStore.activeRuns.map(\.taskID))
        return filtered.sorted { lhs, rhs in
            let lhsRunning = runningIDs.contains(lhs.id)
            let rhsRunning = runningIDs.contains(rhs.id)
            if lhsRunning != rhsRunning {
                return lhsRunning
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func emptyStateText(_ copy: AppCopy, tab: TaskSourceTab) -> String {
        switch tab {
        case .all:
            copy.noOpenTasks
        case .manual:
            copy.noManualTasks
        case .localCalendar:
            copy.noLocalCalendarTasks
        case .agent:
            copy.language == .chinese ? "暂无 Agent 任务" : "No Agent tasks"
        }
    }

    private func arranged(_ tasks: [TodoTask], now: Date) -> [TodoTask] {
        switch sortMode {
        case .priority:
            tasks.sorted { lhs, rhs in
                if let overdueOrder = overdueOrder(lhs, rhs, now: now) {
                    return overdueOrder
                }
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
            }
        case .due:
            tasks.sorted { lhs, rhs in
                if let overdueOrder = overdueOrder(lhs, rhs, now: now) {
                    return overdueOrder
                }
                return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
            }
        case .created:
            tasks.sorted { lhs, rhs in
                if let overdueOrder = overdueOrder(lhs, rhs, now: now) {
                    return overdueOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    private func overdueOrder(_ lhs: TodoTask, _ rhs: TodoTask, now: Date) -> Bool? {
        let lhsOverdue = lhs.displayDeadlineState(at: now) == .overdue
        let rhsOverdue = rhs.displayDeadlineState(at: now) == .overdue
        if lhsOverdue != rhsOverdue {
            return lhsOverdue
        }
        if lhsOverdue, rhsOverdue {
            return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
        }
        return nil
    }

    private func toggleTask(_ task: TodoTask) {
        mutate(task.id) {
            if task.status == .done {
                taskStore.undoDone(task.id)
                return
            }
            taskStore.complete(task.id)
        }

        if task.status != .done {
            showFeedback(message: environment.copy.completedTask(task.title), action: .undoDone(task.id))
            environment.telemetry.track(.taskCompleted, properties: [
                "surface": .publicText("today_list")
            ])
        }
    }

    private func refreshCalendarImports(
        reason: CalendarImportRefreshReason,
        showUserFeedback: Bool,
        preferredPrivacyPane: CalendarPrivacyPane? = nil
    ) async {
        let outcome = await calendarImport.refresh(reason: reason)
        let importedTasks: [TodoTask]
        switch outcome {
        case .refreshed, .partialPermissionMissing:
            importedTasks = importPendingCalendarCandidates()
        case .skippedNeedsUserAction, .permissionDenied, .failed:
            importedTasks = []
        }

        if !importedTasks.isEmpty {
            await environment.scheduleNextFlightReminder(reason: FlightReminderTriggerPolicy.taskConfirmed)
        }

        guard showUserFeedback else {
            return
        }

        switch outcome {
        case .skippedNeedsUserAction:
            showFeedback(message: calendarPermissionGuidance(environment.copy))
        case .permissionDenied:
            showFeedback(message: calendarPermissionGuidance(environment.copy))
        case .refreshed:
            showFeedback(message: environment.copy.calendarImported(importedTasks.count))
        case .partialPermissionMissing:
            if calendarImport.authorizationState != .granted {
                showFeedback(message: calendarPermissionGuidance(environment.copy))
            } else {
                showFeedback(message: environment.copy.calendarImported(importedTasks.count))
            }
        case .failed:
            showFeedback(message: environment.copy.calendarFetchFailed)
        }

        openMissingCalendarPrivacySettingsIfNeeded(preferredPane: preferredPrivacyPane)
    }

    private func refreshCalendarImportsAutomaticallyIfNeeded(at date: Date) async {
        guard CalendarAutomaticRefreshPolicy.shouldRefresh(
            lastRefreshAt: calendarImport.lastRefreshAt,
            isRefreshing: calendarImport.isRefreshing,
            now: date
        ) else {
            return
        }
        await refreshCalendarImports(reason: .automatic, showUserFeedback: false)
    }

    private func importPendingCalendarCandidates() -> [TodoTask] {
        var importedTasks: [TodoTask] = []
        for candidate in calendarImport.pendingCandidates {
            if let task = taskStore.addImportedTaskIfNeeded(
                title: candidate.taskTitle,
                detail: nil,
                priority: .medium,
                dueAt: candidate.dueAt,
                source: .localCalendar,
                sourceKey: candidate.sourceKey
            ) {
                importedTasks.append(task)
                environment.telemetry.track(.taskCreated, properties: [
                    "source": .publicText("local_calendar"),
                    "has_due_at": .boolean(candidate.dueAt != nil)
                ])
            }
            calendarImport.mark(candidate, as: .added)
        }
        return importedTasks
    }

    private func showEditor(_ task: TodoTask) {
        taskSheet = .edit(task)
    }

    private func snoozeTask(_ task: TodoTask) {
        mutate(task.id) {
            taskStore.snooze(task.id, minutes: 10)
        }
        showFeedback(message: environment.copy.snoozedTask(task.title))
    }

    private func deleteTask(_ task: TodoTask) {
        mutate(task.id) {
            taskStore.softDelete(task.id)
        }
        showFeedback(message: environment.copy.deletedTask(task.title), action: .restoreDeleted(task.id))
    }

    private func mutate(_ id: TodoTask.ID, action: @escaping () -> Void) {
        guard !pendingTaskIDs.contains(id) else {
            return
        }
        pendingTaskIDs.insert(id)
        withAnimation(.easeOut(duration: 0.18)) {
            action()
        }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            await MainActor.run {
                _ = pendingTaskIDs.remove(id)
            }
        }
    }

    private func showFeedback(message: String, action: TaskFeedback.Action? = nil) {
        let feedback = TaskFeedback(message: message, action: action)
        self.feedback = feedback
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if self.feedback?.id == feedback.id {
                    clearFeedback()
                }
            }
        }
    }

    private func clearFeedback() {
        feedback = nil
    }

    private func calendarPermissionGuidance(_ copy: AppCopy) -> String {
        permissionGuidance(
            eventState: calendarImport.authorizationState,
            reminderState: calendarImport.reminderAuthorizationState,
            copy: copy
        )
    }

    private func requestCalendarAccess(preferredPane: CalendarPrivacyPane) {
        Task {
            await refreshCalendarImports(
                reason: .manual,
                showUserFeedback: true,
                preferredPrivacyPane: preferredPane
            )
        }
    }

    private func openMissingCalendarPrivacySettingsIfNeeded(preferredPane: CalendarPrivacyPane?) {
        if preferredPane == .calendar, calendarImport.authorizationState != .granted {
            openCalendarPrivacySettings()
            return
        }
        if preferredPane == .reminders, calendarImport.reminderAuthorizationState != .granted {
            openRemindersPrivacySettings()
            return
        }
        if calendarImport.authorizationState != .granted {
            openCalendarPrivacySettings()
            return
        }
        if calendarImport.reminderAuthorizationState != .granted {
            openRemindersPrivacySettings()
        }
    }

    private func openCalendarPrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Calendars")
        showFeedback(message: environment.copy.calendarPrivacySettingsOpened)
    }

    private func openRemindersPrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Reminders")
        showFeedback(message: environment.copy.remindersPrivacySettingsOpened)
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func permissionGuidance(
        eventState: CalendarImportAuthorizationState,
        reminderState: CalendarImportAuthorizationState,
        copy: AppCopy
    ) -> String {
        if eventState.isBlocked {
            return copy.calendarEventsAccessDenied
        }
        if eventState == .notDetermined {
            return copy.calendarEventsNeedPermission
        }
        if reminderState.isBlocked {
            return copy.remindersAccessDenied
        }
        if reminderState == .notDetermined {
            return copy.remindersNeedPermission
        }
        return copy.calendarNeedsPermission
    }

    private func runFeedbackAction(_ action: TaskFeedback.Action) {
        switch action {
        case let .undoDone(id):
            taskStore.undoDone(id)
        case let .restoreDeleted(id):
            taskStore.restoreDeleted(id)
        }
    }
}

struct TodayListLayout: Equatable {
    static let maxContentWidth: CGFloat = 900
    static let topPadding: CGFloat = 32
    static let leadingPadding: CGFloat = 34
    static let trailingPadding: CGFloat = 28
    static let bottomPadding: CGFloat = 24

    static func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, min(maxContentWidth, availableWidth - leadingPadding - trailingPadding))
    }
}

private extension CalendarImportAuthorizationState {
    var isBlocked: Bool {
        self == .denied || self == .restricted
    }
}

private enum CalendarPrivacyPane {
    case calendar
    case reminders
}

private enum TaskSheet: Identifiable {
    case create(UUID)
    case edit(TodoTask)

    var id: String {
        switch self {
        case let .create(id):
            "create-\(id.uuidString)"
        case let .edit(task):
            "edit-\(task.id.uuidString)"
        }
    }
}

private struct TaskFeedback: Identifiable {
    enum Action {
        case undoDone(TodoTask.ID)
        case restoreDeleted(TodoTask.ID)
    }

    let id = UUID()
    let message: String
    let action: Action?
}

private enum TaskSourceTab: String, CaseIterable, Identifiable {
    case all
    case manual
    case localCalendar
    case agent

    var id: String { rawValue }

    var taskSource: TodoTaskSource? {
        switch self {
        case .all:
            nil
        case .manual:
            .manual
        case .localCalendar:
            .localCalendar
        case .agent:
            .codeAgent
        }
    }

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .all:
            copy.allTasks
        case .manual:
            copy.manualTasks
        case .localCalendar:
            copy.localCalendar
        case .agent:
            copy.language == .chinese ? "Agent" : "Agent"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "tray.full"
        case .manual:
            "square.and.pencil"
        case .localCalendar:
            "calendar"
        case .agent:
            "terminal"
        }
    }
}

private struct TaskSourceTabBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var selectedTab: TaskSourceTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 44) {
                ForEach(TaskSourceTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 12) {
                            Text(tab.title(environment.copy))
                                .font(.system(size: 14, weight: selectedTab == tab ? .bold : .semibold))
                                .foregroundStyle(selectedTab == tab ? TodoPilotTheme.accent : TodoPilotTheme.primaryText)
                                .lineLimit(1)
                                .frame(width: 70)

                            Rectangle()
                                .fill(selectedTab == tab ? TodoPilotTheme.accent : Color.clear)
                                .frame(width: 70, height: 2)
                        }
                        .animation(.easeOut(duration: 0.16), value: selectedTab == tab)
                    }
                    .buttonStyle(.plain)
                    .help(tab.title(environment.copy))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1)
        }
    }
}

private struct AgentSourceToolbar: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TodoPilotTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(environment.copy.language == .chinese ? "本机 Agent 自动任务" : "Local Agent tasks")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                Text(environment.copy.language == .chinese
                    ? "回合开始自动加入；终态由官方 Hook 驱动"
                    : "Turns are added automatically; terminal state comes from official hooks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TodoPilotTheme.secondaryText)
            }

            Spacer()

            TaskMetaPill(
                text: environment.copy.language == .chinese
                    ? "运行中 \(environment.agentRunStore.activeRuns.count)"
                    : "Running \(environment.agentRunStore.activeRuns.count)",
                foreground: TodoPilotTheme.accent,
                background: TodoPilotTheme.accent.opacity(0.10)
            )

            if !environment.agentRunStore.unreadReminderRuns.isEmpty {
                TaskMetaPill(
                    text: environment.copy.language == .chinese
                        ? "未读 \(environment.agentRunStore.unreadReminderRuns.count)"
                        : "Unread \(environment.agentRunStore.unreadReminderRuns.count)",
                    foreground: TodoPilotTheme.warning,
                    background: TodoPilotTheme.warning.opacity(0.10),
                    systemImage: "circle.fill"
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(TodoPilotTheme.accent.opacity(0.18), lineWidth: 1))
    }
}

private struct CalendarSourceToolbar: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var service: CalendarImportService

    let onRefresh: () -> Void
    let onRequestCalendarAccess: () -> Void
    let onRequestRemindersAccess: () -> Void

    var body: some View {
        let copy = environment.copy

        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TodoPilotTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(copy.localCalendarSyncTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                HStack(spacing: 6) {
                    SourceStatusText(text: copy.autoImportEnabled)
                    if let lastRefreshAt = service.lastRefreshAt {
                        SourceStatusText(text: copy.lastFetchAt(lastRefreshAt))
                    }
                }
            }

            Spacer(minLength: 10)

            Button(action: onRequestCalendarAccess) {
                permissionPill(
                    label: copy.calendarPermissionLabel,
                    state: service.authorizationState,
                    copy: copy
                )
            }
            .buttonStyle(.plain)
            .help(copy.openCalendarPrivacySettings)

            Button(action: onRequestRemindersAccess) {
                permissionPill(
                    label: copy.remindersPermissionLabel,
                    state: service.reminderAuthorizationState,
                    copy: copy
                )
            }
            .buttonStyle(.plain)
            .help(copy.openRemindersPrivacySettings)

            Button(action: onRefresh) {
                SourceActionLabel(
                    title: copy.fetchTasks,
                    systemImage: service.isRefreshing ? "hourglass" : "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .disabled(service.isRefreshing)
            .help(copy.fetchFromCalendar)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(red: 0.97, green: 0.99, blue: 1.0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TodoPilotTheme.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private func permissionPill(
        label: String,
        state: CalendarImportAuthorizationState,
        copy: AppCopy
    ) -> some View {
        let status = permissionStatus(for: state, copy: copy)
        return CalendarStatusPill(
            text: "\(label) \(status.text)",
            foreground: status.foreground,
            background: status.background,
            stroke: status.stroke
        )
    }

    private func permissionStatus(
        for state: CalendarImportAuthorizationState,
        copy: AppCopy
    ) -> (text: String, foreground: Color, background: Color, stroke: Color) {
        switch state {
        case .granted:
            let foreground = Color(red: 0.09, green: 0.55, blue: 0.28)
            return (
                copy.permissionGranted,
                foreground,
                Color(red: 0.90, green: 0.98, blue: 0.93),
                Color(red: 0.65, green: 0.90, blue: 0.74)
            )
        case .notDetermined:
            return (
                copy.permissionNeedsGrant,
                TodoPilotTheme.accent,
                TodoPilotTheme.accent.opacity(0.08),
                TodoPilotTheme.accent.opacity(0.20)
            )
        case .denied:
            return (
                copy.permissionDeniedShort,
                TodoPilotTheme.danger,
                TodoPilotTheme.danger.opacity(0.10),
                TodoPilotTheme.danger.opacity(0.20)
            )
        case .restricted:
            return (
                copy.permissionRestrictedShort,
                TodoPilotTheme.warning,
                TodoPilotTheme.warning.opacity(0.10),
                TodoPilotTheme.warning.opacity(0.24)
            )
        }
    }
}

private struct SourceStatusText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TodoPilotTheme.secondaryText)
            .lineLimit(1)
    }
}

private struct SourceActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(TodoPilotTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct CalendarImportDrawer: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var service: CalendarImportService
    @Binding var isExpanded: Bool

    let pendingSourceKeys: Set<String>
    let onRefresh: () -> Void
    let onAdd: (CalendarImportCandidate) -> Void
    let onIgnore: (CalendarImportCandidate) -> Void
    let onRequestCalendarAccess: () -> Void
    let onRequestRemindersAccess: () -> Void

    var body: some View {
        let copy = environment.copy

        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            header(copy)

            if isExpanded {
                if service.candidates.isEmpty {
                    CalendarImportEmptyState(text: emptyStateText(copy))
                        .padding(.top, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(service.candidates) { candidate in
                            CalendarImportCandidateRow(
                                candidate: candidate,
                                state: service.candidateStates[candidate.sourceKey],
                                isLoading: pendingSourceKeys.contains(candidate.sourceKey),
                                onAdd: { onAdd(candidate) },
                                onIgnore: { onIgnore(candidate) }
                            )
                            .environmentObject(environment)

                            if candidate.id != service.candidates.last?.id {
                                Divider()
                                    .padding(.leading, 82)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.top, 10)

                    Label(copy.handledCalendarEventsSkipped, systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 0.97, green: 0.99, blue: 1.0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TodoPilotTheme.accent.opacity(0.36), lineWidth: 1)
        )
    }

    private func header(_ copy: AppCopy) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TodoPilotTheme.accent)
                .frame(width: 24)

            Text(copy.fromCalendar)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TodoPilotTheme.primaryText)
                .fixedSize(horizontal: true, vertical: false)

            CalendarStatusPill(
                text: copy.localAutoRefresh,
                foreground: Color(red: 0.09, green: 0.55, blue: 0.28),
                background: Color(red: 0.90, green: 0.98, blue: 0.93),
                stroke: Color(red: 0.65, green: 0.90, blue: 0.74)
            )

            CalendarStatusPill(
                text: copy.calendarCandidateCount(service.pendingCandidateCount),
                foreground: TodoPilotTheme.accent,
                background: TodoPilotTheme.accent.opacity(0.08),
                stroke: TodoPilotTheme.accent.opacity(0.20)
            )

            if let lastRefreshAt = service.lastRefreshAt {
                HStack(spacing: 4) {
                    Text(copy.lastAutoRefresh)
                    Text(lastRefreshAt, style: .time)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TodoPilotTheme.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
            }

            if !isExpanded, service.pendingCandidateCount > 0 {
                Text(copy.calendarPendingReviewCount(service.pendingCandidateCount))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TodoPilotTheme.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 8)

            if service.authorizationState != .granted {
                Button(action: onRequestCalendarAccess) {
                    permissionPill(
                        label: copy.calendarPermissionLabel,
                        state: service.authorizationState,
                        copy: copy
                    )
                }
                .buttonStyle(.plain)
                .help(copy.openCalendarPrivacySettings)
            }

            if service.reminderAuthorizationState != .granted {
                Button(action: onRequestRemindersAccess) {
                    permissionPill(
                        label: copy.remindersPermissionLabel,
                        state: service.reminderAuthorizationState,
                        copy: copy
                    )
                }
                .buttonStyle(.plain)
                .help(copy.openRemindersPrivacySettings)
            }

            Button(action: onRefresh) {
                Label(copy.fetchFromCalendar, systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(service.isRefreshing)
            .help(copy.fetchFromCalendar)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(isExpanded ? copy.collapse : copy.expand)
        }
    }

    private func emptyStateText(_ copy: AppCopy) -> String {
        let eventState = service.authorizationState
        let reminderState = service.reminderAuthorizationState
        let hasEventAccess = eventState == .granted
        let hasReminderAccess = reminderState == .granted

        if !hasEventAccess && !hasReminderAccess {
            if eventState.isBlocked {
                return copy.calendarEventsAccessDenied
            }
            if eventState == .notDetermined {
                return copy.calendarEventsNeedPermission
            }
            if reminderState.isBlocked {
                return copy.remindersAccessDenied
            }
            if reminderState == .notDetermined {
                return copy.remindersNeedPermission
            }
            return copy.calendarAccessDenied
        }

        if service.lastRefreshFailed {
            return copy.calendarFetchFailed
        }

        if hasEventAccess && !hasReminderAccess {
            return copy.noCalendarCandidatesCalendarOnly
        }
        if !hasEventAccess && hasReminderAccess {
            return copy.noCalendarCandidatesRemindersOnly
        }

        return copy.noCalendarCandidates
    }

    private func permissionPill(
        label: String,
        state: CalendarImportAuthorizationState,
        copy: AppCopy
    ) -> some View {
        let status = permissionStatus(for: state, copy: copy)
        return CalendarStatusPill(
            text: "\(label) \(status.text)",
            foreground: status.foreground,
            background: status.background,
            stroke: status.stroke
        )
    }

    private func permissionStatus(
        for state: CalendarImportAuthorizationState,
        copy: AppCopy
    ) -> (text: String, foreground: Color, background: Color, stroke: Color) {
        switch state {
        case .granted:
            let foreground = Color(red: 0.09, green: 0.55, blue: 0.28)
            return (
                copy.permissionGranted,
                foreground,
                Color(red: 0.90, green: 0.98, blue: 0.93),
                Color(red: 0.65, green: 0.90, blue: 0.74)
            )
        case .notDetermined:
            let foreground = TodoPilotTheme.accent
            return (
                copy.permissionNeedsGrant,
                foreground,
                TodoPilotTheme.accent.opacity(0.08),
                TodoPilotTheme.accent.opacity(0.20)
            )
        case .denied:
            let foreground = TodoPilotTheme.danger
            return (
                copy.permissionDeniedShort,
                foreground,
                TodoPilotTheme.danger.opacity(0.10),
                TodoPilotTheme.danger.opacity(0.20)
            )
        case .restricted:
            let foreground = TodoPilotTheme.warning
            return (
                copy.permissionRestrictedShort,
                foreground,
                TodoPilotTheme.warning.opacity(0.10),
                TodoPilotTheme.warning.opacity(0.24)
            )
        }
    }
}

private struct CalendarImportCandidateRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let candidate: CalendarImportCandidate
    let state: CalendarImportCandidateState?
    let isLoading: Bool
    let onAdd: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        let copy = environment.copy

        HStack(spacing: 12) {
            if candidate.isAllDay {
                Text(copy.allDay)
            } else {
                Text(candidate.startsAt, style: .time)
            }

            HStack(spacing: 6) {
                Image(systemName: candidate.sourceKind == .reminder ? "circle" : "calendar")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.accent)
                Text(candidate.eventTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 166, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TodoPilotTheme.secondaryText.opacity(0.55))

            Text(candidate.taskTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TodoPilotTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 10)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
            } else if let state {
                CalendarImportHandledState(state: state)
                    .environmentObject(environment)
            } else {
                HStack(spacing: 8) {
                    Button(copy.addToToday, action: onAdd)
                        .buttonStyle(CalendarImportActionButtonStyle(kind: .primary))
                    Button(copy.ignore, action: onIgnore)
                        .buttonStyle(CalendarImportActionButtonStyle(kind: .quiet))
                }
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(TodoPilotTheme.primaryText)
        .padding(.horizontal, 14)
        .frame(height: 46)
    }
}

private struct CalendarImportHandledState: View {
    @EnvironmentObject private var environment: AppEnvironment
    let state: CalendarImportCandidateState

    var body: some View {
        HStack(spacing: 8) {
            CalendarStatusPill(
                text: title,
                foreground: foreground,
                background: background,
                stroke: foreground.opacity(0.18)
            )
            Text(environment.copy.handledCalendarEventsSkipped)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TodoPilotTheme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
        }
    }

    private var title: String {
        let copy = environment.copy
        switch state {
        case .added:
            return copy.added
        case .ignored:
            return copy.ignored
        }
    }

    private var foreground: Color {
        switch state {
        case .added:
            return Color(red: 0.09, green: 0.55, blue: 0.28)
        case .ignored:
            return TodoPilotTheme.secondaryText
        }
    }

    private var background: Color {
        switch state {
        case .added:
            return Color(red: 0.90, green: 0.98, blue: 0.93)
        case .ignored:
            return Color.black.opacity(0.05)
        }
    }
}

private struct CalendarImportEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TodoPilotTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct CalendarStatusPill: View {
    let text: String
    let foreground: Color
    let background: Color
    let stroke: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

private struct CalendarImportActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case quiet
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        CalendarImportActionButtonBody(configuration: configuration, kind: kind)
    }
}

private struct CalendarImportActionButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyle.Configuration
    let kind: CalendarImportActionButtonStyle.Kind
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : (isEnabled && isHovering ? 1.015 : 1))
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }

    private var foreground: Color {
        guard isEnabled else {
            return TodoPilotTheme.secondaryText.opacity(0.50)
        }
        if kind == .primary || isHovering {
            return TodoPilotTheme.accent
        }
        return TodoPilotTheme.primaryText
    }

    private var background: Color {
        if configuration.isPressed {
            return (kind == .primary ? Color.white : Color.black.opacity(0.035)).opacity(0.72)
        }
        if isEnabled && isHovering {
            return TodoPilotTheme.accent.opacity(0.08)
        }
        return kind == .primary ? Color.white : Color.black.opacity(0.035)
    }

    private var stroke: Color {
        if isEnabled && isHovering {
            return TodoPilotTheme.accent.opacity(0.30)
        }
        return kind == .primary ? TodoPilotTheme.accent.opacity(0.46) : Color.black.opacity(0.10)
    }
}

enum TodoPilotTheme {
    static let appBackground = Color(red: 0.97, green: 0.98, blue: 0.98)
    static let primaryText = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let secondaryText = Color(red: 0.48, green: 0.51, blue: 0.56)
    static let rowBackground = Color.white.opacity(0.86)
    static let rowStroke = Color.black.opacity(0.045)
    static let accent = Color(red: 0.18, green: 0.42, blue: 1)
    static let nextBackground = Color(red: 0.92, green: 0.95, blue: 1.0)
    static let nextStroke = Color(red: 0.72, green: 0.82, blue: 1.0)
    static let danger = Color(red: 0.96, green: 0.15, blue: 0.18)
    static let dangerBackground = Color(red: 1.0, green: 0.92, blue: 0.92)
    static let dangerStroke = Color(red: 1.0, green: 0.55, blue: 0.55)
    static let warning = Color(red: 0.84, green: 0.35, blue: 0.04)

    static func priorityColor(_ priority: TodoTaskPriority) -> Color {
        switch priority {
        case .high:
            Color(red: 1.0, green: 0.30, blue: 0.31)
        case .medium:
            Color(red: 1.0, green: 0.67, blue: 0.06)
        case .low:
            Color(red: 0.25, green: 0.78, blue: 0.20)
        }
    }

    static func priorityBackground(_ priority: TodoTaskPriority) -> Color {
        priorityColor(priority).opacity(0.12)
    }
}

private struct NextActionCard: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: TodoTask
    let now: Date
    let isLoading: Bool
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        let deadlineState = task.deadlineState(at: now)
        let isOverdue = deadlineState == .overdue

        HStack(spacing: 16) {
            Button(action: onComplete) {
                ZStack {
                    Circle()
                        .stroke(isOverdue ? TodoPilotTheme.danger : TodoPilotTheme.priorityColor(task.priority), lineWidth: 1.8)
                        .frame(width: 24, height: 24)
                    if task.status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.13, green: 0.79, blue: 0.59))
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            TaskSourcePill(source: task.source)
                .environmentObject(environment)

            VStack(alignment: .leading, spacing: 9) {
                Text(task.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isOverdue ? TodoPilotTheme.danger : TodoPilotTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    AgentRunPill(taskID: task.id, now: now)
                        .environmentObject(environment)
                    if let dueAt = task.dueAt {
                        TaskDueSummary(dueAt: dueAt, state: deadlineState)
                            .environmentObject(environment)
                    }
                    TaskPrioritySummary(priority: task.priority, overdue: isOverdue)
                        .environmentObject(environment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                RowIconButton(systemImage: "pencil", help: environment.copy.edit, action: onEdit)
                RowIconButton(systemImage: "trash", help: environment.copy.delete, role: .destructive, action: onDelete)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 86)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isHovering ? Color.white.opacity(0.92) : Color.white.opacity(0.78)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TodoPilotTheme.accent.opacity(isHovering ? 0.68 : 0.56), lineWidth: 1.1)
        )
        .shadow(color: TodoPilotTheme.accent.opacity(isHovering ? 0.14 : 0.06), radius: isHovering ? 18 : 10, y: isHovering ? 8 : 4)
        .offset(y: isHovering ? -1 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct TaskListTable: View {
    @EnvironmentObject private var environment: AppEnvironment
    let title: String
    let tasks: [TodoTask]
    let now: Date
    let isSourceScoped: Bool
    let pendingTaskIDs: Set<TodoTask.ID>
    let onToggle: (TodoTask) -> Void
    let onEdit: (TodoTask) -> Void
    let onSnooze: (TodoTask) -> Void
    let onDelete: (TodoTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(TodoPilotTheme.primaryText)
                .padding(.top, 4)

            if tasks.isEmpty {
                EmptyTaskCard(text: environment.copy.noOpenTasks)
            } else {
                LazyVStack(spacing: 0) {
                    TaskTableHeader()
                        .environmentObject(environment)

                    ForEach(tasks) { task in
                        Divider()
                            .padding(.leading, 56)
                        TaskTableRow(
                            task: task,
                            now: now,
                            isLoading: pendingTaskIDs.contains(task.id),
                            onToggle: { onToggle(task) },
                            onEdit: { onEdit(task) },
                            onSnooze: { onSnooze(task) },
                            onDelete: { onDelete(task) }
                        )
                        .environmentObject(environment)
                    }

                    if isSourceScoped {
                        Divider()
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .semibold))
                            Text(environment.copy.sourceDedupedNote)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                    }
                }
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
            }
        }
    }
}

private struct TaskTableHeader: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "square")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TodoPilotTheme.secondaryText)
                .frame(width: 56)

            Text(environment.copy.taskColumn)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(environment.copy.priorityColumn)
                .frame(width: 120, alignment: .leading)

            Text(environment.copy.dueColumn)
                .frame(width: 160, alignment: .leading)

            Text(environment.copy.actionsColumn)
                .frame(width: 142, alignment: .center)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(TodoPilotTheme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.black.opacity(0.025))
    }
}

private struct TaskTableRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: TodoTask
    let now: Date
    let isLoading: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onSnooze: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        let deadlineState = task.displayDeadlineState(at: now)
        let isOverdue = deadlineState == .overdue
        let isDone = task.status == .done

        HStack(spacing: 0) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDone ? TodoPilotTheme.secondaryText : TodoPilotTheme.secondaryText)
                    .frame(width: 56, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            HStack(spacing: 12) {
                TaskSourcePill(source: task.source)
                    .environmentObject(environment)

                AgentRunPill(taskID: task.id, now: now)
                    .environmentObject(environment)

                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOverdue ? TodoPilotTheme.danger : (isDone ? TodoPilotTheme.secondaryText.opacity(0.66) : TodoPilotTheme.primaryText))
                    .lineLimit(1)
                    .strikethrough(isDone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TaskPrioritySummary(priority: task.priority, overdue: isOverdue)
                .environmentObject(environment)
                .frame(width: 120, alignment: .leading)

            Group {
                if let dueAt = task.dueAt {
                    TaskDueSummary(dueAt: dueAt, state: deadlineState)
                        .environmentObject(environment)
                } else {
                    Text("-")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TodoPilotTheme.secondaryText.opacity(0.7))
                }
            }
            .frame(width: 160, alignment: .leading)

            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if isDone {
                    Text(environment.copy.done)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                    RowIconButton(
                        systemImage: "trash",
                        help: environment.copy.delete,
                        role: .destructive,
                        action: onDelete
                    )
                } else {
                    RowIconButton(systemImage: "pencil", help: environment.copy.edit, action: onEdit)
                    RowIconButton(systemImage: "clock", help: environment.copy.snooze, action: onSnooze)
                    RowIconButton(systemImage: "trash", help: environment.copy.delete, role: .destructive, action: onDelete)
                }
            }
            .frame(width: 142, alignment: .center)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(isHovering ? TodoPilotTheme.accent.opacity(0.035) : Color.clear)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct TodayTaskListRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: TodoTask
    let now: Date
    let isLoading: Bool
    let onToggle: (TodoTask) -> Void
    let onEdit: (TodoTask) -> Void
    let onSnooze: (TodoTask) -> Void
    let onDelete: (TodoTask) -> Void
    @State private var isHovering = false

    var body: some View {
        let deadlineState = task.deadlineState(at: now)
        let isOverdue = deadlineState == .overdue

        HStack(alignment: .top, spacing: 16) {
            Button {
                onToggle(task)
            } label: {
                ZStack {
                    Circle()
                        .stroke(isOverdue ? TodoPilotTheme.danger : TodoPilotTheme.priorityColor(task.priority), lineWidth: 2.4)
                        .frame(width: 24, height: 24)
                    if task.status == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.13, green: 0.79, blue: 0.59))
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.top, -3)

            VStack(alignment: .leading, spacing: 7) {
                Text(task.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOverdue ? TodoPilotTheme.danger : TodoPilotTheme.primaryText)
                    .lineLimit(2)
                    .strikethrough(task.status == .done)

                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    TaskSourcePill(source: task.source)
                        .environmentObject(environment)

                    AgentRunPill(taskID: task.id, now: now)
                        .environmentObject(environment)

                    TaskMetaPill(
                        text: environment.copy.priorityTitle(task.priority),
                        foreground: isOverdue ? TodoPilotTheme.danger : TodoPilotTheme.priorityColor(task.priority),
                        background: isOverdue ? TodoPilotTheme.danger.opacity(0.12) : TodoPilotTheme.priorityBackground(task.priority)
                    )

                    if task.sourceQuote != nil {
                        TaskMetaPill(
                            text: environment.copy.capturedSource,
                            foreground: TodoPilotTheme.accent,
                            background: TodoPilotTheme.accent.opacity(0.10),
                            systemImage: "viewfinder",
                            help: environment.copy.capturedSourceHelp
                        )
                    }

                    if let dueAt = task.dueAt {
                        TaskDuePill(dueAt: dueAt, state: deadlineState)
                    }
                }
            }

            Spacer(minLength: 16)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 12)
            } else {
                HStack(spacing: 14) {
                    RowIconButton(systemImage: "pencil", help: environment.copy.edit) {
                        onEdit(task)
                    }
                    RowIconButton(systemImage: "clock.arrow.circlepath", help: environment.copy.snooze) {
                        onSnooze(task)
                    }
                    RowIconButton(systemImage: "trash", help: environment.copy.delete, role: .destructive) {
                        onDelete(task)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isHovering ? TodoPilotTheme.accent.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .offset(y: isHovering ? -1 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
    }
}

private struct TaskMetaPill: View {
    let text: String
    let foreground: Color
    let background: Color
    var systemImage: String?
    var help: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .help(help ?? text)
    }
}

private struct TaskSourcePill: View {
    @EnvironmentObject private var environment: AppEnvironment
    let source: TodoTaskSource

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
            Text(environment.copy.taskSourceTitle(source))
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .help(environment.copy.taskSourceTitle(source))
    }

    private var systemImage: String {
        switch source {
        case .manual:
            "square.and.pencil"
        case .localCalendar:
            "calendar"
        case .codeAgent:
            "terminal"
        }
    }

    private var foreground: Color {
        switch source {
        case .manual:
            TodoPilotTheme.secondaryText
        case .localCalendar:
            Color(red: 0.13, green: 0.49, blue: 0.82)
        case .codeAgent:
            Color(red: 0.45, green: 0.30, blue: 0.84)
        }
    }

    private var background: Color {
        switch source {
        case .manual:
            Color.black.opacity(0.055)
        case .localCalendar:
            Color(red: 0.90, green: 0.96, blue: 1.0)
        case .codeAgent:
            Color(red: 0.94, green: 0.91, blue: 1.0)
        }
    }
}

private struct AgentRunPill: View {
    @EnvironmentObject private var environment: AppEnvironment
    let taskID: UUID
    let now: Date

    var body: some View {
        if let run = environment.agentRunStore.run(taskID: taskID) {
            HStack(spacing: 5) {
                if run.reminderState == .unread {
                    Circle()
                        .fill(TodoPilotTheme.warning)
                        .frame(width: 6, height: 6)
                }
                Text(label(for: run))
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(foreground(for: run))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(foreground(for: run).opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .help(label(for: run))
        }
    }

    private func label(for run: AgentRun) -> String {
        let provider = run.provider.installerProvider.displayName
        if run.state == .running {
            let seconds = max(0, now.timeIntervalSince(run.startedAt))
            if seconds < 60 {
                return "\(provider) · \(Int(seconds))s"
            }
            if seconds < 60 * 60 {
                return "\(provider) · \(Int(seconds / 60))m"
            }
            return "\(provider) · \(Int(seconds / 3600))h"
        }
        switch run.outcome {
        case .completed: return "\(provider) · \(environment.copy.language == .chinese ? "已完成" : "Completed")"
        case .failed: return "\(provider) · \(environment.copy.language == .chinese ? "失败" : "Failed")"
        case .cancelled: return "\(provider) · \(environment.copy.language == .chinese ? "已取消" : "Cancelled")"
        case .lost: return "\(provider) · \(environment.copy.language == .chinese ? "已失联" : "Lost")"
        case nil: return provider
        }
    }

    private func foreground(for run: AgentRun) -> Color {
        if run.state == .running {
            return TodoPilotTheme.accent
        }
        return run.outcome == .completed
            ? Color(red: 0.12, green: 0.62, blue: 0.34)
            : TodoPilotTheme.warning
    }
}

private struct TaskPrioritySummary: View {
    @EnvironmentObject private var environment: AppEnvironment
    let priority: TodoTaskPriority
    let overdue: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(environment.copy.priorityTitle(priority))
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(overdue ? TodoPilotTheme.danger : TodoPilotTheme.priorityColor(priority))
        .lineLimit(1)
    }
}

private struct TaskDueSummary: View {
    @EnvironmentObject private var environment: AppEnvironment
    let dueAt: Date
    let state: TodoTaskDeadlineState

    var body: some View {
        let isOverdue = state == .overdue

        HStack(spacing: 5) {
            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                .font(.system(size: 12, weight: .semibold))
            Text(dueText)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(isOverdue ? TodoPilotTheme.danger : TodoPilotTheme.secondaryText)
        .lineLimit(1)
    }

    private var dueText: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = environment.copy.language == .chinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm"
        let timeText = formatter.string(from: dueAt)

        if state == .overdue {
            return "\(environment.copy.overdue) \(timeText)"
        }
        if calendar.isDateInToday(dueAt) {
            return "\(environment.copy.today) \(timeText)"
        }
        if calendar.isDateInTomorrow(dueAt) {
            return "\(environment.copy.tomorrow) \(timeText)"
        }

        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: dueAt)
    }
}

private struct TaskDuePill: View {
    @EnvironmentObject private var environment: AppEnvironment
    let dueAt: Date
    let state: TodoTaskDeadlineState

    var body: some View {
        let isOverdue = state == .overdue
        let isDueSoon = state == .dueSoon

        HStack(spacing: 4) {
            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                .font(.system(size: 10, weight: .bold))
            if isOverdue {
                Text(environment.copy.overdue)
            }
            Text(dueAt, style: .time)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isOverdue ? TodoPilotTheme.danger : TodoPilotTheme.secondaryText)
        .padding(.horizontal, isOverdue || isDueSoon ? 7 : 0)
        .frame(height: isOverdue || isDueSoon ? 22 : nil)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var backgroundColor: Color {
        switch state {
        case .overdue:
            TodoPilotTheme.danger.opacity(0.12)
        case .dueSoon:
            TodoPilotTheme.priorityBackground(.medium)
        case .none, .scheduled:
            Color.clear
        }
    }
}

private struct TaskSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TodoPilotTheme.secondaryText)
                .padding(.leading, 28)

            Rectangle()
                .fill(Color.black.opacity(0.09))
                .frame(height: 1)

            VStack(spacing: 10, content: content)
        }
    }
}

private struct EmptyTaskCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(TodoPilotTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(TodoPilotTheme.rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TodoPilotTheme.rowStroke, lineWidth: 1)
            )
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: TodoTask
    let emphasized: Bool
    let isLoading: Bool
    let onToggle: (TodoTask) -> Void
    let onEdit: (TodoTask) -> Void
    let onSnooze: (TodoTask) -> Void
    let onDelete: (TodoTask) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                onToggle(task)
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            VStack(alignment: .leading, spacing: 5) {
            Text(task.title)
                    .font(.system(size: emphasized ? 17 : 16, weight: emphasized ? .semibold : .regular))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                    .lineLimit(1)
                    .strikethrough(task.status == .done)

                HStack(spacing: 10) {
                    Text(environment.copy.priorityTitle(task.priority))
                    if let dueAt = task.dueAt {
                        Text(dueAt, style: .time)
                    }
                    if task.sourceQuote != nil {
                        Label(environment.copy.capturedSource, systemImage: "viewfinder")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TodoPilotTheme.secondaryText)
            }
            .help(task.sourceQuote ?? task.detail ?? task.title)

            Spacer(minLength: 16)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 88, alignment: .trailing)
            } else {
                HStack(spacing: 10) {
                    RowIconButton(systemImage: "pencil", help: environment.copy.edit) {
                        onEdit(task)
                    }
                    RowIconButton(systemImage: "clock.arrow.circlepath", help: environment.copy.snooze) {
                        onSnooze(task)
                    }
                    RowIconButton(systemImage: "trash", help: environment.copy.delete, role: .destructive) {
                        onDelete(task)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovering ? TodoPilotTheme.accent.opacity(0.22) : TodoPilotTheme.rowStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.060 : (emphasized ? 0.055 : 0.025)), radius: isHovering ? 14 : (emphasized ? 12 : 8), y: isHovering ? 6 : (emphasized ? 6 : 3))
        .offset(y: isHovering ? -1 : 0)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isHovering {
            return Color.white.opacity(0.96)
        }
        return emphasized ? Color.white.opacity(0.94) : TodoPilotTheme.rowBackground
    }
}

private struct RowIconButton: View {
    let systemImage: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.08 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var foreground: Color {
        if role == .destructive {
            return Color(red: 1, green: 0.30, blue: 0.31).opacity(isHovering ? 1 : 0.88)
        }
        return isHovering ? TodoPilotTheme.accent : TodoPilotTheme.secondaryText
    }

    private var background: Color {
        if role == .destructive {
            return Color(red: 1, green: 0.30, blue: 0.31).opacity(isHovering ? 0.10 : 0)
        }
        return TodoPilotTheme.accent.opacity(isHovering ? 0.09 : 0)
    }
}

struct TaskEditorSheet: View {
    enum Mode {
        case create
        case edit
    }

    struct EditedTask {
        var title: String
        var detail: String?
        var priority: TodoTaskPriority
        var dueAt: Date?
    }

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onSave: (EditedTask) -> Void

    @State private var title: String
    @State private var detail: String
    @State private var priority: TodoTaskPriority
    @State private var hasDueAt: Bool
    @State private var dueAt: Date
    @State private var isSaving = false

    init(
        mode: Mode,
        task: TodoTask? = nil,
        initialTitle: String? = nil,
        initialDetail: String? = nil,
        onSave: @escaping (EditedTask) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? initialTitle ?? "")
        _detail = State(initialValue: task?.detail ?? initialDetail ?? "")
        _priority = State(initialValue: task?.priority ?? .medium)
        _hasDueAt = State(initialValue: task?.dueAt != nil)
        _dueAt = State(initialValue: task?.dueAt ?? Date())
    }

    var body: some View {
        let copy = environment.copy

        TodoPilotModalShell(
            title: mode == .create ? copy.newTask : copy.editTask,
            headerSystemImage: mode == .create ? "note.text.badge.plus" : "pencil",
            width: 680,
            height: 560,
            chromePolicy: .closableContentDialog,
            allowsContentScrolling: false,
            layout: .designReferenceFloating,
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 24) {
                TaskEditorInputField(
                    placeholder: copy.title,
                    text: $title,
                    characterCount: title.count,
                    maxCharacterCount: 80,
                    minHeight: 56
                )

                TaskEditorInputField(
                    placeholder: copy.taskDescriptionPlaceholder,
                    text: $detail,
                    characterCount: detail.count,
                    maxCharacterCount: 200,
                    minHeight: 118,
                    isMultiline: true
                )

                TaskEditorControlRow(label: copy.priority) {
                    TaskEditorPrioritySelector(priority: $priority)
                        .environmentObject(environment)
                }

                TaskEditorControlRow(label: copy.due) {
                    TaskEditorDueSelector(
                        hasDueAt: $hasDueAt,
                        dueAt: $dueAt
                    )
                    .environmentObject(environment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } footer: {
            HStack {
                Button(copy.cancel) {
                    dismiss()
                }
                .buttonStyle(TodoPilotModalGhostButtonStyle())
                .disabled(isSaving)

                Spacer()

                Button {
                    isSaving = true
                    onSave(EditedTask(
                        title: normalizedTitle,
                        detail: normalizedDetail,
                        priority: priority,
                        dueAt: hasDueAt ? dueAt : nil
                    ))
                    dismiss()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(copy.save, systemImage: "checkmark")
                    }
                }
                .buttonStyle(TodoPilotModalPrimaryButtonStyle())
                .disabled(normalizedTitle.isEmpty || isSaving)
            }
        }
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDetail: String? {
        let value = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct TaskEditorInputField: View {
    let placeholder: String
    @Binding var text: String
    let characterCount: Int
    let maxCharacterCount: Int
    let minHeight: CGFloat
    var isMultiline = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)

            TextField(placeholder, text: $text, axis: isMultiline ? .vertical : .horizontal)
                .textFieldStyle(.plain)
                .font(.system(size: isMultiline ? 16 : 20, weight: .semibold))
                .foregroundStyle(TodoPilotTheme.primaryText)
                .lineLimit(isMultiline ? 3...5 : 1...1)
                .padding(.horizontal, 20)
                .padding(.top, isMultiline ? 18 : 0)
                .padding(.trailing, 78)
                .frame(minHeight: minHeight, alignment: isMultiline ? .topLeading : .center)

            HStack {
                Spacer()
                Text("\(characterCount)/\(maxCharacterCount)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TodoPilotTheme.secondaryText.opacity(0.70))
                    .monospacedDigit()
                    .padding(.trailing, 18)
                    .padding(.top, isMultiline ? minHeight - 34 : 0)
            }
            .frame(minHeight: minHeight, alignment: isMultiline ? .topTrailing : .center)
            .allowsHitTesting(false)
        }
        .frame(minHeight: minHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TodoPilotTheme.accent.opacity(isMultiline ? 0 : 0.92), lineWidth: isMultiline ? 0 : 1.7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TodoPilotModalTheme.controlStroke, lineWidth: isMultiline ? 1 : 0)
        )
        .shadow(color: TodoPilotTheme.accent.opacity(isMultiline ? 0 : 0.12), radius: 8, y: 0)
    }
}

private struct TaskEditorControlRow<Content: View>: View {
    let label: String
    private let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 28) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TodoPilotTheme.primaryText)
                .frame(width: 92, alignment: .leading)

            content
        }
    }
}

private struct TaskEditorPrioritySelector: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var priority: TodoTaskPriority

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TodoTaskPriority.allCases, id: \.self) { value in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        priority = value
                    }
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(TodoPilotTheme.priorityColor(value))
                            .frame(width: 9, height: 9)
                        Text(environment.copy.priorityTitle(value))
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(priority == value ? TodoPilotTheme.accent : TodoPilotTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(priority == value ? TodoPilotTheme.accent.opacity(0.07) : Color.clear)
                }
                .buttonStyle(.plain)

                if value != TodoTaskPriority.allCases.last {
                    Rectangle()
                        .fill(TodoPilotModalTheme.controlStroke)
                        .frame(width: 1, height: 44)
                }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TodoPilotModalTheme.controlStroke, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

private struct TaskEditorDueSelector: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var hasDueAt: Bool
    @Binding var dueAt: Date
    @State private var isCustomDuePopoverPresented = false

    var body: some View {
        HStack(spacing: 10) {
            dueButton(
                title: environment.copy.today,
                systemImage: "sun.max",
                isSelected: hasDueAt && Calendar.current.isDateInToday(dueAt)
            ) {
                hasDueAt = true
                dueAt = defaultDueDate(daysFromToday: 0, hour: 18)
            }

            dueButton(
                title: environment.copy.tomorrow,
                systemImage: "sun.horizon",
                isSelected: hasDueAt && Calendar.current.isDateInTomorrow(dueAt)
            ) {
                hasDueAt = true
                dueAt = defaultDueDate(daysFromToday: 1, hour: 9)
            }

            Button {
                hasDueAt = true
                isCustomDuePopoverPresented = true
            } label: {
                Label(environment.copy.chooseDueDateTime, systemImage: "calendar")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(chooseTimeIsSelected ? TodoPilotTheme.accent : TodoPilotTheme.primaryText)
                    .frame(width: 164, height: 44)
                    .background(
                        chooseTimeIsSelected ? TodoPilotTheme.accent.opacity(0.08) : Color.white,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(chooseTimeIsSelected ? TodoPilotTheme.accent.opacity(0.28) : TodoPilotModalTheme.controlStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isCustomDuePopoverPresented, arrowEdge: .bottom) {
                customDuePopover
            }

            if hasDueAt {
                Button {
                    hasDueAt = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.045), in: Circle())
                }
                .buttonStyle(.plain)
                .help(environment.copy.noDueDate)
            }
        }
    }

    private var customDuePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(environment.copy.chooseDueDateTime)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TodoPilotTheme.primaryText)

            DatePicker(
                "",
                selection: Binding(
                    get: { dueAt },
                    set: { newValue in
                        hasDueAt = true
                        dueAt = newValue
                    }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            HStack {
                Spacer()
                Button(environment.copy.confirm) {
                    isCustomDuePopoverPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var chooseTimeIsSelected: Bool {
        hasDueAt &&
        !Calendar.current.isDateInToday(dueAt) &&
        !Calendar.current.isDateInTomorrow(dueAt)
    }

    private func dueButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isSelected ? TodoPilotTheme.accent : TodoPilotTheme.primaryText)
                .frame(width: 124, height: 44)
                .background(
                    isSelected ? TodoPilotTheme.accent.opacity(0.08) : Color.white,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? TodoPilotTheme.accent.opacity(0.28) : TodoPilotModalTheme.controlStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func defaultDueDate(daysFromToday: Int, hour: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: daysFromToday, to: start) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}

private struct DeletedTaskRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: TodoTask
    let onRestore: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TodoPilotTheme.secondaryText)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(TodoPilotTheme.primaryText)
                    .lineLimit(1)
                if let deletedAt = task.deletedAt {
                    (Text(environment.copy.deleted + " ") + Text(deletedAt, style: .relative))
                        .font(.caption)
                        .foregroundStyle(TodoPilotTheme.secondaryText)
                }
            }

            Spacer()

            Button {
                onRestore()
            } label: {
                Label(environment.copy.restore, systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background((isHovering ? Color.white.opacity(0.96) : TodoPilotTheme.rowBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovering ? TodoPilotTheme.accent.opacity(0.18) : TodoPilotTheme.rowStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.045 : 0), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

struct MenuBarTodayView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        let copy = environment.copy

        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let now = timeline.date

            VStack(alignment: .leading, spacing: 14) {
                StatusIslandPreview(taskStore: environment.taskStore)
                    .environmentObject(environment)

                if let task = environment.taskStore.nextAction(asOf: now) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(task.isOverdue(at: now) ? TodoPilotTheme.danger : TodoPilotTheme.primaryText)
                        .lineLimit(2)

                    if let dueAt = task.dueAt {
                        TaskDuePill(dueAt: dueAt, state: task.deadlineState(at: now))
                    }

                    HStack {
                        Button {
                            environment.taskStore.complete(task.id)
                        } label: {
                            Label(copy.done, systemImage: "checkmark")
                        }

                        Button {
                            environment.taskStore.snooze(task.id, minutes: 10)
                        } label: {
                            Label(copy.later, systemImage: "clock")
                        }
                    }
                } else {
                    Text(copy.clear)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 320)
        }
    }
}
