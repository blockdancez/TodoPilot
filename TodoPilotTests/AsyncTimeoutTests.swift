import XCTest
@testable import TodoPilot

final class AsyncTimeoutTests: XCTestCase {
    func testTimeoutReturnsFastOperationResult() async throws {
        let result = try await withTodoPilotTimeout(seconds: 1, message: "Timed out") {
            "done"
        }

        XCTAssertEqual(result, "done")
    }

    func testTimeoutThrowsWhenOperationTakesTooLong() async {
        do {
            _ = try await withTodoPilotTimeout(seconds: 0.01, message: "Timed out") {
                try await Task.sleep(nanoseconds: 200_000_000)
                return "late"
            }
            XCTFail("Expected timeout")
        } catch TodoPilotError.operationTimedOut(let message) {
            XCTAssertEqual(message, "Timed out")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
