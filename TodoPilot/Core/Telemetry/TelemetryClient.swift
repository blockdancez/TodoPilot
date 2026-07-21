import Foundation

enum TelemetryEvent: String {
    case appFirstOpen = "app_first_open"
    case permissionScreenRecordingPrompted = "permission_screen_recording_prompted"
    case captureStarted = "capture_started"
    case captureCompleted = "capture_completed"
    case ocrCompleted = "ocr_completed"
    case taskCreated = "task_created"
    case taskCompleted = "task_completed"
    case taskEdited = "task_edited"
    case airplaneReminderShown = "airplane_reminder_shown"
    case airplaneActionClicked = "airplane_action_clicked"
    case reminderMuted = "reminder_muted"
}

enum TelemetryProperty: Equatable {
    case publicText(String)
    case numeric(Int)
    case boolean(Bool)
}

protocol TelemetryClient {
    func track(_ event: TelemetryEvent, properties: [String: TelemetryProperty])
}

struct LocalTelemetryClient: TelemetryClient {
    let logger: PrivacyLogger

    func track(_ event: TelemetryEvent, properties: [String: TelemetryProperty] = [:]) {
        logger.info("local_event", metadata: [
            "event": .publicText(event.rawValue),
            "property_count": .numeric(properties.count)
        ])
    }
}
