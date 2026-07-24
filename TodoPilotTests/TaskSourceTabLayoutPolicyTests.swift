import XCTest
@testable import TodoPilot

final class TaskSourceTabLayoutPolicyTests: XCTestCase {
    func testEnglishSourceTabsExpandToFitTheirLabels() {
        let titles = [
            "All",
            "Self-created",
            "Local Calendar",
            "Feishu",
            "Friend Reminders",
            "Agent"
        ]

        let widths = titles.map(TaskSourceTabLayoutPolicy.width(for:))

        XCTAssertEqual(widths[0], TaskSourceTabLayoutPolicy.minimumWidth)
        XCTAssertGreaterThan(widths[1], widths[0])
        XCTAssertGreaterThan(widths[2], widths[0])
        XCTAssertGreaterThan(widths[4], widths[0])
        XCTAssertLessThanOrEqual(
            TaskSourceTabLayoutPolicy.requiredWidth(for: titles),
            648
        )
    }
}
