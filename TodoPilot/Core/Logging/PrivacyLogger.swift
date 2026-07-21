import Foundation
import OSLog

enum PrivacyLogValue: Equatable {
    case publicText(String)
    case numeric(Int)
    case boolean(Bool)
    case redacted

    static func telemetry(_ property: TelemetryProperty) -> PrivacyLogValue {
        switch property {
        case let .publicText(value):
            .publicText(value)
        case let .numeric(value):
            .numeric(value)
        case let .boolean(value):
            .boolean(value)
        }
    }
}

struct PrivacyLogger {
    private let logger = Logger(subsystem: "com.fubb.TodoPilot", category: "privacy")

    func info(_ event: String, metadata: [String: PrivacyLogValue] = [:]) {
        let metadataKeys = metadata.keys.sorted().joined(separator: ",")
        logger.info("event=\(event, privacy: .public) metadata_keys=\(metadataKeys, privacy: .public)")
    }

    func error(_ event: String, metadata: [String: PrivacyLogValue] = [:]) {
        let metadataKeys = metadata.keys.sorted().joined(separator: ",")
        logger.error("event=\(event, privacy: .public) metadata_keys=\(metadataKeys, privacy: .public)")
    }
}
