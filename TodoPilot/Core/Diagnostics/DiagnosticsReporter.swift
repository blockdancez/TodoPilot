import Foundation

struct DiagnosticsReport: Equatable {
    let items: [DiagnosticsItem]

    var asText: String {
        items
            .map { "\($0.title): \($0.value)" }
            .joined(separator: "\n")
    }
}

struct DiagnosticsItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
}

struct DiagnosticsReporter {
    @MainActor
    func makeReport(taskStore: TaskStore, settingsStore: LocalSettingsStore, copy: AppCopy) -> DiagnosticsReport {
        DiagnosticsReport(items: [
            DiagnosticsItem(
                title: copy.openTasks,
                value: "\(taskStore.activeTasks.count)",
                systemImage: "checklist"
            ),
            DiagnosticsItem(
                title: copy.doneTasks,
                value: "\(taskStore.completedTasks.count)",
                systemImage: "checkmark.circle"
            ),
            DiagnosticsItem(
                title: copy.deletedTasks,
                value: "\(taskStore.deletedTasks.count)",
                systemImage: "trash"
            ),
            DiagnosticsItem(
                title: copy.capture,
                value: settingsStore.settings.captureEnabled ? copy.enabled : copy.disabled,
                systemImage: "viewfinder"
            ),
            DiagnosticsItem(
                title: copy.flightReminders,
                value: settingsStore.settings.flightRemindersEnabled ? copy.enabled : copy.disabled,
                systemImage: "airplane"
            ),
            DiagnosticsItem(
                title: copy.statusIsland,
                value: copy.statusIslandModeTitle(settingsStore.settings.statusIslandMode),
                systemImage: "capsule"
            ),
            DiagnosticsItem(
                title: copy.privacyLogging,
                value: copy.metadataKeysOnly,
                systemImage: "lock.shield"
            ),
            DiagnosticsItem(
                title: copy.localSchema,
                value: "v\(LocalMigrationCoordinator.currentSchemaVersion)",
                systemImage: "externaldrive"
            )
        ])
    }
}
