import Foundation

struct TaskExportEnvelope: Codable, Equatable {
    let exportedAt: Date
    let schemaVersion: Int
    let tasks: [TodoTask]
}

struct TaskDataExporter {
    func exportJSON(tasks: [TodoTask], exportedAt: Date = Date()) throws -> Data {
        let envelope = TaskExportEnvelope(
            exportedAt: exportedAt,
            schemaVersion: LocalMigrationCoordinator.currentSchemaVersion,
            tasks: tasks
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    func exportMarkdown(tasks: [TodoTask], exportedAt: Date = Date()) -> String {
        var lines = [
            "# TodoPilot Export",
            "",
            "Exported at: \(Self.iso8601.string(from: exportedAt))",
            "Schema version: \(LocalMigrationCoordinator.currentSchemaVersion)",
            ""
        ]

        if tasks.isEmpty {
            lines.append("No tasks.")
            return lines.joined(separator: "\n")
        }

        for task in tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
            let marker = task.status == .done ? "x" : " "
            lines.append("- [\(marker)] \(task.title)")
            lines.append("  - id: \(task.id.uuidString)")
            lines.append("  - status: \(task.status.rawValue)")
            lines.append("  - priority: \(task.priority.rawValue)")

            if let dueAt = task.dueAt {
                lines.append("  - due_at: \(Self.iso8601.string(from: dueAt))")
            }

            if let deletedAt = task.deletedAt {
                lines.append("  - deleted_at: \(Self.iso8601.string(from: deletedAt))")
            }
        }

        return lines.joined(separator: "\n")
    }

    func exportCSV(tasks: [TodoTask]) -> String {
        let header = [
            "id",
            "title",
            "detail",
            "status",
            "priority",
            "due_at",
            "created_at",
            "updated_at"
        ].joined(separator: ",")

        let rows = tasks.sorted(by: { $0.createdAt < $1.createdAt }).map { task in
            [
                task.id.uuidString,
                task.title,
                task.detail ?? "",
                task.status.rawValue,
                task.priority.rawValue,
                task.dueAt.map(Self.iso8601.string(from:)) ?? "",
                Self.iso8601.string(from: task.createdAt),
                Self.iso8601.string(from: task.updatedAt)
            ]
            .map(Self.csvField)
            .joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        guard escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") else {
            return escaped
        }
        return "\"\(escaped)\""
    }

    private static let iso8601 = ISO8601DateFormatter()
}
