import XCTest
@testable import TodoPilot

final class TaskDataExporterTests: XCTestCase {
    func testMarkdownExportIncludesStatusAndPriority() {
        let task = TodoTask(title: "Export me", priority: .high, status: .done)
        let exporter = TaskDataExporter()

        let markdown = exporter.exportMarkdown(tasks: [task], exportedAt: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(markdown.contains("- [x] Export me"))
        XCTAssertTrue(markdown.contains("status: DONE"))
        XCTAssertTrue(markdown.contains("priority: HIGH"))
    }

    func testJSONExportWrapsTasksWithSchemaVersion() throws {
        let task = TodoTask(title: "Export me", priority: .medium)
        let exporter = TaskDataExporter()

        let data = try exporter.exportJSON(tasks: [task], exportedAt: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder.todoPilot.decode(TaskExportEnvelope.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, LocalMigrationCoordinator.currentSchemaVersion)
        XCTAssertEqual(decoded.tasks.map(\.id), [task.id])
    }

    func testCSVExportEscapesCommasQuotesAndNewlines() {
        let task = TodoTask(title: "Review, \"ship\"\nplan", detail: "Line 1\nLine 2", priority: .low)
        let exporter = TaskDataExporter()

        let csv = exporter.exportCSV(tasks: [task])

        XCTAssertTrue(csv.contains("\"Review, \"\"ship\"\"\nplan\""))
        XCTAssertTrue(csv.contains("\"Line 1\nLine 2\""))
        XCTAssertTrue(csv.contains("LOW"))
    }
}

private extension JSONDecoder {
    static var todoPilot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
