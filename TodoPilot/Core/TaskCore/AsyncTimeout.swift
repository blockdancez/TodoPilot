import Foundation

func withTodoPilotTimeout<Value>(
    seconds: TimeInterval,
    message: String,
    operation: @escaping () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds(for: seconds))
            throw TodoPilotError.operationTimedOut(message)
        }

        guard let result = try await group.next() else {
            throw TodoPilotError.operationTimedOut(message)
        }

        group.cancelAll()
        return result
    }
}

private func timeoutNanoseconds(for seconds: TimeInterval) -> UInt64 {
    let clampedSeconds = max(0.001, seconds)
    let nanoseconds = clampedSeconds * 1_000_000_000
    return UInt64(min(nanoseconds, Double(UInt64.max)))
}
