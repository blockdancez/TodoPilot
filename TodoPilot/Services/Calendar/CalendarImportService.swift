import EventKit
import Foundation
import OSLog

enum CalendarImportRefreshReason {
    case automatic
    case manual

    var logValue: String {
        switch self {
        case .automatic:
            return "automatic"
        case .manual:
            return "manual"
        }
    }
}

enum CalendarImportAuthorizationState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted

    var logValue: String {
        switch self {
        case .notDetermined:
            return "not_determined"
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        }
    }
}

enum CalendarImportRefreshOutcome: Equatable {
    case skippedNeedsUserAction
    case permissionDenied
    case refreshed(newCandidateCount: Int)
    case partialPermissionMissing(newCandidateCount: Int)
    case failed
}

enum CalendarAutomaticRefreshPolicy {
    static let minimumInterval: TimeInterval = 10 * 60

    static func shouldRefresh(
        lastRefreshAt: Date?,
        isRefreshing: Bool,
        now: Date
    ) -> Bool {
        guard !isRefreshing else { return false }
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= minimumInterval
    }
}

enum CalendarImportCandidateState: String, Codable, Equatable {
    case added
    case ignored

    var isHandled: Bool { true }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.added.rawValue:
            self = .added
        case Self.ignored.rawValue, "reminderOnly":
            self = .ignored
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown calendar import candidate state."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct CalendarImportCandidate: Identifiable, Equatable {
    enum SourceKind: String, Equatable {
        case event
        case reminder
    }

    var id: String { sourceKey }

    let sourceKey: String
    let sourceKind: SourceKind
    let eventTitle: String
    let taskTitle: String
    let startsAt: Date
    let endsAt: Date?
    let isAllDay: Bool
    let calendarTitle: String?

    var dueAt: Date? {
        isAllDay ? nil : startsAt
    }
}

@MainActor
final class CalendarImportService: ObservableObject {
    @Published private(set) var authorizationState: CalendarImportAuthorizationState
    @Published private(set) var reminderAuthorizationState: CalendarImportAuthorizationState
    @Published private(set) var candidates: [CalendarImportCandidate] = []
    @Published private(set) var candidateStates: [String: CalendarImportCandidateState] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastRefreshFailed = false

    private let eventStore: EKEventStore
    private let memoryStore: CalendarImportMemoryStore
    private let calendar: Calendar
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.fubb.TodoPilot", category: "calendar-import")

    init(
        eventStore: EKEventStore = EKEventStore(),
        memoryStore: CalendarImportMemoryStore = CalendarImportMemoryStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.eventStore = eventStore
        self.memoryStore = memoryStore
        self.calendar = calendar
        self.now = now
        self.authorizationState = Self.authorizationState(from: EKEventStore.authorizationStatus(for: .event))
        self.reminderAuthorizationState = Self.authorizationState(from: EKEventStore.authorizationStatus(for: .reminder))
    }

    var pendingCandidates: [CalendarImportCandidate] {
        candidates.filter { candidateStates[$0.sourceKey] == nil }
    }

    var pendingCandidateCount: Int {
        pendingCandidates.count
    }

    @discardableResult
    func refresh(reason: CalendarImportRefreshReason) async -> CalendarImportRefreshOutcome {
        lastRefreshFailed = false
        syncAuthorizationStatesFromSystem()
        logger.info(
            "calendar_import_refresh_started reason=\(reason.logValue, privacy: .public) event_auth=\(self.authorizationState.logValue, privacy: .public) reminder_auth=\(self.reminderAuthorizationState.logValue, privacy: .public)"
        )
        logger.info(
            "calendar_import_runtime_identity bundle_id=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public) process_name=\(ProcessInfo.processInfo.processName, privacy: .public)"
        )

        isRefreshing = true
        defer { isRefreshing = false }

        await requestAccessIfNeeded(reason: reason)
        syncAuthorizationStatesFromSystem(preserveOptimisticGrant: true)

        guard authorizationState == .granted || reminderAuthorizationState == .granted else {
            if authorizationState == .notDetermined || reminderAuthorizationState == .notDetermined {
                logRefreshSkipped(reason: reason, status: "needs_user_action")
                return .skippedNeedsUserAction
            }
            lastRefreshFailed = true
            logRefreshSkipped(reason: reason, status: "permission_denied")
            return .permissionDenied
        }

        do {
            eventStore.reset()
            let fetched = try await fetchTodayCandidates()
            let beforeKeys = Set(pendingCandidates.map(\.sourceKey))
            let mergeStats = mergeFetchedCandidates(fetched)
            lastRefreshAt = now()
            let afterKeys = Set(pendingCandidates.map(\.sourceKey))
            let newCandidateCount = afterKeys.subtracting(beforeKeys).count
            logger.info(
                "calendar_import_refresh_completed reason=\(reason.logValue, privacy: .public) event_auth=\(self.authorizationState.logValue, privacy: .public) reminder_auth=\(self.reminderAuthorizationState.logValue, privacy: .public) fetched_candidates=\(fetched.count, privacy: .public) pending_candidates=\(afterKeys.count, privacy: .public) skipped_handled=\(mergeStats.skippedHandledCount, privacy: .public)"
            )
            if authorizationState != .granted || reminderAuthorizationState != .granted {
                return .partialPermissionMissing(newCandidateCount: newCandidateCount)
            }
            return .refreshed(newCandidateCount: newCandidateCount)
        } catch {
            lastRefreshFailed = true
            logger.error("calendar_import_refresh_failed reason=\(reason.logValue, privacy: .public) error_type=\(String(describing: type(of: error)), privacy: .public)")
            return .failed
        }
    }

    func mark(_ candidate: CalendarImportCandidate, as state: CalendarImportCandidateState) {
        memoryStore.set(state, for: candidate.sourceKey)
        candidateStates[candidate.sourceKey] = state
    }

    private func syncAuthorizationStatesFromSystem(preserveOptimisticGrant: Bool = false) {
        authorizationState = resolvedPublishedState(
            current: authorizationState,
            system: Self.authorizationState(from: EKEventStore.authorizationStatus(for: .event)),
            preserveOptimisticGrant: preserveOptimisticGrant
        )
        reminderAuthorizationState = resolvedPublishedState(
            current: reminderAuthorizationState,
            system: Self.authorizationState(from: EKEventStore.authorizationStatus(for: .reminder)),
            preserveOptimisticGrant: preserveOptimisticGrant
        )
    }

    private func resolvedPublishedState(
        current: CalendarImportAuthorizationState,
        system: CalendarImportAuthorizationState,
        preserveOptimisticGrant: Bool
    ) -> CalendarImportAuthorizationState {
        if preserveOptimisticGrant, current == .granted, system == .notDetermined {
            return .granted
        }
        return system
    }

    private func requestAccessIfNeeded(reason: CalendarImportRefreshReason) async {
        if authorizationState == .notDetermined {
            let result = await requestFullAccessToEvents()
            authorizationState = await resolvedAuthorizationState(
                for: .event,
                optimisticGrant: result.granted
            )
            logAccessRequestCompleted(
                reason: reason,
                entity: "event",
                result: result,
                resolvedState: authorizationState
            )
        }

        if reminderAuthorizationState == .notDetermined {
            let result = await requestFullAccessToReminders()
            reminderAuthorizationState = await resolvedAuthorizationState(
                for: .reminder,
                optimisticGrant: result.granted
            )
            logAccessRequestCompleted(
                reason: reason,
                entity: "reminder",
                result: result,
                resolvedState: reminderAuthorizationState
            )
        }

        let systemEventState = Self.authorizationState(from: EKEventStore.authorizationStatus(for: .event))
        let systemReminderState = Self.authorizationState(from: EKEventStore.authorizationStatus(for: .reminder))
        logger.info(
            "calendar_import_access_checked reason=\(reason.logValue, privacy: .public) event_auth=\(self.authorizationState.logValue, privacy: .public) reminder_auth=\(self.reminderAuthorizationState.logValue, privacy: .public) system_event_auth=\(systemEventState.logValue, privacy: .public) system_reminder_auth=\(systemReminderState.logValue, privacy: .public)"
        )
    }

    private func requestFullAccessToEvents() async -> CalendarImportAccessRequestResult {
        let fullAccessResult = await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                continuation.resume(
                    returning: CalendarImportAccessRequestResult(granted: granted, error: error)
                )
            }
        }

        if fullAccessResult.granted {
            return fullAccessResult
        }

        let state = Self.authorizationState(from: EKEventStore.authorizationStatus(for: .event))
        guard state == .notDetermined else {
            return fullAccessResult
        }

        let fallbackResult = await requestLegacyAccess(to: .event)
        logger.info(
            "calendar_import_access_legacy_fallback_completed entity=event granted=\(fallbackResult.granted, privacy: .public) error_type=\(fallbackResult.errorType, privacy: .public)"
        )
        return fallbackResult.granted ? fallbackResult : fullAccessResult
    }

    private func requestFullAccessToReminders() async -> CalendarImportAccessRequestResult {
        await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                continuation.resume(
                    returning: CalendarImportAccessRequestResult(granted: granted, error: error)
                )
            }
        }
    }

    private func requestLegacyAccess(to entityType: EKEntityType) async -> CalendarImportAccessRequestResult {
        await withCheckedContinuation { continuation in
            eventStore.requestAccess(to: entityType) { granted, error in
                continuation.resume(
                    returning: CalendarImportAccessRequestResult(granted: granted, error: error)
                )
            }
        }
    }

    private func resolvedAuthorizationState(
        for entityType: EKEntityType,
        optimisticGrant: Bool
    ) async -> CalendarImportAuthorizationState {
        for attempt in 0..<5 {
            let state = Self.authorizationState(from: EKEventStore.authorizationStatus(for: entityType))
            if state != .notDetermined {
                return state
            }
            if attempt < 4 {
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        return optimisticGrant ? .granted : .notDetermined
    }

    private func logAccessRequestCompleted(
        reason: CalendarImportRefreshReason,
        entity: String,
        result: CalendarImportAccessRequestResult,
        resolvedState: CalendarImportAuthorizationState
    ) {
        logger.info(
            "calendar_import_access_request_completed reason=\(reason.logValue, privacy: .public) entity=\(entity, privacy: .public) granted=\(result.granted, privacy: .public) error_type=\(result.errorType, privacy: .public) resolved_auth=\(resolvedState.logValue, privacy: .public)"
        )
    }

    private func fetchTodayCandidates() async throws -> [CalendarImportCandidate] {
        let referenceDate = now()
        let startOfDay = calendar.startOfDay(for: referenceDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let eventCandidates = authorizationState == .granted
            ? fetchEventCandidates(startOfDay: startOfDay, endOfDay: endOfDay)
            : []
        let reminderCandidates = reminderAuthorizationState == .granted
            ? await fetchReminderCandidates(startOfDay: startOfDay, endOfDay: endOfDay)
            : []

        logger.info(
            "calendar_import_fetch_counts raw_event_count=\(eventCandidates.count, privacy: .public) raw_reminder_count=\(reminderCandidates.count, privacy: .public)"
        )

        return (eventCandidates + reminderCandidates)
            .sorted { lhs, rhs in
                if lhs.startsAt != rhs.startsAt {
                    return lhs.startsAt < rhs.startsAt
                }
                return lhs.eventTitle.localizedCaseInsensitiveCompare(rhs.eventTitle) == .orderedAscending
            }
    }

    private func fetchEventCandidates(
        startOfDay: Date,
        endOfDay: Date
    ) -> [CalendarImportCandidate] {
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .compactMap { CalendarImportCandidate(event: $0) }
    }

    private func fetchReminderCandidates(
        startOfDay: Date,
        endOfDay: Date
    ) async -> [CalendarImportCandidate] {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: startOfDay,
            ending: endOfDay,
            calendars: nil
        )

        let reminders = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        return reminders.compactMap { reminder in
            CalendarImportCandidate(reminder: reminder, calendar: calendar)
        }
    }

    private func mergeFetchedCandidates(_ fetched: [CalendarImportCandidate]) -> CalendarImportMergeStats {
        let handledVisible = candidates.filter { candidate in
            candidateStates[candidate.sourceKey]?.isHandled == true
        }
        let handledVisibleKeys = Set(handledVisible.map(\.sourceKey))
        let pendingFetched = fetched.filter { candidate in
            guard !handledVisibleKeys.contains(candidate.sourceKey) else {
                return false
            }
            return memoryStore.state(for: candidate.sourceKey) == nil
        }

        candidateStates = Dictionary(uniqueKeysWithValues: handledVisible.map { candidate in
            (candidate.sourceKey, memoryStore.state(for: candidate.sourceKey) ?? .ignored)
        })
        candidates = (handledVisible + pendingFetched).sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt {
                return lhs.startsAt < rhs.startsAt
            }
            return lhs.eventTitle.localizedCaseInsensitiveCompare(rhs.eventTitle) == .orderedAscending
        }

        return CalendarImportMergeStats(
            skippedHandledCount: fetched.count - pendingFetched.count
        )
    }

    private func logRefreshSkipped(reason: CalendarImportRefreshReason, status: String) {
        logger.info(
            "calendar_import_refresh_skipped reason=\(reason.logValue, privacy: .public) status=\(status, privacy: .public) event_auth=\(self.authorizationState.logValue, privacy: .public) reminder_auth=\(self.reminderAuthorizationState.logValue, privacy: .public)"
        )
    }

    private static func authorizationState(from status: EKAuthorizationStatus) -> CalendarImportAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized, .fullAccess:
            return .granted
        case .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

private struct CalendarImportMergeStats {
    let skippedHandledCount: Int
}

private struct CalendarImportAccessRequestResult {
    let granted: Bool
    let errorType: String

    init(granted: Bool, error: Error?) {
        self.granted = granted
        self.errorType = error.map { String(describing: type(of: $0)) } ?? "none"
    }
}

extension CalendarImportCandidate {
    init?(event: EKEvent) {
        let eventTitle = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventTitle.isEmpty,
              let startsAt = event.startDate else {
            return nil
        }

        let calendarItemIdentifier = event.calendarItemIdentifier
        let baseIdentifier = calendarItemIdentifier.isEmpty ? (event.eventIdentifier ?? UUID().uuidString) : calendarItemIdentifier
        let startTimestamp = Int(startsAt.timeIntervalSince1970.rounded())
        let sourceKey = "calendar:\(baseIdentifier):\(startTimestamp)"

        self.init(
            sourceKey: sourceKey,
            sourceKind: .event,
            eventTitle: eventTitle,
            taskTitle: Self.suggestedTaskTitle(for: eventTitle),
            startsAt: startsAt,
            endsAt: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar?.title
        )
    }

    init?(reminder: EKReminder, calendar: Calendar) {
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let dueDateComponents = reminder.dueDateComponents,
              let dueDate = calendar.date(from: dueDateComponents) else {
            return nil
        }

        let baseIdentifier = reminder.calendarItemIdentifier.isEmpty ? UUID().uuidString : reminder.calendarItemIdentifier
        let dueTimestamp = Int(dueDate.timeIntervalSince1970.rounded())
        let sourceKey = "reminder:\(baseIdentifier):\(dueTimestamp)"
        let isAllDay = dueDateComponents.hour == nil && dueDateComponents.minute == nil

        self.init(
            sourceKey: sourceKey,
            sourceKind: .reminder,
            eventTitle: title,
            taskTitle: Self.suggestedTaskTitle(for: title),
            startsAt: dueDate,
            endsAt: nil,
            isAllDay: isAllDay,
            calendarTitle: reminder.calendar?.title
        )
    }

    private static func suggestedTaskTitle(for eventTitle: String) -> String {
        let trimmed = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "日程事项" : trimmed
    }
}

final class CalendarImportMemoryStore {
    private enum Keys {
        static let states = "todopilot.calendarImport.states.v1"
    }

    private let defaults: UserDefaults
    private var states: [String: CalendarImportCandidateState]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.states),
           let decoded = try? JSONDecoder().decode([String: CalendarImportCandidateState].self, from: data) {
            self.states = decoded
        } else {
            self.states = [:]
        }
    }

    func state(for sourceKey: String) -> CalendarImportCandidateState? {
        states[sourceKey]
    }

    func set(_ state: CalendarImportCandidateState, for sourceKey: String) {
        states[sourceKey] = state
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(states) else {
            return
        }
        defaults.set(data, forKey: Keys.states)
    }
}
