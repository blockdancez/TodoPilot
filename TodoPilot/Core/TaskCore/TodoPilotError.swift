import Foundation

enum TodoPilotError: LocalizedError, Equatable {
    case notImplemented(String)
    case permissionRequired(String)
    case invalidInput(String)
    case storageFailure(String)
    case operationTimedOut(String)

    var errorDescription: String? {
        switch self {
        case let .notImplemented(message):
            message
        case let .permissionRequired(message):
            message
        case let .invalidInput(message):
            message
        case let .storageFailure(message):
            message
        case let .operationTimedOut(message):
            message
        }
    }
}
